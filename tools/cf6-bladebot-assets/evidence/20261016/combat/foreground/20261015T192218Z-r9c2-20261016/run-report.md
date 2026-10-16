# Unattended Arena Calibration Run

- status: completed
- batchId: `bladebot-front-r9c2-20261016`
- slot: `cf7_agent_bladebot_front_r9c2`
- seedSource: `saves/cf7_agent_bladebot_seed_r2.json`
- manifest: `tmp/arena-calibration/batches/bladebot-front-r9c2-20261016/case-manifest-69a1e72aa648f2232bca48ba5b6fa5f76f6db6335f8c0ccde6494601a5ed9a44.json`
- resultPath: `tmp/arena-calibration/unattended/20261015T192218Z-bladebot-front-r9c2-20261016-202833f8-bb5f-4752-a603-441c8fc9f714/attempt-1-bladebot-front-r9c2-20261016-attempt-7d0b70e4-f066-4eb7-908a-7e03d8c5207f-results.jsonl`
- summaryPath: `tmp/arena-calibration/unattended/20261015T192218Z-bladebot-front-r9c2-20261016-202833f8-bb5f-4752-a603-441c8fc9f714/summary.json`
- recoveryAttemptsUsed: 0/0
- startedAt: 2026-10-15T19:22:18.702Z
- completedAt: 2026-10-15T19:33:02.075Z

## Runtime Binary Identity

- verified: true
- runtimeMode: `isolated_candidate`
- processPath: `C:\Users\fs\.codex\worktrees\wings-combat\CrazyFlashNight\tmp\runtime-candidates\v2\wings-r1\runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe`
- coreSha256: `0B77B242CD101494C5B4944A13B8226D7B3FBBB93D078386D0F3E7A342980DE6`
- buildIdentity: `8EA4A84690A931791CAEB33952B7C7200AA5AA4A5141962085C5D049196C6212`
- payloadClosure: `20FE94FD57A50939F5DA7E00532D56B6A83250ED51714D8A976D148CD0ABA156`
- protectedSaveUnchanged: true
- protectedSaveBefore: `sha256:e78194075c8f52ff8fc52e879a6c0744d75ad7f95b25b55018bae04f194f031f`
- protectedSaveAfter: `sha256:e78194075c8f52ff8fc52e879a6c0744d75ad7f95b25b55018bae04f194f031f`

## Attempts

| # | status | batchId | rows | resultPath | rerun |
|---|---|---|---:|---|---|
| 1 | completed | `bladebot-front-r9c2-20261016` | 4/4 | `tmp/arena-calibration/unattended/20261015T192218Z-bladebot-front-r9c2-20261016-202833f8-bb5f-4752-a603-441c8fc9f714/attempt-1-bladebot-front-r9c2-20261016-attempt-7d0b70e4-f066-4eb7-908a-7e03d8c5207f-results.jsonl` |  |

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
  "sessionEpoch": "550afe6b6e6445e9ac758272d4e9c7ee",
  "assignmentId": "assignment-0a4e3317-4086-4851-b9b4-06c67049553c",
  "attemptId": "attempt-7d0b70e4-f066-4eb7-908a-7e03d8c5207f",
  "transportPoisoned": false,
  "state": "completed",
  "note": null,
  "batchId": "bladebot-front-r9c2-20261016",
  "manifestHash": "sha256:69a1e72aa648f2232bca48ba5b6fa5f76f6db6335f8c0ccde6494601a5ed9a44",
  "manifestPath": "tmp/arena-calibration/batches/bladebot-front-r9c2-20261016/case-manifest-69a1e72aa648f2232bca48ba5b6fa5f76f6db6335f8c0ccde6494601a5ed9a44.json",
  "frozenManifestPath": "tmp/arena-calibration/batches/bladebot-front-r9c2-20261016/attempts/attempt-7d0b70e4-f066-4eb7-908a-7e03d8c5207f/case_manifest.json",
  "resultPath": "tmp/arena-calibration/batches/bladebot-front-r9c2-20261016/attempts/attempt-7d0b70e4-f066-4eb7-908a-7e03d8c5207f/results.jsonl",
  "totalRuns": 4,
  "completedRuns": 4,
  "currentCaseId": null,
  "currentRunId": null,
  "lastError": null,
  "lastResult": {
    "schema": "arena-calibration.result.v1",
    "workerId": "guardian",
    "sessionEpoch": "550afe6b6e6445e9ac758272d4e9c7ee",
    "assignmentId": "assignment-0a4e3317-4086-4851-b9b4-06c67049553c",
    "attemptId": "attempt-7d0b70e4-f066-4eb7-908a-7e03d8c5207f",
    "batchId": "bladebot-front-r9c2-20261016",
    "manifestHash": "sha256:69a1e72aa648f2232bca48ba5b6fa5f76f6db6335f8c0ccde6494601a5ed9a44",
    "caseId": "blackiron-99-red",
    "caseHash": "sha256:1a87208647a56b978ced9e630f9352b4828e4f7214d5d2761ad8cc3933e4dfed",
    "runId": "blackiron-99-red-r002",
    "repeatIndex": 2,
    "status": "finished",
    "winner": "red",
    "startedAt": "2026-10-15T19:30:47.2697264Z",
    "completedAt": "2026-10-15T19:33:00.6433632Z",
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
        "level": 99,
        "name": "斗兽标定_blue_blackiron_99_red_r002_0",
        "x": 570,
        "y": 430
      }
    ],
    "redSpawnPositions": [
      {
        "side": "red",
        "index": 0,
        "unit": "兵种465",
        "level": 99,
        "name": "斗兽标定_red_blackiron_99_red_r002_0",
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
      "tier": 9,
      "timeoutExtensionOf": "bladebot-front-r9b-20261016"
    },
    "blueUnitResults": [
      {
        "sourceId": "blackiron-99",
        "petId": -1,
        "identifier": "敌人-黑铁会改造人",
        "resolvedType": "敌人-黑铁会改造人",
        "level": 99,
        "strategicPromotions": [],
        "strategicPromotionsValid": true,
        "startMaxHp": 35505,
        "remainHp": 0,
        "hpPermille": 0,
        "alive": false
      }
    ],
    "redUnitResults": [
      {
        "sourceId": "bladebot-99",
        "petId": -1,
        "identifier": "敌人-CF6大刀机器人",
        "resolvedType": "敌人-CF6大刀机器人",
        "level": 99,
        "strategicPromotions": [],
        "strategicPromotionsValid": true,
        "startMaxHp": 38261,
        "remainHp": 7748,
        "hpPermille": 203,
        "alive": true
      }
    ],
    "frames": 3938,
    "durationMs": 133336,
    "spawnDistance": 650,
    "blueX": 570,
    "redX": 1220,
    "skillStateAudit": {
      "blue": [
        {
          "unit": "兵种347",
          "sourceId": "blackiron-99",
          "name": "斗兽标定_blue_blackiron_99_red_r002_0",
          "observed": false,
          "state": null
        }
      ],
      "red": [
        {
          "unit": "兵种465",
          "sourceId": "bladebot-99",
          "name": "斗兽标定_red_blackiron_99_red_r002_0",
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
      "maxHp": 35505,
      "remainHp": 0,
      "aliveCount": 0,
      "startMaxHp": 35505,
      "startCount": 1
    },
    "red": {
      "maxHp": 38261,
      "remainHp": 7748,
      "aliveCount": 1,
      "startMaxHp": 38261,
      "startCount": 1
    },
    "errors": []
  }
}
```
