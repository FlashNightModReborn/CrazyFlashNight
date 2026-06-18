#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const timelinePath = path.join(projectRoot, 'launcher', 'web', 'modules', 'asset-timeline.js');
const timelineSource = fs.readFileSync(timelinePath, 'utf8').replace(/^\uFEFF/, '');

const context = { console };
vm.createContext(context);
vm.runInContext(timelineSource, context, { filename: 'asset-timeline.js' });

const Timeline = context.AssetTimeline;
if (!Timeline) throw new Error('AssetTimeline was not exported.');

const entry = {
    fps: 1,
    frames: [
        { frame: 1, uri: 'raw1.png' },
        { frame: 2, uri: 'raw2.png' }
    ],
    timelineFrames: [
        { frame: 1, uri: 'hold-a.png', durationFrames: 3 },
        { frame: 4, uri: 'hold-b.png', durationFrames: 2 }
    ]
};

const samples = [0, 2000, 3000, 4000, 5000].map(nowMs => ({
    nowMs,
    uri: Timeline.select(entry, nowMs).frame.uri
}));

const duplicateOnly = {
    fps: 1,
    frames: [
        { frame: 1, uri: 'same.png' },
        { frame: 2, uri: 'same.png', duplicateOfFrame: 1 }
    ]
};
const duplicateSelection = Timeline.select(duplicateOnly, 1000);

const layerA = { fps: 1, frames: [1, 2, 3, 4, 5].map(i => ({ frame: i, uri: `a${i}.png` })) };
const layerB = { fps: 1, frames: [1, 2, 3, 4, 5, 6, 7].map(i => ({ frame: i, uri: `b${i}.png` })) };
const independent = {
    at6s: {
        a: Timeline.select(layerA, 6000).frame.uri,
        b: Timeline.select(layerB, 6000).frame.uri
    },
    at7s: {
        a: Timeline.select(layerA, 7000).frame.uri,
        b: Timeline.select(layerB, 7000).frame.uri
    }
};

const payload = {
    playbackUsesTimelineFrames: Timeline.playbackFrames(entry)[0].uri === 'hold-a.png',
    totalDurationFrames: Timeline.totalDurationFrames(Timeline.playbackFrames(entry)),
    samples,
    duplicateOnlyAnimated: duplicateSelection.animated,
    duplicateOnlyDistinct: Timeline.distinctFrameCount(duplicateOnly.frames, ['uri']),
    independent
};

process.stdout.write(JSON.stringify(payload, null, 2) + '\n');

const expected = ['hold-a.png', 'hold-a.png', 'hold-b.png', 'hold-b.png', 'hold-a.png'];
const sampleFailure = samples.some((sample, index) => sample.uri !== expected[index]);
if (
    !payload.playbackUsesTimelineFrames ||
    payload.totalDurationFrames !== 5 ||
    sampleFailure ||
    payload.duplicateOnlyAnimated !== false ||
    payload.duplicateOnlyDistinct !== 1 ||
    independent.at6s.a !== 'a2.png' ||
    independent.at6s.b !== 'b7.png' ||
    independent.at7s.a !== 'a3.png' ||
    independent.at7s.b !== 'b1.png'
) {
    process.exit(1);
}
