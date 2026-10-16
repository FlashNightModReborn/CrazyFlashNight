# Unattended Arena Calibration Run

- status: completed
- batchId: `bladebot-front-r8a-20261016`
- slot: `cf7_agent_bladebot_front_r8a`
- seedSource: `saves/cf7_agent_bladebot_seed_r2.json`
- manifest: `tmp/arena-calibration/batches/bladebot-front-r8a-20261016/case-manifest-596d3ab4d7ec929c606733fd0245195dc92e148cda2a9b14322ae45f40c4bda1.json`
- resultPath: `tmp/arena-calibration/unattended/20261015T184338Z-bladebot-front-r8a-20261016-47f33755-7642-43dd-acbe-b35e70183fe2/attempt-1-bladebot-front-r8a-20261016-attempt-4b0c153d-70d6-4fc3-95e8-75dfc5d83e51-results.jsonl`
- summaryPath: `tmp/arena-calibration/unattended/20261015T184338Z-bladebot-front-r8a-20261016-47f33755-7642-43dd-acbe-b35e70183fe2/summary.json`
- recoveryAttemptsUsed: 0/0
- startedAt: 2026-10-15T18:43:38.573Z
- completedAt: 2026-10-15T18:51:58.488Z

## Runtime Binary Identity

- verified: true
- runtimeMode: `isolated_candidate`
- processPath: `C:\Users\fs\.codex\worktrees\wings-combat\CrazyFlashNight\tmp\runtime-candidates\v2\wings-r1\runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe`
- coreSha256: `0B77B242CD101494C5B4944A13B8226D7B3FBBB93D078386D0F3E7A342980DE6`
- buildIdentity: `8EA4A84690A931791CAEB33952B7C7200AA5AA4A5141962085C5D049196C6212`
- payloadClosure: `20FE94FD57A50939F5DA7E00532D56B6A83250ED51714D8A976D148CD0ABA156`
- protectedSaveUnchanged: true
- protectedSaveBefore: `sha256:7f94b260c4c0890b8fa3f5ee0f64e5dde53e6dd361a886f6f04eb6536172043c`
- protectedSaveAfter: `sha256:7f94b260c4c0890b8fa3f5ee0f64e5dde53e6dd361a886f6f04eb6536172043c`

## Attempts

| # | status | batchId | rows | resultPath | rerun |
|---|---|---|---:|---|---|
| 1 | completed | `bladebot-front-r8a-20261016` | 6/6 | `tmp/arena-calibration/unattended/20261015T184338Z-bladebot-front-r8a-20261016-47f33755-7642-43dd-acbe-b35e70183fe2/attempt-1-bladebot-front-r8a-20261016-attempt-4b0c153d-70d6-4fc3-95e8-75dfc5d83e51-results.jsonl` |  |

## Failures

```json
[]
```

## Final Status

