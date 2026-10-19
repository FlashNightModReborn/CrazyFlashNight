'use strict';
// Explicitly authorized candidate-page mouse input; never business-function injection.
const { execFileSync } = require('node:child_process');
const { CdpGeometry } = require('./run');
const norm = value => String(value).replace(/\\/g, '/').toLowerCase();
const ownershipScript = `
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$guardianId=[int]$env:CF7_SCENE_GUARDIAN
$portNumber=[int]$env:CF7_SCENE_PORT
$rows=@(Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe' OR ProcessId=$guardianId")
$listeners=@(Get-NetTCPConnection -State Listen -LocalPort $portNumber -ErrorAction Stop | Select-Object LocalAddress,OwningProcess)
@{observedAt=[DateTime]::UtcNow.ToString('o');listeners=$listeners;processes=@($rows | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine,@{n='createdAt';e={$_.CreationDate.ToUniversalTime().ToString('o')}})} | ConvertTo-Json -Depth 5 -Compress
`;
function validateBinding(proof, identity, port, startedAt) {
  if (!Number.isInteger(port) || port < 1 || port > 65535 || !proof.listeners?.length
      || Math.abs(Date.now() - Date.parse(proof.observedAt)) > 15000) throw new Error('stale/missing CDP listener');
  const guardian = proof.processes.find(row => row.ProcessId === identity.guardianPid);
  if (!guardian || norm(guardian.ExecutablePath) !== norm(identity.processPath)
      || !(Date.parse(guardian.createdAt) >= Date.parse(startedAt) - 1000)) throw new Error('Guardian identity mismatch');
  const owners = [...new Set(proof.listeners.map(row => row.OwningProcess))];
  if (owners.length !== 1 || proof.listeners.some(row => !['127.0.0.1', '::1'].includes(row.LocalAddress)))
    throw new Error('CDP endpoint is not an exclusive loopback listener');
  const browser = proof.processes.find(row => row.ProcessId === owners[0]);
  const userData = /--user-data-dir=(?:"([^"]+)"|(\S+))/.exec(browser?.CommandLine || '');
  const ownData = ['launcher/webview2_userdata', 'launcher/webview2_overlay_userdata']
    .map(suffix => norm(identity.projectRoot + '/' + suffix));
  const dataPath = userData && norm(userData[1] || userData[2]);
  // FixedWebViewRuntime.ResolveUserDataFolder adds fixed-<version>; Edge adds EBWebView.
  const ownedData = dataPath && ownData.some(base => dataPath === base
    || (dataPath.startsWith(base) && /^\/fixed-\d+\.\d+\.\d+\.\d+\/ebwebview$/.test(dataPath.slice(base.length))));
  if (!browser || browser.Name.toLowerCase() !== 'msedgewebview2.exe' || !ownedData) throw new Error('foreign WebView userdata');
  const chain = [browser];
  while (chain.at(-1).ProcessId !== guardian.ProcessId && chain.length < 8) {
    const parent = proof.processes.find(row => row.ProcessId === chain.at(-1).ParentProcessId);
    if (!parent || chain.some(row => row.ProcessId === parent.ProcessId)) throw new Error('foreign browser process ancestry');
    chain.push(parent);
  }
  if (chain.at(-1).ProcessId !== guardian.ProcessId) throw new Error('browser is not owned by Guardian');
  return { port, guardianPid: guardian.ProcessId, browserPid: browser.ProcessId,
    userDataDirectory: userData[1] || userData[2], observedAt: proof.observedAt, chain };
}
function readBinding(identity, port, startedAt) {
  const output = execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-EncodedCommand',
    Buffer.from(ownershipScript, 'utf16le').toString('base64')], { encoding: 'utf8', windowsHide: true,
    timeout: 15000, env: { ...process.env, CF7_SCENE_GUARDIAN: String(identity.guardianPid), CF7_SCENE_PORT: String(port) } });
  return validateBinding(JSON.parse(output.replace(/^\uFEFF/, '')), identity, port, startedAt);
}
async function command(ws, id, method, params) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => { cleanup(); reject(new Error('CDP result unknown: ' + method)); }, 8000);
    const cleanup = () => { clearTimeout(timer); ws.removeEventListener('message', onMessage); ws.removeEventListener('close', onClose); };
    const onClose = () => { cleanup(); reject(new Error('CDP closed before result: ' + method)); };
    const onMessage = event => {
      const message = JSON.parse(event.data);
      if (message.id !== id) return;
      cleanup();
      if (message.error) reject(new Error('CDP rejected ' + method + ': ' + message.error.message));
      else resolve(message.result || {});
    };
    ws.addEventListener('message', onMessage); ws.addEventListener('close', onClose);
    ws.send(JSON.stringify({ id, method, params }));
  });
}
class CandidateInput {
  constructor(session) {
    if (!session.data.start) throw new Error('attach normal start before browser input');
    this.session = session; this.geometry = new CdpGeometry(session.identity.projectRoot); this.uncertain = false;
  }
  async click(selector, page = 'overlay') {
    if (this.uncertain) throw new Error('prior input failed/unknown; navigation replay prohibited');
    if (!['bootstrap', 'overlay'].includes(page) || typeof selector !== 'string' || !selector.length)
      throw new Error('candidate page/selector required');
    await this.geometry.discoverPort(2000);
    const url = 'https://' + page + '.local/' + page + '.html';
    const matches = [];
    for (const port of this.geometry.ports) {
      // Bootstrap shuts down after entry, leaving a stale DevToolsActivePort file.
      // Discovery is read-only; an unreachable port is not an input target.
      let targets;
      try { targets = await this.geometry.httpJson(port, '/json/list'); }
      catch (error) {
        this.session.data.discovery = [...(this.session.data.discovery || []),
          { at: new Date().toISOString(), port, result: 'unreachable_readonly', error: error.message }];
        this.session.persist(); continue;
      }
      const exact = targets.filter(t => t.type === 'page' && t.url === url);
      if (!exact.length) continue;
      const binding = readBinding(this.session.identity, port, this.session.data.start.startedAt);
      for (const target of exact) matches.push({ binding, target });
    }
    if (matches.length !== 1) throw new Error('expected one exact owned candidate page');
    const { binding, target } = matches[0];
    const endpoint = new URL(target.webSocketDebuggerUrl);
    if (endpoint.protocol !== 'ws:' || endpoint.hostname !== '127.0.0.1' || Number(endpoint.port) !== binding.port
        || endpoint.pathname !== '/devtools/page/' + target.id || endpoint.search || endpoint.hash || endpoint.username || endpoint.password)
      throw new Error('unexpected CDP page endpoint');
    const ws = new WebSocket(endpoint.toString());
    const record = { at: new Date().toISOString(), channel: 'cdp_input', candidatePageInput: true,
      physicalInputAttestation: false, selector, pageUrl: url, targetId: target.id, binding, packets: [], result: 'prepared' };
    try {
      await new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error('CDP connection timeout')), 5000);
        ws.onopen = () => { clearTimeout(timer); resolve(); };
        ws.onerror = () => { clearTimeout(timer); reject(new Error('CDP connection failed')); };
      });
      const expression = `(() => { const selector=${JSON.stringify(selector)};
        const matches=[...document.querySelectorAll(selector)].filter(e=>{const r=e.getBoundingClientRect();return r.width>0&&r.height>0});
        if(matches.length!==1)return {ok:false,count:matches.length};
        const e=matches[0],r=e.getBoundingClientRect(),x=r.left+r.width/2,y=r.top+r.height/2,s=getComputedStyle(e),hit=document.elementFromPoint(x,y);
        return {ok:location.href===${JSON.stringify(url)}&&!e.disabled&&e.getAttribute('aria-disabled')!=='true'&&s.visibility!=='hidden'&&s.display!=='none'&&x>=0&&y>=0&&x<innerWidth&&y<innerHeight&&!!hit&&(hit===e||e.contains(hit)),
          x,y,rect:{x:r.x,y:r.y,w:r.width,h:r.height},viewport:{w:innerWidth,h:innerHeight},label:e.getAttribute('aria-label'),text:e.textContent.trim().slice(0,120)};
      })()`;
      const value = await command(ws, 1, 'Runtime.evaluate', { expression, returnByValue: true, userGesture: false });
      record.geometry = value.result?.value;
      if (value.exceptionDetails || record.geometry?.ok !== true) throw new Error('button is not visibly actionable: ' + JSON.stringify(record.geometry));
      this.session.browserAction(record);
      for (const [index, type] of ['mouseMoved', 'mousePressed', 'mouseReleased'].entries()) {
        const params = { type, x: record.geometry.x, y: record.geometry.y,
          button: index ? 'left' : 'none', buttons: index === 1 ? 1 : 0, clickCount: index ? 1 : 0 };
        const packet = { id: index + 2, method: 'Input.dispatchMouseEvent', params, state: 'sent' };
        record.packets.push(packet); this.session.persist();
        packet.response = await command(ws, packet.id, packet.method, params); packet.state = 'acknowledged'; this.session.persist();
      }
      record.result = 'browser_input_dispatched'; this.session.persist(); return record;
    } catch (error) {
      // A failed geometry read sent no input and cannot have navigated. A sent
      // packet without the complete acknowledgement chain must never be replayed.
      this.uncertain = record.packets.length > 0;
      record.result = this.uncertain ? 'failed_or_unknown' : 'not_dispatched'; record.error = error.message;
      if (!this.session.data.actions.includes(record)) this.session.browserAction(record);
      this.session.persist(); throw error;
    } finally { ws.close(); }
  }
}
module.exports = { CandidateInput, validateBinding };
