# Unattended Arena Calibration Run

- status: completed
- batchId: `bladebot-front-r9d-20261016`
- slot: `cf7_agent_bladebot_front_r9d`
- seedSource: `saves/cf7_agent_bladebot_seed_r2.json`
- manifest: `tmp/arena-calibration/batches/bladebot-front-r9d-20261016/case-manifest-01c513df65c30a989487fa5627b3c43b28c926a399f64653ffd6efd03343e16e.json`
- resultPath: `tmp/arena-calibration/unattended/20261015T193423Z-bladebot-front-r9d-20261016-e5755ad8-672f-4930-87a0-60fe818affdd/attempt-1-bladebot-front-r9d-20261016-attempt-2c039f09-6e69-4a17-9279-a94a21cef903-results.jsonl`
- summaryPath: `tmp/arena-calibration/unattended/20261015T193423Z-bladebot-front-r9d-20261016-e5755ad8-672f-4930-87a0-60fe818affdd/summary.json`
- recoveryAttemptsUsed: 0/0
- startedAt: 2026-10-15T19:34:23.355Z
- completedAt: 2026-10-15T19:41:37.184Z

## Runtime Binary Identity

- verified: true
- runtimeMode: `isolated_candidate`
- processPath: `C:\Users\fs\.codex\worktrees\wings-combat\CrazyFlashNight\tmp\runtime-candidates\v2\wings-r1\runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe`
- coreSha256: `0B77B242CD101494C5B4944A13B8226D7B3FBBB93D078386D0F3E7A342980DE6`
- buildIdentity: `8EA4A84690A931791CAEB33952B7C7200AA5AA4A5141962085C5D049196C6212`
- payloadClosure: `20FE94FD57A50939F5DA7E00532D56B6A83250ED51714D8A976D148CD0ABA156`
- protectedSaveUnchanged: true
- protectedSaveBefore: `sha256:153001a816412b17ffb93edb4e8fc18deb7ab7c6c89d1865414775db73754363`
- protectedSaveAfter: `sha256:153001a816412b17ffb93edb4e8fc18deb7ab7c6c89d1865414775db73754363`

## Attempts

| # | status | batchId | rows | resultPath | rerun |
|---|---|---|---:|---|---|
| 1 | completed | `bladebot-front-r9d-20261016` | 4/4 | `tmp/arena-calibration/unattended/20261015T193423Z-bladebot-front-r9d-20261016-e5755ad8-672f-4930-87a0-60fe818affdd/attempt-1-bladebot-front-r9d-20261016-attempt-2c039f09-6e69-4a17-9279-a94a21cef903-results.jsonl` |  |

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
  "sessionEpoch": "7d7a6d2f8a934e9aa26d7227759073f1",
  "assignmentId": "assignment-0f4561af-8bd8-430a-a059-27b2207efb3e",
  "attemptId": "attempt-2c039f09-6e69-4a17-9279-a94a21cef903",
  "transportPoisoned": false,
  "state": "completed",
  "note": null,
  "batchId": "bladebot-front-r9d-20261016",
  "manifestHash": "sha256:01c513df65c30a989487fa5627b3c43b28c926a399f64653ffd6efd03343e16e",
  "manifestPath": "tmp/arena-calibration/batches/bladebot-front-r9d-20261016/case-manifest-01c513df65c30a989487fa5627b3c43b28c926a399f64653ffd6efd03343e16e.json",
  "frozenManifestPath": "tmp/arena-calibration/batches/bladebot-front-r9d-20261016/attempts/attempt-2c039f09-6e69-4a17-9279-a94a21cef903/case_manifest.json",
  "resultPath": "tmp/arena-calibration/batches/bladebot-front-r9d-20261016/attempts/attempt-2c039f09-6e69-4a17-9279-a94a21cef903/results.jsonl",
  "totalRuns": 4,
  "completedRuns": 4,
  "currentCaseId": null,
  "currentRunId": null,
  "lastError": null,
  "lastResult": {
    "schema": "arena-calibration.result.v1",
    "workerId": "guardian",
    "sessionEpoch": "7d7a6d2f8a934e9aa26d7227759073f1",
    "assignmentId": "assignment-0f4561af-8bd8-430a-a059-27b2207efb3e",
    "attemptId": "attempt-2c039f09-6e69-4a17-9279-a94a21cef903",
    "batchId": "bladebot-front-r9d-20261016",
    "manifestHash": "sha256:01c513df65c30a989487fa5627b3c43b28c926a399f64653ffd6efd03343e16e",
    "caseId": "blackiron-60-red",
    "caseHash": "sha256:4a5295977199cb15152a88c0a0c5794749bdda66a0a521f85415d50f6c36b524",
    "runId": "blackiron-60-red-r001",
    "repeatIndex": 1,
    "status": "finished",
    "winner": "red",
    "startedAt": "2026-10-15T19:40:10.6001287Z",
    "completedAt": "2026-10-15T19:41:35.3016088Z",
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
      "dataSha256": "51cc64832e4b05e31383bc61a56b8953b9222594c92d9991f2025eef97f64e40",
      "evidenceLane": "interactive_candidate",
      "mode": "confirm",
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
        "startMaxHp": 27004,
        "remainHp": 10449,
        "hpPermille": 387,
        "alive": true
      }
    ],
    "frames": 2514,
    "durationMs": 84660,
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
        "appliedCommand": 2,
        "sceneEpoch": 3,
        "paused": false,
        "frameRate": 30
      },
      "atEnd": {
        "observed": true,
        "qualityApplied": "MEDIUM",
        "performanceLevel": 0,
        "lastAppliedSoftU": 0,
        "appliedCommand": 2,
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
      "maxHp": 27004,
      "remainHp": 10449,
      "aliveCount": 1,
      "startMaxHp": 27004,
      "startCount": 1
    },
    "errors": []
  }
}
```
