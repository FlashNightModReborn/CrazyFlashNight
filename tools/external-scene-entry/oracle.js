'use strict';

// Consumes only post-action, lossless log lines from one isolated process.
// Capture freshness, overlay dismissal and a clean shutdown are not scene-entry proofs.
class TransitionOracle {
  constructor({ label, scene, route = null, minimumScene = 0 }) {
    this.expected = { label, scene, route, minimumScene };
    this.records = [];
  }

  add(lines) {
    this.records.push(...lines);
    return this.result();
  }

  result() {
    const begins = [];
    const phases = [];
    const ready = [];
    const navigations = [];
    const revealed = [];
    for (let index = 0; index < this.records.length; index++) {
      const raw = this.records[index];
      const line = typeof raw === 'string' ? raw : raw.line;
      let match;
      if ((match = /event=scene_transition_begin id=(\S+)/.exec(line))) begins.push({ id: match[1], index });
      if ((match = /event=scene_transition_revealed id=(\S+) scene=(\d+)/.exec(line))) {
        revealed.push({ id: match[1], scene: Number(match[2]), index });
      }
      for (const readyMatch of line.matchAll(/\[SceneEntryReady\] request=(\S+) targetScene=(\d+) rootFrame=(\d+) scene=([^\s&"|<>]+)/g)) {
        ready.push({ id: readyMatch[1], scene: Number(readyMatch[2]), rootFrame: Number(readyMatch[3]), name: readyMatch[4], index });
      }
      for (const navMatch of line.matchAll(/\[SceneEntryNavigation\] route=(\S+) from=(\d+) target=(\d+) scene=([^\s&"|<>]+)/g)) {
        navigations.push({ route: navMatch[1], from: Number(navMatch[2]), target: Number(navMatch[3]), name: navMatch[4], index });
      }
      const marker = line.indexOf('[XmlSocket:JSON] ');
      if (marker >= 0) {
        try {
          const message = JSON.parse(line.slice(marker + '[XmlSocket:JSON] '.length));
          if (message.task === 'scene_transition' && message.payload) phases.push({ ...message.payload, index });
        } catch (_) { /* Non-JSON length summaries are not receipts. */ }
      }
    }
    const outcome = (status, reason, extra = {}) => ({ status, reason, ...this.expected, ...extra });
    if (begins.length > 1) return outcome('fail', 'another transition superseded the action');
    if (begins.length === 0) return outcome('pending', 'fresh transition begin not observed');
    const requestId = begins[0].id;
    const own = phases.filter(p => p.requestId === requestId);
    if (own.some(p => p.phase === 'error')) return outcome('fail', 'AS2 rejected scene loading', { requestId });
    const terminal = revealed.filter(p => p.id === requestId);
    if (terminal.length > 1) return outcome('fail', 'duplicate revealed receipt', { requestId });
    if (terminal.length === 0) return outcome('pending', 'matching revealed receipt not observed', { requestId });
    const end = terminal[0];
    if (end.scene <= this.expected.minimumScene) return outcome('fail', 'scene generation did not advance', { requestId });
    const accepted = ready.filter(p => p.id === requestId && p.scene === end.scene && p.name === this.expected.scene);
    if (accepted.length !== 1) return outcome('pending', 'exact target-world SceneReady receipt missing', { requestId });
    const cover = own.find(p => p.phase === 'cover');
    const loading = own.find(p => p.phase === 'loading');
    const reveal = own.find(p => p.phase === 'reveal' && p.targetScene === end.scene);
    if (!cover || !loading || !reveal) return outcome('pending', 'matching cover/loading/reveal chain missing', { requestId });
    // AS2 server messages are batched separately from scene_transition JSON.
    // Bind their identities, but do not invent cross-channel arrival ordering.
    if (!(cover.index < loading.index && loading.index < reveal.index && reveal.index < end.index)) {
      return outcome('fail', 'scene receipts are out of order', { requestId });
    }
    if (!(cover.revision < loading.revision && loading.revision < reveal.revision)) {
      return outcome('fail', 'transition revisions did not advance', { requestId });
    }
    let navigation = null;
    if (this.expected.route) {
      const matches = navigations.filter(p => p.name === this.expected.scene && p.route === this.expected.route);
      if (matches.length !== 1) return outcome('pending', 'required navigation branch not observed', { requestId });
      navigation = matches[0];
      if (navigation.route === 'same_frame' && !(navigation.from === navigation.target
          && navigation.target === accepted[0].rootFrame)) {
        return outcome('fail', 'same-frame route changed the root frame', { requestId });
      }
      if (navigation.route === 'remembered_frame' && !(navigation.from !== navigation.target
          && navigation.target === accepted[0].rootFrame)) {
        return outcome('fail', 'remembered-frame route does not match the mounted world', { requestId });
      }
    }
    return outcome('pass', 'exact target world ready and Host revealed', {
      requestId, targetScene: end.scene, rootFrame: accepted[0].rootFrame, navigation,
      recordCount: this.records.length,
    });
  }
}

module.exports = { TransitionOracle };
