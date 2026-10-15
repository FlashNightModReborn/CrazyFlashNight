# Unattended Arena Calibration Run

- status: needs_rerun
- batchId: `bladebot-front-r6b-20261016`
- slot: `cf7_agent_bladebot_front_r6b`
- seedSource: `saves/cf7_agent_bladebot_seed_r2.json`
- manifest: `tmp/arena-calibration/batches/bladebot-front-r6b-20261016/case-manifest-d465c97fcd1ca7a35241ebb402a8806d06dc2a4f8b13b5f878c80f1f4723e81c.json`
- resultPath: `tmp/arena-calibration/unattended/20261015T174625Z-bladebot-front-r6b-20261016-8ee667b7-80b5-4c75-b398-8ddb104fd7b2/attempt-1-bladebot-front-r6b-20261016-attempt-3a3dce9f-c2ca-435f-947b-1fcd28482884-results.jsonl`
- summaryPath: `tmp/arena-calibration/unattended/20261015T174625Z-bladebot-front-r6b-20261016-8ee667b7-80b5-4c75-b398-8ddb104fd7b2/summary.json`
- recoveryAttemptsUsed: 0/0
- startedAt: 2026-10-15T17:46:25.107Z
- completedAt: 2026-10-15T17:52:35.865Z

## Runtime Binary Identity

- verified: true
- runtimeMode: `isolated_candidate`
- processPath: `C:\Users\fs\.codex\worktrees\wings-combat\CrazyFlashNight\tmp\runtime-candidates\v2\wings-r1\runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe`
- coreSha256: `0B77B242CD101494C5B4944A13B8226D7B3FBBB93D078386D0F3E7A342980DE6`
- buildIdentity: `8EA4A84690A931791CAEB33952B7C7200AA5AA4A5141962085C5D049196C6212`
- payloadClosure: `20FE94FD57A50939F5DA7E00532D56B6A83250ED51714D8A976D148CD0ABA156`
- protectedSaveUnchanged: true
- protectedSaveBefore: `sha256:36ab501a3ea33717b006e32e1e93061db6f56681dc7a6eabac2582e073213530`
- protectedSaveAfter: `sha256:36ab501a3ea33717b006e32e1e93061db6f56681dc7a6eabac2582e073213530`

## Attempts

| # | status | batchId | rows | resultPath | rerun |
|---|---|---|---:|---|---|
| 1 | failed | `bladebot-front-r6b-20261016` | 1/4 | `tmp/arena-calibration/unattended/20261015T174625Z-bladebot-front-r6b-20261016-8ee667b7-80b5-4c75-b398-8ddb104fd7b2/attempt-1-bladebot-front-r6b-20261016-attempt-3a3dce9f-c2ca-435f-947b-1fcd28482884-results.jsonl` | `tmp/arena-calibration/batches/bladebot-front-r6b-20261016-rerun-20261015T175235Z/case-manifest-30047cb203aa46577203238d639b23d657f997bc85b93e96196ecfcc2a991bf0.json` |

## Failures

