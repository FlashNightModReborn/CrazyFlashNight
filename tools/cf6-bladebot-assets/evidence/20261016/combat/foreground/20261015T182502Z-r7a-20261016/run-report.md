# Unattended Arena Calibration Run

- status: completed
- batchId: `bladebot-front-r7a-20261016`
- slot: `cf7_agent_bladebot_front_r7a`
- seedSource: `saves/cf7_agent_bladebot_seed_r2.json`
- manifest: `tmp/arena-calibration/batches/bladebot-front-r7a-20261016/case-manifest-dfdfde2cd40334b12a8cfe664029495c47ef54f006211c838ff754c4b213f01c.json`
- resultPath: `tmp/arena-calibration/unattended/20261015T182502Z-bladebot-front-r7a-20261016-f80774f0-53a5-4e4a-aca1-331340da46e0/attempt-1-bladebot-front-r7a-20261016-attempt-0666b0bb-42dc-4b89-99f4-7dad14120392-results.jsonl`
- summaryPath: `tmp/arena-calibration/unattended/20261015T182502Z-bladebot-front-r7a-20261016-f80774f0-53a5-4e4a-aca1-331340da46e0/summary.json`
- recoveryAttemptsUsed: 0/0
- startedAt: 2026-10-15T18:25:02.521Z
- completedAt: 2026-10-15T18:35:05.198Z

## Runtime Binary Identity

- verified: true
- runtimeMode: `isolated_candidate`
- processPath: `C:\Users\fs\.codex\worktrees\wings-combat\CrazyFlashNight\tmp\runtime-candidates\v2\wings-r1\runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe`
- coreSha256: `0B77B242CD101494C5B4944A13B8226D7B3FBBB93D078386D0F3E7A342980DE6`
- buildIdentity: `8EA4A84690A931791CAEB33952B7C7200AA5AA4A5141962085C5D049196C6212`
- payloadClosure: `20FE94FD57A50939F5DA7E00532D56B6A83250ED51714D8A976D148CD0ABA156`
- protectedSaveUnchanged: true
- protectedSaveBefore: `sha256:83368d0813bb33e648fb182bcfda874f483d0e8f909361cd6260a33db9e92f67`
- protectedSaveAfter: `sha256:83368d0813bb33e648fb182bcfda874f483d0e8f909361cd6260a33db9e92f67`

## Attempts

