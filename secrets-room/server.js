#!/usr/bin/env node
/**
 * Secrets Room — manage Collaboration FE/BE env keys in Vault KV.
 * Diffs against .env.example on disk; write keys to Vault; Apply exports + recreate.
 */
'use strict';

const express = require('express');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const fetch = require('node-fetch');

const PORT = Number(process.env.PORT || 8300);
const VAULT_ADDR = (process.env.VAULT_ADDR || 'http://127.0.0.1:8200').replace(/\/$/, '');
const VAULT_TOKEN = process.env.VAULT_TOKEN || '';
const BASIC_USER = process.env.ROOM_BASIC_USER || 'operator';
const BASIC_PASS = process.env.ROOM_BASIC_PASS || '';
const DEVOPS_ROOT = process.env.DEVOPS_ROOT || '/var/devops';
const JENKINS_URL = (process.env.JENKINS_URL || 'http://172.16.50.39:8080').replace(/\/$/, '');
const JENKINS_USER = process.env.JENKINS_ADMIN_USER || 'admin';
const JENKINS_PASS = process.env.JENKINS_ADMIN_PASS || '';
const COLLAB_SOURCE =
  process.env.COLLABORATION_SOURCE ||
  '/home/ienetworks/workspace/company/SelamnewCollaboration';

const ROOMS = {
  backend: {
    label: 'Collaboration Backend',
    vaultPath: 'secret/data/collaboration/backend',
    exampleFile: path.join(COLLAB_SOURCE, 'backend/.env.example'),
    envFile: path.join(DEVOPS_ROOT, 'collaboration/env/backend.env'),
  },
  frontend: {
    label: 'Collaboration Frontend',
    vaultPath: 'secret/data/collaboration/frontend',
    exampleFile: path.join(COLLAB_SOURCE, 'frontend/.env.example'),
    envFile: path.join(DEVOPS_ROOT, 'collaboration/env/frontend.env'),
  },
};

function parseEnvExample(filePath) {
  if (!fs.existsSync(filePath)) return [];
  const text = fs.readFileSync(filePath, 'utf8');
  const keys = [];
  const seen = new Set();
  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const cleaned = line.replace(/^export\s+/, '');
    if (!cleaned.includes('=')) continue;
    const key = cleaned.split('=')[0].trim();
    if (!key || seen.has(key)) continue;
    seen.add(key);
    keys.push(key);
  }
  return keys;
}

async function vaultRequest(method, apiPath, body) {
  if (!VAULT_TOKEN) {
    const err = new Error('VAULT_TOKEN not configured');
    err.status = 500;
    throw err;
  }
  const res = await fetch(`${VAULT_ADDR}/v1/${apiPath}`, {
    method,
    headers: {
      'X-Vault-Token': VAULT_TOKEN,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = { raw: text };
  }
  if (!res.ok) {
    const err = new Error(json?.errors?.join?.(', ') || text || res.statusText);
    err.status = res.status;
    err.body = json;
    throw err;
  }
  return json;
}

async function readVaultData(vaultPath) {
  try {
    const json = await vaultRequest('GET', vaultPath);
    return json?.data?.data || {};
  } catch (e) {
    if (e.status === 404) return {};
    throw e;
  }
}

async function writeVaultData(vaultPath, data) {
  // Merge with existing
  const current = await readVaultData(vaultPath);
  const merged = { ...current, ...data };
  delete merged._seed;
  await vaultRequest('POST', vaultPath, { data: merged });
  return merged;
}

function basicAuth(req, res, next) {
  if (!BASIC_PASS) {
    return next();
  }
  const hdr = req.headers.authorization || '';
  if (!hdr.startsWith('Basic ')) {
    res.set('WWW-Authenticate', 'Basic realm="Secrets Room"');
    return res.status(401).send('Auth required');
  }
  const decoded = Buffer.from(hdr.slice(6), 'base64').toString('utf8');
  const idx = decoded.indexOf(':');
  const user = decoded.slice(0, idx);
  const pass = decoded.slice(idx + 1);
  if (user !== BASIC_USER || pass !== BASIC_PASS) {
    res.set('WWW-Authenticate', 'Basic realm="Secrets Room"');
    return res.status(401).send('Invalid credentials');
  }
  return next();
}

function runScript(scriptPath, env = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn('bash', [scriptPath], {
      env: { ...process.env, ...env },
      cwd: DEVOPS_ROOT,
    });
    let out = '';
    child.stdout.on('data', (d) => {
      out += d.toString();
    });
    child.stderr.on('data', (d) => {
      out += d.toString();
    });
    child.on('close', (code) => {
      if (code === 0) resolve(out);
      else reject(new Error(out || `exit ${code}`));
    });
  });
}

const app = express();
app.use(basicAuth);
app.use(express.json({ limit: '2mb' }));
app.use(express.static(path.join(__dirname, 'public')));

