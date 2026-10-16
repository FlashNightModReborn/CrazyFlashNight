# Unattended Arena Calibration Run

- status: needs_rerun
- batchId: `bladebot-front-r4-20261016`
- slot: `cf7_agent_bladebot_front_r4`
- seedSource: `saves/cf7_agent_bladebot_seed_r2.json`
- manifest: `tmp/arena-calibration/batches/bladebot-front-r4-20261016/case-manifest-736a80cc9e4b307b5218028f4073274339e57e0ec2fe483c0eb492a832276cdc.json`
- resultPath: `tmp/arena-calibration/unattended/20261015T165816Z-bladebot-front-r4-20261016-e9574212-5dcf-497c-8c5e-bdd0c23d2cc6/attempt-1-bladebot-front-r4-20261016-attempt-d66842e2-6e0c-4801-b63c-b97a72dcb457-results.jsonl`
- summaryPath: `tmp/arena-calibration/unattended/20261015T165816Z-bladebot-front-r4-20261016-e9574212-5dcf-497c-8c5e-bdd0c23d2cc6/summary.json`
- recoveryAttemptsUsed: 0/0
- startedAt: 2026-10-15T16:58:16.770Z
- completedAt: 2026-10-15T17:04:45.440Z

## Runtime Binary Identity

- verified: true
- runtimeMode: `isolated_candidate`
- processPath: `C:\Users\fs\.codex\worktrees\wings-combat\CrazyFlashNight\tmp\runtime-candidates\v2\wings-r1\runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe`
- coreSha256: `0B77B242CD101494C5B4944A13B8226D7B3FBBB93D078386D0F3E7A342980DE6`
- buildIdentity: `8EA4A84690A931791CAEB33952B7C7200AA5AA4A5141962085C5D049196C6212`
- payloadClosure: `20FE94FD57A50939F5DA7E00532D56B6A83250ED51714D8A976D148CD0ABA156`
- protectedSaveUnchanged: true
- protectedSaveBefore: `sha256:45dbb25e24a3cf6776d97b7c13be583d08b81fd40c27c2271223ea65ac19a952`
- protectedSaveAfter: `sha256:45dbb25e24a3cf6776d97b7c13be583d08b81fd40c27c2271223ea65ac19a952`

## Attempts

| # | status | batchId | rows | resultPath | rerun |
|---|---|---|---:|---|---|
| 1 | failed | `bladebot-front-r4-20261016` | 1/4 | `tmp/arena-calibration/unattended/20261015T165816Z-bladebot-front-r4-20261016-e9574212-5dcf-497c-8c5e-bdd0c23d2cc6/attempt-1-bladebot-front-r4-20261016-attempt-d66842e2-6e0c-4801-b63c-b97a72dcb457-results.jsonl` | `tmp/arena-calibration/batches/bladebot-front-r4-20261016-rerun-20261015T170445Z/case-manifest-175cfd993033da2c459816e533de7dd7da40b642e5b68ed157215e9871cb2fd3.json` |

## Failures

```json
[
  {
    "type": "needs_rerun",
    "attempt": 1,
    "batchId": "bladebot-front-r4-20261016",
    "rerunManifestPath": "tmp/arena-calibration/batches/bladebot-front-r4-20261016-rerun-20261015T170445Z/case-manifest-175cfd993033da2c459816e533de7dd7da40b642e5b68ed157215e9871cb2fd3.json"
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
  "sessionEpoch": "89a36f3248c34f8eb7ad34890628a276",
  "assignmentId": "assignment-9b81b38d-fad2-4519-82b1-da1ef2ed8840",
  "attemptId": "attempt-d66842e2-6e0c-4801-b63c-b97a72dcb457",
  "transportPoisoned": true,
  "state": "failed",
  "note": null,
  "batchId": "bladebot-front-r4-20261016",
  "manifestHash": "sha256:736a80cc9e4b307b5218028f4073274339e57e0ec2fe483c0eb492a832276cdc",
  "manifestPath": "tmp/arena-calibration/batches/bladebot-front-r4-20261016/case-manifest-736a80cc9e4b307b5218028f4073274339e57e0ec2fe483c0eb492a832276cdc.json",
  "frozenManifestPath": "tmp/arena-calibration/batches/bladebot-front-r4-20261016/attempts/attempt-d66842e2-6e0c-4801-b63c-b97a72dcb457/case_manifest.json",
  "resultPath": "tmp/arena-calibration/batches/bladebot-front-r4-20261016/attempts/attempt-d66842e2-6e0c-4801-b63c-b97a72dcb457/results.jsonl",
  "totalRuns": 4,
  "completedRuns": 1,
  "currentCaseId": null,
  "currentRunId": null,
  "lastError": "Host transport deadline elapsed before AS2 arena calibration response",
  "lastResult": {
    "schema": "arena-calibration.result.v1",
    "workerId": "guardian",
    "sessionEpoch": "89a36f3248c34f8eb7ad34890628a276",
    "assignmentId": "assignment-9b81b38d-fad2-4519-82b1-da1ef2ed8840",
    "attemptId": "attempt-d66842e2-6e0c-4801-b63c-b97a72dcb457",
    "batchId": "bladebot-front-r4-20261016",
    "manifestHash": "sha256:736a80cc9e4b307b5218028f4073274339e57e0ec2fe483c0eb492a832276cdc",
    "caseId": "blackiron-30-blue",
    "caseHash": "sha256:4190cf3bb23c039607ffe06a81e72c4e5c71dac5b784ec05b9b8becacd50cca3",
    "runId": "blackiron-30-blue-r001",
    "repeatIndex": 1,
    "status": "bridge_lost",
    "winner": "none",
    "startedAt": "2026-10-15T17:00:13.6240690Z",
    "completedAt": "2026-10-15T17:04:43.6298321Z",
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
      "aiSourceSha256": "77ddd87310758b74afed0ec438d132ade2605515515d852f576e2382b11cb743",
      "candidateSide": "blue",
      "comparison": "blackiron",
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

- Run rerun manifest: tmp/arena-calibration/batches/bladebot-front-r4-20261016-rerun-20261015T170445Z/case-manifest-175cfd993033da2c459816e533de7dd7da40b642e5b68ed157215e9871cb2fd3.json
- Inspect finalArenaStatus and result JSONL before planning the next exploratory batch.
