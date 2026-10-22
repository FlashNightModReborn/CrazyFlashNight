'use strict';

const fs = require('fs');
const path = require('path');
const { connectExactTarget, evaluateByValue } =
    require('../workbench-live-e2e/kshop/cdp-client');
const { atomicWriteJson, nextEvent, redactOpaqueTokens, sha256Bytes } =
    require('../workbench-live-e2e/kshop/common');
const Evidence = require('../workbench-live-e2e/lib/evidence-artifact');
const RuntimeGuard = require('../workbench-live-e2e/lib/runtime-guard');
const SourceClosure = require('./source-closure');

const ROOT = path.resolve(__dirname, '..', '..');
const OWNED_BASE = path.join('tmp', 'workbench-live-e2e', 'cf6');
const OVERLAY_URL = 'https://overlay.local/overlay.html';
const BINDING = '__cf7Cf6PassiveEmitV1';
const MARKER = '__cf7Cf6PassiveObserverV1';
const MAX_EVENT_BYTES = 8 * 1024 * 1024;
const LOADED_WEB = Object.freeze([
    ['launcher/web/modules/bridge.js','modules/bridge.js'],
    ['launcher/web/modules/panels.js','modules/panels.js'],
    ['launcher/web/modules/panels-lazy-registry.js','modules/panels-lazy-registry.js'],
    ['launcher/web/modules/bookshelf-runtime.js','modules/bookshelf-runtime.js'],
    ['launcher/web/modules/bookshelf-panel.js','modules/bookshelf-panel.js']
]);
const CF6_TOKEN_KEYS = new Set(['openToken', 'sessionToken', 'token', 'nextToken', 'reconcileToken']);

function expectedOverlayProfile(root, specification) {
    if (!specification || specification.schema !== 'cf7-fixed-webview2.v1'
            || specification.architecture !== 'x64'
            || !/^\d+\.\d+\.\d+\.\d+$/.test(specification.version)) {
        throw new Error('Cf6 observer requires the exact fixed WebView2 profile contract');
    }
    return path.join(root, 'launcher', 'webview2_overlay_userdata',
        'fixed-' + specification.version, 'EBWebView');
}

function redactCf6Tokens(value, key) {
    if (Array.isArray(value)) return value.map(entry => redactCf6Tokens(entry, null));
    if (value && typeof value === 'object') {
        const copy = {};
        Object.keys(value).forEach(name => { copy[name] = redactCf6Tokens(value[name], name); });
        return copy;
    }
    if (CF6_TOKEN_KEYS.has(key) && typeof value === 'string'
            && !/^sha256:[a-f0-9]{64}$/.test(value)) {
        return 'sha256:' + sha256Bytes(Buffer.from(value, 'utf8'));
    }
    return value;
}

class TranscriptWriter {
    constructor(runDir, observerId) {
        this.runDir = Evidence.assertOwnedRunDirectory(ROOT, runDir,
            OWNED_BASE, 'cf6_transcript');
        this.path = path.join(this.runDir, 'cf6-passive-transcript.jsonl');
        this.summaryPath = path.join(this.runDir, 'cf6-passive-transcript.json');
        this.observerId = String(observerId || 'cf6-passive');
        this.events = [];
        this.previousHash = '0'.repeat(64);
        fs.writeFileSync(this.path, '', { encoding:'utf8', mode:0o600, flag:'wx' });
    }
    append(rawEvent) {
        if (!rawEvent || typeof rawEvent !== 'object' || Array.isArray(rawEvent)
                || Object.prototype.hasOwnProperty.call(rawEvent, 'observerId')) {
            throw new Error('cf6 passive event is not a plain observer-owned object');
        }
        const event = nextEvent(this.previousHash, this.events.length + 1,
            Object.assign({}, rawEvent, { observerId:this.observerId,
                observedAt:new Date().toISOString() }));
        const line = JSON.stringify(event);
        if (Buffer.byteLength(line, 'utf8') > MAX_EVENT_BYTES) {
            throw new Error('cf6 passive event exceeded the evidence limit');
        }
        fs.appendFileSync(this.path, line + '\n', { encoding:'utf8' });
        this.events.push(event);
        this.previousHash = event.eventHash;
        return event;
    }
    flush(extra) {
        const value = Object.assign({ schema:'cf7-cf6-live-e2e.passive-transcript.v1',
            observerId:this.observerId, pageUrl:OVERLAY_URL,
            eventCount:this.events.length, chainHead:this.previousHash,
            events:this.events.slice() }, extra || {});
        atomicWriteJson(this.summaryPath, value);
        return value;
    }
}

