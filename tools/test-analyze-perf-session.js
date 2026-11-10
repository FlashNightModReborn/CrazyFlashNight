'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const {
    CATEGORY_ORDER,
    SOURCE_SAMPLE_STALE_MS,
    analyzeLines,
    classifyPerfSample,
    formatHumanSummary,
    isSameFilePath,
    main
} = require('./analyze-perf-session.js');

function sample(overrides) {
    return Object.assign({
        type: 'perf_sample',
        connected: true,
        connectionState: 'connected',
        paused: false,
        foreground: true,
        minimized: false,
        hostFrameOrdinal: 100,
        sourceSampleSequence: 200,
        acceptedSampleFrame: 300,
        connectionGeneration: 1,
        sourceScene: 1,
        transportAgeMs: 10,
        frameIngressAgeMs: 10,
        sampleAgeMs: 10,
        sampleRejectReason: null
    }, overrides || {});
}

function advancing(overrides) {
    return sample(Object.assign({
        hostFrameOrdinal: 101,
        sourceSampleSequence: 201,
        acceptedSampleFrame: 301
    }, overrides || {}));
}

test('disconnect evidence has highest priority, even over inactivity and missing fields', () => {
    const disconnected = classifyPerfSample({
        type: 'perf_sample',
        connected: false,
        paused: true
    }, null);
    assert.equal(disconnected.category, 'disconnected');
    assert.equal(disconnected.reasonCode, 'explicit_disconnect');

    const state = classifyPerfSample({ connectionState: 'disconnected' }, null);
    assert.equal(state.category, 'disconnected');
});

test('paused, background and minimized states precede legacy evidence validation', () => {
    for (const value of [{ paused: true }, { foreground: false }, { minimized: true }]) {
        const decision = classifyPerfSample(value, null);
        assert.equal(decision.category, 'paused_or_inactive');
        assert.equal(decision.reasonCode, 'explicit_inactive');
        assert.ok(decision.evidence.triggers.length > 0);
    }
});

test('legacy samples and first samples without a baseline remain insufficient', () => {
    const legacy = classifyPerfSample({ type: 'perf_sample', timestamp: 1 }, null);
    assert.equal(legacy.category, 'insufficient_evidence');
    assert.equal(legacy.reasonCode, 'missing_required_evidence');
    assert.ok(legacy.evidence.missingFields.includes('hostFrameOrdinal'));
    assert.ok(legacy.evidence.missingFields.includes('acceptedSampleFrame'));
    assert.ok(legacy.evidence.missingFields.includes('connectionGeneration'));
    assert.ok(legacy.evidence.missingFields.includes('sourceScene'));
    assert.ok(legacy.evidence.missingFields.includes('previous_sample'));

    const first = classifyPerfSample(sample(), null);
    assert.equal(first.category, 'insufficient_evidence');
    assert.deepEqual(first.evidence.missingFields, ['previous_sample']);

    const invalidPrevious = classifyPerfSample(advancing(), { hostFrameOrdinal: 100 });
    assert.equal(invalidPrevious.category, 'insufficient_evidence');
    assert.ok(invalidPrevious.evidence.missingFields.includes('previous.acceptedSampleFrame'));
    assert.ok(invalidPrevious.evidence.missingFields.includes('previous.connectionGeneration'));
    assert.ok(invalidPrevious.evidence.missingFields.includes('previous.sourceScene'));
});

test('legacy F, accepted and acceptedSampleSequence fields are never canonical aliases', () => {
    const legacy = {
        type: 'perf_sample',
        F: 101,
        sourceSampleSequence: 201,
        accepted: 301,
        acceptedSampleSequence: 301,
        transportAgeMs: 10,
        frameIngressAgeMs: 10,
        sampleAgeMs: 10
    };
    const currentDecision = classifyPerfSample(legacy, sample());
    assert.equal(currentDecision.category, 'insufficient_evidence');
    assert.deepEqual(currentDecision.evidence.missingFields, [
        'hostFrameOrdinal',
        'acceptedSampleFrame',
        'connectionGeneration',
        'sourceScene'
    ]);

    const previousDecision = classifyPerfSample(advancing(), legacy);
    assert.equal(previousDecision.category, 'insufficient_evidence');
    assert.ok(previousDecision.evidence.missingFields.includes('previous.hostFrameOrdinal'));
    assert.ok(previousDecision.evidence.missingFields.includes('previous.acceptedSampleFrame'));
});

test('canonical samples missing connection identity fields remain insufficient', () => {
    for (const field of ['connectionGeneration', 'sourceScene']) {
        const current = advancing();
        delete current[field];
        const decision = classifyPerfSample(current, sample());
        assert.equal(decision.category, 'insufficient_evidence');
        assert.equal(decision.reasonCode, 'missing_required_evidence');
        assert.deepEqual(decision.evidence.missingFields, [field]);
        assert.equal(Object.hasOwn(decision.evidence, 'hostFrameOrdinal'), false);
    }
});

