# Unattended Arena Calibration Run

- status: build_failed
- batchId: `bladebot-front-r2-20261016`
- slot: `cf7_agent_bladebot_front_r2`
- seedSource: ``
- manifest: `tmp/arena-calibration/batches/bladebot-front-r2-20261016/case-manifest-a5bb23af5ca6213f27b2a16838eb28c7099b56bd889270d4b1a5c5cd9e6e3aa9.json`
- resultPath: ``
- summaryPath: `tmp/arena-calibration/unattended/20261015T162446Z-bladebot-front-r2-20261016-9ba82a0e-d81f-4ad8-bc3e-27713a33169d/summary.json`
- recoveryAttemptsUsed: 0/0
- startedAt: 2026-10-15T16:24:46.054Z
- completedAt: 2026-10-15T16:25:22.886Z

## Runtime Binary Identity

- verified: false
- runtimeMode: `not observed`
- processPath: `not observed`
- coreSha256: `not observed`
- buildIdentity: `not observed`
- payloadClosure: `not observed`
- protectedSaveUnchanged: not checked
- protectedSaveBefore: `not observed`
- protectedSaveAfter: `not observed`

## Attempts

| # | status | batchId | rows | resultPath | rerun |
|---|---|---|---:|---|---|

## Failures

```json
[
  {
    "type": "build_gate",
    "gate": "arena-tools",
    "exitCode": 1,
    "signal": null,
    "message": "build gate failed: arena-tools"
  }
]
```

## Final Status

```json
{
  "message": "build gate failed: arena-tools",
  "gate": "arena-tools",
  "exitCode": 1,
  "signal": null
}
```

## Suggestions

- Fix the failing build gate before launching the unattended calibration batch.
- Rerun with the same manifest after checking launcher.log and the run report.