| # | status | batchId | rows | resultPath | rerun |
|---|---|---|---:|---|---|
| 1 | completed | `bladebot-front-r7a-20261016` | 6/6 | `tmp/arena-calibration/unattended/20261015T182502Z-bladebot-front-r7a-20261016-f80774f0-53a5-4e4a-aca1-331340da46e0/attempt-1-bladebot-front-r7a-20261016-attempt-0666b0bb-42dc-4b89-99f4-7dad14120392-results.jsonl` |  |

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
  "sessionEpoch": "a7d0eb708e0f4de8ac0742835ecbc82d",
  "assignmentId": "assignment-ae3c2641-a4bd-41c0-8137-3f3c595bde11",
  "attemptId": "attempt-0666b0bb-42dc-4b89-99f4-7dad14120392",
  "transportPoisoned": false,
  "state": "completed",
  "note": null,
  "batchId": "bladebot-front-r7a-20261016",
  "manifestHash": "sha256:dfdfde2cd40334b12a8cfe664029495c47ef54f006211c838ff754c4b213f01c",
  "manifestPath": "tmp/arena-calibration/batches/bladebot-front-r7a-20261016/case-manifest-dfdfde2cd40334b12a8cfe664029495c47ef54f006211c838ff754c4b213f01c.json",
  "frozenManifestPath": "tmp/arena-calibration/batches/bladebot-front-r7a-20261016/attempts/attempt-0666b0bb-42dc-4b89-99f4-7dad14120392/case_manifest.json",
  "resultPath": "tmp/arena-calibration/batches/bladebot-front-r7a-20261016/attempts/attempt-0666b0bb-42dc-4b89-99f4-7dad14120392/results.jsonl",
  "totalRuns": 6,
  "completedRuns": 6,
  "currentCaseId": null,
  "currentRunId": null,
  "lastError": null,
  "lastResult": {
    "schema": "arena-calibration.result.v1",
    "workerId": "guardian",
    "sessionEpoch": "a7d0eb708e0f4de8ac0742835ecbc82d",
    "assignmentId": "assignment-ae3c2641-a4bd-41c0-8137-3f3c595bde11",
    "attemptId": "attempt-0666b0bb-42dc-4b89-99f4-7dad14120392",
    "batchId": "bladebot-front-r7a-20261016",
    "manifestHash": "sha256:dfdfde2cd40334b12a8cfe664029495c47ef54f006211c838ff754c4b213f01c",
    "caseId": "arkclaw-30-red",
    "caseHash": "sha256:63fb8dfe426c11d72d901fb297cdaa6b43e7010d793d403413301f4fb9f7a1c3",
    "runId": "arkclaw-30-red-r001",
    "repeatIndex": 1,
    "status": "finished",
    "winner": "blue",
    "startedAt": "2026-10-15T18:33:51.8013041Z",
    "completedAt": "2026-10-15T18:35:03.2761870Z",
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
        "unit": "兵种286",
        "level": 30,
        "name": "斗兽标定_blue_arkclaw_30_red_r001_0",
        "x": 570,
        "y": 430
      }
    ],
    "redSpawnPositions": [
      {
        "side": "red",
        "index": 0,
        "unit": "兵种465",
        "level": 30,
        "name": "斗兽标定_red_arkclaw_30_red_r001_0",
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
      "aiSourceSha256": "64403584ae37e153be2e9a4b082d94273d194f783c0f49e7f8a51effaa06c1b6",
      "candidateSide": "red",
      "comparison": "arkclaw",
      "dataPath": "data/enemy_properties/CF6重制敌人.xml",
      "dataSha256": "0374ba19908af21464aac7f786f2d6c72e1f4ae8a431c40334d7e17007daf41e",
      "evidenceLane": "interactive_candidate",
      "mode": "pilot",
      "rivalDataPath": "data/enemy_properties/诺亚新敌人.xml",
      "rivalDataSha256": "d339f0a4de759cce186fe98dbdf8f1f966cacf1fa5bd803714d9d41ea331321b",
      "sourceSwf": "flashswf/arts/new/Codex大刀机器人素材.swf",
      "sourceSwfSha256": "bca805648f40c7360405c490690d109ebd8882a9a171b7236c8f76c520e5d700",
      "stage": 8,
      "tier": 9
    },
    "blueUnitResults": [
      {
        "sourceId": "arkclaw-30",
        "petId": -1,
        "identifier": "敌人-方舟爪豪",
        "resolvedType": "敌人-方舟爪豪",
        "level": 30,
        "strategicPromotions": [],
        "strategicPromotionsValid": true,
        "startMaxHp": 37711,
        "remainHp": 31254,
        "hpPermille": 829,
        "alive": true
      }
    ],
    "redUnitResults": [
      {
        "sourceId": "bladebot-30",
        "petId": -1,
        "identifier": "敌人-CF6大刀机器人",
        "resolvedType": "敌人-CF6大刀机器人",
        "level": 30,
        "strategicPromotions": [],
        "strategicPromotionsValid": true,
        "startMaxHp": 26165,
        "remainHp": 0,
        "hpPermille": 0,
        "alive": false
      }
    ],
    "frames": 1926,
    "durationMs": 71413,
    "spawnDistance": 650,
    "blueX": 570,
    "redX": 1220,
    "skillStateAudit": {
      "blue": [
        {
          "unit": "兵种286",
          "sourceId": "arkclaw-30",
          "name": "斗兽标定_blue_arkclaw_30_red_r001_0",
          "observed": false,
          "state": null
        }
      ],
      "red": [
        {
          "unit": "兵种465",
          "sourceId": "bladebot-30",
          "name": "斗兽标定_red_arkclaw_30_red_r001_0",
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
        "appliedCommand": 4,
        "sceneEpoch": 3,
        "paused": false,
        "frameRate": 30
      },
      "atEnd": {
        "observed": true,
        "qualityApplied": "MEDIUM",
        "performanceLevel": 0,
        "lastAppliedSoftU": 0,
        "appliedCommand": 4,
        "sceneEpoch": 3,
        "paused": false,
        "frameRate": 30
      }
    },
    "blue": {
      "maxHp": 37711,
      "remainHp": 31254,
      "aliveCount": 1,
      "startMaxHp": 37711,
      "startCount": 1
    },
    "red": {
      "maxHp": 26165,
      "remainHp": 0,
      "aliveCount": 0,
      "startMaxHp": 26165,
      "startCount": 1
    },
    "errors": []
  }
}
```
