'use strict';
// Read-only candidate-page geometry. Windows input belongs to the Computer Use runtime.
const fs=require('node:fs'),path=require('node:path'),http=require('node:http');
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
class CdpGeometry {
  constructor(projectRoot) { this.projectRoot = projectRoot; this.ports = []; }
  async discoverPort(timeoutMs) {
    const roots = [
      path.join(this.projectRoot, 'launcher', 'webview2_userdata'),
      path.join(this.projectRoot, 'launcher', 'webview2_overlay_userdata'),
    ];
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const found = new Set();
      for (const root of roots) {
        try {
          const walk = (dir, depth) => {
            if (depth > 3) return;
            for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
              const p = path.join(dir, entry.name);
              if (entry.isDirectory()) walk(p, depth + 1);
              else if (entry.name === 'DevToolsActivePort') {
                const content = fs.readFileSync(p, 'utf8').split(/\r?\n/);
                const port = Number(content[0]);
                if (Number.isInteger(port) && port > 0 && port < 65536) found.add(port);
              }
            }
          };
          if (fs.existsSync(root)) walk(root, 0);
        } catch (_e) {}
      }
      if (found.size > 0) {
        this.ports = [...found];
        return this.ports[0];
      }
      await sleep(500);
    }
    return null;
  }
  httpJson(port, route) {
    return new Promise((resolve, reject) => {
      const req = http.get({ host: '127.0.0.1', port, path: route, timeout: 5000 }, (res) => {
        let body = '';
        res.on('data', (c) => { body += c; });
        res.on('end', () => { try { resolve(JSON.parse(body)); } catch (e) { reject(e); } });
      });
      req.on('error', reject);
      req.on('timeout', () => { req.destroy(); reject(new Error('cdp http timeout')); });
    });
  }
  async listAllTargets() {
    const all = [];
    for (const port of this.ports) {
      try {
        const list = await this.httpJson(port, '/json/list');
        for (const t of list) all.push(t);
      } catch (_e) {}
    }
    return all;
  }
  // 所有 panel 都在同一页 overlay.local/overlay.html 内（#panel-content 内切换）。
  async findOverlayTarget() {
    const targets = await this.listAllTargets();
    return targets.find((t) => t.type === 'page'
      && typeof t.url === 'string' && t.url.includes('overlay.local/overlay.html')) || null;
  }
  async overlayEvaluate(expression) {
    const target = await this.findOverlayTarget();
    if (!target) return null;
    return this.evaluateOnTarget(target, expression);
  }
  // 选关页当前是否在 overlay 内激活（mod 测试空间按钮存在即激活）
  async findStageSelectTarget() {
    const target = await this.findOverlayTarget();
    if (!target) return null;
    const active = await this.evaluateOnTarget(target,
      `!!document.querySelector('#stage-select-mod-test-space,.stage-select-panel')`);
    return active ? target : null;
  }
  async evaluateOnTarget(target, expression) {
    const ws = new WebSocket(target.webSocketDebuggerUrl);
    try {
      await new Promise((resolve, reject) => {
        ws.onopen = resolve;
        ws.onerror = () => reject(new Error('cdp ws error'));
      });
      const id = 1;
      const result = await new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error('cdp evaluate timeout')), 8000);
        ws.onmessage = (ev) => {
          const msg = JSON.parse(ev.data);
          if (msg.id === id) { clearTimeout(timer); resolve(msg.result); }
        };
        ws.send(JSON.stringify({ id, method: 'Runtime.evaluate', params: {
          expression, returnByValue: true, awaitPromise: false } }));
      });
      if (result && result.exceptionDetails) return null;
      return result && result.result ? result.result.value : null;
    } finally {
      try { ws.close(); } catch (_e) {}
    }
  }
  async buttonRectByText(pattern) {
    const re = String(pattern).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    return this.overlayEvaluate(`(() => {
      const re = new RegExp(${JSON.stringify(re)});
      const els = [...document.querySelectorAll('.stage-select-nav-button,.stage-select-mod-btn,.stage-select-tab,button')];
      const el = els.find(b => re.test((b.textContent || '').trim()) && b.offsetWidth > 0 && b.offsetHeight > 0);
      if (!el) return null;
      const r = el.getBoundingClientRect();
      return { x: r.x, y: r.y, w: r.width, h: r.height,
        vw: window.innerWidth, vh: window.innerHeight, dpr: window.devicePixelRatio || 1,
        text: (el.textContent || '').trim().slice(0, 40) };
    })()`);
  }
  async mapRailCandidates() {
    return this.overlayEvaluate(`(() => {
      const rows = [...document.querySelectorAll('.map-rail-stage-select-btn')];
      if (!rows.length) return null;
      return rows.map(el => {
        const r = el.getBoundingClientRect();
        return { id: el.getAttribute('data-hotspot-id'),
          frame: el.getAttribute('data-stage-select-frame'),
          label: (el.getAttribute('aria-label') || el.textContent || '').trim().slice(0, 40),
          x: r.x, y: r.y, w: r.width, h: r.height,
          vw: window.innerWidth, vh: window.innerHeight };
      }).filter(r => r.w > 0 && r.h > 0);
    })()`);
  }
  async mapSceneItems() {
    return this.overlayEvaluate(`(() => {
      const rows = [...document.querySelectorAll('.map-rail-scene-item')];
      if (!rows.length) return null;
      return rows.map(el => {
        const r = el.getBoundingClientRect();
        return { id: el.getAttribute('data-hotspot-id'),
          label: (el.getAttribute('aria-label') || el.textContent || '').trim().slice(0, 30),
          disabled: el.classList.contains('is-disabled'),
          x: r.x, y: r.y, w: r.width, h: r.height,
          vw: window.innerWidth, vh: window.innerHeight };
      }).filter(r => r.w > 0 && r.h > 0 && !r.disabled);
    })()`);
  }
  async mapPageTabs() {
    return this.overlayEvaluate(`(() => {
      const tabs = [...document.querySelectorAll('.map-page-tab')];
      if (!tabs.length) return null;
      return tabs.map(el => {
        const r = el.getBoundingClientRect();
        const visible = el.offsetWidth > 0 && el.offsetHeight > 0 && getComputedStyle(el).display !== 'none';
        return { id: el.getAttribute('data-page-id'),
          label: (el.getAttribute('aria-label') || el.textContent || '').trim().slice(0, 30),
          active: el.classList.contains('is-active'),
          hidden: !visible,
          x: r.x, y: r.y, w: r.width, h: r.height,
          vw: window.innerWidth, vh: window.innerHeight };
      });
    })()`);
  }
  async mapFilters() {
    return this.overlayEvaluate(`(() => {
      const fs = [...document.querySelectorAll('.map-filter-hotspot')];
      if (!fs.length) return null;
      return fs.map(el => {
        const r = el.getBoundingClientRect();
        return { id: el.getAttribute('data-filter-id'),
          label: (el.getAttribute('aria-label') || '').slice(0, 50),
          active: el.classList.contains('is-active'),
          empty: el.classList.contains('is-empty'),
          locked: el.classList.contains('is-locked'),
          meta: el.getAttribute('data-filter-id') === 'all' || el.getAttribute('data-filter-id') === 'hierarchy',
          x: r.x, y: r.y, w: r.width, h: r.height,
          vw: window.innerWidth, vh: window.innerHeight };
      });
    })()`);
  }
  async mapDebugSnapshot() {
    return this.overlayEvaluate(`(() => {
      const pc = document.getElementById('panel-content');
      const rail = document.getElementById('map-rail-shell');
      const filters = [...document.querySelectorAll('.map-filter-hotspot')].map(b => ({
        id: b.getAttribute('data-filter-id'), label: (b.getAttribute('aria-label') || '').slice(0, 50),
        active: b.classList.contains('is-active'), empty: b.classList.contains('is-empty'),
        locked: b.classList.contains('is-locked') }));
      const sceneItems = [...document.querySelectorAll('.map-rail-scene-item')].map(b => ({
        label: (b.getAttribute('aria-label') || '').slice(0, 30),
        disabled: b.classList.contains('is-disabled') }));
      const stageBtns = [...document.querySelectorAll('.map-rail-stage-select-btn')].map(b => ({
        frame: b.getAttribute('data-stage-select-frame'), label: (b.getAttribute('aria-label') || '').slice(0, 40) }));
      const sceneLists = document.querySelectorAll('.map-rail-scene-list').length;
      return { url: location.href.slice(0, 120),
        panelChildren: [...(pc ? pc.children : [])].map(c => c.className || c.tagName),
        filters, sceneItems, stageBtns, sceneLists,
        railChildCount: rail ? rail.children.length : -1 };
    })()`);
  }
  async mapPageHasStageEntry() {
    // overlay 页内用 StageSelectData 真源计算哪些场景有选关入口。
    return this.overlayEvaluate(`(() => {
      if (typeof StageSelectData === 'undefined' || !StageSelectData) return { hasData: false };
      const m = (StageSelectData.exportManifest ? StageSelectData.exportManifest() : StageSelectData.getManifest());
      return { hasData: true, frames: (m.frames || []).map(f => f.frameLabel).filter(Boolean),
        frameOrder: m.frameOrder || [] };
    })()`);
  }
  async bootstrapAdmission() {
    const target = (await this.listAllTargets()).find(t => t.type === 'page' && typeof t.url === 'string'
      && t.url.startsWith('https://bootstrap.local/bootstrap.html'));
    if (!target) return null;
    return this.evaluateOnTarget(target, `(() => {
      const el = document.getElementById('btn-confirm-start');
      const rect = el?.getBoundingClientRect();
      return { confirmVisible: !!el && !el.disabled && rect.width > 0 && rect.height > 0
        && getComputedStyle(el).visibility !== 'hidden' && getComputedStyle(el).display !== 'none',
        activeTag: document.activeElement?.tagName || '', activeId: document.activeElement?.id || '' };
    })()`);
  }
  async stageSelectState() {
    const target = await this.findStageSelectTarget();
    if (!target) return null;
    return this.evaluateOnTarget(target, `(() => {
      const mod = document.querySelector('#stage-select-mod-test-space');
      const cards = [...document.querySelectorAll('[data-frame-label],button')].slice(0, 80)
        .map(b => (b.textContent || '').trim()).filter(t => t.length > 0 && t.length < 30);
      return { hasTestSpace: !!mod, url: location.href.slice(0, 200), sampleButtons: cards.slice(0, 30) };
    })()`);
  }

}


module.exports={CdpGeometry};
if(require.main===module)throw new Error('Import this read-only helper in the Computer Use runtime; use normal candidate UI and ui-session.js, not the A5 specialist entry.');
