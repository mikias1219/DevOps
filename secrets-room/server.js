#!/usr/bin/env node
/**
 * Secrets Room — project-scoped Vault + env file management UI.
 */
'use strict';

const express = require('express');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
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

/** Project registry: each project has multiple env files (Vault path + disk path). */
const PROJECTS = {
  collaboration: {
    id: 'collaboration',
    label: 'Collaboration',
    description: 'Selamnew Collaboration — NestJS API + Next.js frontend',
    accent: '#14b8a6',
    applyTarget: 'both',
    envFiles: {
      backend: {
        id: 'backend',
        label: 'Backend',
        subtitle: 'NestJS API runtime',
        vaultPath: 'secret/data/collaboration/backend',
        exampleFile: path.join(COLLAB_SOURCE, 'backend/.env.example'),
        envFile: path.join(DEVOPS_ROOT, 'collaboration/env/backend.env'),
        applyTarget: 'backend',
      },
      frontend: {
        id: 'frontend',
        label: 'Frontend',
        subtitle: 'Next.js app runtime',
        vaultPath: 'secret/data/collaboration/frontend',
        exampleFile: path.join(COLLAB_SOURCE, 'frontend/.env.example'),
        envFile: path.join(DEVOPS_ROOT, 'collaboration/env/frontend.env'),
        applyTarget: 'frontend',
      },
      compose: {
        id: 'compose',
        label: 'Compose',
        subtitle: 'Docker paths, branches, ports',
        vaultPath: 'secret/data/collaboration/compose',
        exampleFile: path.join(DEVOPS_ROOT, 'collaboration/.env.docker.example'),
        envFile: path.join(DEVOPS_ROOT, 'collaboration/.env.docker'),
        applyTarget: 'both',
      },
    },
  },
};

function parseEnvFile(filePath) {
  /** @type {Record<string, string>} */
  const data = {};
  if (!fs.existsSync(filePath)) return data;
  const text = fs.readFileSync(filePath, 'utf8');
  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const cleaned = line.replace(/^export\s+/, '');
    if (!cleaned.includes('=')) continue;
    const eq = cleaned.indexOf('=');
    const key = cleaned.slice(0, eq).trim();
    let value = cleaned.slice(eq + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (key) data[key] = value;
  }
  return data;
}

function parseEnvExampleKeys(filePath) {
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

function maskValue(value) {
  if (value == null || value === '') return '';
  return '••••••••';
}

function writeEnvFile(filePath, data) {
  const keys = Object.keys(data)
    .filter((k) => k !== '_seed')
    .sort();
  const lines = keys.map((k) => `${k}=${data[k] ?? ''}`);
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, lines.join('\n') + (lines.length ? '\n' : ''), 'utf8');
  try {
    fs.chmodSync(filePath, 0o600);
  } catch {
    /* ignore on some mounts */
  }
}

function getProject(projectId) {
  return PROJECTS[projectId] || null;
}

function getEnvFile(projectId, envId) {
  const project = getProject(projectId);
  if (!project) return null;
  return project.envFiles[envId] || null;
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
  const current = await readVaultData(vaultPath);
  const merged = { ...current, ...data };
  delete merged._seed;
  await vaultRequest('POST', vaultPath, { data: merged });
  return merged;
}

function buildKeyRows(vaultData, envData, expectedKeys) {
  const vaultKeys = Object.keys(vaultData).filter((k) => k !== '_seed');
  const envKeys = Object.keys(envData);
  const allKeys = [...new Set([...expectedKeys, ...vaultKeys, ...envKeys])].sort();

  return allKeys.map((key) => {
    const inVault = Object.prototype.hasOwnProperty.call(vaultData, key);
    const inEnv = Object.prototype.hasOwnProperty.call(envData, key);
    const inExample = expectedKeys.includes(key);
    const vaultVal = inVault ? vaultData[key] : undefined;
    const envVal = inEnv ? envData[key] : undefined;

    let status = 'optional';
    if (inExample && !inVault) status = 'missing_vault';
    else if (inVault && !inEnv) status = 'missing_env';
    else if (inVault && inEnv && String(vaultVal ?? '') !== String(envVal ?? '')) status = 'drift';
    else if (inVault && inEnv) status = 'synced';
    else if (inVault && !inExample) status = 'extra_vault';

    return {
      key,
      status,
      inExample,
      inVault,
      inEnv,
      vaultValue: maskValue(vaultVal),
      envValue: maskValue(envVal),
      vaultEmpty: inVault && (vaultVal == null || vaultVal === ''),
      envEmpty: inEnv && (envVal == null || envVal === ''),
    };
  });
}

