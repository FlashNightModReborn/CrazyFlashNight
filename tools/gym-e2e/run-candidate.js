#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const Preflight = require('./preflight');
const Ledger = require('./ledger');
const SourceClosure = require('./source-closure');
const { openGymInputChannel } = require('./cdp-input-channel');
const CloneSaveGuard = require('../workbench-live-e2e/lib/clone-save-guard');
const SharedEvidence = require('../workbench-live-e2e/lib/evidence-artifact');
const LauncherObservation = require('../workbench-live-e2e/lib/launcher-observation');
const { atomicWriteJson, canonicalJson, sha256Text, sleep, timestampId } =
    require('../workbench-live-e2e/kshop/common');
const {
    assertNoLauncherBeforeMutation, openGenericRuntime, releaseGenericClone,
    restartGenericRuntime
} = require('../workbench-live-e2e/kshop/generic-opener');

const ROOT = path.resolve(__dirname, '..', '..');
const OWNED_RELATIVE = path.join('tmp', 'workbench-live-e2e', 'gym');
const OWNED_BASE = path.join(ROOT, OWNED_RELATIVE);
const EXPECTED_PROJECTS = Object.freeze({
    goldStat:{ id:'dummy.0', currency:'money', cost:60000, rewardAmount:3,
        durationMs:10000, rewardLabel:'空手攻击力', cap:500 },
    kSkill:{ id:'dummy.7', currency:'kpoint', cost:1250, rewardAmount:25,
        durationMs:1000, rewardLabel:'技能点', cap:null }
});

function fail(code, message, details) {
    const error = new Error(message);
    error.code = code;
    error.details = details || null;
    throw error;
}

function parseArgs(argv) {
    if (argv.includes('--help') || argv.includes('-h')) return { help:true };
    const observeOnly = argv.includes('--observe-only');
    const flags = argv.filter(arg => arg === '--execute-isolated-candidate'
        || arg === '--allow-clone-training-writes' || arg === '--observe-only');
    const expectedFlags = observeOnly
        ? ['--execute-isolated-candidate', '--observe-only']
        : ['--execute-isolated-candidate', '--allow-clone-training-writes'];
    if (flags.length !== 2 || expectedFlags.some(flag => !flags.includes(flag))) {
        fail('gym_run_explicit_scope_required',
            'choose exact observe-only or clone-training-write execution flags');
    }
    const args = Preflight.parseArgs(argv.filter(arg => !flags.includes(arg)));
    if (!args.expectedBuildIdentity || !args.expectedPayloadClosure) {
        fail('gym_run_identity_pin_required',
            'candidate build identity and payload closure must both be pinned');
    }
    return Object.assign(args, {
        slot:Preflight.TARGET_SLOT, ownedBaseRelative:OWNED_RELATIVE,
        readyTimeoutMs:180000, operatorTimeoutMs:60000, pollMs:200,
        cloneBaselineTimeoutMs:30000, cloneBaselineStableMs:2000,
        preserveSeedBytes:true, observeOnly
    });
}

function help() {
    return [
        'Gym full journey in an isolated candidate and fixed cf7_agent_gym clone.',
        'No Computer Use, direct Panel/Bridge success call, fresh slot, or real-slot write.',
        'Usage: node tools/gym-e2e/run-candidate.js',
        '  --candidate-root <absolute candidate> --seed-slot <exact source slot>',
        '  --expected-build-identity <SHA-256> --expected-payload-closure <SHA-256>',
        '  [--allow-read-only-live-seed]',
        '  --execute-isolated-candidate --observe-only',
        'or --execute-isolated-candidate --allow-clone-training-writes'
    ].join('\n');
}

function runDirectory() {
    fs.mkdirSync(OWNED_BASE, { recursive:true });
    SharedEvidence.assertExactDirectory(OWNED_BASE, 'gym_run_directory');
    const runDir = path.join(OWNED_BASE, timestampId() + '-u4-' + Preflight.TARGET_SLOT);
    fs.mkdirSync(runDir);
    return SharedEvidence.assertOwnedRunDirectory(ROOT, runDir,
        OWNED_RELATIVE, 'gym_run_directory');
}