```json
{
  "success": true,
  "ok": true,
  "task": "arena_calibration",
  "workerId": "guardian",
  "sessionEpoch": "bd77d1058dc7420491ddecbe617aca25",
  "assignmentId": "assignment-8c5465ec-e14e-4584-80f2-0669652d0d50",
  "attemptId": "attempt-4b0c153d-70d6-4fc3-95e8-75dfc5d83e51",
  "transportPoisoned": false,
  "state": "completed",
  "note": null,
  "batchId": "bladebot-front-r8a-20261016",
  "manifestHash": "sha256:596d3ab4d7ec929c606733fd0245195dc92e148cda2a9b14322ae45f40c4bda1",
  "manifestPath": "tmp/arena-calibration/batches/bladebot-front-r8a-20261016/case-manifest-596d3ab4d7ec929c606733fd0245195dc92e148cda2a9b14322ae45f40c4bda1.json",
  "frozenManifestPath": "tmp/arena-calibration/batches/bladebot-front-r8a-20261016/attempts/attempt-4b0c153d-70d6-4fc3-95e8-75dfc5d83e51/case_manifest.json",
  "resultPath": "tmp/arena-calibration/batches/bladebot-front-r8a-20261016/attempts/attempt-4b0c153d-70d6-4fc3-95e8-75dfc5d83e51/results.jsonl",
  "totalRuns": 6,
  "completedRuns": 6,
  "currentCaseId": null,
  "currentRunId": null,
  "lastError": null,
  "lastResult": {
    "schema": "arena-calibration.result.v1",
    "workerId": "guardian",
    "sessionEpoch": "bd77d1058dc7420491ddecbe617aca25",
    "assignmentId": "assignment-8c5465ec-e14e-4584-80f2-0669652d0d50",
    "attemptId": "attempt-4b0c153d-70d6-4fc3-95e8-75dfc5d83e51",
    "batchId": "bladebot-front-r8a-20261016",
    "manifestHash": "sha256:596d3ab4d7ec929c606733fd0245195dc92e148cda2a9b14322ae45f40c4bda1",
    "caseId": "blackiron-60-red",
    "caseHash": "sha256:c04dbc9ec6593b2c4b4d783d935ffb7ed9bea6de225f0c973dc0dee5c1a3df6b",
    "runId": "blackiron-60-red-r001",
    "repeatIndex": 1,
    "status": "finished",
    "winner": "red",
    "startedAt": "2026-10-15T18:50:39.4386490Z",
    "completedAt": "2026-10-15T18:51:56.9224906Z",
    "requestedSpawnDistance": 650,
    "blueFormation": "line",
    "redFormation": "line",
    "formationSpacing": 54,
    "phaseSpawnCount": 0,
    "spawnedUnits": [],
    "blueSpawnPositions": [
      {
        "side": "blue",
        "index": 0,
        "unit": "兵种347",
        "level": 60,
        "name": "斗兽标定_blue_blackiron_60_red_r001_0",
        "x": 570,
        "y": 430
      }
    ],
    "redSpawnPositions": [
      {
        "side": "red",
        "index": 0,
        "unit": "兵种465",
        "level": 60,
        "name": "斗兽标定_red_blackiron_60_red_r001_0",
        "x": 1220,
        "y": 430
      }
    ],
    "formationAudit": {
      "blue": {
        "count": 1,
        "minX": 570,
        "maxX": 570,
        "minY": 430,
        "maxY": 430,
        "xRange": 0,
        "yRange": 0,
        "distinctX": 1,
        "distinctY": 1
      },
      "red": {
        "count": 1,
        "minX": 1220,
        "maxX": 1220,
        "minY": 430,
        "maxY": 430,
        "xRange": 0,
        "yRange": 0,
        "distinctX": 1,
        "distinctY": 1
      }
    },
    "authorityContext": {
      "aiSourceSha256": "53a2b3aa779ea2b66f69959c43b83ac44eedb57b2dba6823dc3a3359f778ef92",
      "candidateSide": "red",
      "comparison": "blackiron",
      "dataPath": "data/enemy_properties/CF6重制敌人.xml",
      "dataSha256": "896140146aa6fc0175abf9a9cc808d2b3f23730017a9d431c8a75873a10c5477",
      "evidenceLane": "interactive_candidate",
      "mode": "pilot",
      "rivalDataPath": "data/enemy_properties/诺亚新敌人.xml",
      "rivalDataSha256": "d339f0a4de759cce186fe98dbdf8f1f966cacf1fa5bd803714d9d41ea331321b",
      "sourceSwf": "flashswf/arts/new/Codex大刀机器人素材.swf",
      "sourceSwfSha256": "d4dc955f19e7ad41e2da1018a8ab5f4af6469a762a2793c4a2e3ad4a6a9195c8",
      "stage": 8,
      "tier": 9
    },
    "blueUnitResults": [
      {
        "sourceId": "blackiron-60",
        "petId": -1,
        "identifier": "敌人-黑铁会改造人",
        "resolvedType": "敌人-黑铁会改造人",
        "level": 60,
        "strategicPromotions": [],
        "strategicPromotionsValid": true,
        "startMaxHp": 25457,
        "remainHp": 0,
        "hpPermille": 0,
        "alive": false
      }
    ],
    "redUnitResults": [
      {
        "sourceId": "bladebot-60",
        "petId": -1,
        "identifier": "敌人-CF6大刀机器人",
        "resolvedType": "敌人-CF6大刀机器人",
        "level": 60,
        "strategicPromotions": [],
        "strategicPromotionsValid": true,
        "startMaxHp": 29993,
        "remainHp": 5355,
        "hpPermille": 179,
        "alive": true
      }
    ],
    "frames": 2289,
    "durationMs": 77413,
    "spawnDistance": 650,
    "blueX": 570,
    "redX": 1220,
    "skillStateAudit": {
      "blue": [
        {
          "unit": "兵种347",
          "sourceId": "blackiron-60",
          "name": "斗兽标定_blue_blackiron_60_red_r001_0",
          "observed": false,
          "state": null
        }
      ],
      "red": [
        {
          "unit": "兵种465",
          "sourceId": "bladebot-60",
          "name": "斗兽标定_red_blackiron_60_red_r001_0",
          "observed": false,
          "state": null
        }
      ]
    },
    "presentationAudit": {
      "qualityAtStart": "MEDIUM",
      "qualityApplied": "MEDIUM",
      "atStart": {
        "observed": true,
        "qualityApplied": "MEDIUM",
        "performanceLevel": 0,
        "lastAppliedSoftU": 0,
        "appliedCommand": 6,
        "sceneEpoch": 3,
        "paused": false,
        "frameRate": 30
      },
      "atEnd": {
        "observed": true,
        "qualityApplied": "MEDIUM",
        "performanceLevel": 0,
        "lastAppliedSoftU": 0,
        "appliedCommand": 6,
        "sceneEpoch": 3,
        "paused": false,
        "frameRate": 30
      }
    },
    "blue": {
      "maxHp": 25457,
      "remainHp": 0,
      "aliveCount": 0,
      "startMaxHp": 25457,
      "startCount": 1
    },
    "red": {
      "maxHp": 29993,
      "remainHp": 5355,
      "aliveCount": 1,
      "startMaxHp": 29993,
      "startCount": 1
    },
    "errors": []
  }
}
```
