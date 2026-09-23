#!/usr/bin/env node
'use strict';

const path = require('path');
const ROOT = path.resolve(__dirname, '..', '..');
const RuntimeIdentity = require(path.join(ROOT, 'tools', 'lib', 'runtime-process-identity'));
const RuntimeGuard = require(path.join(ROOT, 'tools', 'workbench-live-e2e', 'lib', 'runtime-guard'));
const CloneSaveGuard = require(path.join(ROOT, 'tools', 'workbench-live-e2e', 'lib', 'clone-save-guard'));
const SharedEvidence = require(path.join(ROOT, 'tools', 'workbench-live-e2e', 'lib', 'evidence-artifact'));
const GenericOpener = require(path.join(ROOT, 'tools', 'workbench-live-e2e', 'kshop', 'generic-opener'));

const TARGET_SLOT = 'cf7_agent_gym';
const LIVE_SEED = /^crazyflasher7_saves\d*$/i;

function usage(reason) {
    const error = new Error(reason);
    error.code = 'gym_usage_invalid';
    throw error;
}

function parseArgs(argv) {
    const args = { candidateRoot:null, seedSlot:null, expectedBuildIdentity:null,
        expectedPayloadClosure:null, allowReadOnlyLiveSeed:false, help:false };
    for (let index = 0; index < argv.length; index++) {
        const arg = argv[index];
        if (arg === '--help' || arg === '-h') args.help = true;
        else if (arg === '--candidate-root' || arg === '--seed-slot'
                || arg === '--expected-build-identity' || arg === '--expected-payload-closure') {
            const value = argv[++index];
            if (!value || value.startsWith('--')) usage(arg + ' requires a value');
            const key = { '--candidate-root':'candidateRoot', '--seed-slot':'seedSlot',
                '--expected-build-identity':'expectedBuildIdentity',
                '--expected-payload-closure':'expectedPayloadClosure' }[arg];
            args[key] = value;
        } else if (arg === '--allow-read-only-live-seed') args.allowReadOnlyLiveSeed = true;
        else usage('unsupported argument: ' + arg);
    }
    if (args.help) return args;
    if (!args.candidateRoot || !path.isAbsolute(args.candidateRoot)) {
        usage('--candidate-root must be one explicit absolute path');
    }
    if (!args.seedSlot || !/^[A-Za-z0-9_-]{1,80}$/.test(args.seedSlot)
            || args.seedSlot === TARGET_SLOT) {
        usage('--seed-slot must be an exact source slot distinct from cf7_agent_gym');
    }
    if (LIVE_SEED.test(args.seedSlot) && !args.allowReadOnlyLiveSeed) {
        usage('a player slot may only be a read-only seed with --allow-read-only-live-seed');
    }
    for (const key of ['expectedBuildIdentity', 'expectedPayloadClosure']) {
        if (args[key] !== null && !/^[a-f0-9]{64}$/i.test(args[key])) {
            usage(key + ' must be a 64-character SHA-256 value');
        }
    }
    return args;
}

function inspect(args, options) {
    options = options || {};
    const appDataValue = options.appData || process.env.APPDATA;
    if (!appDataValue || !path.isAbsolute(appDataValue)) {
        usage('an exact absolute APPDATA directory is required to account for owned SOL files');
    }
    const repo = SharedEvidence.assertExactDirectory(ROOT, 'gym_preflight');
    const candidateRoot = SharedEvidence.assertExactDirectory(
        path.resolve(args.candidateRoot), 'gym_preflight');
    const appData = SharedEvidence.assertExactDirectory(
        path.resolve(appDataValue), 'gym_preflight');
    GenericOpener.assertNoLauncherBeforeMutation();
    const identity = RuntimeGuard.publicCandidateIdentity(
        RuntimeGuard.validateCandidateIdentity(
            RuntimeIdentity.resolveExpectedRuntimeIdentity(repo, candidateRoot), candidateRoot));
    if (args.expectedBuildIdentity
            && identity.buildIdentity.toUpperCase() !== args.expectedBuildIdentity.toUpperCase()) {
        usage('candidate build identity differs from the pinned expectation');
    }
    if (args.expectedPayloadClosure
            && identity.payloadClosure.toUpperCase() !== args.expectedPayloadClosure.toUpperCase()) {
        usage('candidate payload closure differs from the pinned expectation');
    }
    const seed = CloneSaveGuard.captureSlotArtifactSet({
        root:repo, appData, slot:args.seedSlot, requireJson:true
    });
    const targetBefore = CloneSaveGuard.captureSlotArtifactSet({
        root:repo, appData, slot:TARGET_SLOT, requireJson:false
    });
    const lock = CloneSaveGuard.inspectCloneLock({ root:repo, slot:TARGET_SLOT });
    if (lock.lockPresent || lock.recoveryPresent) {
        usage('cf7_agent_gym has a clone lock or recovery record; resolve it before a run');
    }
    const seedJson = path.join(repo, 'saves', args.seedSlot + '.json');
    const seedFile = SharedEvidence.readExactRegularFile(seedJson, {
        phase:'gym_preflight', maximumBytes:128 * 1024 * 1024
    });
    let data;
    try { data = JSON.parse(seedFile.bytes.toString('utf8')); }
    catch (error) { usage('seed JSON is invalid: ' + error.message); }
    if (!GenericOpener.isValidSaveData(data)) usage('seed does not satisfy the runtime save contract');
    return {
        schema:'cf7-gym-e2e.preflight.v1',
        writePerformed:false,
        targetSlot:TARGET_SLOT,
        seedSlot:args.seedSlot,
        seedIsLive:LIVE_SEED.test(args.seedSlot),
        seedArtifactSetSha256:seed.setSha256,
        targetBeforeArtifactSetSha256:targetBefore.setSha256,
        targetBeforeArtifacts:targetBefore.artifacts.length,
        candidate:identity,
        cloneLockAbsent:true,
        runRequiresFreshClone:true
    };
}

function help() {
    return [
        'Gym isolated-candidate read-only preflight (does not launch or train).',
        'Usage: node tools/gym-e2e/preflight.js --candidate-root <absolute candidate>',
        '       --seed-slot <exact source slot> [--allow-read-only-live-seed]',
        '       [--expected-build-identity <SHA-256> --expected-payload-closure <SHA-256>]',
        'The future runner target is fixed to cf7_agent_gym; this command performs no writes.'
    ].join('\n');
}

if (require.main === module) {
    try {
        const args = parseArgs(process.argv.slice(2));
        process.stdout.write(args.help ? help() + '\n' : JSON.stringify(inspect(args), null, 2) + '\n');
    } catch (error) {
        console.error(error.code || 'gym_preflight_failed', String(error.message || error));
        process.exitCode = 1;
    }
}

module.exports = { TARGET_SLOT, LIVE_SEED, parseArgs, inspect };