async function buildEnvSnapshot(projectId, envId) {
  const envCfg = getEnvFile(projectId, envId);
  if (!envCfg) {
    const err = new Error('unknown env file');
    err.status = 404;
    throw err;
  }

  const expected = parseEnvExampleKeys(envCfg.exampleFile);
  const vaultData = await readVaultData(envCfg.vaultPath);
  const envData = parseEnvFile(envCfg.envFile);
  const keys = buildKeyRows(vaultData, envData, expected);

  const stats = {
    expected: expected.length,
    vault: Object.keys(vaultData).filter((k) => k !== '_seed').length,
    env: Object.keys(envData).length,
    missingVault: keys.filter((k) => k.status === 'missing_vault').length,
    missingEnv: keys.filter((k) => k.status === 'missing_env').length,
    drift: keys.filter((k) => k.status === 'drift').length,
    synced: keys.filter((k) => k.status === 'synced').length,
  };

  return {
    projectId,
    envId,
    label: envCfg.label,
    subtitle: envCfg.subtitle,
    vaultPath: envCfg.vaultPath,
    exampleFile: envCfg.exampleFile,
    envFile: envCfg.envFile,
    exampleExists: fs.existsSync(envCfg.exampleFile),
    envExists: fs.existsSync(envCfg.envFile),
    applyTarget: envCfg.applyTarget,
    stats,
    keys,
  };
}

async function buildProjectSummary(projectId) {
  const project = getProject(projectId);
  if (!project) return null;

  const envFiles = [];
  let totalMissing = 0;
  let totalDrift = 0;

  for (const [envId, cfg] of Object.entries(project.envFiles)) {
    try {
      const snap = await buildEnvSnapshot(projectId, envId);
      totalMissing += snap.stats.missingVault;
      totalDrift += snap.stats.drift + snap.stats.missingEnv;
      envFiles.push({
        id: envId,
        label: cfg.label,
        subtitle: cfg.subtitle,
        stats: snap.stats,
        vaultPath: cfg.vaultPath,
        envFile: cfg.envFile,
      });
    } catch {
      envFiles.push({
        id: envId,
        label: cfg.label,
        subtitle: cfg.subtitle,
        stats: null,
        vaultPath: cfg.vaultPath,
        envFile: cfg.envFile,
      });
    }
  }

  return {
    id: project.id,
    label: project.label,
    description: project.description,
    accent: project.accent,
    applyTarget: project.applyTarget,
    envFiles,
    totalMissing,
    totalDrift,
  };
}

const COOKIE_NAME = 'sr_session';
const SESSION_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const SESSION_SECRET = process.env.ROOM_SESSION_SECRET
  || crypto.createHash('sha256').update(`secrets-room:${BASIC_USER}:${BASIC_PASS}`).digest('hex');

function parseCookies(req) {
  const out = {};
  for (const part of String(req.headers.cookie || '').split(';')) {
    const i = part.indexOf('=');
    if (i < 1) continue;
    out[part.slice(0, i).trim()] = decodeURIComponent(part.slice(i + 1).trim());
  }
  return out;
}

function signSession(payload) {
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const sig = crypto.createHmac('sha256', SESSION_SECRET).update(body).digest('base64url');
  return `${body}.${sig}`;
}

function readSession(token) {
  if (!token || !token.includes('.')) return null;
  const [body, sig] = token.split('.');
  const expect = crypto.createHmac('sha256', SESSION_SECRET).update(body).digest('base64url');
  const a = Buffer.from(sig);
  const b = Buffer.from(expect);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  try {
    const data = JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
    if (!data || data.exp < Date.now()) return null;
    return data;
  } catch {
    return null;
  }
}

function setSessionCookie(res, token, maxAgeSec) {
  res.setHeader(
    'Set-Cookie',
    `${COOKIE_NAME}=${token}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${maxAgeSec}`,
  );
}