app.get('/api/health', (_req, res) => {
  res.json({
    ok: true,
    vaultAddr: VAULT_ADDR,
    hasToken: Boolean(VAULT_TOKEN),
    collabSource: COLLAB_SOURCE,
  });
});

app.get('/api/rooms', (_req, res) => {
  res.json(
    Object.entries(ROOMS).map(([id, r]) => ({
      id,
      label: r.label,
      vaultPath: r.vaultPath,
      exampleFile: r.exampleFile,
    })),
  );
});

app.get('/api/rooms/:id', async (req, res) => {
  try {
    const room = ROOMS[req.params.id];
    if (!room) return res.status(404).json({ error: 'unknown room' });
    const expected = parseEnvExample(room.exampleFile);
    const data = await readVaultData(room.vaultPath);
    const present = Object.keys(data).filter((k) => k !== '_seed');
    const presentSet = new Set(present);
    const expectedSet = new Set(expected);
    const missing = expected.filter((k) => !presentSet.has(k));
    const extra = present.filter((k) => !expectedSet.has(k));
    const values = {};
    for (const k of present) {
      const v = data[k];
      values[k] = typeof v === 'string' && v.length > 0 ? '••••••••' : '';
    }
    res.json({
      id: req.params.id,
      label: room.label,
      expected,
      present,
      missing,
      extra,
      values,
      exampleExists: fs.existsSync(room.exampleFile),
    });
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message });
  }
});

app.put('/api/rooms/:id/keys', async (req, res) => {
  try {
    const room = ROOMS[req.params.id];
    if (!room) return res.status(404).json({ error: 'unknown room' });
    const { key, value } = req.body || {};
    if (!key || typeof key !== 'string') {
      return res.status(400).json({ error: 'key required' });
    }
    if (typeof value !== 'string') {
      return res.status(400).json({ error: 'value must be string' });
    }
    await writeVaultData(room.vaultPath, { [key]: value });
    res.json({ ok: true, key });
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message });
  }
});

app.post('/api/rooms/:id/keys/bulk', async (req, res) => {
  try {
    const room = ROOMS[req.params.id];
    if (!room) return res.status(404).json({ error: 'unknown room' });
    const pairs = req.body?.pairs;
    if (!pairs || typeof pairs !== 'object') {
      return res.status(400).json({ error: 'pairs object required' });
    }
    await writeVaultData(room.vaultPath, pairs);
    res.json({ ok: true, count: Object.keys(pairs).length });
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message });
  }
});

async function triggerJenkinsApply(target) {
  if (!JENKINS_PASS) {
    throw new Error('JENKINS_ADMIN_PASS not set — cannot trigger apply-vault-env');
  }
  const auth = Buffer.from(`${JENKINS_USER}:${JENKINS_PASS}`).toString('base64');
  const crumbRes = await fetch(`${JENKINS_URL}/crumbIssuer/api/json`, {
    headers: { Authorization: `Basic ${auth}` },
  });
  let crumbField = '';
  let crumbValue = '';
  if (crumbRes.ok) {
    const crumbJson = await crumbRes.json();
    crumbField = crumbJson.crumbRequestField || '';
    crumbValue = crumbJson.crumb || '';
  }
  const headers = {
    Authorization: `Basic ${auth}`,
    'Content-Type': 'application/x-www-form-urlencoded',
  };
  if (crumbField && crumbValue) headers[crumbField] = crumbValue;

  const body = new URLSearchParams({ TARGET: target }).toString();
  const res = await fetch(
    `${JENKINS_URL}/job/apply-vault-env/buildWithParameters`,
    { method: 'POST', headers, body },
  );
  if (![200, 201, 302].includes(res.status)) {
    const t = await res.text();
    throw new Error(`Jenkins apply-vault-env HTTP ${res.status}: ${t.slice(0, 300)}`);
  }
  return `Triggered Jenkins job apply-vault-env TARGET=${target}. Watch: ${JENKINS_URL}/job/apply-vault-env/`;
}

app.post('/api/apply', async (req, res) => {
  try {
    const target = req.body?.target || 'both';
    // Prefer Jenkins (has Docker + Vault CLI on agent); fall back to local script.
    if (JENKINS_PASS) {
      const output = await triggerJenkinsApply(target);
      return res.json({ ok: true, output });
    }
    const script = path.join(DEVOPS_ROOT, 'scripts/vault-apply-collaboration.sh');
    if (!fs.existsSync(script)) {
      return res.status(500).json({ error: `missing ${script} and no Jenkins creds` });
    }
    const out = await runScript(script, { TARGET: target });
    res.json({ ok: true, output: out });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Secrets Room listening on :${PORT}`);
  console.log(`Vault: ${VAULT_ADDR} token=${VAULT_TOKEN ? 'set' : 'MISSING'}`);
});
