(() => {
  let rooms = [];
  let activeId = 'backend';
  let snapshot = null;

  const tabsEl = document.getElementById('tabs');
  const missingList = document.getElementById('missing-list');
  const presentList = document.getElementById('present-list');
  const meta = document.getElementById('meta');
  const suggestions = document.getElementById('key-suggestions');
  const banner = document.getElementById('banner');
  const health = document.getElementById('health');
  const keyInput = document.getElementById('key-input');
  const valueInput = document.getElementById('value-input');

  function showBanner(text, isError) {
    banner.hidden = !text;
    banner.textContent = text || '';
    banner.classList.toggle('error', Boolean(isError));
  }

  async function api(path, opts) {
    const res = await fetch(path, {
      headers: { 'Content-Type': 'application/json' },
      ...opts,
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(data.error || res.statusText);
    return data;
  }

  function renderTabs() {
    tabsEl.innerHTML = '';
    for (const r of rooms) {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.textContent = r.label;
      btn.classList.toggle('active', r.id === activeId);
      btn.addEventListener('click', () => {
        activeId = r.id;
        renderTabs();
        loadRoom();
      });
      tabsEl.appendChild(btn);
    }
  }

  function renderRoom() {
    if (!snapshot) return;
    missingList.innerHTML = '';
    presentList.innerHTML = '';
    suggestions.innerHTML = '';

    meta.textContent = [
      `${snapshot.present.length} in Vault`,
      `${snapshot.missing.length} missing`,
      `${snapshot.extra.length} extra`,
      snapshot.exampleExists ? 'example found' : 'WARNING: .env.example missing',
    ].join(' · ');

    for (const k of snapshot.missing) {
      const li = document.createElement('li');
      li.className = 'missing';
      li.textContent = k;
      li.title = 'Click to fill form';
      li.addEventListener('click', () => {
        keyInput.value = k;
        valueInput.focus();
      });
      missingList.appendChild(li);
    }
    if (!snapshot.missing.length) {
      const li = document.createElement('li');
      li.textContent = 'None — all example keys present';
      missingList.appendChild(li);
    }

    for (const k of snapshot.present) {
      const li = document.createElement('li');
      if (snapshot.extra.includes(k)) li.className = 'extra';
      li.textContent = `${k} = ${snapshot.values[k] || '(empty)'}`;
      li.addEventListener('click', () => {
        keyInput.value = k;
        valueInput.value = '';
        valueInput.placeholder = 'Enter new value to overwrite';
        valueInput.focus();
      });
      presentList.appendChild(li);
    }

    const all = [...new Set([...snapshot.expected, ...snapshot.present])];
    for (const k of all) {
      const opt = document.createElement('option');
      opt.value = k;
      suggestions.appendChild(opt);
    }
  }

  async function loadRoom() {
    showBanner('');
    snapshot = await api(`/api/rooms/${activeId}`);
    renderRoom();
  }

  async function boot() {
    try {
      const h = await api('/api/health');
      health.textContent = `Vault ${h.vaultAddr} · token ${h.hasToken ? 'ok' : 'MISSING'} · source ${h.collabSource}`;
      rooms = await api('/api/rooms');
      if (!rooms.length) throw new Error('No rooms');
      activeId = rooms[0].id;
      renderTabs();
      await loadRoom();
    } catch (e) {
      showBanner(e.message, true);
    }
  }

  document.getElementById('btn-refresh').addEventListener('click', () => {
    loadRoom().catch((e) => showBanner(e.message, true));
  });

  document.getElementById('btn-apply').addEventListener('click', async () => {
    showBanner('Applying… exporting Vault → env files and recreating containers…');
    try {
      const result = await api('/api/apply', {
        method: 'POST',
        body: JSON.stringify({ target: 'both' }),
      });
      showBanner(result.output || 'Applied.');
    } catch (e) {
      showBanner(e.message, true);
    }
  });

  document.getElementById('upsert-form').addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const key = keyInput.value.trim();
    const value = valueInput.value;
    try {
      await api(`/api/rooms/${activeId}/keys`, {
        method: 'PUT',
        body: JSON.stringify({ key, value }),
      });
      valueInput.value = '';
      showBanner(`Saved ${key} to Vault`);
      await loadRoom();
    } catch (e) {
      showBanner(e.message, true);
    }
  });

  boot();
})();