function browserInjectionSource() {
    return function installCf6PassiveObserver(options) {
        'use strict';
        const bridge = window.Bridge;
        const webview = window.chrome && window.chrome.webview;
        if (!bridge || typeof bridge.send !== 'function'
                || !webview || typeof webview.addEventListener !== 'function') {
            return { ok:false, reason:'production_bridge_unavailable' };
        }
        if (window[options.markerName]) {
            return { ok:false, reason:'cf6_observer_already_installed' };
        }
        const originalSend = bridge.send;
        function emit(value) {
            try {
                const binding = window[options.bindingName];
                if (typeof binding === 'function') binding(JSON.stringify(value));
            } catch (_error) { /* observer transport cannot change game behavior */ }
        }
        function clone(value) {
            try { return JSON.parse(JSON.stringify(value)); }
            catch (_error) { return { observerCloneError:true }; }
        }
        function panelState() {
            const panel = document.getElementById('panel-container');
            return { panel:panel ? String(panel.getAttribute('data-panel') || '') : '',
                hidden:panel ? !!panel.hidden || panel.style.display === 'none' : true };
        }
        function targetOf(event) {
            const target = event.target && event.target.closest
                ? event.target.closest('button') : null;
            if (!target) return null;
            const rect = target.getBoundingClientRect();
            const style = window.getComputedStyle(target);
            const hit = document.elementFromPoint(event.clientX, event.clientY);
            return { selector:target.className ? 'button.'
                + String(target.className).trim().replace(/\s+/g, '.') : 'button',
                className:String(target.className || ''),
                projectId:String(target.getAttribute('data-project-id') || ''),
                text:String(target.textContent || '').trim().slice(0, 160),
                visible:target.isConnected && rect.width > 0 && rect.height > 0
                    && style.display !== 'none' && style.visibility !== 'hidden',
                enabled:target.disabled !== true,
                hitTargetMatches:!!(hit && (hit === target || target.contains(hit))),
                rect:{ left:rect.left, top:rect.top, width:rect.width, height:rect.height } };
        }
        const bridgeWrapper = function(message) {
            emit({ kind:'bridge_send', message:clone(message), panelState:panelState(),
                pageTime:performance.now() });
            return originalSend.apply(this, arguments);
        };
        const webviewHandler = function(event) {
            emit({ kind:'webview_message', message:clone(event.data),
                panelState:panelState(), pageTime:performance.now() });
        };
        const clickHandler = function(event) {
            emit({ kind:'dom_input', eventType:'click', isTrusted:event.isTrusted === true,
                clientX:event.clientX, clientY:event.clientY,
                target:targetOf(event), panelState:panelState(),
                pageTime:performance.now() });
        };
        bridge.send = bridgeWrapper;
        webview.addEventListener('message', webviewHandler);
        document.addEventListener('click', clickHandler, true);
        window[options.markerName] = { uninstall:function() {
            if (bridge.send === bridgeWrapper) bridge.send = originalSend;
            webview.removeEventListener('message', webviewHandler);
            document.removeEventListener('click', clickHandler, true);
            delete window[options.markerName];
            return true;
        } };
        return { ok:true, url:String(location.href), bridgeWrapped:bridge.send === bridgeWrapper,
            webviewObserved:true, clickObserved:true };
    };
}

