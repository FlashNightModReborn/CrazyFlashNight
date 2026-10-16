# Unattended Arena Calibration Run

- status: needs_rerun
- batchId: `bladebot-front-r6e-20261016`
- slot: `cf7_agent_bladebot_front_r6e`
- seedSource: `saves/cf7_agent_bladebot_seed_r2.json`
- manifest: `tmp/arena-calibration/batches/bladebot-front-r6e-20261016/case-manifest-4eb0f469aa3b56f4d5bd21f06e04d2f8d4ad6195aeb3626699b73792e9cc8b77.json`
- resultPath: `tmp/arena-calibration/unattended/20261015T181050Z-bladebot-front-r6e-20261016-0987283a-ce53-45ec-a6b8-877fff48f46a/attempt-1-bladebot-front-r6e-20261016-attempt-73e95330-e849-4936-a4b9-2f553f3c4e62-results.jsonl`
- summaryPath: `tmp/arena-calibration/unattended/20261015T181050Z-bladebot-front-r6e-20261016-0987283a-ce53-45ec-a6b8-877fff48f46a/summary.json`
- recoveryAttemptsUsed: 0/0
- startedAt: 2026-10-15T18:10:50.527Z
- completedAt: 2026-10-15T18:14:08.336Z

## Runtime Binary Identity

- verified: true
- runtimeMode: `isolated_candidate`
- processPath: `C:\Users\fs\.codex\worktrees\wings-combat\CrazyFlashNight\tmp\runtime-candidates\v2\wings-r1\runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe`
- coreSha256: `0B77B242CD101494C5B4944A13B8226D7B3FBBB93D078386D0F3E7A342980DE6`
- buildIdentity: `8EA4A84690A931791CAEB33952B7C7200AA5AA4A5141962085C5D049196C6212`
- payloadClosure: `20FE94FD57A50939F5DA7E00532D56B6A83250ED51714D8A976D148CD0ABA156`
- protectedSaveUnchanged: true
- protectedSaveBefore: `sha256:c1f6430fd3dd5e2a99f0b43b48db118d2362e3949355209ef9d27f5386527f5c`
- protectedSaveAfter: `sha256:c1f6430fd3dd5e2a99f0b43b48db118d2362e3949355209ef9d27f5386527f5c`

## Attempts

| # | status | batchId | rows | resultPath | rerun |
|---|---|---|---:|---|---|
| 1 | interrupted | `bladebot-front-r6e-20261016` | 1/4 | `tmp/arena-calibration/unattended/20261015T181050Z-bladebot-front-r6e-20261016-0987283a-ce53-45ec-a6b8-877fff48f46a/attempt-1-bladebot-front-r6e-20261016-attempt-73e95330-e849-4936-a4b9-2f553f3c4e62-results.jsonl` | `tmp/arena-calibration/batches/bladebot-front-r6e-20261016-rerun-20261015T181408Z/case-manifest-17e9c13ac118fd89e754e7934099b8daa770c3747fb4342b472c5c004cdf1a90.json` |

## Failures

```json
[
  {
    "type": "attempt_error",
    "attempt": 1,
    "batchId": "bladebot-front-r6e-20261016",
    "phase": "poll",
    "message": "arena_calibration status polling failed"
  },
  {
    "type": "needs_rerun",
    "attempt": 1,
    "batchId": "bladebot-front-r6e-20261016",
    "rerunManifestPath": "tmp/arena-calibration/batches/bladebot-front-r6e-20261016-rerun-20261015T181408Z/case-manifest-17e9c13ac118fd89e754e7934099b8daa770c3747fb4342b472c5c004cdf1a90.json"
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
  "sessionEpoch": "09ef069ed1494829b7ac15a56c29820d",
  "assignmentId": "assignment-13a44a41-31f0-48a4-9d4a-f1cb283bcbd5",
  "attemptId": "attempt-73e95330-e849-4936-a4b9-2f553f3c4e62",
  "transportPoisoned": false,
  "state": "running",
  "note": null,
  "batchId": "bladebot-front-r6e-20261016",
  "manifestHash": "sha256:4eb0f469aa3b56f4d5bd21f06e04d2f8d4ad6195aeb3626699b73792e9cc8b77",
  "manifestPath": "tmp/arena-calibration/batches/bladebot-front-r6e-20261016/case-manifest-4eb0f469aa3b56f4d5bd21f06e04d2f8d4ad6195aeb3626699b73792e9cc8b77.json",
  "frozenManifestPath": "tmp/arena-calibration/batches/bladebot-front-r6e-20261016/attempts/attempt-73e95330-e849-4936-a4b9-2f553f3c4e62/case_manifest.json",
  "resultPath": "tmp/arena-calibration/batches/bladebot-front-r6e-20261016/attempts/attempt-73e95330-e849-4936-a4b9-2f553f3c4e62/results.jsonl",
  "totalRuns": 4,
  "completedRuns": 0,
  "currentCaseId": "blackiron-30-blue",
  "currentRunId": "blackiron-30-blue-r001",
  "lastError": null,
  "lastResult": null
}
```

## Suggestions

- Run rerun manifest: tmp/arena-calibration/batches/bladebot-front-r6e-20261016-rerun-20261015T181408Z/case-manifest-17e9c13ac118fd89e754e7934099b8daa770c3747fb4342b472c5c004cdf1a90.json
- Inspect finalArenaStatus and result JSONL before planning the next exploratory batch.