function messageOf(entry) {
    if (!entry || !['webview_message', 'bridge_send'].includes(entry.kind)) return null;
    if (entry.message && typeof entry.message === 'object'
            && !Array.isArray(entry.message)) return entry.message;
    if (typeof entry.message !== 'string') return null;
    try { return JSON.parse(entry.message); }
    catch (_error) { return null; }
}

async function until(label, timeoutMs, pollMs, predicate) {
    const deadline = Date.now() + timeoutMs;
    let lastError = null;
    while (Date.now() <= deadline) {
        try {
            const result = await predicate();
            if (result) return result;
        } catch (error) { lastError = error; }
        await sleep(pollMs);
    }
    fail('gym_' + label + '_timeout', label + ' did not reach the required state',
        { lastError:lastError && lastError.message || null });
}

function assertProject(project, expected) {
    if (!project || Object.keys(expected).some(key => project[key] !== expected[key])) {
        fail('gym_project_terms_changed', 'frozen gym test project terms changed',
            { id:expected.id, project });
    }
    return project;
}

async function openGym(runtime, writer, input, excludedInstance) {
    const afterSequence = writer.events.length;
    const response = await runtime.session.agentControl('openGym', {
        expectedSlot:Preflight.TARGET_SLOT,
        expectedAttemptId:runtime.ready.expectedAttemptId
    });
    LauncherObservation.assertResponseSucceeded(response, 'gym_open', 'fixed agent_control openGym');
    if (response.note !== 'gym_panel_open_requested') {
        fail('gym_opener_note_invalid', 'fixed AS2 gym opener did not acknowledge its request');
    }
    return until('open', 30000, 200, async () => {
        const status = await runtime.session.agentControl('status');
        LauncherObservation.assertRuntimeReadyStatus(status, Preflight.TARGET_SLOT,
            runtime.ready.expectedAttemptId);
        const active = status.activePanel;
        if (!active || active.name !== 'gym' || !active.instanceId
                || active.instanceId === excludedInstance) return null;
        const open = writer.events.find(entry => entry.sequence > afterSequence
            && messageOf(entry)?.type === 'panel_cmd'
            && messageOf(entry)?.cmd === 'open'
            && messageOf(entry)?.panel === 'gym'
            && messageOf(entry)?.panelInstanceId === active.instanceId);
        if (!open) return null;
        const initData = messageOf(open).initData || {};
        const snapshot = initData.snapshot || {};
        if (initData.mode !== 'preview' || initData.source !== 'world_gym'
                || initData.stationId !== 'dummy' || snapshot.stationId !== 'dummy'
                || snapshot.v !== 2 || snapshot.pendingSession !== null) {
            fail('gym_formal_route_invalid', 'gym did not arrive through the fixed AS2 opener',
                { mode:initData.mode, source:initData.source, station:initData.stationId });
        }
        const gold = assertProject((snapshot.projects || []).find(row => row.id === 'dummy.0'),
            EXPECTED_PROJECTS.goldStat);
        const skill = assertProject((snapshot.projects || []).find(row => row.id === 'dummy.7'),
            EXPECTED_PROJECTS.kSkill);
        const visible = await input.readState();
        if (visible.url !== 'https://overlay.local/overlay.html'
                || visible.panel !== 'gym' || visible.hidden
                || visible.station !== '木人桩'
                || !visible.projects.some(row => row.id === gold.id && row.selected)
                || !visible.projects.some(row => row.id === skill.id)) return null;
        return { instanceId:active.instanceId, openSequence:open.sequence,
            balances:snapshot.balances, projects:{ gold, skill }, visible };
    });
}

function settledAfter(writer, sequence, projectId, kind) {
    const event = writer.events.find(entry => entry.sequence > sequence
        && messageOf(entry)?.type === 'panel_event'
        && messageOf(entry)?.panel === 'gym'
        && messageOf(entry)?.event === 'settled'
        && messageOf(entry)?.phase === 'applied'
        && messageOf(entry)?.saved === true
        && messageOf(entry)?.projectId === projectId
        && messageOf(entry)?.award?.kind === kind);
    return event && { sequence:event.sequence, eventHash:event.eventHash,
        result:messageOf(event) };
}