function safeEqual(a, b) {
  const ba = Buffer.from(String(a));
  const bb = Buffer.from(String(b));
  if (ba.length !== bb.length) return false;
  return crypto.timingSafeEqual(ba, bb);
}

function isPublicPath(req) {
  const p = req.path;
  return (
    p === '/login.html'
    || p === '/styles.css'
    ||     p === '/api/login'
    || p === '/api/logout'
    || p === '/favicon.ico'
  );
}

function requireLogin(req, res, next) {
  if (!BASIC_PASS) return next();
  if (isPublicPath(req)) return next();
  const sess = readSession(parseCookies(req)[COOKIE_NAME]);
  if (sess) {
    req.user = sess.u;
    return next();
  }
  if (req.path.startsWith('/api/')) {
    return res.status(401).json({ error: 'login required' });
  }
  return res.redirect('/login.html');
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
  const res = await fetch(`${JENKINS_URL}/job/apply-vault-env/buildWithParameters`, {
    method: 'POST',
    headers,
    body,
  });
  if (![200, 201, 302].includes(res.status)) {
    const t = await res.text();
    throw new Error(`Jenkins apply-vault-env HTTP ${res.status}: ${t.slice(0, 300)}`);
  }
  return `Triggered Jenkins job apply-vault-env TARGET=${target}. Watch: ${JENKINS_URL}/job/apply-vault-env/`;
}

const app = express();
app.use(express.json({ limit: '2mb' }));
app.use(express.urlencoded({ extended: true }));

app.post('/api/login', (req, res) => {
  const user = String((req.body && req.body.username) || '').trim();
  const pass = String((req.body && req.body.password) || '');
  if (!BASIC_PASS || !safeEqual(user, BASIC_USER) || !safeEqual(pass, BASIC_PASS)) {
    return res.status(401).json({ error: 'Invalid username or password' });
  }
  const token = signSession({ u: user, exp: Date.now() + SESSION_TTL_MS });
  setSessionCookie(res, token, Math.floor(SESSION_TTL_MS / 1000));
  res.json({ ok: true });
});

app.post('/api/logout', (_req, res) => {
  setSessionCookie(res, '', 0);
  res.json({ ok: true });
});

app.use(requireLogin);
app.use(express.static(path.join(__dirname, 'public')));

app.get('/api/health', (_req, res) => {
  res.json({
    ok: true,
    vaultAddr: VAULT_ADDR,
    hasToken: Boolean(VAULT_TOKEN),
    collabSource: COLLAB_SOURCE,
    devopsRoot: DEVOPS_ROOT,
  });
});

app.get('/api/projects', async (_req, res) => {
  try {
    const projects = [];
    for (const id of Object.keys(PROJECTS)) {
      projects.push(await buildProjectSummary(id));
    }
    res.json(projects);
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message });
  }
});

app.get('/api/projects/:projectId', async (req, res) => {
  try {
    const summary = await buildProjectSummary(req.params.projectId);
    if (!summary) return res.status(404).json({ error: 'unknown project' });
    res.json(summary);
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message });
  }
});

app.get('/api/projects/:projectId/env/:envId', async (req, res) => {
  try {
    const snap = await buildEnvSnapshot(req.params.projectId, req.params.envId);
    res.json(snap);
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message });
  }
});

app.put('/api/projects/:projectId/env/:envId/keys', async (req, res) => {
  try {
    const envCfg = getEnvFile(req.params.projectId, req.params.envId);
    if (!envCfg) return res.status(404).json({ error: 'unknown env file' });
    const { key, value } = req.body || {};
    if (!key || typeof key !== 'string') {
      return res.status(400).json({ error: 'key required' });
    }
    if (typeof value !== 'string') {
      return res.status(400).json({ error: 'value must be string' });
    }
    await writeVaultData(envCfg.vaultPath, { [key]: value });
    res.json({ ok: true, key });
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message });
  }
});

app.post('/api/projects/:projectId/env/:envId/keys/bulk', async (req, res) => {
  try {
    const envCfg = getEnvFile(req.params.projectId, req.params.envId);
    if (!envCfg) return res.status(404).json({ error: 'unknown env file' });
    const pairs = req.body?.pairs;
    if (!pairs || typeof pairs !== 'object') {
      return res.status(400).json({ error: 'pairs object required' });
    }
    await writeVaultData(envCfg.vaultPath, pairs);
    res.json({ ok: true, count: Object.keys(pairs).length });
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message });
  }
});