```json
[
  {
    "type": "needs_rerun",
    "attempt": 1,
    "batchId": "bladebot-front-r6b-20261016",
    "rerunManifestPath": "tmp/arena-calibration/batches/bladebot-front-r6b-20261016-rerun-20261015T175235Z/case-manifest-30047cb203aa46577203238d639b23d657f997bc85b93e96196ecfcc2a991bf0.json"
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
  "sessionEpoch": "28b16214de214d71abb848a764c28c8b",
  "assignmentId": "assignment-9e0ba576-14a2-4ac3-9853-c319504f3adc",
  "attemptId": "attempt-3a3dce9f-c2ca-435f-947b-1fcd28482884",
  "transportPoisoned": true,
  "state": "failed",
  "note": null,
  "batchId": "bladebot-front-r6b-20261016",
  "manifestHash": "sha256:d465c97fcd1ca7a35241ebb402a8806d06dc2a4f8b13b5f878c80f1f4723e81c",
  "manifestPath": "tmp/arena-calibration/batches/bladebot-front-r6b-20261016/case-manifest-d465c97fcd1ca7a35241ebb402a8806d06dc2a4f8b13b5f878c80f1f4723e81c.json",
  "frozenManifestPath": "tmp/arena-calibration/batches/bladebot-front-r6b-20261016/attempts/attempt-3a3dce9f-c2ca-435f-947b-1fcd28482884/case_manifest.json",
  "resultPath": "tmp/arena-calibration/batches/bladebot-front-r6b-20261016/attempts/attempt-3a3dce9f-c2ca-435f-947b-1fcd28482884/results.jsonl",
  "totalRuns": 4,
  "completedRuns": 1,
  "currentCaseId": null,
  "currentRunId": null,
  "lastError": "Host transport deadline elapsed before AS2 arena calibration response",
  "lastResult": {
    "schema": "arena-calibration.result.v1",
    "workerId": "guardian",
    "sessionEpoch": "28b16214de214d71abb848a764c28c8b",
    "assignmentId": "assignment-9e0ba576-14a2-4ac3-9853-c319504f3adc",
    "attemptId": "attempt-3a3dce9f-c2ca-435f-947b-1fcd28482884",
    "batchId": "bladebot-front-r6b-20261016",
    "manifestHash": "sha256:d465c97fcd1ca7a35241ebb402a8806d06dc2a4f8b13b5f878c80f1f4723e81c",
    "caseId": "blackiron-30-blue",
    "caseHash": "sha256:6d01738fa8df48b9e60f09add93cd9314f8a75c77b5979852ac31babddcb09ad",
    "runId": "blackiron-30-blue-r001",
    "repeatIndex": 1,
    "status": "bridge_lost",
    "winner": "none",
    "startedAt": "2026-10-15T17:48:04.1204632Z",
    "completedAt": "2026-10-15T17:52:34.1356392Z",
    "requestedSpawnDistance": 650,
    "blueFormation": "line",
    "redFormation": "line",
    "formationSpacing": 54,
    "phaseSpawnCount": 0,
    "spawnedUnits": [],
    "blueSpawnPositions": [],
    "redSpawnPositions": [],
    "formationAudit": {},
    "authorityContext": {
      "aiSourceSha256": "64403584ae37e153be2e9a4b082d94273d194f783c0f49e7f8a51effaa06c1b6",
      "candidateSide": "blue",
      "comparison": "blackiron",
      "dataPath": "data/enemy_properties/CF6重制敌人.xml",
      "dataSha256": "8ca5b37dd6e3d20d33ca08c230af990eedb1219447ce3cf4eca67ec5622ab6f0",
      "mode": "pilot",
      "rivalDataPath": "data/enemy_properties/诺亚新敌人.xml",
      "rivalDataSha256": "d339f0a4de759cce186fe98dbdf8f1f966cacf1fa5bd803714d9d41ea331321b",
      "sourceSwf": "flashswf/arts/new/Codex大刀机器人素材.swf",
      "sourceSwfSha256": "bca805648f40c7360405c490690d109ebd8882a9a171b7236c8f76c520e5d700",
      "stage": 8,
      "tier": 9
    },
    "blueUnitResults": [],
    "redUnitResults": [],
    "frames": null,
    "durationMs": null,
    "blue": {
      "maxHp": 0,
      "remainHp": 0,
      "aliveCount": 0,
      "startMaxHp": 0,
      "startCount": 0
    },
    "red": {
      "maxHp": 0,
      "remainHp": 0,
      "aliveCount": 0,
      "startMaxHp": 0,
      "startCount": 0
    },
    "errors": [
      {
        "code": "bridge_lost",
        "message": "Host transport deadline elapsed before AS2 arena calibration response"
      }
    ]
  }
}
```

## Suggestions

- Run rerun manifest: tmp/arena-calibration/batches/bladebot-front-r6b-20261016-rerun-20261015T175235Z/case-manifest-30047cb203aa46577203238d639b23d657f997bc85b93e96196ecfcc2a991bf0.json
- Inspect finalArenaStatus and result JSONL before planning the next exploratory batch.
