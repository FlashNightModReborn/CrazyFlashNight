# Unattended Arena Calibration Run

- status: completed
- batchId: `bladebot-front-r6f-20261016`
- slot: `cf7_agent_bladebot_front_r6f`
- seedSource: `saves/cf7_agent_bladebot_seed_r2.json`
- manifest: `tmp/arena-calibration/batches/bladebot-front-r6f-20261016/case-manifest-c005348839ab5c12e174f8875af9ad589b7608dd47c7bd39365df4503261d832.json`
- resultPath: `tmp/arena-calibration/unattended/20261015T181453Z-bladebot-front-r6f-20261016-e79a01f4-0568-40b4-beee-b79596e203b4/attempt-1-bladebot-front-r6f-20261016-attempt-acc19049-f324-4d46-bf6a-86b1abea5ba3-results.jsonl`
- summaryPath: `tmp/arena-calibration/unattended/20261015T181453Z-bladebot-front-r6f-20261016-e79a01f4-0568-40b4-beee-b79596e203b4/summary.json`
- recoveryAttemptsUsed: 0/0
- startedAt: 2026-10-15T18:14:53.365Z
- completedAt: 2026-10-15T18:20:55.194Z

## Runtime Binary Identity

- verified: true
- runtimeMode: `isolated_candidate`
- processPath: `C:\Users\fs\.codex\worktrees\wings-combat\CrazyFlashNight\tmp\runtime-candidates\v2\wings-r1\runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe`
- coreSha256: `0B77B242CD101494C5B4944A13B8226D7B3FBBB93D078386D0F3E7A342980DE6`
- buildIdentity: `8EA4A84690A931791CAEB33952B7C7200AA5AA4A5141962085C5D049196C6212`
- payloadClosure: `20FE94FD57A50939F5DA7E00532D56B6A83250ED51714D8A976D148CD0ABA156`
- protectedSaveUnchanged: true
- protectedSaveBefore: `sha256:3dc5b24c007545e3c0376fe893a7f2c200f5be5337719a333adfeb4d03b53eaf`
- protectedSaveAfter: `sha256:3dc5b24c007545e3c0376fe893a7f2c200f5be5337719a333adfeb4d03b53eaf`

## Attempts

| # | status | batchId | rows | resultPath | rerun |
|---|---|---|---:|---|---|
| 1 | completed | `bladebot-front-r6f-20261016` | 4/4 | `tmp/arena-calibration/unattended/20261015T181453Z-bladebot-front-r6f-20261016-e79a01f4-0568-40b4-beee-b79596e203b4/attempt-1-bladebot-front-r6f-20261016-attempt-acc19049-f324-4d46-bf6a-86b1abea5ba3-results.jsonl` |  |

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
  "sessionEpoch": "421991a3fe064485849a72589a06d85b",
  "assignmentId": "assignment-bae4073a-e457-48b7-abbd-9e162def189e",
  "attemptId": "attempt-acc19049-f324-4d46-bf6a-86b1abea5ba3",
  "transportPoisoned": false,
  "state": "completed",
  "note": null,
  "batchId": "bladebot-front-r6f-20261016",
  "manifestHash": "sha256:c005348839ab5c12e174f8875af9ad589b7608dd47c7bd39365df4503261d832",
  "manifestPath": "tmp/arena-calibration/batches/bladebot-front-r6f-20261016/case-manifest-c005348839ab5c12e174f8875af9ad589b7608dd47c7bd39365df4503261d832.json",
  "frozenManifestPath": "tmp/arena-calibration/batches/bladebot-front-r6f-20261016/attempts/attempt-acc19049-f324-4d46-bf6a-86b1abea5ba3/case_manifest.json",
  "resultPath": "tmp/arena-calibration/batches/bladebot-front-r6f-20261016/attempts/attempt-acc19049-f324-4d46-bf6a-86b1abea5ba3/results.jsonl",
  "totalRuns": 4,
  "completedRuns": 4,
  "currentCaseId": null,
  "currentRunId": null,
  "lastError": null,
  "lastResult": {
    "schema": "arena-calibration.result.v1",
    "workerId": "guardian",
    "sessionEpoch": "421991a3fe064485849a72589a06d85b",
    "assignmentId": "assignment-bae4073a-e457-48b7-abbd-9e162def189e",
    "attemptId": "attempt-acc19049-f324-4d46-bf6a-86b1abea5ba3",
    "batchId": "bladebot-front-r6f-20261016",
    "manifestHash": "sha256:c005348839ab5c12e174f8875af9ad589b7608dd47c7bd39365df4503261d832",
    "caseId": "arkclaw-30-red",
    "caseHash": "sha256:87da1bd31041c51b7a3cdfe8c910eaf35e5be3338ddbd2ecb16499386483f021",
    "runId": "arkclaw-30-red-r001",
    "repeatIndex": 1,
    "status": "finished",
    "winner": "blue",
    "startedAt": "2026-10-15T18:19:58.7930903Z",
    "completedAt": "2026-10-15T18:20:53.5205820Z",
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
      "dataSha256": "8ca5b37dd6e3d20d33ca08c230af990eedb1219447ce3cf4eca67ec5622ab6f0",
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
        "remainHp": 31324,
        "hpPermille": 831,
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
        "startMaxHp": 20321,
        "remainHp": 0,
        "hpPermille": 0,
        "alive": false
      }
    ],
    "frames": 1578,
    "durationMs": 54690,
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
      "maxHp": 37711,
      "remainHp": 31324,
      "aliveCount": 1,
      "startMaxHp": 37711,
      "startCount": 1
    },
    "red": {
      "maxHp": 20321,
      "remainHp": 0,
      "aliveCount": 0,
      "startMaxHp": 20321,
      "startCount": 1
    },
    "errors": []
  }
}
```