async function attachPassiveObserver(options) {
    const writer = options.writer;
    const binding = options.cdpBinding;
    const identity = options.runtimeIdentity;
    const closure = options.sourceClosure;
    if (!writer || typeof writer.append !== 'function'
            || !identity || !binding || identity.pid !== binding.runtimePid
            || binding.exclusiveBeforeLaunch !== true
            || !Number.isInteger(binding.port) || binding.port < 1024
            || binding.port > 65535) {
        throw new Error('cf6 observer requires exact candidate PID and transcript');
    }
    SourceClosure.assertUnchanged(closure, SourceClosure.capture(ROOT));
    const connected = await connectExactTarget(binding.port, OVERLAY_URL,
        options.timeoutMs || 30000, options.pollMs || 250);
    const client = connected.client;
    const parsed = new Map();
    const removeScriptListener = client.onEvent(message => {
        if (message.method !== 'Debugger.scriptParsed' || !message.params
                || typeof message.params.url !== 'string') return;
        const url = message.params.url;
        const scripts = parsed.get(url) || [];
        scripts.push(message.params.scriptId);
        parsed.set(url, scripts);
    });
    let removeBindingListener = null;
    try {
        await client.call('Runtime.enable', {}, 10000);
        await client.call('Debugger.enable', {}, 10000);
        await client.call('Page.enable', {}, 10000);
        const endpoint = RuntimeGuard.attestLoopbackCdpEndpoint({
            port:binding.port, runtimePid:identity.pid,
            expectedUserDataRoot:expectedOverlayProfile(ROOT, JSON.parse(fs.readFileSync(
                path.join(ROOT, 'launcher', 'webview2-runtime.lock.json'), 'utf8'))),
            expectedExecutableName:'msedgewebview2.exe'
        });
        const page = await evaluateByValue(client,
            '({url:String(location.href),origin:String(location.origin),readyState:String(document.readyState)})',
            'Cf6 observer exact page identity');
        if (page.url !== OVERLAY_URL || page.origin !== new URL(OVERLAY_URL).origin) {
            throw new Error('cf6 observer attached to the wrong Overlay page');
        }
        writer.append({ kind:'cf6_observer_bound', runtimePid:identity.pid,
            cdpPort:binding.port, page, endpoint, sourceClosureSha256:closure.closureSha256,
            physicalInputAttestation:false });
        await client.call('Runtime.addBinding', { name:BINDING }, 10000);
        removeBindingListener = client.onEvent(message => {
            if (message.method !== 'Runtime.bindingCalled' || !message.params
                    || message.params.name !== BINDING
                    || typeof message.params.payload !== 'string') return;
            let raw;
            try { raw = JSON.parse(message.params.payload); }
            catch (_error) { throw new Error('cf6 observer received malformed page evidence'); }
            writer.append(redactCf6Tokens(redactOpaqueTokens(raw), null));
        });
        const installed = await evaluateByValue(client,
            '(' + browserInjectionSource().toString() + ')('
                + JSON.stringify({ bindingName:BINDING, markerName:MARKER }) + ')',
            'Cf6 passive observer installation');
        if (!installed || installed.ok !== true || installed.url !== OVERLAY_URL
                || !installed.bridgeWrapped || !installed.webviewObserved
                || !installed.clickObserved) {
            throw new Error('cf6 observer did not bind the exact production primitives');
        }

        async function assertLoadedCf6Scripts() {
            const rows = [];
            for (const [relativePath, webPath] of LOADED_WEB) {
                const url = new URL(webPath, OVERLAY_URL).href;
                const ids = parsed.get(url) || [];
                if (ids.length !== 1) {
                    throw new Error('cf6 Web source missing or duplicated: ' + webPath);
                }
                const source = await client.call('Debugger.getScriptSource',
                    { scriptId:ids[0] }, 15000);
                if (!source || typeof source.scriptSource !== 'string') {
                    throw new Error('cf6 loaded Web source unavailable: ' + webPath);
                }
                const bytes = Buffer.from(source.scriptSource, 'utf8');
                const actual = sha256Bytes(bytes);
                const expected = closure.files.find(entry => entry.relativePath === relativePath);
                const disk = Evidence.readExactRegularFile(path.join(ROOT,
                    ...relativePath.split('/')), {
                    phase:'cf6_loaded_web', maximumBytes:1024 * 1024
                });
                const browserStrippedBom = disk.bytes.subarray(0, 3).equals(
                    Buffer.from([0xef, 0xbb, 0xbf]))
                    && sha256Bytes(Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), bytes]))
                        === expected?.sha256;
                if (!expected || disk.sha256 !== expected.sha256
                        || (actual !== expected.sha256 && !browserStrippedBom)) {
                    throw new Error('cf6 loaded Web source differs from audited file: ' + webPath);
                }
                rows.push({ relativePath, url, scriptId:ids[0], bytes:bytes.length,
                    sha256:actual, browserStrippedBom });
            }
            const evidence = { kind:'cf6_loaded_web_source_verified',
                runtimePid:identity.pid, sources:rows,
                sourceClosureSha256:closure.closureSha256 };
            writer.append(evidence);
            return evidence;
        }

        async function panelState() {
            return evaluateByValue(client, `(function(){
                var panel=document.getElementById('panel-container');
                return {panel:panel?String(panel.getAttribute('data-panel')||''):'',
                    hidden:panel?!!panel.hidden||panel.style.display==='none':true};
            })()`, 'Cf6 passive panel state');
        }

        let detached = false;
        return Object.freeze({ assertLoadedCf6Scripts, panelState,
            async detach() {
                if (detached) return;
                detached = true;
                try {
                    const removed = await evaluateByValue(client,
                        '(function(){var marker=window[' + JSON.stringify(MARKER)
                            + '];return marker&&marker.uninstall?marker.uninstall():false;})()',
                        'Cf6 passive observer detach');
                    if (removed !== true) throw new Error('cf6 passive observer did not detach');
                    writer.append({ kind:'cf6_observer_detached', runtimePid:identity.pid });
                } finally {
                    if (removeBindingListener) removeBindingListener();
                    removeScriptListener();
                    client.close();
                }
            }
        });
    } catch (error) {
        if (removeBindingListener) removeBindingListener();
        removeScriptListener();
        client.close();
        throw error;
    }
}

module.exports = { TranscriptWriter, attachPassiveObserver,
    browserInjectionSource, redactCf6Tokens, LOADED_WEB, OVERLAY_URL, expectedOverlayProfile };