async function clickAndProve(writer, input, target) {
    const watermark = writer.events.length;
    const geometry = await input.click(target);
    const trusted = await until('trusted_click', 10000, 50, () => {
        const event = writer.events.find(entry => entry.sequence > watermark
            && entry.kind === 'dom_input' && entry.eventType === 'click'
            && entry.isTrusted === true && entry.panelState?.panel === 'gym'
            && entry.panelState.hidden === false && entry.target?.visible === true
            && entry.target.enabled === true && entry.target.hitTargetMatches === true
            && entry.clientX >= geometry.rect.left
            && entry.clientX <= geometry.rect.left + geometry.rect.width
            && entry.clientY >= geometry.rect.top
            && entry.clientY <= geometry.rect.top + geometry.rect.height);
        return event && { sequence:event.sequence, eventHash:event.eventHash,
            browserIsTrusted:true, physicalInputAttestation:false };
    });
    return { geometry, trusted };
}

async function closeGym(runtime, input, writer, expectedInstance) {
    const click = await clickAndProve(writer, input, 'close');
    const closed = await until('close', 15000, 200, async () => {
        const status = await runtime.session.agentControl('status');
        const active = status.activePanel;
        const visible = await input.readState();
        const idle = !active || (active.name == null && active.instanceId == null);
        return idle && visible.hidden && visible.panel !== 'gym'
            ? { activePanel:active || null, visiblePanel:visible.panel,
                closedInstance:expectedInstance } : null;
    });
    return { click, closed };
}

function expectSameLedger(before, after, phase) {
    if (!Ledger.sameValues(before, after)) {
        fail('gym_' + phase + '_economic_delta',
            phase + ' changed currency, experience, skill points, or gym bonuses',
            { before:before.values, after:after.values });
    }
}

function solArtifacts(set) {
    return (set && set.artifacts || []).filter(item => item.kind === 'sol');
}

async function stableArtifacts(runtime, args) {
    return CloneSaveGuard.captureStableSlotArtifactSet({ root:ROOT,
        appData:runtime.appData, slot:Preflight.TARGET_SLOT, requireJson:true,
        timeoutMs:args.cloneBaselineTimeoutMs,
        stableMs:args.cloneBaselineStableMs, pollMs:args.pollMs });
}

function assertSolAdvanced(before, after, phase) {
    const prior = solArtifacts(before.set || before);
    const next = solArtifacts(after.set || after);
    if (!next.length
            || (prior.length > 0
                && SharedEvidence.canonicalJson(prior) === SharedEvidence.canonicalJson(next))) {
        fail('gym_' + phase + '_sol_unchanged',
            'strict saved result did not change the dedicated slot SOL artifact');
    }
    return { before:prior, after:next };
}

function expectGoldDelta(before, after, settled) {
    const prior = before.values, next = after.values, result = settled.result;
    const award = result.award || {};
    const other = ['hp','mp','defense','innerPower'];
    if (award.kind !== 'stat' || award.amount !== 3 || award.baseExperience !== 10000
            || award.capExperience !== 0 || next.money !== prior.money - 60000
            || next.kpoint !== prior.kpoint || next.bonuses.unarmed !== prior.bonuses.unarmed + 3
            || other.some(key => next.bonuses[key] !== prior.bonuses[key])
            || next.experience !== prior.experience + 10000
            || next.level !== result.level || next.skillPoints !== result.skillPoints
            || result.balances?.money !== next.money || result.balances?.kpoint !== next.kpoint
            || result.current !== next.bonuses.unarmed) {
        fail('gym_gold_settlement_delta', 'gold stat settlement differs from saved AS2 result',
            { prior, next, result });
    }
}

function expectSkillDelta(before, after, settled) {
    const prior = before.values, next = after.values, result = settled.result;
    const award = result.award || {};
    if (award.kind !== 'skillPoints' || award.amount !== 25
            || award.baseExperience !== 0 || award.capExperience !== 0
            || next.money !== prior.money || next.kpoint !== prior.kpoint - 1250
            || next.experience !== prior.experience || next.level !== prior.level
            || next.skillPoints !== prior.skillPoints + 25
            || Ledger.BONUS_FIELDS.some(key => next.bonuses[key] !== prior.bonuses[key])
            || result.balances?.money !== next.money || result.balances?.kpoint !== next.kpoint
            || result.current !== next.skillPoints) {
        fail('gym_kpoint_settlement_delta', 'K-point skill settlement differs from saved AS2 result',
            { prior, next, result });
    }
}

