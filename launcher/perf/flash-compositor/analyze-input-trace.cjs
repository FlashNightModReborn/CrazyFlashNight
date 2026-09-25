// Endpoint observations only. Neither WndProc return nor nearby panel_request
// proves the AS2 release target or a causal business acknowledgement.
const fs = require('node:fs');
function analyze(text) {
  const edges = new Map(), sessions = new Map(), gaps = [], panels = [];
  const session = id => {
    if (!sessions.has(id)) sessions.set(id, { session: id, endpointTraceAttached: false });
    return sessions.get(id);
  };
  const edge = (id, seq) => {
    const key = `${id}/${seq}`;
    if (!edges.has(key)) edges.set(key, { session: id, sequence: seq, host: null, endpoint: [] });
    return edges.get(key);
  };
  for (const line of text.split(/\r?\n/)) {
    const time = line.match(/^\d\d:\d\d:\d\d\.\d{3}/)?.[0] || null;
    let m;
    if ((m = line.match(/world_pointer_posted msg=(0x[\dA-F]+) seq=(\d+) epoch=(\d+).*? x=(-?\d+) y=(-?\d+).*? session=(\d+)/))) {
      session(m[6]);
      edge(m[6], m[2]).host = { time, message: m[1], epoch: m[3], x: +m[4], y: +m[5] };
    }
    if ((m = line.match(/TRACE session=(\d+) ordinal=(\d+) qpc=(\d+) frequency=(\d+) stage=(\d+) seq=(\d+) epoch=(\d+) msg=(0x[\dA-F]+) x=(-?\d+) y=(-?\d+) buttons=(\d+) localFloor=(\d+) focus=(0x[\dA-F]+)/))) {
      const current = session(m[1]);
      if (m[5] === '9') current.endpointTraceAttached = true;
      const record = { ordinal: m[2], qpc: m[3], frequency: m[4], stage: +m[5], epoch: m[7], message: m[8],
        x: +m[9], y: +m[10], buttons: +m[11], localFloor: m[12], focus: m[13] };
      if (m[6] !== '0') edge(m[1], m[6]).endpoint.push(record);
      else (current.lifecycle ??= []).push(record);
    }
    if ((m = line.match(/TRACE_GAP session=(\d+) skipped=(\d+) totalLost=(\d+)/))) gaps.push({ session: m[1], skipped: +m[2], totalLost: +m[3] });
    if (line.includes('"task":"panel_request"')) panels.push({ time, raw: line });
  }
  const result = [...edges.values()].map(e => ({ ...e,
    endpointEntered: e.endpoint.some(r => r.stage === 1),
    endpointReturned: e.endpoint.some(r => r.stage === 2),
    rejectionStages: e.endpoint.filter(r => [3,4,5].includes(r.stage)).map(r => r.stage)
  }));
  return { version: 1, evidenceKind: 'host-and-native-endpoint-observation',
    businessAcknowledgement: 'NOT_OBSERVED_BY_THIS_TRACE', humanAcceptance: 'NOT_INFERRED',
    stages: { 1: 'original_enter', 2: 'original_return', 3: 'stale_reject', 4: 'stopped_reject',
      5: 'invalid_reject', 6: 'focus_loss', 7: 'cancel_return', 8: 'outside_move', 9: 'trace_attached',
      10: 'native_pointer_message', 11: 'cursor_virtual', 12: 'cursor_physical', 13: 'source_leave_suppressed' },
    sessions: [...sessions.values()], traceGaps: gaps, edges: result, panelRequestsWithoutCausalBinding: panels };
}
module.exports = { analyze };
if (require.main === module) {
  const [input, output] = process.argv.slice(2);
  if (!input || !output) throw new Error('Usage: node analyze-input-trace.cjs <launcher.log> <output.json>');
  fs.writeFileSync(output, JSON.stringify(analyze(fs.readFileSync(input, 'utf8')), null, 2) + '\n');
}
