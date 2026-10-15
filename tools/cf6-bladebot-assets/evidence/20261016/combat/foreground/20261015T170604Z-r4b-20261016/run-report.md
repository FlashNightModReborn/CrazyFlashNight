# Unattended Arena Calibration Run

- status: completed
- batchId: `bladebot-front-r4b-20261016`
- slot: `cf7_agent_bladebot_front_r4b`
- seedSource: `saves/cf7_agent_bladebot_seed_r2.json`
- manifest: `tmp/arena-calibration/batches/bladebot-front-r4b-20261016/case-manifest-c587a7417c2fc7458a05922222d734a88107b1d7bdce86eb3fc1ba40d36010b4.json`
- resultPath: `tmp/arena-calibration/unattended/20261015T170604Z-bladebot-front-r4b-20261016-a51c18a2-8f52-4241-91dc-09d6bafe9ff6/attempt-1-bladebot-front-r4b-20261016-attempt-d48c9aa6-e408-4e23-bdfb-892fcb86baee-results.jsonl`
- summaryPath: `tmp/arena-calibration/unattended/20261015T170604Z-bladebot-front-r4b-20261016-a51c18a2-8f52-4241-91dc-09d6bafe9ff6/summary.json`
- recoveryAttemptsUsed: 0/0
- startedAt: 2026-10-15T17:06:04.223Z
- completedAt: 2026-10-15T17:11:55.693Z

## Runtime Binary Identity

- verified: true
- runtimeMode: `isolated_candidate`
- processPath: `C:\Users\fs\.codex\worktrees\wings-combat\CrazyFlashNight\tmp\runtime-candidates\v2\wings-r1\runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe`
- coreSha256: `0B77B242CD101494C5B4944A13B8226D7B3FBBB93D078386D0F3E7A342980DE6`
- buildIdentity: `8EA4A84690A931791CAEB33952B7C7200AA5AA4A5141962085C5D049196C6212`
- payloadClosure: `20FE94FD57A50939F5DA7E00532D56B6A83250ED51714D8A976D148CD0ABA156`
- protectedSaveUnchanged: true
- protectedSaveBefore: `sha256:c277ad718a497dd9f43b8ce035f0f8c20c4a08d7a3ed40271ffec241e80b50de`
- protectedSaveAfter: `sha256:c277ad718a497dd9f43b8ce035f0f8c20c4a08d7a3ed40271ffec241e80b50de`

## Attempts

| # | status | batchId | rows | resultPath | rerun |
|---|---|---|---:|---|---|
| 1 | completed | `bladebot-front-r4b-20261016` | 4/4 | `tmp/arena-calibration/unattended/20261015T170604Z-bladebot-front-r4b-20261016-a51c18a2-8f52-4241-91dc-09d6bafe9ff6/attempt-1-bladebot-front-r4b-20261016-attempt-d48c9aa6-e408-4e23-bdfb-892fcb86baee-results.jsonl` |  |

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
  "sessionEpoch": "2c33d5c3bb9e414197b35629a97082e9",
  "assignmentId": "assignment-fa3c805b-5019-49a0-a7da-1912fd0df798",
  "attemptId": "attempt-d48c9aa6-e408-4e23-bdfb-892fcb86baee",
  "transportPoisoned": false,
  "state": "completed",
  "note": null,
  "batchId": "bladebot-front-r4b-20261016",
  "manifestHash": "sha256:c587a7417c2fc7458a05922222d734a88107b1d7bdce86eb3fc1ba40d36010b4",
  "manifestPath": "tmp/arena-calibration/batches/bladebot-front-r4b-20261016/case-manifest-c587a7417c2fc7458a05922222d734a88107b1d7bdce86eb3fc1ba40d36010b4.json",
  "frozenManifestPath": "tmp/arena-calibration/batches/bladebot-front-r4b-20261016/attempts/attempt-d48c9aa6-e408-4e23-bdfb-892fcb86baee/case_manifest.json",
  "resultPath": "tmp/arena-calibration/batches/bladebot-front-r4b-20261016/attempts/attempt-d48c9aa6-e408-4e23-bdfb-892fcb86baee/results.jsonl",
  "totalRuns": 4,
  "completedRuns": 4,
  "currentCaseId": null,
  "currentRunId": null,
  "lastError": null,
  "lastResult": {
    "schema": "arena-calibration.result.v1",
    "workerId": "guardian",
    "sessionEpoch": "2c33d5c3bb9e414197b35629a97082e9",
    "assignmentId": "assignment-fa3c805b-5019-49a0-a7da-1912fd0df798",
    "attemptId": "attempt-d48c9aa6-e408-4e23-bdfb-892fcb86baee",
    "batchId": "bladebot-front-r4b-20261016",
    "manifestHash": "sha256:c587a7417c2fc7458a05922222d734a88107b1d7bdce86eb3fc1ba40d36010b4",
    "caseId": "arkclaw-30-red",
    "caseHash": "sha256:74d3cbc788332b78a8c67c3a2ecbf85e2c9632338916fcc358328fc5eb9b331c",
    "runId": "arkclaw-30-red-r001",
    "repeatIndex": 1,
    "status": "finished",
    "winner": "blue",
    "startedAt": "2026-10-15T17:11:23.8980290Z",
    "completedAt": "2026-10-15T17:11:54.2251596Z",
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
      "aiSourceSha256": "77ddd87310758b74afed0ec438d132ade2605515515d852f576e2382b11cb743",
      "candidateSide": "red",
      "comparison": "arkclaw",
      "dataPath": "data/enemy_properties/CF6重制敌人.xml",
      "dataSha256": "64841084b2eb4189113c0bfdaab533bcae67b53661fe310a6fbfee40dd33e753",
      "evidenceLane": "interactive_candidate",
      "mode": "pilot",
      "revision": "r4-early-guard-spacing",
      "rivalDataPath": "data/enemy_properties/诺亚新敌人.xml",
      "rivalDataSha256": "d339f0a4de759cce186fe98dbdf8f1f966cacf1fa5bd803714d9d41ea331321b",
      "sourceSwf": "flashswf/arts/new/Codex大刀机器人素材.swf",
      "sourceSwfSha256": "b64bc9da409de23065df04ed6417ecdb5f1f106cb48b28b5af9ed41e904bca9f",
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
        "remainHp": 35342,
        "hpPermille": 937,
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
    "frames": 889,
    "durationMs": 30278,
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
      "remainHp": 35342,
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