async function finishSession(input, writer, projectId, kind, timeoutMs) {
    const watermark = writer.events.length;
    const start = await clickAndProve(writer, input, 'start');
    let pausedSince = null;
    const completion = await until('settlement', timeoutMs, 200, async () => {
        const visible = await input.readState();
        if (visible.panel !== 'gym' || visible.hidden) return null;
        if (visible.progress.status.includes('已暂停计时')) {
            if (pausedSince === null) pausedSince = Date.now();
            if (Date.now() - pausedSince > 3000) {
                fail('gym_candidate_not_active',
                    'candidate window stayed inactive; training clock correctly remained paused');
            }
            return null;
        }
        pausedSince = null;
        if (visible.progress.status.includes('待核实')
                || visible.progress.status.includes('等待保存')
                || visible.progress.status.includes('无法核实')) {
            fail('gym_settlement_not_confirmed', 'training result needs reconcile or save');
        }
        const settled = settledAfter(writer, watermark, projectId, kind);
        if (settled && visible.progress.status.includes('已结算并保存')) {
            return { start, settled, visible };
        }
        return null;
    });
    return completion;
}

async function waitNoLauncher() {
    return until('launcher_shutdown', 30000, 250, () => {
        try { return assertNoLauncherBeforeMutation() === true; }
        catch (_error) { return false; }
    });
}

async function shutdown(runtime) {
    const response = await runtime.session.agentControl('shutdown');
    LauncherObservation.assertResponseSucceeded(response, 'gym_shutdown', 'agent_control shutdown');
    await waitNoLauncher();
    return { responseSucceeded:true, pid:runtime.identity.pid };
}

