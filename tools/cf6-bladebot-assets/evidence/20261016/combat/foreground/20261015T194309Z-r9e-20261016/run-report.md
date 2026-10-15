# Unattended Arena Calibration Run

- status: completed
- batchId: `bladebot-front-r9e-20261016`
- slot: `cf7_agent_bladebot_front_r9e`
- seedSource: `saves/cf7_agent_bladebot_seed_r2.json`
- manifest: `tmp/arena-calibration/batches/bladebot-front-r9e-20261016/case-manifest-42653ae227535e6ac9c3b37d9d1f6c0eeb5befc0d89684d9940151ceb65af7ef.json`
- resultPath: `tmp/arena-calibration/unattended/20261015T194309Z-bladebot-front-r9e-20261016-76afeac8-9871-40d3-8a02-bde07fcda08c/attempt-1-bladebot-front-r9e-20261016-attempt-282b383c-ff95-4ba2-a82a-2d9ecb842a6b-results.jsonl`
- summaryPath: `tmp/arena-calibration/unattended/20261015T194309Z-bladebot-front-r9e-20261016-76afeac8-9871-40d3-8a02-bde07fcda08c/summary.json`
- recoveryAttemptsUsed: 0/0
- startedAt: 2026-10-15T19:43:09.543Z
- completedAt: 2026-10-15T19:48:56.587Z

## Runtime Binary Identity

- verified: true
- runtimeMode: `isolated_candidate`
- processPath: `C:\Users\fs\.codex\worktrees\wings-combat\CrazyFlashNight\tmp\runtime-candidates\v2\wings-r1\runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe`
- coreSha256: `0B77B242CD101494C5B4944A13B8226D7B3FBBB93D078386D0F3E7A342980DE6`
- buildIdentity: `8EA4A84690A931791CAEB33952B7C7200AA5AA4A5141962085C5D049196C6212`
- payloadClosure: `20FE94FD57A50939F5DA7E00532D56B6A83250ED51714D8A976D148CD0ABA156`
- protectedSaveUnchanged: true
- protectedSaveBefore: `sha256:28c8e2b9331d9671f2585de66da12487699dc95809d01a1609ac32efe7320cf9`
- protectedSaveAfter: `sha256:28c8e2b9331d9671f2585de66da12487699dc95809d01a1609ac32efe7320cf9`

## Attempts

| # | status | batchId | rows | resultPath | rerun |
|---|---|---|---:|---|---|
| 1 | completed | `bladebot-front-r9e-20261016` | 4/4 | `tmp/arena-calibration/unattended/20261015T194309Z-bladebot-front-r9e-20261016-76afeac8-9871-40d3-8a02-bde07fcda08c/attempt-1-bladebot-front-r9e-20261016-attempt-282b383c-ff95-4ba2-a82a-2d9ecb842a6b-results.jsonl` |  |

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
  "sessionEpoch": "bc8e4031173d48f695c7f7cbde3b09f9",
  "assignmentId": "assignment-baa28aab-66c6-4dcb-b0f9-46c99b195b74",
  "attemptId": "attempt-282b383c-ff95-4ba2-a82a-2d9ecb842a6b",
  "transportPoisoned": false,
  "state": "completed",
  "note": null,
  "batchId": "bladebot-front-r9e-20261016",
  "manifestHash": "sha256:42653ae227535e6ac9c3b37d9d1f6c0eeb5befc0d89684d9940151ceb65af7ef",
  "manifestPath": "tmp/arena-calibration/batches/bladebot-front-r9e-20261016/case-manifest-42653ae227535e6ac9c3b37d9d1f6c0eeb5befc0d89684d9940151ceb65af7ef.json",
  "frozenManifestPath": "tmp/arena-calibration/batches/bladebot-front-r9e-20261016/attempts/attempt-282b383c-ff95-4ba2-a82a-2d9ecb842a6b/case_manifest.json",
  "resultPath": "tmp/arena-calibration/batches/bladebot-front-r9e-20261016/attempts/attempt-282b383c-ff95-4ba2-a82a-2d9ecb842a6b/results.jsonl",
  "totalRuns": 4,
  "completedRuns": 4,
  "currentCaseId": null,
  "currentRunId": null,
  "lastError": null,
  "lastResult": {
    "schema": "arena-calibration.result.v1",
    "workerId": "guardian",
    "sessionEpoch": "bc8e4031173d48f695c7f7cbde3b09f9",
    "assignmentId": "assignment-baa28aab-66c6-4dcb-b0f9-46c99b195b74",
    "attemptId": "attempt-282b383c-ff95-4ba2-a82a-2d9ecb842a6b",
    "batchId": "bladebot-front-r9e-20261016",
    "manifestHash": "sha256:42653ae227535e6ac9c3b37d9d1f6c0eeb5befc0d89684d9940151ceb65af7ef",
    "caseId": "arkclaw-99-red",
    "caseHash": "sha256:db510dd35f4fc1c28dcdec080dfbebabe35d829159bb5db9540466841066d3d3",
    "runId": "arkclaw-99-red-r001",
    "repeatIndex": 1,
    "status": "finished",
    "winner": "blue",
    "startedAt": "2026-10-15T19:47:47.3464690Z",
    "completedAt": "2026-10-15T19:48:54.6767878Z",
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
        "level": 99,
        "name": "斗兽标定_blue_arkclaw_99_red_r001_0",
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
        "name": "斗兽标定_red_arkclaw_99_red_r001_0",
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
      "comparison": "arkclaw",
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
        "sourceId": "arkclaw-99",
        "petId": -1,
        "identifier": "敌人-方舟爪豪",
        "resolvedType": "敌人-方舟爪豪",
        "level": 99,
        "strategicPromotions": [],
        "strategicPromotionsValid": true,
        "startMaxHp": 66949,
        "remainHp": 52763,
        "hpPermille": 788,
        "alive": true
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
        "remainHp": 0,
        "hpPermille": 0,
        "alive": false
      }
    ],
    "frames": 1962,
    "durationMs": 67282,
    "spawnDistance": 650,
    "blueX": 570,
    "redX": 1220,
    "skillStateAudit": {
      "blue": [
        {
          "unit": "兵种286",
          "sourceId": "arkclaw-99",
          "name": "斗兽标定_blue_arkclaw_99_red_r001_0",
          "observed": false,
          "state": null
        }
      ],
      "red": [
        {
          "unit": "兵种465",
          "sourceId": "bladebot-99",
          "name": "斗兽标定_red_arkclaw_99_red_r001_0",
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
      "maxHp": 66949,
      "remainHp": 52763,
      "aliveCount": 1,
      "startMaxHp": 66949,
      "startCount": 1
    },
    "red": {
      "maxHp": 38261,
      "remainHp": 0,
      "aliveCount": 0,
      "startMaxHp": 38261,
      "startCount": 1
    },
    "errors": []
  }
}
```