test('reconnect sequence zeroing is generation_changed, then same-identity samples resume healthy', async () => {
    const before = sample({ connectionGeneration: 1 });
    const reconnected = sample({
        connectionGeneration: 2,
        hostFrameOrdinal: 0,
        sourceSampleSequence: 0,
        acceptedSampleFrame: 0,
        transportAgeMs: 5000,
        frameIngressAgeMs: 5000
    });
    const resumed = sample({
        connectionGeneration: 2,
        hostFrameOrdinal: 1,
        sourceSampleSequence: 1,
        acceptedSampleFrame: 1
    });
    const report = await analyzeLines([before, reconnected, resumed].map(value => JSON.stringify(value)));

    assert.deepEqual(report.decisions.map(row => row.reasonCode), [
        'missing_required_evidence',
        'generation_changed',
        'all_required_sequences_advanced'
    ]);
    assert.deepEqual(report.decisions.map(row => row.category), [
        'insufficient_evidence',
        'insufficient_evidence',
        'healthy'
    ]);
    assert.deepEqual(report.decisions[1].evidence.connectionGeneration, { previous: 1, current: 2 });
    assert.equal(Object.hasOwn(report.decisions[1].evidence, 'hostFrameOrdinal'), false);
    assert.equal(report.classificationCounts.transport_quiet_unknown, 0);
});

test('new-scene source reset is source_scene_changed, then same-scene samples resume healthy', async () => {
    const before = sample({ sourceScene: 1 });
    const changed = sample({
        sourceScene: 2,
        hostFrameOrdinal: 101,
        sourceSampleSequence: 0,
        acceptedSampleFrame: 0,
        sampleAgeMs: 5000
    });
    const resumed = sample({
        sourceScene: 2,
        hostFrameOrdinal: 102,
        sourceSampleSequence: 1,
        acceptedSampleFrame: 1
    });
    const report = await analyzeLines([before, changed, resumed].map(value => JSON.stringify(value)));

    assert.deepEqual(report.decisions.map(row => row.reasonCode), [
        'missing_required_evidence',
        'source_scene_changed',
        'all_required_sequences_advanced'
    ]);
    assert.deepEqual(report.decisions.map(row => row.category), [
        'insufficient_evidence',
        'insufficient_evidence',
        'healthy'
    ]);
    assert.deepEqual(report.decisions[1].evidence.sourceScene, {
        previous: 1,
        current: 2
    });
    assert.equal(Object.hasOwn(report.decisions[1].evidence, 'sourceSampleSequence'), false);
    assert.equal(report.classificationCounts.source_sample_stale, 0);
});

test('fresh transport plus stopped stale frame ingress identifies a stalled frame pipeline first', () => {
    const current = advancing({
        hostFrameOrdinal: 100,
        transportAgeMs: 50,
        frameIngressAgeMs: 2500,
        acceptedSampleFrame: 300,
        sampleAgeMs: 5000,
        sampleRejectReason: 'rate_out_of_policy'
    });
    const decision = classifyPerfSample(current, sample());
    assert.equal(decision.category, 'frame_pipeline_stalled');
    assert.equal(decision.reasonCode, 'transport_fresh_frame_stale');
    assert.equal(decision.evidence.hostFrameOrdinal.advanced, false);
    assert.match(decision.reason, /transportAgeMs=50ms/);
});

test('quiet frame and transport evidence is unknown, not proof of disconnect or AS2 activity', () => {
    const previous = sample({ compositorReceived: 10, compositorPresented: 20 });
    const current = sample({
        hostFrameOrdinal: 100,
        sourceSampleSequence: 201,
        acceptedSampleFrame: 300,
        transportAgeMs: 3000,
        frameIngressAgeMs: 3000,
        sampleRejectReason: 'rate_out_of_policy',
        compositorReceived: 11,
        compositorPresented: 21
    });
    const decision = classifyPerfSample(current, previous);
    assert.equal(decision.category, 'transport_quiet_unknown');
    assert.equal(decision.reasonCode, 'frame_and_transport_quiet');
    assert.equal(Object.hasOwn(decision.evidence, 'compositorReceived'), false);
    assert.equal(Object.hasOwn(decision.evidence, 'compositorPresented'), false);
});

test('continued rate policy rejection precedes stale-source classification', () => {
    const current = advancing({
        acceptedSampleFrame: 300,
        sampleAgeMs: 4000,
        sampleRejectReason: 'rate_out_of_policy'
    });
    const decision = classifyPerfSample(current, sample());
    assert.equal(decision.category, 'render_policy_rejected');
    assert.equal(decision.evidence.sourceSampleSequence.advanced, true);
    assert.equal(decision.evidence.acceptedSampleFrame.advanced, false);

    const otherReason = classifyPerfSample(advancing({
        acceptedSampleFrame: 300,
        sampleRejectReason: 'other'
    }), sample());
    assert.equal(otherReason.category, 'insufficient_evidence');
    assert.equal(otherReason.reasonCode, 'no_rule_matched');
});

