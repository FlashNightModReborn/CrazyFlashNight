#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const {
  aggregateRows,
  deriveCropBox,
  scoreBoxes,
} = require("./evaluate-human-alignment");

const geometry = {
  mustIncludeSafeMargin: 0.1,
  modes: {
    head_closeup: {
      featureAnchor: [0.5, 0.5],
      featureWidthOccupancy: 0.8,
      featureHeightOccupancy: 0.8,
    },
  },
};
const selection = {
  reviewKey: "fixture::default",
  framingMode: "head_closeup",
  featureBox: [0.2, 0.1, 0.6, 0.3],
  mustIncludeBox: [0.2, 0.1, 0.6, 0.3],
};
const crop = deriveCropBox(selection, { width: 100, height: 200 }, geometry);
assert.deepEqual(crop.map((value) => Number(value.toFixed(6))), [0.15, 0.075, 0.65, 0.325]);

const identical = scoreBoxes(crop, crop, 100, 200);
assert.equal(identical.zoomCorrectionToHuman, 1);
assert.equal(identical.centerDistanceInHumanSides, 0);
assert.equal(identical.cropIoU, 1);
assert.equal(identical.loss, 0);
assert.equal(identical.nearHumanTarget, true);

const wide = scoreBoxes([0, 0, 1, 0.5], [0.25, 0.125, 0.75, 0.375], 100, 200);
assert.equal(wide.zoomCorrectionToHuman, 2);
assert.equal(wide.centerDistanceInHumanSides, 0);
assert.equal(wide.cropIoU, 0.25);
assert.equal(wide.absLog2ScaleError, 1);
assert.equal(wide.loss, 1.75);
assert.equal(wide.nearHumanTarget, false);

const aggregate = aggregateRows([
  { candidateMatch: true, nearHumanTarget: true, zoomCorrectionToHuman: 1, absLog2ScaleError: 0, centerDistanceInHumanSides: 0, cropIoU: 1, loss: 0 },
  { candidateMatch: false, nearHumanTarget: false, zoomCorrectionToHuman: null, absLog2ScaleError: null, centerDistanceInHumanSides: null, cropIoU: 0, loss: 4 },
]);
assert.equal(aggregate.candidateMatchRate, 0.5);
assert.equal(aggregate.nearHumanTargetRate, 0.5);
assert.equal(aggregate.meanLoss, 2);
assert.equal(aggregate.alignmentScore, 0.333333);

process.stdout.write(`${JSON.stringify({ status: "human_alignment_evaluator_test_passed" })}\n`);
