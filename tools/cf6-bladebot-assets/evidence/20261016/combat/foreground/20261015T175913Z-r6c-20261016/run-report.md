# Unattended Arena Calibration Run

- status: needs_rerun
- batchId: `bladebot-front-r6c-20261016`
- slot: `cf7_agent_bladebot_front_r6c`
- seedSource: `saves/cf7_agent_bladebot_seed_r2.json`
- manifest: `tmp/arena-calibration/batches/bladebot-front-r6c-20261016/case-manifest-6a3f7f25bdbf091bdc999b062cb2d8f2b580d93f917c192a531eaa66f979fadb.json`
- resultPath: `tmp/arena-calibration/unattended/20261015T175913Z-bladebot-front-r6c-20261016-e65ae1b6-1fce-470b-9941-51c8f1980315/attempt-1-bladebot-front-r6c-20261016-attempt-5f365fd3-caf9-45f7-9eca-2577de72c89b-results.jsonl`
- summaryPath: `tmp/arena-calibration/unattended/20261015T175913Z-bladebot-front-r6c-20261016-e65ae1b6-1fce-470b-9941-51c8f1980315/summary.json`
- recoveryAttemptsUsed: 0/0
- startedAt: 2026-10-15T17:59:13.538Z
- completedAt: 2026-10-15T18:04:24.180Z

## Runtime Binary Identity

- verified: true
- runtimeMode: `isolated_candidate`
- processPath: `C:\Users\fs\.codex\worktrees\wings-combat\CrazyFlashNight\tmp\runtime-candidates\v2\wings-r1\runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe`
- coreSha256: `0B77B242CD101494C5B4944A13B8226D7B3FBBB93D078386D0F3E7A342980DE6`
- buildIdentity: `8EA4A84690A931791CAEB33952B7C7200AA5AA4A5141962085C5D049196C6212`
- payloadClosure: `20FE94FD57A50939F5DA7E00532D56B6A83250ED51714D8A976D148CD0ABA156`
- protectedSaveUnchanged: true
- protectedSaveBefore: `sha256:242ac63aea8607492114b51601764decadb688698f7eb76854068fd1b8716c86`
- protectedSaveAfter: `sha256:242ac63aea8607492114b51601764decadb688698f7eb76854068fd1b8716c86`

## Attempts

| # | status | batchId | rows | resultPath | rerun |
|---|---|---|---:|---|---|
| 1 | interrupted | `bladebot-front-r6c-20261016` | 1/4 | `tmp/arena-calibration/unattended/20261015T175913Z-bladebot-front-r6c-20261016-e65ae1b6-1fce-470b-9941-51c8f1980315/attempt-1-bladebot-front-r6c-20261016-attempt-5f365fd3-caf9-45f7-9eca-2577de72c89b-results.jsonl` | `tmp/arena-calibration/batches/bladebot-front-r6c-20261016-rerun-20261015T180424Z/case-manifest-f8c27d364aa2e273ef3d95cd75f42ae855abcae3c7f5d848460a2db41924689d.json` |

## Failures

```json
[
  {
    "type": "attempt_error",
    "attempt": 1,
    "batchId": "bladebot-front-r6c-20261016",
    "phase": "poll",
    "message": "arena_calibration status polling failed"
  },
  {
    "type": "needs_rerun",
    "attempt": 1,
    "batchId": "bladebot-front-r6c-20261016",
    "rerunManifestPath": "tmp/arena-calibration/batches/bladebot-front-r6c-20261016-rerun-20261015T180424Z/case-manifest-f8c27d364aa2e273ef3d95cd75f42ae855abcae3c7f5d848460a2db41924689d.json"
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
  "sessionEpoch": "da0c306749a44887b5a9f03f5ed78a6b",
  "assignmentId": "assignment-14f183a3-a49f-44a1-8fe0-ac6ecbd36efb",
  "attemptId": "attempt-5f365fd3-caf9-45f7-9eca-2577de72c89b",
  "transportPoisoned": false,
  "state": "running",
  "note": null,
  "batchId": "bladebot-front-r6c-20261016",
  "manifestHash": "sha256:6a3f7f25bdbf091bdc999b062cb2d8f2b580d93f917c192a531eaa66f979fadb",
  "manifestPath": "tmp/arena-calibration/batches/bladebot-front-r6c-20261016/case-manifest-6a3f7f25bdbf091bdc999b062cb2d8f2b580d93f917c192a531eaa66f979fadb.json",
  "frozenManifestPath": "tmp/arena-calibration/batches/bladebot-front-r6c-20261016/attempts/attempt-5f365fd3-caf9-45f7-9eca-2577de72c89b/case_manifest.json",
  "resultPath": "tmp/arena-calibration/batches/bladebot-front-r6c-20261016/attempts/attempt-5f365fd3-caf9-45f7-9eca-2577de72c89b/results.jsonl",
  "totalRuns": 4,
  "completedRuns": 0,
  "currentCaseId": "blackiron-30-blue",
  "currentRunId": "blackiron-30-blue-r001",
  "lastError": null,
  "lastResult": null
}
```

## Suggestions

- Run rerun manifest: tmp/arena-calibration/batches/bladebot-front-r6c-20261016-rerun-20261015T180424Z/case-manifest-f8c27d364aa2e273ef3d95cd75f42ae855abcae3c7f5d848460a2db41924689d.json
- Inspect finalArenaStatus and result JSONL before planning the next exploratory batch.
