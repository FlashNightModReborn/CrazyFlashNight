# Unattended Arena Calibration Run

- status: completed
- batchId: `bladebot-front-r3-20261016`
- slot: `cf7_agent_bladebot_front_r3`
- seedSource: `saves/cf7_agent_bladebot_seed_r2.json`
- manifest: `tmp/arena-calibration/batches/bladebot-front-r3-20261016/case-manifest-853748c05e3070687dcae655b24c63d869219c30a9b05ecb6fd92ea1a30d3884.json`
- resultPath: `tmp/arena-calibration/unattended/20261015T164221Z-bladebot-front-r3-20261016-19780890-347b-4ff6-9351-369a3242f887/attempt-1-bladebot-front-r3-20261016-attempt-b7d95a9f-8650-4139-9768-7fa4b8a4c77e-results.jsonl`
- summaryPath: `tmp/arena-calibration/unattended/20261015T164221Z-bladebot-front-r3-20261016-19780890-347b-4ff6-9351-369a3242f887/summary.json`
- recoveryAttemptsUsed: 0/0
- startedAt: 2026-10-15T16:42:21.685Z
- completedAt: 2026-10-15T16:48:21.124Z

## Runtime Binary Identity

- verified: true
- runtimeMode: `isolated_candidate`
- processPath: `C:\Users\fs\.codex\worktrees\wings-combat\CrazyFlashNight\tmp\runtime-candidates\v2\wings-r1\runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe`
- coreSha256: `0B77B242CD101494C5B4944A13B8226D7B3FBBB93D078386D0F3E7A342980DE6`
- buildIdentity: `8EA4A84690A931791CAEB33952B7C7200AA5AA4A5141962085C5D049196C6212`
- payloadClosure: `20FE94FD57A50939F5DA7E00532D56B6A83250ED51714D8A976D148CD0ABA156`
- protectedSaveUnchanged: true
- protectedSaveBefore: `sha256:7bceabea5cefeee7eaad1cf232cb465f3965875a5d4c01852ecee29dc7552282`
- protectedSaveAfter: `sha256:7bceabea5cefeee7eaad1cf232cb465f3965875a5d4c01852ecee29dc7552282`

## Attempts

| # | status | batchId | rows | resultPath | rerun |
|---|---|---|---:|---|---|
| 1 | completed | `bladebot-front-r3-20261016` | 4/4 | `tmp/arena-calibration/unattended/20261015T164221Z-bladebot-front-r3-20261016-19780890-347b-4ff6-9351-369a3242f887/attempt-1-bladebot-front-r3-20261016-attempt-b7d95a9f-8650-4139-9768-7fa4b8a4c77e-results.jsonl` |  |

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
  "sessionEpoch": "82d0c255b32248a0b0b9bce6499c06b3",
  "assignmentId": "assignment-89e2e53b-9e45-4e63-ae5b-cfaf5e4fd12c",
  "attemptId": "attempt-b7d95a9f-8650-4139-9768-7fa4b8a4c77e",
  "transportPoisoned": false,
  "state": "completed",
  "note": null,
  "batchId": "bladebot-front-r3-20261016",
  "manifestHash": "sha256:853748c05e3070687dcae655b24c63d869219c30a9b05ecb6fd92ea1a30d3884",
  "manifestPath": "tmp/arena-calibration/batches/bladebot-front-r3-20261016/case-manifest-853748c05e3070687dcae655b24c63d869219c30a9b05ecb6fd92ea1a30d3884.json",
  "frozenManifestPath": "tmp/arena-calibration/batches/bladebot-front-r3-20261016/attempts/attempt-b7d95a9f-8650-4139-9768-7fa4b8a4c77e/case_manifest.json",
  "resultPath": "tmp/arena-calibration/batches/bladebot-front-r3-20261016/attempts/attempt-b7d95a9f-8650-4139-9768-7fa4b8a4c77e/results.jsonl",
  "totalRuns": 4,
  "completedRuns": 4,
  "currentCaseId": null,
  "currentRunId": null,
  "lastError": null,
  "lastResult": {
    "schema": "arena-calibration.result.v1",
    "workerId": "guardian",
    "sessionEpoch": "82d0c255b32248a0b0b9bce6499c06b3",
    "assignmentId": "assignment-89e2e53b-9e45-4e63-ae5b-cfaf5e4fd12c",
    "attemptId": "attempt-b7d95a9f-8650-4139-9768-7fa4b8a4c77e",
    "batchId": "bladebot-front-r3-20261016",
    "manifestHash": "sha256:853748c05e3070687dcae655b24c63d869219c30a9b05ecb6fd92ea1a30d3884",
    "caseId": "arkclaw-30-red",
    "caseHash": "sha256:929dbb9e31c6636b79eb918f912983c06a6d439debd8d48442a943d1600c0824",
    "runId": "arkclaw-30-red-r001",
    "repeatIndex": 1,
    "status": "finished",
    "winner": "blue",
    "startedAt": "2026-10-15T16:47:49.5257408Z",
    "completedAt": "2026-10-15T16:48:18.8967315Z",
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
      "aiSourceSha256": "d5b3565772b3d0bd0cfb2c23f7e8f32d668eebce9c00b8f45059b9c97631978b",
      "candidateSide": "red",
      "comparison": "arkclaw",
      "dataPath": "data/enemy_properties/CF6重制敌人.xml",
      "dataSha256": "64841084b2eb4189113c0bfdaab533bcae67b53661fe310a6fbfee40dd33e753",
      "evidenceLane": "interactive_candidate",
      "mode": "pilot",
      "rivalDataPath": "data/enemy_properties/诺亚新敌人.xml",
      "rivalDataSha256": "d339f0a4de759cce186fe98dbdf8f1f966cacf1fa5bd803714d9d41ea331321b",
      "sourceSwf": "flashswf/arts/new/Codex大刀机器人素材.swf",
      "sourceSwfSha256": "4c40e613697805b4994beded0df59b58eb320ac40a4e06358430e0f019dedb11",
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
        "remainHp": 36589,
        "hpPermille": 970,
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
        "startMaxHp": 17408,
        "remainHp": 0,
        "hpPermille": 0,
        "alive": false
      }
    ],
    "frames": 844,
    "durationMs": 29329,
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
      "maxHp": 37711,
      "remainHp": 36589,
      "aliveCount": 1,
      "startMaxHp": 37711,
      "startCount": 1
    },
    "red": {
      "maxHp": 17408,
      "remainHp": 0,
      "aliveCount": 0,
      "startMaxHp": 17408,
      "startCount": 1
    },
    "errors": []
  }
}
```
