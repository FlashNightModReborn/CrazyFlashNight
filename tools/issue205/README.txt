Issue #205 qualification diagnostics

Activation
  Enabled only after the trusted isolated-candidate bootstrap admits the exact
  cf7_agent_i2051110 test slot. Formal and ordinary startup leave it disabled.
  The Host and input credential expire after 80 minutes; the controller work
  budget is 75 minutes. This does not extend ordinary unattended profiles.

Evidence paths
  AS2 samples a root getTimer/sequence over LoadVars HTTP every 500 ms, with at
  most one request outstanding. It does not depend on frameUpdate, frameEnd,
  XMLSocket or the FPS payload. A disabled config removes the initial timer.
  Fixed counters record update/end entry and return, callback order, F build
  and send-call entry/return, FPS generation, no-socket and no-world returns.
  Plain owner records and EventCoordinator callbacks distinguish world attach,
  cleanup request and actual unload without adding a diagnostic MovieClip.

  Host counters distinguish byte reads and their generation, NUL boundaries,
  admitted messages, current-generation F prefix, consumer progress/returns/
  exceptions, FPS parsing, source rejection, policy rejection and accepted push.
  F5 parsed and accepted identities are separate. Legacy F5 has no independent
  snapshot sequence: it is reported as NOT_RECORDED, never synthesized.
  F8 header/cache identities are separate from successful native submissions.
  A successful native submission is not a presentation acknowledgement.

Preservation
  A 1 Hz sampler retains 180 samples in memory. On a two-second suspect gap
  during foreground, unpaused, stable combat context it latches the first
  incident and its prehistory. The result is SUSPECT_ONLY. Later focus, pause
  or generation changes cannot erase that incident. Repeated hide messages
  do not create fresh transition grace; transition eligibility comes from the
  current sampled source flags and world owner.
  Counters never take the log writer lock. A bounded queue feeds a separate
  writer. The shutdown fence checkpoints retained facts before persistence/
  cleanup; early shutdown seals without waiting for heavy evidence or writers.

External supervisor
  node tools/issue205/supervise.js <runtime-spec.json> <evidence-directory>
  The spec binds candidateRoot, buildIdentity and payloadClosure. The supervisor
  verifies process identity and rejects PID/diagnostic-session replacement.
  Every HTTP read has an absolute 900 ms deadline and 2 MB response bound.
  Small immutable facts precede optional log-prefix workers. Worker termination
  is requested after 1500 ms and never awaited on the preservation path.
  Write <evidence-directory>/seal.request BEFORE requesting normal game shutdown.
  The supervisor also stops after 73 minutes. It never restarts or heals Flash,
  invokes ProbeRequestContentProof, forces frame counters, or changes game speed.

Checks
  scripts/run-issue205-probe-tests.ps1
  tools/run-focus-sol-recheck.ps1 -Phase integration -Canonical
  node --test tools/issue205/test-preservation.js
  The historical A/B replay must use the complete hash-verified redacted logs.
  Their missing root/F-wire/runtime identity premises remain NOT_RECORDED;
  those logs cannot establish whether this new production detector would fire.

Limits
  This probe observes one Flash lifetime in a candidate qualification session.
  HTTP arrival does not authenticate a producer against malicious local software.
  Source clocks/counters show execution progress; composed screenshots and
  native received/presented counts alone do not prove fresh AS2 pixels.
  A clean 70-minute run narrows reproduction conditions; it cannot prove #205 fixed.
