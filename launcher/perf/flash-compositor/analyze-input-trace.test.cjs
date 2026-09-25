const { test } = require('node:test');
const assert = require('node:assert/strict');
const { analyze } = require('./analyze-input-trace.cjs');
test('posting and a different session return cannot become delivery or business success', () => {
  const report = analyze(`09:54:33.001 event=world_pointer_posted msg=0x201 seq=3 epoch=2 x=14 y=16 source=100x100 session=18446744073709551601
09:54:33.200 event=world_pointer_bridge TRACE session=18446744073709551603 ordinal=4 qpc=4481592793527 frequency=10000000 stage=2 seq=3 epoch=2 msg=0x201 x=14 y=16 buttons=1 localFloor=0 focus=0xABC
09:54:33.201 event=world_pointer_bridge TRACE_GAP session=18446744073709551603 skipped=4 totalLost=4
09:54:33.202 [XmlSocket:JSON] {"task":"panel_request","panel":"surgery"}`);
  assert.equal(report.edges.length, 2);
  assert.equal(report.edges[0].endpointReturned, false);
  assert.equal(report.edges[1].host, null);
  assert.equal(report.traceGaps[0].skipped, 4);
  assert.equal(report.businessAcknowledgement, 'NOT_OBSERVED_BY_THIS_TRACE');
  assert.equal(report.panelRequestsWithoutCausalBinding.length, 1);
});
test('exact session and sequence retain rejection and QPC without rounding', () => {
  const r = analyze('TRACE session=99 ordinal=1 qpc=9007199254740993 frequency=10000000 stage=3 seq=17 epoch=5 msg=0x201 x=0 y=0 buttons=0 localFloor=6 focus=0x0');
  assert.deepEqual(r.edges[0].rejectionStages, [3]);
  assert.equal(r.edges[0].endpoint[0].qpc, '9007199254740993');
  assert.equal(r.edges[0].endpointEntered, false);
});
test('suppressed source leave remains a lifecycle observation, not button delivery', () => {
  const r = analyze('TRACE session=99 ordinal=8 qpc=9007199254740993 frequency=10000000 stage=13 seq=0 epoch=5 msg=0x2A3 x=120 y=90 buttons=0 localFloor=2 focus=0xABC');
  assert.equal(r.edges.length, 0);
  assert.equal(r.sessions[0].lifecycle[0].stage, 13);
  assert.equal(r.stages[13], 'source_leave_suppressed');
  assert.equal(r.businessAcknowledgement, 'NOT_OBSERVED_BY_THIS_TRACE');
});