test('stale source requires advancing hostFrameOrdinal and strictly more than the fixed 2000ms age', () => {
    const stale = advancing({
        sourceSampleSequence: 200,
        acceptedSampleFrame: 301,
        sampleAgeMs: SOURCE_SAMPLE_STALE_MS + 1
    });
    const decision = classifyPerfSample(stale, sample());
    assert.equal(decision.category, 'source_sample_stale');
    assert.equal(decision.evidence.sourceSampleSequence.advanced, false);
    assert.match(decision.reason, /固定阈值 2000ms/);

    const atBoundary = advancing({
        sourceSampleSequence: 200,
        acceptedSampleFrame: 300,
        sampleAgeMs: SOURCE_SAMPLE_STALE_MS
    });
    assert.equal(classifyPerfSample(atBoundary, sample()).category, 'insufficient_evidence');
    assert.throws(
        () => classifyPerfSample(stale, sample(), { sourceSampleStaleMs: 3000 }),
        /fixed at 2000ms/
    );
});

test('healthy requires hostFrameOrdinal, source sequence and acceptedSampleFrame to advance together', () => {
    const previous = sample();
    const current = advancing();
    const before = JSON.stringify(current);
    const decision = classifyPerfSample(current, previous);
    assert.equal(decision.category, 'healthy');
    assert.equal(decision.reasonCode, 'all_required_sequences_advanced');
    assert.equal(JSON.stringify(current), before, 'classification must not mutate its input');

    const compositorOnly = classifyPerfSample(sample({
        received: 999,
        presented: 999
    }), sample({ received: 1, presented: 1 }));
    assert.equal(compositorOnly.category, 'insufficient_evidence');
    assert.notEqual(compositorOnly.category, 'healthy');
});

test('freshness thresholds are configurable except the fixed source age', () => {
    const current = sample({ transportAgeMs: 1500, frameIngressAgeMs: 1500 });
    const previous = sample();
    assert.equal(classifyPerfSample(current, previous).category, 'insufficient_evidence');

    const quiet = classifyPerfSample(current, previous, {
        transportFreshMs: 1000,
        frameIngressStaleMs: 1000
    });
    assert.equal(quiet.category, 'transport_quiet_unknown');
    assert.equal(quiet.evidence.thresholds.transportFreshMs, 1000);
    assert.equal(quiet.evidence.thresholds.frameIngressStaleMs, 1000);
    assert.equal(quiet.evidence.thresholds.sourceSampleStaleMs, 2000);

    const stalled = classifyPerfSample(current, previous, { frameIngressStaleMs: 1000 });
    assert.equal(stalled.category, 'frame_pipeline_stalled');
});

test('streaming line analysis provides auditable counts, decisions and human summary in memory', async () => {
    const previous = sample({ timestamp: 100 });
    const current = advancing({ timestamp: 200 });
    const lines = [
        JSON.stringify({ type: 'metadata', version: 1 }),
        '{not-json',
        '',
        JSON.stringify({ type: 'perf_sample', timestamp: 1 }),
        JSON.stringify(previous),
        JSON.stringify(current),
        JSON.stringify({ type: 'perf_sample', connected: false, timestamp: 300 })
    ];
    const report = await analyzeLines(lines, { inputPath: '<memory>' });

    assert.equal(report.inputLineCount, 7);
    assert.equal(report.blankLineCount, 1);
    assert.equal(report.badLineCount, 1);
    assert.equal(report.otherRecordCount, 1);
    assert.equal(report.perfSampleCount, 4);
    assert.deepEqual(report.badLines.map(row => row.lineNumber), [2]);
    assert.deepEqual(report.decisions.map(row => row.lineNumber), [4, 5, 6, 7]);
    assert.deepEqual(report.decisions.map(row => row.category), [
        'insufficient_evidence',
        'insufficient_evidence',
        'healthy',
        'disconnected'
    ]);
    assert.equal(report.classificationCounts.insufficient_evidence, 2);
    assert.equal(report.classificationCounts.healthy, 1);
    assert.equal(report.classificationCounts.disconnected, 1);
    assert.equal(report.decisions[2].timestamp, 200);
    assert.ok(report.decisions.every(row => row.reason.length > 0));
    assert.deepEqual(Object.keys(report.classificationCounts), CATEGORY_ORDER);
    assert.equal(JSON.stringify(report).includes('main_thread_deadlock'), false);

    const summary = formatHumanSummary(report);
    assert.match(summary, /输入 7 行/);
    assert.match(summary, /坏行=1/);
    assert.match(summary, /source 过期 > 2000ms（固定）/);
});