async function main(argv) {
    const args = parseArgs(argv);
    if (args.help) { process.stdout.write(help() + '\n'); return; }
    const preflight = Preflight.inspect(args);
    // Resolve and audit the Gym observer before cloning any save.
    const { TranscriptWriter, attachPassiveObserver } =
        require('./passive-observer');
    const sourceClosure = SourceClosure.capture(ROOT);
    const runDir = runDirectory();
    const writer = new TranscriptWriter(runDir, 'gym-u4-' + timestampId());
    const report = { schema:'cf7-gym-e2e.candidate-journey.v1',
        status:'running', startedAt:new Date().toISOString(), runDir,
        preflight, sourceClosure, phases:[] };
    let first = null, current = null, observer = null, input = null, released = false;
    function persist() { atomicWriteJson(path.join(runDir, 'report.json'), report); }
    persist();
    async function attach(runtime) {
        observer = await attachPassiveObserver({ root:ROOT, runDir, writer,
            cdpBinding:runtime.cdpBinding, runtimeIdentity:runtime.identity,
            sourceClosure,
            timeoutMs:args.readyTimeoutMs, pollMs:args.pollMs,
        });
        input = await openGymInputChannel({ runDir, cdpBinding:runtime.cdpBinding,
            runtimeIdentity:runtime.identity, writer,
            timeoutMs:args.readyTimeoutMs, pollMs:args.pollMs });
    }
    async function detach() {
        if (input) { input.close(); input = null; }
        if (observer) { await observer.detach(); observer = null; }
    }
    try {
        first = await openGenericRuntime(ROOT, args, runDir);
        current = first;
        if (first.preparation.transformId !== 'exact-byte-copy'
                || first.expectedIdentity.buildIdentity !== preflight.candidate.buildIdentity
                || first.expectedIdentity.payloadClosure !== preflight.candidate.payloadClosure
                || first.preparation.seedBegin.setSha256 !== preflight.seedArtifactSetSha256
                || first.preparation.targetBefore.setSha256
                    !== preflight.targetBeforeArtifactSetSha256) {
            fail('gym_candidate_or_clone_drift', 'candidate identity or exact clone changed after preflight');
        }
        report.candidate = { firstPid:first.identity.pid,
            buildIdentity:first.identity.buildIdentity,
            payloadClosureSha256:first.identity.payloadClosureSha256,
            executablePath:first.identity.executablePath };
        await attach(first);
        const before = Ledger.capture(ROOT, Preflight.TARGET_SLOT);
        const beforeArtifacts = first.baseline;
        if (before.values.money < 60000 || before.values.kpoint < 1250
                || before.values.bonuses.unarmed > 497) {
            fail('gym_clone_seed_not_eligible',
                'clone needs 60,000 gold, 1,250 K points, and room for +3 unarmed bonus');
        }
        const open1 = await openGym(first, writer, input, null);
        report.loadedWebFirst = await observer.assertLoadedGymScripts();
        if (open1.balances.money !== before.values.money
                || open1.balances.kpoint !== before.values.kpoint) {
            fail('gym_open_balance_mismatch', 'AS2 open snapshot differs from clone ledger');
        }
        const preview = await input.captureScreenshot(path.join(runDir, 'gym-preview.png'), 'preview');
        if (args.observeOnly) {
            const close = await closeGym(first, input, writer, open1.instanceId);
            expectSameLedger(before, Ledger.capture(ROOT, Preflight.TARGET_SLOT),
                'observe_only');
            report.phases.push({ phase:'formal_open_close_observe_only',
                openInstance:open1.instanceId, preview, close, zeroGymLedgerDelta:true });
            await detach();
            report.firstShutdown = await shutdown(first);
            report.cloneLifecycle = releaseGenericClone(first);
            released = true;
            SourceClosure.assertUnchanged(sourceClosure, SourceClosure.capture(ROOT));
            report.sourceClosureUnchanged = true;
            report.transcript = writer.flush({ journeyComplete:true, observeOnly:true });
            report.status = 'passed_observe_only';
            report.completedAt = new Date().toISOString();
            report.reportSha256 = sha256Text(canonicalJson(report));
            persist();
            process.stdout.write(JSON.stringify({ ok:true, observeOnly:true, runDir,
                reportSha256:report.reportSha256, candidate:report.candidate }, null, 2) + '\n');
            return;
        }
        await clickAndProve(writer, input, 'start');
        const running = await until('cancel_running', 5000, 100, async () => {
            const state = await input.readState();
            return state.progress.status.startsWith('已进行') && state.progress.value < 50
                ? state : null;
        });
        expectSameLedger(before, Ledger.capture(ROOT, Preflight.TARGET_SLOT), 'before_cancel');
        await clickAndProve(writer, input, 'cancelTarget');
        const cancelled = await until('cancel', 10000, 150, async () => {
            const state = await input.readState();
            return state.progress.status === '尚未开始训练'
                && state.start.text === '开始训练'
                && state.projects.some(row => row.id === 'dummy.1' && row.selected)
                ? state : null;
        });
        expectSameLedger(before, Ledger.capture(ROOT, Preflight.TARGET_SLOT), 'cancel');
        const close1 = await closeGym(first, input, writer, open1.instanceId);
        report.phases.push({ phase:'cancel_before_finish', openInstance:open1.instanceId,
            preview, running, cancelled, close:close1, zeroGymLedgerDelta:true });
        persist();

        const open2 = await openGym(first, writer, input, open1.instanceId);
        const gold = await finishSession(input, writer, 'dummy.0', 'stat', 45000);
        const afterGold = await until('gold_durable', 10000, 150, () => {
            const value = Ledger.capture(ROOT, Preflight.TARGET_SLOT);
            return value.values.money === before.values.money - 60000 ? value : null;
        });
        expectGoldDelta(before, afterGold, gold.settled);
        const afterGoldArtifacts = await stableArtifacts(first, args);
        const goldSol = assertSolAdvanced(beforeArtifacts, afterGoldArtifacts, 'gold');
        const goldScreenshot = await input.captureScreenshot(
            path.join(runDir, 'gym-gold-complete.png'), 'gold-complete');
        const close2 = await closeGym(first, input, writer, open2.instanceId);
        report.phases.push({ phase:'gold_stat_completed', openInstance:open2.instanceId,
            settledSequence:gold.settled.sequence, result:gold.settled.result,
            before:before.values, after:afterGold.values,
            sol:goldSol, screenshot:goldScreenshot, close:close2 });
        persist();

        const open3 = await openGym(first, writer, input, open2.instanceId);
        await clickAndProve(writer, input, 'kSkill');
        const selected = await input.readState();
        if (!selected.projects.some(row => row.id === 'dummy.7' && row.selected)) {
            fail('gym_skill_selection_missing', 'fixed K skill project was not selected');
        }
        const skill = await finishSession(input, writer, 'dummy.7', 'skillPoints', 20000);
        const afterSkill = await until('skill_durable', 10000, 150, () => {
            const value = Ledger.capture(ROOT, Preflight.TARGET_SLOT);
            return value.values.kpoint === afterGold.values.kpoint - 1250 ? value : null;
        });
        expectSkillDelta(afterGold, afterSkill, skill.settled);
        const afterSkillArtifacts = await stableArtifacts(first, args);
        const skillSol = assertSolAdvanced(afterGoldArtifacts, afterSkillArtifacts, 'kpoint');
        const skillScreenshot = await input.captureScreenshot(
            path.join(runDir, 'gym-kpoint-complete.png'), 'kpoint-complete');
        const close3 = await closeGym(first, input, writer, open3.instanceId);
        report.phases.push({ phase:'kpoint_skill_completed', openInstance:open3.instanceId,
            settledSequence:skill.settled.sequence, result:skill.settled.result,
            before:afterGold.values, after:afterSkill.values,
            sol:skillSol, screenshot:skillScreenshot, close:close3 });
        persist();

        await detach();
        report.firstShutdown = await shutdown(first);
        current = await restartGenericRuntime(ROOT, args, first.preparation,
            first.expectedIdentity, first);
        report.candidate.restartPid = current.identity.pid;
        if (current.identity.pid === first.identity.pid) {
            fail('gym_restart_pid_reused', 'restart must have a fresh candidate PID');
        }
        await attach(current);
        const readback = Ledger.capture(ROOT, Preflight.TARGET_SLOT);
        expectSameLedger(afterSkill, readback, 'restart_readback');
        const open4 = await openGym(current, writer, input, null);
        report.loadedWebRestart = await observer.assertLoadedGymScripts();
        if (open4.balances.money !== readback.values.money
                || open4.balances.kpoint !== readback.values.kpoint
                || open4.projects.gold.current !== readback.values.bonuses.unarmed
                || open4.projects.skill.current !== readback.values.skillPoints) {
            fail('gym_restart_projection_mismatch',
                'AS2 restart snapshot differs from durable clone ledger');
        }
        const restartScreenshot = await input.captureScreenshot(
            path.join(runDir, 'gym-restart-readback.png'), 'restart-readback');
        await closeGym(current, input, writer, open4.instanceId);
        report.phases.push({ phase:'restart_readback', pid:current.identity.pid,
            ledger:readback.values, screenshot:restartScreenshot });
        await detach();
        report.restartShutdown = await shutdown(current);
        report.cloneLifecycle = releaseGenericClone(first);
        released = true;
        SourceClosure.assertUnchanged(sourceClosure, SourceClosure.capture(ROOT));
        report.sourceClosureUnchanged = true;
        report.transcript = writer.flush({ journeyComplete:true });
        report.status = 'passed';
        report.completedAt = new Date().toISOString();
        report.reportSha256 = sha256Text(canonicalJson(report));
        persist();
        process.stdout.write(JSON.stringify({ ok:true, runDir,
            reportSha256:report.reportSha256, candidate:report.candidate,
            phases:report.phases.map(row => row.phase) }, null, 2) + '\n');
    } catch (error) {
        report.status = 'failed_closed';
        report.failedAt = new Date().toISOString();
        report.failure = { code:error.code || 'unhandled_error',
            message:String(error.message || error), details:error.details || null };
        try { await detach(); } catch (detachError) {
            report.detachFailure = String(detachError.message || detachError);
        }
        try { if (current) report.failureShutdown = await shutdown(current); }
        catch (shutdownError) { report.shutdownFailure = String(shutdownError.message || shutdownError); }
        try {
            if (first && !released) {
                assertNoLauncherBeforeMutation();
                report.cloneLifecycle = releaseGenericClone(first);
                released = true;
            }
        } catch (releaseError) {
            report.cloneReleaseFailure = String(releaseError.message || releaseError);
        }
        try { report.transcript = writer.flush({ journeyComplete:false }); }
        catch (flushError) { report.transcriptFailure = String(flushError.message || flushError); }
        persist();
        throw error;
    }
}

module.exports = { EXPECTED_PROJECTS, parseArgs, assertProject,
    expectGoldDelta, expectSkillDelta, expectSameLedger };

if (require.main === module) {
    main(process.argv.slice(2)).catch(error => {
        console.error(error && error.stack || String(error));
        process.exitCode = 1;
    });
}
