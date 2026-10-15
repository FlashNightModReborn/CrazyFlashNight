# Unattended Arena Calibration Run

- status: needs_rerun
- batchId: `bladebot-front-r2-20261016`
- slot: `cf7_agent_bladebot_front_r2`
- seedSource: `saves/cf7_agent_bladebot_seed_r2.json`
- manifest: `tmp/arena-calibration/batches/bladebot-front-r2-20261016/case-manifest-a5bb23af5ca6213f27b2a16838eb28c7099b56bd889270d4b1a5c5cd9e6e3aa9.json`
- resultPath: `tmp/arena-calibration/unattended/20261015T162849Z-bladebot-front-r2-20261016-94115afa-abaa-4062-932c-40f551644c49/attempt-1-bladebot-front-r2-20261016-attempt-abf94b8b-2709-4bb4-8964-dfc57277e5db-results.jsonl`
- summaryPath: `tmp/arena-calibration/unattended/20261015T162849Z-bladebot-front-r2-20261016-94115afa-abaa-4062-932c-40f551644c49/summary.json`
- recoveryAttemptsUsed: 0/0
- startedAt: 2026-10-15T16:28:49.449Z
- completedAt: 2026-10-15T16:35:01.367Z

## Runtime Binary Identity

- verified: true
- runtimeMode: `isolated_candidate`
- processPath: `C:\Users\fs\.codex\worktrees\wings-combat\CrazyFlashNight\tmp\runtime-candidates\v2\wings-r1\runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe`
- coreSha256: `0B77B242CD101494C5B4944A13B8226D7B3FBBB93D078386D0F3E7A342980DE6`
- buildIdentity: `8EA4A84690A931791CAEB33952B7C7200AA5AA4A5141962085C5D049196C6212`
- payloadClosure: `20FE94FD57A50939F5DA7E00532D56B6A83250ED51714D8A976D148CD0ABA156`
- protectedSaveUnchanged: true
- protectedSaveBefore: `sha256:cd2a911b1f36c4fa3f2f3ff8cf2e53477f599ec0d14b4a1274c92c0a8693d962`
- protectedSaveAfter: `sha256:cd2a911b1f36c4fa3f2f3ff8cf2e53477f599ec0d14b4a1274c92c0a8693d962`

## Attempts

| # | status | batchId | rows | resultPath | rerun |
|---|---|---|---:|---|---|
| 1 | failed | `bladebot-front-r2-20261016` | 1/4 | `tmp/arena-calibration/unattended/20261015T162849Z-bladebot-front-r2-20261016-94115afa-abaa-4062-932c-40f551644c49/attempt-1-bladebot-front-r2-20261016-attempt-abf94b8b-2709-4bb4-8964-dfc57277e5db-results.jsonl` | `tmp/arena-calibration/batches/bladebot-front-r2-20261016-rerun-20261015T163501Z/case-manifest-31a0500a7fd9cd42615a2a11305aa9911a2f00ca66c5a6e5ed46422b274c0daf.json` |

## Failures

```json
[
  {
    "type": "needs_rerun",
    "attempt": 1,
    "batchId": "bladebot-front-r2-20261016",
    "rerunManifestPath": "tmp/arena-calibration/batches/bladebot-front-r2-20261016-rerun-20261015T163501Z/case-manifest-31a0500a7fd9cd42615a2a11305aa9911a2f00ca66c5a6e5ed46422b274c0daf.json"
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
  "sessionEpoch": "ca3544a5f0d74bdea36dac48d6b11629",
  "assignmentId": "assignment-a635d3a4-3d00-4acb-b3c2-180d7e85b39b",
  "attemptId": "attempt-abf94b8b-2709-4bb4-8964-dfc57277e5db",
  "transportPoisoned": true,
  "state": "failed",
  "note": null,
  "batchId": "bladebot-front-r2-20261016",
  "manifestHash": "sha256:a5bb23af5ca6213f27b2a16838eb28c7099b56bd889270d4b1a5c5cd9e6e3aa9",
  "manifestPath": "tmp/arena-calibration/batches/bladebot-front-r2-20261016/case-manifest-a5bb23af5ca6213f27b2a16838eb28c7099b56bd889270d4b1a5c5cd9e6e3aa9.json",
  "frozenManifestPath": "tmp/arena-calibration/batches/bladebot-front-r2-20261016/attempts/attempt-abf94b8b-2709-4bb4-8964-dfc57277e5db/case_manifest.json",
  "resultPath": "tmp/arena-calibration/batches/bladebot-front-r2-20261016/attempts/attempt-abf94b8b-2709-4bb4-8964-dfc57277e5db/results.jsonl",
  "totalRuns": 4,
  "completedRuns": 1,
  "currentCaseId": null,
  "currentRunId": null,
  "lastError": "Host transport deadline elapsed before AS2 arena calibration response",
  "lastResult": {
    "schema": "arena-calibration.result.v1",
    "workerId": "guardian",
    "sessionEpoch": "ca3544a5f0d74bdea36dac48d6b11629",
    "assignmentId": "assignment-a635d3a4-3d00-4acb-b3c2-180d7e85b39b",
    "attemptId": "attempt-abf94b8b-2709-4bb4-8964-dfc57277e5db",
    "batchId": "bladebot-front-r2-20261016",
    "manifestHash": "sha256:a5bb23af5ca6213f27b2a16838eb28c7099b56bd889270d4b1a5c5cd9e6e3aa9",
    "caseId": "blackiron-30-blue",
    "caseHash": "sha256:9f34bb070f27704e24dfd9254049669935b2462b49de505486496a8ab54965d3",
    "runId": "blackiron-30-blue-r001",
    "repeatIndex": 1,
    "status": "bridge_lost",
    "winner": "none",
    "startedAt": "2026-10-15T16:30:30.3220376Z",
    "completedAt": "2026-10-15T16:35:00.3242958Z",
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
      "aiSourceSha256": "d5b3565772b3d0bd0cfb2c23f7e8f32d668eebce9c00b8f45059b9c97631978b",
      "candidateSide": "blue",
      "comparison": "blackiron",
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

- Run rerun manifest: tmp/arena-calibration/batches/bladebot-front-r2-20261016-rerun-20261015T163501Z/case-manifest-31a0500a7fd9cd42615a2a11305aa9911a2f00ca66c5a6e5ed46422b274c0daf.json
- Inspect finalArenaStatus and result JSONL before planning the next exploratory batch.
