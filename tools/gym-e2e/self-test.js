#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');
const Preflight = require('./preflight');
const Ledger = require('./ledger');
const Input = require('./cdp-input-channel');
const Runner = require('./run-candidate');
const Observer = require('./passive-observer');
const SourceClosure = require('./source-closure');
const LauncherObservation = require('../workbench-live-e2e/lib/launcher-observation');
const RuntimeGuard = require('../workbench-live-e2e/lib/runtime-guard');

async function main() {
    let passed = 0;
    function test(name, body) { body(); passed++; }
    test('fixed target slot and explicit source', () => {
        assert.strictEqual(Preflight.TARGET_SLOT, 'cf7_agent_gym');
        assert.throws(() => Preflight.parseArgs(['--seed-slot', 'cf7_agent_seed']),
            /candidate-root/);
        assert.throws(() => Preflight.parseArgs(['--candidate-root', 'C:\\fixture',
            '--seed-slot', 'cf7_agent_gym']), /distinct/);
        assert.throws(() => Preflight.parseArgs(['--candidate-root', 'C:\\fixture',
            '--seed-slot', 'crazyflasher7_saves']), /read-only seed/);
        assert.throws(() => Preflight.parseArgs(['--candidate-root', 'C:\\fixture',
            '--seed-slot', 'cf7_agent_seed', '--slot', 'crazyflasher7_saves']), /unsupported argument/);
        assert.throws(() => Preflight.parseArgs(['--candidate-root', 'C:\\fixture',
            '--seed-slot', 'cf7_agent_seed', '--fresh']), /unsupported argument/);
        const valid = Preflight.parseArgs(['--candidate-root', 'C:\\fixture',
            '--seed-slot', 'crazyflasher7_saves', '--allow-read-only-live-seed']);
        assert.strictEqual(valid.seedSlot, 'crazyflasher7_saves');
    });
    test('gym ledger exposes only settlement fields', () => {
        const save = { '0':Array(14).fill(0), '7':[1,2,3,4,5] };
        save['0'][2] = 60000;
        save['0'][3] = 50;
        save['0'][4] = 100;
        save['0'][6] = 8;
        save['0'][9] = 9000;
        const values = Ledger.project(save);
        assert.deepStrictEqual(values, { money:60000, level:50, experience:100,
            skillPoints:8, kpoint:9000,
            bonuses:{ hp:1, mp:2, unarmed:3, defense:4, innerPower:5 } });
        assert.throws(() => Ledger.project({ '0':[], '7':[] }), /shape/);
        save['7'][2] = -1;
        assert.throws(() => Ledger.project(save), /unarmed/);
    });
    test('only fixed gym page targets are available', () => {
        assert.deepStrictEqual(Object.keys(Input.TARGETS),
            ['close', 'start', 'goldStat', 'cancelTarget', 'kSkill']);
        assert.strictEqual(Input.OVERLAY_URL, 'https://overlay.local/overlay.html');
    });
    test('paid runner requires exact candidate pins and explicit clone write scope', () => {
        const base = ['--candidate-root', 'C:\\fixture', '--seed-slot', 'cf7_agent_seed',
            '--expected-build-identity', 'a'.repeat(64),
            '--expected-payload-closure', 'b'.repeat(64)];
        assert.throws(() => Runner.parseArgs(base), /observe-only/);
        const valid = Runner.parseArgs(base.concat(
            ['--execute-isolated-candidate', '--allow-clone-training-writes']));
        assert.strictEqual(valid.slot, 'cf7_agent_gym');
        assert.strictEqual(valid.preserveSeedBytes, true);
        assert.strictEqual(valid.observeOnly, false);
        const observe = Runner.parseArgs(base.concat(
            ['--execute-isolated-candidate', '--observe-only']));
        assert.strictEqual(observe.observeOnly, true);
        assert.throws(() => Runner.parseArgs(base.concat([
            '--execute-isolated-candidate', '--observe-only', '--allow-clone-training-writes'
        ])), /observe-only/);
        assert.throws(() => Runner.parseArgs(base.concat([
            '--execute-isolated-candidate', '--allow-clone-training-writes',
            '--slot', 'crazyflasher7_saves'
        ])), /unsupported argument/);
        assert.deepStrictEqual(Object.keys(Runner.EXPECTED_PROJECTS), ['goldStat', 'kSkill']);
    });
    test('cancel and two paid outcomes have independent exact ledger checks', () => {
        const before = { values:{ money:200000, kpoint:9000, experience:100,
            level:50, skillPoints:8,
            bonuses:{ hp:1, mp:2, unarmed:3, defense:4, innerPower:5 } } };
        const gold = { values:{ money:140000, kpoint:9000, experience:10100,
            level:50, skillPoints:8,
            bonuses:{ hp:1, mp:2, unarmed:6, defense:4, innerPower:5 } } };
        const skill = { values:{ money:140000, kpoint:7750, experience:10100,
            level:50, skillPoints:33,
            bonuses:{ hp:1, mp:2, unarmed:6, defense:4, innerPower:5 } } };
        Runner.expectSameLedger(before, JSON.parse(JSON.stringify(before)), 'cancel');
        assert.throws(() => Runner.expectSameLedger(before, gold, 'cancel'), /changed/);
        const goldResult = { result:{ award:{ kind:'stat', amount:3,
            baseExperience:10000, capExperience:0 }, level:50, skillPoints:8,
            current:6, balances:{ money:140000, kpoint:9000 } } };
        Runner.expectGoldDelta(before, gold, goldResult);
        assert.throws(() => Runner.expectGoldDelta(before, skill, goldResult), /differs/);
        const skillResult = { result:{ award:{ kind:'skillPoints', amount:25,
            baseExperience:0, capExperience:0 }, current:33,
            balances:{ money:140000, kpoint:7750 } } };
        Runner.expectSkillDelta(gold, skill, skillResult);
        assert.throws(() => Runner.expectSkillDelta(before, gold, skillResult), /differs/);
    });
    test('Gym source closure covers Host, AS2 SWF, Web, and fixed input', () => {
        const root = path.resolve(__dirname, '..', '..');
        const closure = SourceClosure.capture(root);
        assert.strictEqual(closure.files.length, 29);
        assert.ok(closure.files.some(row => row.role === 'candidate_start'
            && row.relativePath === 'automation/start.ps1'));
        const startup = fs.readFileSync(path.join(root, 'automation', 'start.ps1'), 'utf8');
        const hashBody = startup.split('function Get-Cf7Sha256 {')[1]
            ?.split('function Assert-Cf7PlainPath {')[0];
        assert.ok(hashBody && hashBody.includes('[Security.Cryptography.SHA256]::Create()'));
        assert.ok(!hashBody.includes('Get-FileHash'));
        assert.ok(closure.files.some(row => row.role === 'as2_publish'
            && row.relativePath === 'scripts/asLoader.swf'));
        assert.ok(closure.files.some(row => row.role === 'host_session'
            && row.relativePath === 'launcher/src/Tasks/GymTrainingTask.cs'));
        assert.strictEqual(SourceClosure.assertUnchanged(closure, SourceClosure.capture(root)), true);
        const changed = JSON.parse(JSON.stringify(closure));
        changed.files[0].sha256 = '0'.repeat(64);
        assert.throws(() => SourceClosure.assertUnchanged(closure, changed), /changed/);
    });
    test('page observer only relays original send and trusted click evidence', () => {
        const emitted = [];
        const originalCalls = [];
        const listeners = {};
        const documentListeners = {};
        const button = { className:'gym-start-button', disabled:false, isConnected:true,
            textContent:'开始训练', getAttribute(name) { return name === 'data-project-id' ? '' : null; },
            getBoundingClientRect() { return { left:10, top:20, width:80, height:30 }; },
            contains(hit) { return hit === this; } };
        const panel = { hidden:false, style:{ display:'' },
            getAttribute(name) { return name === 'data-panel' ? 'gym' : null; } };
        const bridge = { send(message) { originalCalls.push(message); return true; } };
        const original = bridge.send;
        const webview = { addEventListener(name, handler) { listeners[name] = handler; },
            removeEventListener(name, handler) {
                if (listeners[name] === handler) delete listeners[name];
            } };
        const sandbox = { window:{ Bridge:bridge, chrome:{ webview },
            __cf7GymPassiveEmitV1(value) { emitted.push(JSON.parse(value)); },
            getComputedStyle() { return { display:'block', visibility:'visible' }; } },
        document:{ getElementById() { return panel; },
            addEventListener(name, handler) { documentListeners[name] = handler; },
            removeEventListener(name, handler) {
                if (documentListeners[name] === handler) delete documentListeners[name];
            }, elementFromPoint() { return button; } },
        performance:{ now() { return 123; } },
        location:{ href:Observer.OVERLAY_URL }, JSON };
        const install = vm.runInNewContext('(' + Observer.browserInjectionSource().toString()
            + ')', sandbox);
        const installed = install({ bindingName:'__cf7GymPassiveEmitV1',
            markerName:'__cf7GymPassiveObserverV1' });
        assert.strictEqual(installed.ok, true);
        const message = { type:'panel', panel:'gym', cmd:'start' };
        assert.strictEqual(bridge.send(message), true);
        assert.strictEqual(originalCalls.length, 1);
        assert.strictEqual(originalCalls[0], message);
        listeners.message({ data:{ type:'panel_event', panel:'gym', phase:'applied' } });
        documentListeners.click({ isTrusted:true, clientX:50, clientY:35,
            target:{ closest() { return button; } } });
        assert.deepStrictEqual(emitted.map(row => row.kind),
            ['bridge_send','webview_message','dom_input']);
        assert.strictEqual(emitted[2].isTrusted, true);
        assert.strictEqual(emitted[2].target.hitTargetMatches, true);
        assert.strictEqual(sandbox.window.__cf7GymPassiveObserverV1.uninstall(), true);
        assert.strictEqual(bridge.send, original);
        assert.deepStrictEqual(Object.keys(listeners), []);
        assert.deepStrictEqual(Object.keys(documentListeners), []);
    });
    test('transcript redacts Gym session and open capabilities', () => {
        const raw = { type:'panel_event', openToken:'gym.open.123',
            nested:{ sessionToken:'gym.session.456', panelInstanceId:'panel_123' } };
        const clean = Observer.redactGymTokens(raw);
        assert.match(clean.openToken, /^sha256:[a-f0-9]{64}$/);
        assert.match(clean.nested.sessionToken, /^sha256:[a-f0-9]{64}$/);
        assert.strictEqual(clean.nested.panelInstanceId, 'panel_123');
        assert.strictEqual(raw.openToken, 'gym.open.123');
        assert.deepStrictEqual(Observer.redactGymTokens(clean), clean);
    });
    test('process gate admits only the authenticated same-Core HotkeyGuard child', () => {
        const exe = 'C:\\candidate\\runtime\\CRAZYFLASHER7MercenaryEmpire.Core.exe';
        const mvid = 'fc915c76-c141-43b2-8b8b-326e6f3f90d4';
        const guardian = { pid:17308, parentPid:1, processPath:exe,
            argv:[exe,'--project-root','C:\\project','--legacy-http-automation'] };
        const child = { pid:4744, parentPid:17308, processPath:exe,
            argv:[exe,'--hotkey-guard','17308',mvid] };
        const options = { readCoreMvid(value) { assert.strictEqual(value, exe); return mvid; } };
        assert.strictEqual(LauncherObservation.assertExclusiveLauncherProcess(
            [guardian, child], 17308, options), true);
        for (const bad of [
            Object.assign({}, child, { parentPid:999 }),
            Object.assign({}, child, { processPath:'C:\\other\\Core.exe' }),
            Object.assign({}, child, { argv:[exe,'--hotkey-guard','17308',
                '00000000-0000-0000-0000-000000000000'] }),
            Object.assign({}, child, { argv:[exe,'--hotkey-guard','17308',mvid,'--other'] })
        ]) {
            assert.throws(() => LauncherObservation.assertExclusiveLauncherProcess(
                [guardian,bad],17308,options),
            error => error && error.code === 'launcher_process_not_exclusive');
        }
        assert.throws(() => LauncherObservation.assertExclusiveLauncherProcess(
            [guardian, child, Object.assign({}, child, { pid:4745 })],17308,options),
        error => error && error.code === 'launcher_process_not_exclusive');
        assert.throws(() => LauncherObservation.assertExclusiveLauncherProcess(
            [guardian, child],null,options),
        error => error && error.code === 'unverified_launcher_process_present');
        const guardianLine = '"' + exe + '" --project-root "C:\\project" --legacy-http-automation';
        const childLine = '"' + exe + '" --hotkey-guard 17308 ' + mvid;
        assert.strictEqual(RuntimeGuard.parseWindowsCommandLine(guardianLine)[0], exe);
        assert.deepStrictEqual(RuntimeGuard.parseWindowsCommandLine(childLine), child.argv);
    });
    const tempParent = fs.realpathSync.native(os.tmpdir());
    const tmp = fs.mkdtempSync(path.join(tempParent, 'cf7-gym-e2e-selftest-'));
    try {
        fs.writeFileSync(path.join(tmp, 'launcher_ports.json'),
            JSON.stringify({ pid:7001, httpPort:18080, socketPort:18081 }));
        fs.writeFileSync(path.join(tmp, 'legacy-http-credential.json'),
            JSON.stringify({ token:'fixture' }));
        const calls = [];
        const context = { projectRoot:tmp,
            portsFile:path.join(tmp, 'launcher_ports.json'),
            pid:7001, httpPort:18080, socketPort:18081,
            authorizationHeaders:{ 'X-CF7-Automation-Token':'x' },
            credential:{ path:path.join(tmp, 'legacy-http-credential.json'),
                header:'X-CF7-Automation-Token', token:'fixture-secret',
                pid:7001, processStartUtcTicks:'638900000000000001',
                lifecycleId:'fixture-life-one',
                capabilities:['legacy.console','legacy.status','legacy.task','legacy.logs'] } };
        const session = LauncherObservation.openAuthenticatedLegacyHttpSession({ root:tmp,
            contextReader() { return context; },
            requestImpl(_context, method, pathname, body) {
                calls.push({ method, pathname, body });
                return Promise.resolve({ statusCode:200,
                    text:JSON.stringify({ success:true, ok:true }) });
            } });
        await session.agentControl('openGym', {
            expectedSlot:'cf7_agent_gym', expectedAttemptId:'attempt-1'
        });
        assert.deepStrictEqual(calls[0].body, { task:'agent_control', action:'openGym',
            expectedSlot:'cf7_agent_gym', expectedAttemptId:'attempt-1' });
        await assert.rejects(() => session.agentControl('openGym', {
            expectedSlot:'crazyflasher7_saves', expectedAttemptId:'attempt-1'
        }), error => error && error.code === 'agent_control_gym_open_invalid');
        await assert.rejects(() => session.agentControl('openGym', {
            expectedSlot:'cf7_agent_gym', expectedAttemptId:'attempt-1', panel:'gym'
        }), error => error && error.code === 'agent_control_fields_forbidden');
        await assert.rejects(() => session.agentControl('openGym', {
            expectedSlot:'cf7_agent_gym', expectedAttemptId:'attempt-1', stationId:'squat'
        }), error => error && error.code === 'agent_control_fields_forbidden');
        assert.strictEqual(calls.length, 1);
        passed++;
    } finally {
        const resolved = path.resolve(tmp);
        const parent = path.resolve(tempParent);
        if (path.dirname(resolved) === parent
                && path.basename(resolved).startsWith('cf7-gym-e2e-selftest-')) {
            fs.rmSync(resolved, { recursive:true, force:true });
        }
    }
    process.stdout.write('Gym E2E safety self-tests passed: ' + passed + '/' + passed + '\n');
}

main().catch(error => { console.error(error && error.stack || String(error)); process.exitCode = 1; });