app.delete('/api/projects/:projectId/env/:envId/keys/:key', async (req, res) => {
  try {
    const envCfg = getEnvFile(req.params.projectId, req.params.envId);
    if (!envCfg) return res.status(404).json({ error: 'unknown env file' });
    const current = await readVaultData(envCfg.vaultPath);
    delete current[req.params.key];
    delete current._seed;
    await vaultRequest('POST', envCfg.vaultPath, { data: current });
    res.json({ ok: true, key: req.params.key });
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message });
  }
});

app.post('/api/projects/:projectId/env/:envId/import-from-file', async (req, res) => {
  try {
    const envCfg = getEnvFile(req.params.projectId, req.params.envId);
    if (!envCfg) return res.status(404).json({ error: 'unknown env file' });
    if (!fs.existsSync(envCfg.envFile)) {
      return res.status(404).json({ error: `env file not found: ${envCfg.envFile}` });
    }
    const data = parseEnvFile(envCfg.envFile);
    const count = Object.keys(data).length;
    await writeVaultData(envCfg.vaultPath, data);
    res.json({ ok: true, count, message: `Imported ${count} keys from disk → Vault` });
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message });
  }
});

app.post('/api/projects/:projectId/env/:envId/export-to-file', async (req, res) => {
  try {
    const envCfg = getEnvFile(req.params.projectId, req.params.envId);
    if (!envCfg) return res.status(404).json({ error: 'unknown env file' });
    const vaultData = await readVaultData(envCfg.vaultPath);
    const clean = { ...vaultData };
    delete clean._seed;
    writeEnvFile(envCfg.envFile, clean);
    res.json({
      ok: true,
      count: Object.keys(clean).length,
      message: `Exported ${Object.keys(clean).length} keys from Vault → ${envCfg.envFile}`,
    });
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message });
  }
});

app.post('/api/apply', async (req, res) => {
  try {
    const target = req.body?.target || 'both';
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

// Legacy API (backward compatible)
app.get('/api/rooms', async (_req, res) => {
  const collab = PROJECTS.collaboration;
  res.json(
    Object.entries(collab.envFiles)
      .filter(([id]) => id !== 'compose')
      .map(([id, cfg]) => ({
        id,
        label: `${collab.label} ${cfg.label}`,
        vaultPath: cfg.vaultPath,
        exampleFile: cfg.exampleFile,
      })),
  );
});

app.get('/api/rooms/:id', async (req, res) => {
  try {
    if (!PROJECTS.collaboration.envFiles[req.params.id]) {
      return res.status(404).json({ error: 'unknown room' });
    }
    const snap = await buildEnvSnapshot('collaboration', req.params.id);
    res.json({
      id: req.params.id,
      label: snap.label,
      expected: snap.keys.filter((k) => k.inExample).map((k) => k.key),
      present: snap.keys.filter((k) => k.inVault).map((k) => k.key),
      missing: snap.keys.filter((k) => k.status === 'missing_vault').map((k) => k.key),
      extra: snap.keys.filter((k) => k.status === 'extra_vault').map((k) => k.key),
      values: Object.fromEntries(
        snap.keys.filter((k) => k.inVault).map((k) => [k.key, k.vaultValue]),
      ),
      exampleExists: snap.exampleExists,
    });
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message });
  }
});

app.put('/api/rooms/:id/keys', async (req, res) => {
  req.params.projectId = 'collaboration';
  req.params.envId = req.params.id;
  const envCfg = getEnvFile('collaboration', req.params.id);
  if (!envCfg) return res.status(404).json({ error: 'unknown room' });
  try {
    const { key, value } = req.body || {};
    if (!key || typeof key !== 'string') return res.status(400).json({ error: 'key required' });
    if (typeof value !== 'string') return res.status(400).json({ error: 'value must be string' });
    await writeVaultData(envCfg.vaultPath, { [key]: value });
    res.json({ ok: true, key });
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message });
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Secrets Room listening on :${PORT}`);
  console.log(`Vault: ${VAULT_ADDR} token=${VAULT_TOKEN ? 'set' : 'MISSING'}`);
});