test('empty and non-perf inputs produce zero classifications instead of guesses', async () => {
    const empty = await analyzeLines([]);
    assert.equal(empty.inputLineCount, 0);
    assert.equal(empty.badLineCount, 0);
    assert.equal(empty.perfSampleCount, 0);
    assert.ok(CATEGORY_ORDER.every(category => empty.classificationCounts[category] === 0));
    assert.match(formatHumanSummary(empty), /不作分类推断/);

    const nonPerf = await analyzeLines([JSON.stringify({ type: 'heartbeat' })]);
    assert.equal(nonPerf.otherRecordCount, 1);
    assert.equal(nonPerf.perfSampleCount, 0);
    assert.ok(CATEGORY_ORDER.every(category => nonPerf.classificationCounts[category] === 0));
});

test('high-rate samples from first sample keep acceptedSampleFrame null while classifying policy rejection and subsequent frame stall', async () => {
    const first = sample({
        hostFrameOrdinal: 1,
        sourceSampleSequence: 1,
        acceptedSampleFrame: null,
        acceptedFps: null,
        acceptedSampleAgeMs: null,
        acceptedStalenessFrames: null,
        sourceFps: 125,
        sampleRejectReason: 'rate_out_of_policy'
    });
    const second = sample({
        hostFrameOrdinal: 2,
        sourceSampleSequence: 2,
        acceptedSampleFrame: null,
        acceptedFps: null,
        acceptedSampleAgeMs: null,
        acceptedStalenessFrames: null,
        sourceFps: 124,
        sampleRejectReason: 'rate_out_of_policy'
    });
    const stalled = sample({
        hostFrameOrdinal: 2,
        sourceSampleSequence: 2,
        acceptedSampleFrame: null,
        acceptedFps: null,
        acceptedSampleAgeMs: null,
        acceptedStalenessFrames: null,
        transportAgeMs: 50,
        frameIngressAgeMs: 2500,
        sampleAgeMs: 2500,
        sampleRejectReason: 'rate_out_of_policy'
    });
    const recovered = sample({
        hostFrameOrdinal: 3,
        sourceSampleSequence: 3,
        acceptedSampleFrame: 3,
        acceptedFps: 30,
        acceptedSampleAgeMs: 10,
        acceptedStalenessFrames: 0,
        sourceFps: 30,
        sampleRejectReason: null
    });

    const report = await analyzeLines([first, second, stalled, recovered].map(row => JSON.stringify(row)));
    assert.deepEqual(report.decisions.map(row => row.category), [
        'insufficient_evidence',
        'render_policy_rejected',
        'frame_pipeline_stalled',
        'healthy'
    ]);
    assert.deepEqual(report.decisions.map(row => row.reasonCode), [
        'missing_required_evidence',
        'source_advanced_accepted_sample_frame_stopped_by_policy',
        'transport_fresh_frame_stale',
        'all_required_sequences_advanced'
    ]);
    assert.deepEqual(report.decisions[1].evidence.acceptedSampleFrame, {
        previous: null,
        current: null,
        advanced: false
    });
    assert.deepEqual(report.decisions[2].evidence.acceptedSampleFrame, {
        previous: null,
        current: null,
        advanced: false
    });
    assert.deepEqual(report.decisions[3].evidence.acceptedSampleFrame, {
        previous: null,
        current: 3,
        advanced: true
    });
});

test('output path guard rejects case-variant and file-alias paths without overwriting input JSONL', async () => {
    assert.equal(isSameFilePath('C:\\logs\\session.jsonl', 'c:\\LOGS\\SESSION.JSONL', 'win32'), true);

    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'cf7-perf-session-test-'));
    try {
        const inputPath = path.join(tempDir, 'session.jsonl');
        const upperCaseAlias = path.join(tempDir, 'SESSION.JSONL');
        const originalContent = JSON.stringify(sample()) + '\n';
        fs.writeFileSync(inputPath, originalContent, 'utf8');

        if (process.platform === 'win32') {
            await assert.rejects(
                () => main([inputPath, '--json', upperCaseAlias]),
                /JSON 输出不能覆盖输入 JSONL/
            );
            assert.equal(fs.readFileSync(inputPath, 'utf8'), originalContent);
        }

        const hardlinkPath = path.join(tempDir, 'alias-link.jsonl');
        fs.linkSync(inputPath, hardlinkPath);
        assert.equal(isSameFilePath(inputPath, hardlinkPath), true);
        await assert.rejects(
            () => main([inputPath, '--json', hardlinkPath]),
            /JSON 输出不能覆盖输入 JSONL/
        );
        assert.equal(fs.readFileSync(inputPath, 'utf8'), originalContent);
    } finally {
        fs.rmSync(tempDir, { recursive: true, force: true });
    }
});
