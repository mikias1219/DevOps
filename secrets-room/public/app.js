(() => {
  /** @type {Array<any>} */
  let projects = [];
  let activeProjectId = 'collaboration';
  let activeEnvId = 'backend';
  /** @type {any} */
  let snapshot = null;
  let filterStatus = 'all';
  let searchQuery = '';

  const $ = (id) => document.getElementById(id);

  const els = {
    projectNav: $('project-nav'),
    vaultStatus: $('vault-status'),
    projectEyebrow: $('project-eyebrow'),
    projectTitle: $('project-title'),
    projectDesc: $('project-desc'),
    envTabs: $('env-tabs'),
    statsGrid: $('stats-grid'),
    keysBody: $('keys-body'),
    keysMeta: $('keys-meta'),
    keyInput: $('key-input'),
    valueInput: $('value-input'),
    suggestions: $('key-suggestions'),
    pathsList: $('paths-list'),
    toast: $('toast'),
    searchInput: $('search-input'),
    filterChips: $('filter-chips'),
    editorTitle: $('editor-title'),
  };

  function showToast(text, isError = false) {
    els.toast.hidden = !text;
    els.toast.textContent = text || '';
    els.toast.classList.toggle('error', isError);
    if (text && !isError) {
      setTimeout(() => {
        if (els.toast.textContent === text) els.toast.hidden = true;
      }, 6000);
    }
  }

  const API_ROOT = location.pathname.startsWith('/secrets') ? '/secrets' : '';

  async function api(path, opts = {}) {
    const res = await fetch(API_ROOT + path, {
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json' },
      ...opts,
    });
    if (res.status === 401) {
      location.href = API_ROOT + '/login.html';
      throw new Error('login required');
    }
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(data.error || res.statusText);
    return data;
  }

  function activeProject() {
    return projects.find((p) => p.id === activeProjectId);
  }

  function statusLabel(status) {
    const map = {
      missing_vault: 'Missing in Vault',
      missing_env: 'Missing on disk',
      drift: 'Drift',
      synced: 'Synced',
      extra_vault: 'Extra in Vault',
      optional: 'Optional',
    };
    return map[status] || status;
  }

  function renderVaultStatus(health) {
    const wrap = els.vaultStatus;
    wrap.classList.toggle('ok', health.ok && health.hasToken);
    wrap.classList.toggle('err', !health.ok || !health.hasToken);
    wrap.querySelector('.status-text').textContent = health.hasToken
      ? `Vault ${health.vaultAddr.replace(/^https?:\/\//, '')}`
      : 'Vault token missing';
  }

  function renderProjectNav() {
    els.projectNav.innerHTML = '';
    for (const p of projects) {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = `project-btn${p.id === activeProjectId ? ' active' : ''}`;
      btn.innerHTML = `
        <span class="project-dot" style="background:${p.accent}"></span>
        <span class="project-info">
          <span class="project-name">${esc(p.label)}</span>
          <span class="project-meta">${esc(p.description)}</span>
        </span>
        <span class="project-badges">
          ${p.totalMissing ? `<span class="badge badge-warn">${p.totalMissing}</span>` : ''}
          ${p.totalDrift ? `<span class="badge badge-danger">${p.totalDrift}</span>` : ''}
        </span>
      `;
      btn.addEventListener('click', () => {
        activeProjectId = p.id;
        activeEnvId = p.envFiles[0]?.id || 'backend';
        renderProjectNav();
        renderProjectHeader();
        renderEnvTabs();
        loadEnv().catch((e) => showToast(e.message, true));
      });
      els.projectNav.appendChild(btn);
    }
  }

  function renderProjectHeader() {
    const p = activeProject();
    if (!p) return;
    els.projectEyebrow.textContent = 'Project';
    els.projectTitle.textContent = p.label;
    els.projectDesc.textContent = p.description;
  }

  function renderEnvTabs() {
    const p = activeProject();
    if (!p) return;
    els.envTabs.innerHTML = '';
    for (const ef of p.envFiles) {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = `env-tab${ef.id === activeEnvId ? ' active' : ''}`;
      const s = ef.stats;
      const warn = s?.missingVault ? `<span class="mini-stat warn">${s.missingVault} missing</span>` : '';
      const drift =
        s && (s.drift || s.missingEnv)
          ? `<span class="mini-stat drift">${s.drift + s.missingEnv} drift</span>`
          : '';
      const ok = s?.synced ? `<span class="mini-stat ok">${s.synced} synced</span>` : '';
      btn.innerHTML = `
        <span class="env-tab-label">${esc(ef.label)}</span>
        <span class="env-tab-sub">${esc(ef.subtitle || '')}</span>
        <span class="env-tab-stats">${warn}${drift}${ok}</span>
      `;
      btn.addEventListener('click', () => {
        activeEnvId = ef.id;
        renderEnvTabs();
        loadEnv().catch((e) => showToast(e.message, true));
      });
      els.envTabs.appendChild(btn);
    }
  }

  function renderStats() {
    if (!snapshot?.stats) {
      els.statsGrid.innerHTML = '';
      return;
    }
    const s = snapshot.stats;
    els.statsGrid.innerHTML = `
      <div class="stat-card"><div class="stat-label">Expected keys</div><div class="stat-value">${s.expected}</div></div>
      <div class="stat-card"><div class="stat-label">In Vault</div><div class="stat-value">${s.vault}</div></div>
      <div class="stat-card"><div class="stat-label">On disk</div><div class="stat-value">${s.env}</div></div>
      <div class="stat-card"><div class="stat-label">Missing in Vault</div><div class="stat-value${s.missingVault ? ' warn' : ''}">${s.missingVault}</div></div>
      <div class="stat-card"><div class="stat-label">Drift / not exported</div><div class="stat-value${s.drift + s.missingEnv ? ' drift' : ''}">${s.drift + s.missingEnv}</div></div>
      <div class="stat-card"><div class="stat-label">Synced</div><div class="stat-value${s.synced ? ' ok' : ''}">${s.synced}</div></div>
    `;
  }

  function filteredKeys() {
    if (!snapshot?.keys) return [];
    return snapshot.keys.filter((row) => {
      if (filterStatus !== 'all' && row.status !== filterStatus) return false;
      if (searchQuery && !row.key.toLowerCase().includes(searchQuery.toLowerCase())) return false;
      return true;
    });
  }

  function renderKeysTable() {
    const rows = filteredKeys();
    els.keysMeta.textContent = `${rows.length} shown · ${snapshot?.keys?.length || 0} total`;
    els.keysBody.innerHTML = '';

    if (!rows.length) {
      const tr = document.createElement('tr');
      tr.className = 'empty-row';
      tr.innerHTML = `<td colspan="5">No keys match the current filter</td>`;
      els.keysBody.appendChild(tr);
      return;
    }

    for (const row of rows) {
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td><span class="key-name">${esc(row.key)}</span></td>
        <td><span class="status-pill ${row.status}">${statusLabel(row.status)}</span></td>
        <td><span class="key-val${row.vaultEmpty ? ' empty' : ''}">${row.inVault ? esc(row.vaultValue || '(empty)') : '—'}</span></td>
        <td><span class="key-val${row.envEmpty ? ' empty' : ''}">${row.inEnv ? esc(row.envValue || '(empty)') : '—'}</span></td>
        <td>
          <button type="button" class="icon-btn btn-edit" title="Edit" aria-label="Edit ${esc(row.key)}">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/><path d="M18.5 2.5a2.12 2.12 0 013 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
          </button>
        </td>
      `;
      tr.addEventListener('click', (ev) => {
        if (ev.target.closest('.icon-btn')) return;
        selectKey(row.key);
      });
      tr.querySelector('.btn-edit').addEventListener('click', (ev) => {
        ev.stopPropagation();
        selectKey(row.key);
      });
      els.keysBody.appendChild(tr);
    }

    els.suggestions.innerHTML = '';
    const allKeys = [...new Set(snapshot.keys.map((k) => k.key))];
    for (const k of allKeys) {
      const opt = document.createElement('option');
      opt.value = k;
      els.suggestions.appendChild(opt);
    }
  }

  function renderPaths() {
    if (!snapshot) return;
    els.pathsList.innerHTML = `
      <dt>Vault path</dt>
      <dd>${esc(snapshot.vaultPath)}</dd>
      <dt>Env file</dt>
      <dd>${esc(snapshot.envFile)}${snapshot.envExists ? '' : ' (not found)'}</dd>
      <dt>Example template</dt>
      <dd>${esc(snapshot.exampleFile)}${snapshot.exampleExists ? '' : ' (not found)'}</dd>
    `;
  }

  function selectKey(key) {
    els.keyInput.value = key;
    els.valueInput.value = '';
    els.valueInput.placeholder = 'Enter new value to save to Vault';
    els.editorTitle.textContent = `Edit: ${key}`;
    els.valueInput.focus();
  }

  function esc(str) {
    return String(str ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  async function loadProjects() {
    projects = await api('/api/projects');
    if (!projects.length) throw new Error('No projects configured');
    if (!projects.find((p) => p.id === activeProjectId)) {
      activeProjectId = projects[0].id;
    }
    const p = activeProject();
    if (!p.envFiles.find((e) => e.id === activeEnvId)) {
      activeEnvId = p.envFiles[0]?.id || 'backend';
    }
    renderProjectNav();
    renderProjectHeader();
    renderEnvTabs();
  }

  async function loadEnv() {
    showToast('');
    snapshot = await api(`/api/projects/${activeProjectId}/env/${activeEnvId}`);
    renderStats();
    renderKeysTable();
    renderPaths();
    await loadProjects();
    renderEnvTabs();
  }

  async function boot() {
    try {
      const health = await api('/api/health');
      renderVaultStatus(health);
      await loadProjects();
      await loadEnv();
    } catch (e) {
      showToast(e.message, true);
      renderVaultStatus({ ok: false, hasToken: false, vaultAddr: '' });
    }
  }

  $('btn-refresh').addEventListener('click', () => {
    boot().catch((e) => showToast(e.message, true));
  });

  $('btn-apply-project').addEventListener('click', async () => {
    const p = activeProject();
    const target = snapshot?.applyTarget || p?.applyTarget || 'both';
    showToast(`Applying ${p?.label || activeProjectId} (TARGET=${target})…`);
    try {
      const result = await api('/api/apply', {
        method: 'POST',
        body: JSON.stringify({ target }),
      });
      showToast(result.output || 'Apply triggered successfully.');
      await loadEnv();
    } catch (e) {
      showToast(e.message, true);
    }
  });

  $('btn-import-file').addEventListener('click', async () => {
    if (!confirm('Import all keys from the env file on disk into Vault?')) return;
    try {
      const result = await api(
        `/api/projects/${activeProjectId}/env/${activeEnvId}/import-from-file`,
        { method: 'POST' },
      );
      showToast(result.message || 'Imported.');
      await loadEnv();
    } catch (e) {
      showToast(e.message, true);
    }
  });

  $('btn-export-file').addEventListener('click', async () => {
    if (!confirm('Export Vault keys to the env file on disk? (Does not restart containers)')) return;
    try {
      const result = await api(
        `/api/projects/${activeProjectId}/env/${activeEnvId}/export-to-file`,
        { method: 'POST' },
      );
      showToast(result.message || 'Exported.');
      await loadEnv();
    } catch (e) {
      showToast(e.message, true);
    }
  });

  $('key-form').addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const key = els.keyInput.value.trim();
    const value = els.valueInput.value;
    if (!key) return;
    try {
      await api(`/api/projects/${activeProjectId}/env/${activeEnvId}/keys`, {
        method: 'PUT',
        body: JSON.stringify({ key, value }),
      });
      els.valueInput.value = '';
      els.editorTitle.textContent = 'Add / update key';
      showToast(`Saved ${key} to Vault`);
      await loadEnv();
    } catch (e) {
      showToast(e.message, true);
    }
  });

  $('btn-clear-form').addEventListener('click', () => {
    els.keyInput.value = '';
    els.valueInput.value = '';
    els.editorTitle.textContent = 'Add / update key';
  });

  els.searchInput.addEventListener('input', () => {
    searchQuery = els.searchInput.value.trim();
    renderKeysTable();
  });

  els.filterChips.addEventListener('click', (ev) => {
    const chip = ev.target.closest('.chip');
    if (!chip) return;
    filterStatus = chip.dataset.filter || 'all';
    els.filterChips.querySelectorAll('.chip').forEach((c) => c.classList.remove('active'));
    chip.classList.add('active');
    renderKeysTable();
  });

  const logoutBtn = $('btn-logout');
  if (logoutBtn) {
    logoutBtn.addEventListener('click', async () => {
      const root = location.pathname.startsWith('/secrets') ? '/secrets' : '';
      await fetch(root + '/api/logout', { method: 'POST', credentials: 'same-origin' });
      location.href = root + '/login.html';
    });
  }

  boot();
})();
