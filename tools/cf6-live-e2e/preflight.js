#!/usr/bin/env node
'use strict';

const path = require('path');
const ROOT = path.resolve(__dirname, '..', '..');
const RuntimeIdentity = require(path.join(ROOT, 'tools', 'lib', 'runtime-process-identity'));
const RuntimeGuard = require(path.join(ROOT, 'tools', 'workbench-live-e2e', 'lib', 'runtime-guard'));
const CloneSaveGuard = require(path.join(ROOT, 'tools', 'workbench-live-e2e', 'lib', 'clone-save-guard'));
const SharedEvidence = require(path.join(ROOT, 'tools', 'workbench-live-e2e', 'lib', 'evidence-artifact'));
const GenericOpener = require(path.join(ROOT, 'tools', 'workbench-live-e2e', 'kshop', 'generic-opener'));

const {resolveRoute} = require('./route-config');
const TARGET_SLOT = resolveRoute().slot;

function usage(reason) {
    const error = new Error(reason);
    error.code = 'cf6_usage_invalid';
    throw error;
}

function parseArgs(argv) {
    const args = { candidateRoot:null, seedSlot:null, expectedBuildIdentity:null,
        expectedPayloadClosure:null, expectedAsloaderSha256:null, routeId:'historical', help:false };
    for (let index = 0; index < argv.length; index++) {
        const arg = argv[index];
        if (arg === '--help' || arg === '-h') args.help = true;
        else if (arg === '--candidate-root' || arg === '--seed-slot' || arg === '--route'
                || arg === '--expected-build-identity' || arg === '--expected-payload-closure' || arg === '--expected-asloader-sha256') {
            const value = argv[++index];
            if (!value || value.startsWith('--')) usage(arg + ' requires a value');
            const key = { '--candidate-root':'candidateRoot', '--seed-slot':'seedSlot', '--route':'routeId',
                '--expected-build-identity':'expectedBuildIdentity',
                '--expected-payload-closure':'expectedPayloadClosure', '--expected-asloader-sha256':'expectedAsloaderSha256' }[arg];
            args[key] = value;
        } else usage('unsupported argument: ' + arg);
    }
    if (args.help) return args;
    const route=resolveRoute(args.routeId);
    if (!args.candidateRoot || !path.isAbsolute(args.candidateRoot)) {
        usage('--candidate-root must be one explicit absolute path');
    }
    if (!args.seedSlot || !/^cf7_agent_[A-Za-z0-9_-]+$/.test(args.seedSlot)
            || args.seedSlot === route.slot) {
        usage('--seed-slot must be an exact source slot distinct from the selected route target');
    }
    for (const key of ['expectedBuildIdentity', 'expectedPayloadClosure', 'expectedAsloaderSha256']) {
        if (args[key] !== null && !/^[a-f0-9]{64}$/i.test(args[key])) {
            usage(key + ' must be a 64-character SHA-256 value');
        }
    }
    return args;
}

function inspect(args, options) {
    options = options || {};
    const route=resolveRoute(args.routeId);
    const appDataValue = options.appData || process.env.APPDATA;
    if (!appDataValue || !path.isAbsolute(appDataValue)) {
        usage('an exact absolute APPDATA directory is required to account for owned SOL files');
    }
    const repo = SharedEvidence.assertExactDirectory(ROOT, 'cf6_preflight');
    const candidateRoot = SharedEvidence.assertExactDirectory(
        path.resolve(args.candidateRoot), 'cf6_preflight');
    const appData = SharedEvidence.assertExactDirectory(
        path.resolve(appDataValue), 'cf6_preflight');
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
        root:repo, appData, slot:route.slot, requireJson:false
    });
    const lock = CloneSaveGuard.inspectCloneLock({ root:repo, slot:route.slot });
    if (lock.lockPresent || lock.recoveryPresent) {
        usage(route.slot+' has a clone lock or recovery record; resolve it before a run');
    }
    const seedJson = path.join(repo, 'saves', args.seedSlot + '.json');
    const seedFile = SharedEvidence.readExactRegularFile(seedJson, {
        phase:'cf6_preflight', maximumBytes:128 * 1024 * 1024
    });
    let data;
    try { data = JSON.parse(seedFile.bytes.toString('utf8')); }
    catch (error) { usage('seed JSON is invalid: ' + error.message); }
    if (!GenericOpener.isValidSaveData(data)) usage('seed does not satisfy the runtime save contract');
    if (!(Number(data.tasks.tasks_finished['21']) >= 1) || data.ext?.bookRun || data.ext?.bookshelf?.active)
        usage('seed must have story 21 complete and no active book credential');
    const asloader = SharedEvidence.readExactRegularFile(path.join(repo,'scripts','asLoader.swf'),{
        phase:'cf6_preflight',maximumBytes:64*1024*1024});
    if (args.expectedAsloaderSha256 && asloader.sha256.toLowerCase() !== args.expectedAsloaderSha256.toLowerCase())
        usage('asLoader differs from the pinned compiled artifact');
    const chapter = JSON.parse(SharedEvidence.readExactRegularFile(path.join(repo,route.chapterPath),{
        phase:'cf6_preflight',maximumBytes:32*1024*1024}).bytes.toString('utf8'));
    if (chapter.id !== 'cf6-sting' || chapter.routeId !== route.id) usage('selected runtime chapter is unavailable');
    return {
        schema:'cf7-cf6-live-e2e.preflight.v1',
        writePerformed:false,
        routeId:route.id,
        targetSlot:route.slot,
        seedSlot:args.seedSlot,
        seedIsLive:false,
        seedArtifactSetSha256:seed.setSha256,
        targetBeforeArtifactSetSha256:targetBefore.setSha256,
        targetBeforeArtifacts:targetBefore.artifacts.length,
        candidate:identity,
        asloaderSha256:asloader.sha256,
        cloneLockAbsent:true,
        runRequiresFreshClone:true
    };
}

function help() {
    return [
        'CF6 isolated-candidate read-only preflight (does not launch or write saves).',
        'Usage: node tools/cf6-live-e2e/preflight.js --candidate-root <absolute candidate>',
        '       --seed-slot <existing cf7_agent_* source slot> [--route historical|type61]',
        '       [--expected-build-identity <SHA-256> --expected-payload-closure <SHA-256> --expected-asloader-sha256 <SHA-256>]',
        'Each route has one fixed target slot; this command performs no writes.'
    ].join('\n');
}

if (require.main === module) {
    try {
        const args = parseArgs(process.argv.slice(2));
        process.stdout.write(args.help ? help() + '\n' : JSON.stringify(inspect(args), null, 2) + '\n');
    } catch (error) {
        console.error(error.code || 'cf6_preflight_failed', String(error.message || error));
        process.exitCode = 1;
    }
}

module.exports = { TARGET_SLOT, parseArgs, inspect };
