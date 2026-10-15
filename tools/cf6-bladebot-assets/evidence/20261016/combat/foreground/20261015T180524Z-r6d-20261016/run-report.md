# Unattended Arena Calibration Run

- status: needs_rerun
- batchId: `bladebot-front-r6d-20261016`
- slot: `cf7_agent_bladebot_front_r6d`
- seedSource: `saves/cf7_agent_bladebot_seed_r2.json`
- manifest: `tmp/arena-calibration/batches/bladebot-front-r6d-20261016/case-manifest-7de405ee312164081d424f6d79cd5ec016ddce1d3f0086af704630f9b8fb1f3e.json`
- resultPath: `tmp/arena-calibration/unattended/20261015T180524Z-bladebot-front-r6d-20261016-a7ef07e8-f7bd-4260-8b2f-db737406f5c1/attempt-1-bladebot-front-r6d-20261016-attempt-484e51ca-84bf-457a-8a04-8e4900eae979-results.jsonl`
- summaryPath: `tmp/arena-calibration/unattended/20261015T180524Z-bladebot-front-r6d-20261016-a7ef07e8-f7bd-4260-8b2f-db737406f5c1/summary.json`
- recoveryAttemptsUsed: 0/0
- startedAt: 2026-10-15T18:05:24.711Z
- completedAt: 2026-10-15T18:10:14.489Z

## Runtime Binary Identity

- verified: true
- runtimeMode: `isolated_candidate`
- processPath: `C:\Users\fs\.codex\worktrees\wings-combat\CrazyFlashNight\tmp\runtime-candidates\v2\wings-r1\runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe`
- coreSha256: `0B77B242CD101494C5B4944A13B8226D7B3FBBB93D078386D0F3E7A342980DE6`
- buildIdentity: `8EA4A84690A931791CAEB33952B7C7200AA5AA4A5141962085C5D049196C6212`
- payloadClosure: `20FE94FD57A50939F5DA7E00532D56B6A83250ED51714D8A976D148CD0ABA156`
- protectedSaveUnchanged: true
- protectedSaveBefore: `sha256:605d57474504769c10426c730c507611a14386c415488ccc055e8548ef92d25f`
- protectedSaveAfter: `sha256:605d57474504769c10426c730c507611a14386c415488ccc055e8548ef92d25f`

## Attempts

| # | status | batchId | rows | resultPath | rerun |
|---|---|---|---:|---|---|
| 1 | interrupted | `bladebot-front-r6d-20261016` | 1/4 | `tmp/arena-calibration/unattended/20261015T180524Z-bladebot-front-r6d-20261016-a7ef07e8-f7bd-4260-8b2f-db737406f5c1/attempt-1-bladebot-front-r6d-20261016-attempt-484e51ca-84bf-457a-8a04-8e4900eae979-results.jsonl` | `tmp/arena-calibration/batches/bladebot-front-r6d-20261016-rerun-20261015T181014Z/case-manifest-c29220398660f48e3cbd8880cc740de552126045b4e6962d97392d437083f497.json` |

## Failures

```json
[
  {
    "type": "attempt_error",
    "attempt": 1,
    "batchId": "bladebot-front-r6d-20261016",
    "phase": "poll",
    "message": "arena_calibration status polling failed"
  },
  {
    "type": "needs_rerun",
    "attempt": 1,
    "batchId": "bladebot-front-r6d-20261016",
    "rerunManifestPath": "tmp/arena-calibration/batches/bladebot-front-r6d-20261016-rerun-20261015T181014Z/case-manifest-c29220398660f48e3cbd8880cc740de552126045b4e6962d97392d437083f497.json"
  }
]
```

## Final Status

```json
{
  "success": true,
  "ok": true,
  "task": "arena_calibration",
  "workerId": "guardian",
  "sessionEpoch": "521a73f8be6143808f5c3ef047985c8c",
  "assignmentId": "assignment-7043b9d1-5b2b-44ba-8822-7b8dc762e534",
  "attemptId": "attempt-484e51ca-84bf-457a-8a04-8e4900eae979",
  "transportPoisoned": false,
  "state": "running",
  "note": null,
  "batchId": "bladebot-front-r6d-20261016",
  "manifestHash": "sha256:7de405ee312164081d424f6d79cd5ec016ddce1d3f0086af704630f9b8fb1f3e",
  "manifestPath": "tmp/arena-calibration/batches/bladebot-front-r6d-20261016/case-manifest-7de405ee312164081d424f6d79cd5ec016ddce1d3f0086af704630f9b8fb1f3e.json",
  "frozenManifestPath": "tmp/arena-calibration/batches/bladebot-front-r6d-20261016/attempts/attempt-484e51ca-84bf-457a-8a04-8e4900eae979/case_manifest.json",
  "resultPath": "tmp/arena-calibration/batches/bladebot-front-r6d-20261016/attempts/attempt-484e51ca-84bf-457a-8a04-8e4900eae979/results.jsonl",
  "totalRuns": 4,
  "completedRuns": 0,
  "currentCaseId": "blackiron-30-blue",
  "currentRunId": "blackiron-30-blue-r001",
  "lastError": null,
  "lastResult": null
}
```

## Suggestions

- Run rerun manifest: tmp/arena-calibration/batches/bladebot-front-r6d-20261016-rerun-20261015T181014Z/case-manifest-c29220398660f48e3cbd8880cc740de552126045b4e6962d97392d437083f497.json
- Inspect finalArenaStatus and result JSONL before planning the next exploratory batch.
