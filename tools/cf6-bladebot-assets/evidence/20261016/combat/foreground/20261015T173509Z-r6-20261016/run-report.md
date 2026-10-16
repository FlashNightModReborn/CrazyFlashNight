# Unattended Arena Calibration Run

- status: needs_rerun
- batchId: `bladebot-front-r6-20261016`
- slot: `cf7_agent_bladebot_front_r6`
- seedSource: `saves/cf7_agent_bladebot_seed_r2.json`
- manifest: `tmp/arena-calibration/batches/bladebot-front-r6-20261016/case-manifest-a1e2e165896a6ff130d0ac5ec2299fb33c65dae84b28aa4584c514ecc8ad3a8c.json`
- resultPath: `tmp/arena-calibration/unattended/20261015T173509Z-bladebot-front-r6-20261016-72d0da7f-621f-4a86-b572-bd5517df0f11/attempt-1-bladebot-front-r6-20261016-attempt-f3cc110e-d439-4bf4-ac02-30be63fe655c-results.jsonl`
- summaryPath: `tmp/arena-calibration/unattended/20261015T173509Z-bladebot-front-r6-20261016-72d0da7f-621f-4a86-b572-bd5517df0f11/summary.json`
- recoveryAttemptsUsed: 0/0
- startedAt: 2026-10-15T17:35:09.189Z
- completedAt: 2026-10-15T17:41:20.746Z

## Runtime Binary Identity

- verified: true
- runtimeMode: `isolated_candidate`
- processPath: `C:\Users\fs\.codex\worktrees\wings-combat\CrazyFlashNight\tmp\runtime-candidates\v2\wings-r1\runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe`
- coreSha256: `0B77B242CD101494C5B4944A13B8226D7B3FBBB93D078386D0F3E7A342980DE6`
- buildIdentity: `8EA4A84690A931791CAEB33952B7C7200AA5AA4A5141962085C5D049196C6212`
- payloadClosure: `20FE94FD57A50939F5DA7E00532D56B6A83250ED51714D8A976D148CD0ABA156`
- protectedSaveUnchanged: true
- protectedSaveBefore: `sha256:6957c93ec702cd85a9a65d09562afc08e674e840337db39d9f38a295cc0983cb`
- protectedSaveAfter: `sha256:6957c93ec702cd85a9a65d09562afc08e674e840337db39d9f38a295cc0983cb`

## Attempts

| # | status | batchId | rows | resultPath | rerun |
|---|---|---|---:|---|---|
| 1 | failed | `bladebot-front-r6-20261016` | 1/4 | `tmp/arena-calibration/unattended/20261015T173509Z-bladebot-front-r6-20261016-72d0da7f-621f-4a86-b572-bd5517df0f11/attempt-1-bladebot-front-r6-20261016-attempt-f3cc110e-d439-4bf4-ac02-30be63fe655c-results.jsonl` | `tmp/arena-calibration/batches/bladebot-front-r6-20261016-rerun-20261015T174120Z/case-manifest-83b4cc5d34b0879122d4333bdcaf3c21bb94f8de7e76d58ad12aab0277c07c5a.json` |

## Failures

```json
[
  {
    "type": "needs_rerun",
    "attempt": 1,
    "batchId": "bladebot-front-r6-20261016",
    "rerunManifestPath": "tmp/arena-calibration/batches/bladebot-front-r6-20261016-rerun-20261015T174120Z/case-manifest-83b4cc5d34b0879122d4333bdcaf3c21bb94f8de7e76d58ad12aab0277c07c5a.json"
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
  "sessionEpoch": "5030b6791a74483d96e6e8d4eb42fea3",
  "assignmentId": "assignment-1cc775d4-82ee-4469-ba5d-b10ff4312ef4",
  "attemptId": "attempt-f3cc110e-d439-4bf4-ac02-30be63fe655c",
  "transportPoisoned": true,
  "state": "failed",
  "note": null,
  "batchId": "bladebot-front-r6-20261016",
  "manifestHash": "sha256:a1e2e165896a6ff130d0ac5ec2299fb33c65dae84b28aa4584c514ecc8ad3a8c",
  "manifestPath": "tmp/arena-calibration/batches/bladebot-front-r6-20261016/case-manifest-a1e2e165896a6ff130d0ac5ec2299fb33c65dae84b28aa4584c514ecc8ad3a8c.json",
  "frozenManifestPath": "tmp/arena-calibration/batches/bladebot-front-r6-20261016/attempts/attempt-f3cc110e-d439-4bf4-ac02-30be63fe655c/case_manifest.json",
  "resultPath": "tmp/arena-calibration/batches/bladebot-front-r6-20261016/attempts/attempt-f3cc110e-d439-4bf4-ac02-30be63fe655c/results.jsonl",
  "totalRuns": 4,
  "completedRuns": 1,
  "currentCaseId": null,
  "currentRunId": null,
  "lastError": "Host transport deadline elapsed before AS2 arena calibration response",
  "lastResult": {
    "schema": "arena-calibration.result.v1",
    "workerId": "guardian",
    "sessionEpoch": "5030b6791a74483d96e6e8d4eb42fea3",
    "assignmentId": "assignment-1cc775d4-82ee-4469-ba5d-b10ff4312ef4",
    "attemptId": "attempt-f3cc110e-d439-4bf4-ac02-30be63fe655c",
    "batchId": "bladebot-front-r6-20261016",
    "manifestHash": "sha256:a1e2e165896a6ff130d0ac5ec2299fb33c65dae84b28aa4584c514ecc8ad3a8c",
    "caseId": "blackiron-30-blue",
    "caseHash": "sha256:6d01738fa8df48b9e60f09add93cd9314f8a75c77b5979852ac31babddcb09ad",
    "runId": "blackiron-30-blue-r001",
    "repeatIndex": 1,
    "status": "bridge_lost",
    "winner": "none",
    "startedAt": "2026-10-15T17:36:48.8352382Z",
    "completedAt": "2026-10-15T17:41:18.8421136Z",
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

- Run rerun manifest: tmp/arena-calibration/batches/bladebot-front-r6-20261016-rerun-20261015T174120Z/case-manifest-83b4cc5d34b0879122d4333bdcaf3c21bb94f8de7e76d58ad12aab0277c07c5a.json
- Inspect finalArenaStatus and result JSONL before planning the next exploratory batch.
