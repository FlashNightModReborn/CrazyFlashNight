# Unattended Arena Calibration Run

- status: completed
- batchId: `bladebot-front-r9b-20261016`
- slot: `cf7_agent_bladebot_front_r9b`
- seedSource: `saves/cf7_agent_bladebot_seed_r2.json`
- manifest: `tmp/arena-calibration/batches/bladebot-front-r9b-20261016/case-manifest-4abc6112bbfa57099b7af645cef8e8bb5eaed325b793584659d4b1934bd23bfd.json`
- resultPath: `tmp/arena-calibration/unattended/20261015T190820Z-bladebot-front-r9b-20261016-b1bdeeec-dd80-4374-9264-d81adfa11291/attempt-1-bladebot-front-r9b-20261016-attempt-7d2a614f-11a3-4de9-bc96-4b7454186804-results.jsonl`
- summaryPath: `tmp/arena-calibration/unattended/20261015T190820Z-bladebot-front-r9b-20261016-b1bdeeec-dd80-4374-9264-d81adfa11291/summary.json`
- recoveryAttemptsUsed: 0/0
- startedAt: 2026-10-15T19:08:20.807Z
- completedAt: 2026-10-15T19:19:49.192Z

## Runtime Binary Identity

- verified: true
- runtimeMode: `isolated_candidate`
- processPath: `C:\Users\fs\.codex\worktrees\wings-combat\CrazyFlashNight\tmp\runtime-candidates\v2\wings-r1\runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe`
- coreSha256: `0B77B242CD101494C5B4944A13B8226D7B3FBBB93D078386D0F3E7A342980DE6`
- buildIdentity: `8EA4A84690A931791CAEB33952B7C7200AA5AA4A5141962085C5D049196C6212`
- payloadClosure: `20FE94FD57A50939F5DA7E00532D56B6A83250ED51714D8A976D148CD0ABA156`
- protectedSaveUnchanged: true
- protectedSaveBefore: `sha256:959c91e003659141a566577a0aaed9bd7c523ed04fe8de1c4cb2005b69bcd2eb`
- protectedSaveAfter: `sha256:959c91e003659141a566577a0aaed9bd7c523ed04fe8de1c4cb2005b69bcd2eb`

## Attempts

| # | status | batchId | rows | resultPath | rerun |
|---|---|---|---:|---|---|
| 1 | completed | `bladebot-front-r9b-20261016` | 6/6 | `tmp/arena-calibration/unattended/20261015T190820Z-bladebot-front-r9b-20261016-b1bdeeec-dd80-4374-9264-d81adfa11291/attempt-1-bladebot-front-r9b-20261016-attempt-7d2a614f-11a3-4de9-bc96-4b7454186804-results.jsonl` |  |

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
  "sessionEpoch": "32eca47084984f9caf6d710d4bd79b2d",
  "assignmentId": "assignment-04ea8750-3f11-419f-8a9c-64fe37f8998e",
  "attemptId": "attempt-7d2a614f-11a3-4de9-bc96-4b7454186804",
  "transportPoisoned": false,
  "state": "completed",
  "note": null,
  "batchId": "bladebot-front-r9b-20261016",
  "manifestHash": "sha256:4abc6112bbfa57099b7af645cef8e8bb5eaed325b793584659d4b1934bd23bfd",
  "manifestPath": "tmp/arena-calibration/batches/bladebot-front-r9b-20261016/case-manifest-4abc6112bbfa57099b7af645cef8e8bb5eaed325b793584659d4b1934bd23bfd.json",
  "frozenManifestPath": "tmp/arena-calibration/batches/bladebot-front-r9b-20261016/attempts/attempt-7d2a614f-11a3-4de9-bc96-4b7454186804/case_manifest.json",
  "resultPath": "tmp/arena-calibration/batches/bladebot-front-r9b-20261016/attempts/attempt-7d2a614f-11a3-4de9-bc96-4b7454186804/results.jsonl",
  "totalRuns": 6,
  "completedRuns": 6,
  "currentCaseId": null,
  "currentRunId": null,
  "lastError": null,
  "lastResult": {
    "schema": "arena-calibration.result.v1",
    "workerId": "guardian",
    "sessionEpoch": "32eca47084984f9caf6d710d4bd79b2d",
    "assignmentId": "assignment-04ea8750-3f11-419f-8a9c-64fe37f8998e",
    "attemptId": "attempt-7d2a614f-11a3-4de9-bc96-4b7454186804",
    "batchId": "bladebot-front-r9b-20261016",
    "manifestHash": "sha256:4abc6112bbfa57099b7af645cef8e8bb5eaed325b793584659d4b1934bd23bfd",
    "caseId": "blackiron-99-red",
    "caseHash": "sha256:36c628898c97bd06f0316f167a32df2266225f2623b5ddc89e6344b38f307d6d",
    "runId": "blackiron-99-red-r001",
    "repeatIndex": 1,
    "status": "timeout",
    "winner": "timeout",
    "startedAt": "2026-10-15T19:17:44.3128570Z",
    "completedAt": "2026-10-15T19:19:47.5256271Z",
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
        "name": "斗兽标定_blue_blackiron_99_red_r001_0",
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
        "name": "斗兽标定_red_blackiron_99_red_r001_0",
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
        "sourceId": "blackiron-99",
        "petId": -1,
        "identifier": "敌人-黑铁会改造人",
        "resolvedType": "敌人-黑铁会改造人",
        "level": 99,
        "strategicPromotions": [],
        "strategicPromotionsValid": true,
        "startMaxHp": 35505,
        "remainHp": 3571,
        "hpPermille": 101,
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
        "remainHp": 9945,
        "hpPermille": 260,
        "alive": true
      }
    ],
    "frames": 3600,
    "durationMs": 123153,
    "spawnDistance": 650,
    "blueX": 570,
    "redX": 1220,
    "skillStateAudit": {
      "blue": [
        {
          "unit": "兵种347",
          "sourceId": "blackiron-99",
          "name": "斗兽标定_blue_blackiron_99_red_r001_0",
          "observed": false,
          "state": null
        }
      ],
      "red": [
        {
          "unit": "兵种465",
          "sourceId": "bladebot-99",
          "name": "斗兽标定_red_blackiron_99_red_r001_0",
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
      "remainHp": 3571,
      "aliveCount": 1,
      "startMaxHp": 35505,
      "startCount": 1
    },
    "red": {
      "maxHp": 38261,
      "remainHp": 9945,
      "aliveCount": 1,
      "startMaxHp": 38261,
      "startCount": 1
    },
    "errors": []
  }
}
```
