'use strict';

const fs = require('fs');
const path = require('path');
const { connectExactTarget, evaluateByValue } = require('../workbench-live-e2e/kshop/cdp-client');
const { sha256Bytes, sleep } = require('../workbench-live-e2e/kshop/common');
const SharedEvidence = require('../workbench-live-e2e/lib/evidence-artifact');

const OVERLAY_URL = 'https://overlay.local/overlay.html';
const ROOT = path.resolve(__dirname, '..', '..');
const OWNED_BASE = path.join('tmp', 'workbench-live-e2e', 'gym');
const TARGETS = Object.freeze({
    close:'.gym-close-button',
    start:'.gym-start-button',
    goldStat:'.gym-project-option[data-project-id="dummy.0"]',
    cancelTarget:'.gym-project-option[data-project-id="dummy.1"]',
    kSkill:'.gym-project-option[data-project-id="dummy.7"]'
});

async function openGymInputChannel(options) {
    const binding = options.cdpBinding;
    const identity = options.runtimeIdentity;
    const writer = options.writer;
    const runDir = SharedEvidence.assertOwnedRunDirectory(ROOT, options.runDir,
        OWNED_BASE, 'gym_input');
    if (!binding || !identity || binding.runtimePid !== identity.pid
            || !Number.isInteger(binding.port) || binding.exclusiveBeforeLaunch !== true
            || !writer || typeof writer.append !== 'function') {
        throw new Error('gym CDP input requires the authenticated candidate PID and transcript');
    }
    const connected = await connectExactTarget(binding.port, OVERLAY_URL,
        options.timeoutMs || 30000, options.pollMs || 250);
    const client = connected.client;
    try {
        await client.call('Runtime.enable', {}, 10000);
        await client.call('Page.enable', {}, 10000);
        const page = await evaluateByValue(client,
            '({url:String(location.href),origin:String(location.origin),readyState:String(document.readyState)})',
            'Gym exact Overlay page');
        if (page.url !== OVERLAY_URL || page.origin !== new URL(OVERLAY_URL).origin) {
            throw new Error('gym CDP target is not the exact Overlay page');
        }
        writer.append({ kind:'gym_input_channel_bound', runtimePid:identity.pid,
            cdpPort:binding.port, pageUrl:OVERLAY_URL, candidatePageInput:true,
            physicalInputAttestation:false });

        async function readState() {
            return evaluateByValue(client, `(function(){
                var panel=document.getElementById('panel-container');
                var buttons=Array.prototype.slice.call(document.querySelectorAll('.gym-project-option'));
                var start=document.querySelector('.gym-start-button');
                var progress=document.querySelector('.gym-progress-bar');
                return {
                    url:String(location.href),
                    panel:panel?String(panel.getAttribute('data-panel')||''):'',
                    hidden:panel?!!panel.hidden||panel.style.display==='none':true,
                    station:String((document.querySelector('.gym-station-pill')||{}).textContent||'').trim(),
                    projects:buttons.map(function(button){return {
                        id:String(button.getAttribute('data-project-id')||''),
                        text:String(button.textContent||'').trim(),
                        selected:button.getAttribute('aria-checked')==='true'
                    };}),
                    start:{present:!!start,disabled:start?!!start.disabled:true,
                        text:start?String(start.textContent||'').trim():''},
                    progress:{status:String((document.querySelector('.gym-progress-status')||{}).textContent||'').trim(),
                        amount:String((document.querySelector('.gym-progress-amount')||{}).textContent||'').trim(),
                        value:progress?Number(progress.value):null,max:progress?Number(progress.max):null},
                    detail:String((document.querySelector('.gym-project-detail')||{}).textContent||'').trim(),
                    notice:String((document.querySelector('.gym-preview-note')||{}).textContent||'').trim(),
                    balances:Array.prototype.slice.call(document.querySelectorAll('.gym-balance-card'))
                        .map(function(card){return String(card.textContent||'').trim();})
                };
            })()`, 'Gym visible page state');
        }

        async function click(targetName) {
            const selector = TARGETS[targetName];
            if (!selector) throw new Error('gym input target is outside the fixed allowlist');
            const geometry = await evaluateByValue(client, `(function(selector){
                var panel=document.getElementById('panel-container');
                var element=document.querySelector(selector);
                if(!element)return {ok:false,reason:'missing'};
                var rect=element.getBoundingClientRect();
                var x=rect.left+rect.width/2,y=rect.top+rect.height/2;
                var hit=document.elementFromPoint(x,y);
                var style=window.getComputedStyle(element);
                return {ok:!!(rect.width>0&&rect.height>0&&style.display!=='none'
                    &&style.visibility!=='hidden'&&hit&&(hit===element||element.contains(hit))),
                    panel:panel?String(panel.getAttribute('data-panel')||''):'',
                    hidden:panel?!!panel.hidden||panel.style.display==='none':true,
                    enabled:!element.disabled,x:x,y:y,selector:selector,
                    rect:{left:rect.left,top:rect.top,width:rect.width,height:rect.height},
                    hitTargetMatches:!!(hit&&(hit===element||element.contains(hit)))};
            })(${JSON.stringify(selector)})`, 'Gym ' + targetName + ' visible target');
            if (!geometry || geometry.ok !== true || geometry.panel !== 'gym'
                    || geometry.hidden || !geometry.enabled) {
                throw new Error('gym target is not visibly actionable: ' + targetName);
            }
            await client.call('Input.dispatchMouseEvent', {
                type:'mouseMoved', x:geometry.x, y:geometry.y, button:'none'
            }, 10000);
            await client.call('Input.dispatchMouseEvent', {
                type:'mousePressed', x:geometry.x, y:geometry.y,
                button:'left', buttons:1, clickCount:1
            }, 10000);
            await client.call('Input.dispatchMouseEvent', {
                type:'mouseReleased', x:geometry.x, y:geometry.y,
                button:'left', buttons:0, clickCount:1
            }, 10000);
            await sleep(100);
            writer.append({ kind:'gym_candidate_page_input', inputType:'trusted_click',
                targetName, selector, geometry, runtimePid:identity.pid,
                browserTrustedExpected:true, candidatePageInput:true,
                physicalInputAttestation:false });
            return geometry;
        }

        async function captureScreenshot(outputPath, label) {
            const screenshotPath = path.resolve(outputPath);
            if (path.dirname(screenshotPath).toLowerCase() !== runDir.toLowerCase()
                    || !/^gym-[a-z0-9_-]+\.png$/i.test(path.basename(screenshotPath))) {
                throw new Error('gym screenshot escaped the owned run directory');
            }
            const result = await client.call('Page.captureScreenshot', {
                format:'png', fromSurface:true, captureBeyondViewport:false
            }, 30000);
            if (!result || typeof result.data !== 'string') {
                throw new Error('gym CDP screenshot unavailable');
            }
            const bytes = Buffer.from(result.data, 'base64');
            if (bytes.length < 1024 || bytes.length > 32 * 1024 * 1024
                    || bytes[0] !== 0x89 || bytes[1] !== 0x50
                    || bytes[2] !== 0x4e || bytes[3] !== 0x47) {
                throw new Error('gym CDP screenshot invalid');
            }
            fs.writeFileSync(screenshotPath, bytes, { flag:'wx' });
            const evidence = { kind:'gym_browser_screenshot', label:String(label || ''),
                path:screenshotPath, bytes:bytes.length, sha256:sha256Bytes(bytes),
                runtimePid:identity.pid, physicalInputAttestation:false };
            writer.append(evidence);
            return evidence;
        }

        let closed = false;
        return Object.freeze({ readState, click, captureScreenshot, close() {
            if (closed) return;
            closed = true;
            client.close();
            writer.append({ kind:'gym_input_channel_detached', runtimePid:identity.pid });
        } });
    } catch (error) {
        client.close();
        throw error;
    }
}

module.exports = { OVERLAY_URL, TARGETS, openGymInputChannel };
