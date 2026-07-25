# AS2 Protocol Latency Baseline

Date: 2026-04-16  
Environment: Flash CS6 `TestLoader` + `CRAZYFLASHER7MercenaryEmpire.exe --bus-only` (pre-net10；当前等价路径 `bash tools/cfn-cli.sh start-bus`，绕过 net10 bootstrap 的 runtime 检测 prompt 直跑 `runtime/Core.exe`)

## What was measured

This baseline focuses on the protocol families that AS2 actually uses today:

- local ports discovery via `launcher_ports.json`
- HTTP `LoadVars` paths: `/testConnection`, `/getSocketPort`, `/logBatch`
- XMLSocket fast-lane roundtrip lower bound
- actual `FrameBroadcaster.send()` path
- JSON callback task path
- JSON fire-and-forget path plus C# -> AS2 push ack
- representative business tasks: `archive`, `data_query`

The repeatable harness lives at:

- `scripts/protocol_latency_cycle.ps1`

It holds the repository compile mutex, creates a same-volume persistent recovery sidecar plus scratch marker, temporarily swaps in a benchmark `TestLoader.as`, and compiles through Flash CS6. A sample is accepted only from one exact runId START→END block, fresh compiler output/errors, Compiler Errors `0/0`, and `32K retry=0`; the original runner is then restored by installed/original SHA-256 before the mutex is released.

The current contract contains exactly 14 literal `enqueueMetric(name,count,...)` specifications. The PowerShell schema is derived from those AS2 queue definitions rather than a second hand-maintained metric table, but still asserts the contract count is 14. Every expected summary and raw sample set must occur with the derived count; non-finite/negative values, duplicate summaries, missing names, unexpected names, and summary min/avg/max values that disagree with raw samples all fail the cycle. If child compile succeeds but a unique END is not observed, `compile_state_uncertain.marker` blocks later compilation because the old test player may still append late evidence.

## 2026-07-25 runner-contract replay

This replay validates the current harness and evidence contract; it does not replace the latency samples below:

- cycle runId `38f167b2d06841c5b9ea75fa9b6dd37e`: all exact 14 summaries plus 14 raw-sample sets accepted, `failures=0`, Compiler Errors `0/0`, `32K retry=0`
- `protocol_latency_sweep.ps1 -Runs 1 -Json`: one complete 14-metric sample accepted, `failures=0`
- the self-started bus was bound to the exact Core PID and current ports-file PID, received graceful `/shutdown`, and exited without a hard kill
- the original `TestLoader.as` SHA-256 was restored; no scratch, recovery, uncertain marker, Core process, or owned ports file remained

## Latest baseline

Connection startup:

- `ports_file_ms`: `101`
- `socket_port_ms`: `101`
- `socket_connected_ms`: `2182`

Stable-path transport:

- `http_testConnection`: `avg 2.75ms`, `min 2ms`, `max 5ms`
- `http_getSocketPort`: `avg 2.88ms`, `min 2ms`, `max 4ms`
- `http_logBatch`: `avg 5ms`, `min 4ms`, `max 7ms`
- `xml_fastlane_B_to_K`: `avg 42ms`, `min 32ms`, `max 53ms`
- `frame_broadcaster_F_to_K`: `avg 41.38ms`, `min 31ms`, `max 49ms`
- `json_callback_sync`: `avg 6.88ms`, `min 0ms`, `max 46ms`
- `json_callback_async`: `avg 1.63ms`, `min 1ms`, `max 3ms`
- `json_fire_to_cmd_push`: `avg 41.5ms`, `min 32ms`, `max 49ms`

Business samples:

- `archive_list`: `avg 7ms`, `min 3ms`, `max 18ms`
- `archive_load_first_slot`: `51ms`
- `data_query_merc_bundle_cold`: `289ms`
- `data_query_merc_bundle_warm`: `avg 235.5ms`, `min 213ms`, `max 259ms`
- `data_query_npc_dialogue_cold`: `63ms`
- `data_query_npc_dialogue_warm`: `avg 2ms`, `min 1ms`, `max 3ms`

Reference note:

- first discovered archive slot during the run: `crazyflasher7_saves`

## Interpretation

The biggest startup cost is still XMLSocket connect/policy setup, not HTTP probing. Recent runs put the full `ServerManager` connect baseline around `2.1s` to `2.2s`.

Once connected, the live game transport is mostly frame-bound:

- raw fast-lane roundtrip sits around `32ms` to `53ms`
- actual `FrameBroadcaster.send()` roundtrip lands in almost the same band
- at 30 FPS, this is effectively a `~1 to 1.5 frame` closed loop

The JSON callback transport itself is cheap. The real latency spikes come from handler work and payload size:

- `archive` is not a bottleneck
- `npc_dialogue` is only expensive on first-load cache fill
- `merc_bundle` stays expensive even warm, which suggests payload construction/serialization dominates more than socket transport

## 30 FPS jitter sweep

To study variance, use:

- `scripts/protocol_latency_sweep.ps1`

The sweep accepts a sample only when the underlying cycle exits `0` and returns non-empty JSON with the complete connect/14-metric schema; null, non-finite, negative, missing, duplicate, or failed-cycle values are never converted into zero-valued latency samples.

Latest 5-run sweep at 30 FPS:

- connect `socket_connected_ms`: `p50 2155ms`, `p95 2202.4ms`, span `82ms`
- `http_testConnection`: `p50 3ms`, `p95 18ms`, max `23ms`
- `http_getSocketPort`: `p50 3.5ms`, `p95 10.55ms`, max `53ms`
- `http_logBatch`: `p50 5ms`, `p95 52.05ms`, max `83ms`
- `frame_broadcaster_F_to_K`: `p50 33ms`, `p95 97.55ms`, max `125ms`
- `json_fire_to_cmd_push`: `p50 33ms`, `p95 59.55ms`, max `81ms`
- `json_callback_sync`: `p50 2ms`, `p95 56.7ms`, max `127ms`
- `json_callback_async`: `p50 2ms`, `p95 5ms`, max `33ms`
- `archive_list`: `p50 4ms`, `p95 51.65ms`, max `83ms`
- `archive_load_first_slot`: `p50 40ms`, `p95 142.2ms`, max `150ms`
- `data_query_merc_bundle_warm`: `p50 282.5ms`, `p95 489.65ms`, max `521ms`
- `data_query_npc_dialogue_warm`: `p50 1.5ms`, `p95 3ms`, max `3ms`

Takeaway:

- HTTP paths are still low-latency and are not materially tied to frame rate
- frame-bound paths center on `~33ms` at 30 FPS, so the median is still about `1 frame`
- tails can slip into `2-3 frames`
- one sweep caught an extreme `xml_fastlane_B_to_K` outlier (`1389ms`), so we should treat raw fast-lane tails as "usually 1 frame, occasionally multi-frame, with rare pathological stalls still possible"

That outlier needs separate targeted investigation before we treat it as a transport guarantee breach instead of a bench artifact or transient scheduling stall.

## Tail localization update

The bench harness now uses immediate event-time accounting for:

- `K` receipt on the Flash side
- `cmd` push receipt on the Flash side
- launcher-side microsecond trace points for `raw_b_k`, `frame_ui_k`, `json_sync`, `json_async`, `json_push_cmd`

With that instrumentation, the previous "1 frame baseline" no longer holds for the raw transport itself. What changed:

- `xml_fastlane_B_to_K` now centers at `~1ms` with `p50 1ms`
- `frame_broadcaster_F_to_K` now centers at `~2ms` with `p50 2ms`
- `json_fire_to_cmd_push` now centers at `~2ms` with `p50 2ms`

Launcher-side bench trace confirms the C# processing segment is not the bottleneck:

- `raw_b_k`: `avg 0.94us`, `max 15us`
- `frame_ui_k`: `avg 1.25us`, `max 16us`
- `json_sync`: `avg 0.08us`, `max 1us`
- `json_async`: `avg 0.06us`, `max 1us`
- `json_push_cmd`: `avg 3.33us`, `max 24us`

Current interpretation:

- prior frame-sized values were mostly caused by Flash-side callback timing and frame-polled measurement
- the launcher transport/dispatch segment is effectively negligible compared with AVM1-side event scheduling
- remaining tail latency is dominated by Flash/AVM1 callback delivery, `LoadVars` timing, and business handler work

Practical result:

- for architecture work, do not budget `~1 frame` to the launcher itself
- budget launcher transport as low-millisecond
- budget `LoadVars`/legacy callback paths and heavy data handlers separately, because that is where the meaningful jitter still lives

## Coverage notes

Covered well:

- startup discovery
- stable HTTP
- stable XMLSocket fast-lane
- `FrameBroadcaster`
- JSON callback
- JSON fire-and-forget plus `cmd` push
- `archive`
- `data_query`

Not yet directly bench-acked:

- full launcher-mode `bootstrap_handshake/bootstrap_ready`
- `shop_response` bridge under real shop UI state
- `save_push`, `catalog`, `catalogUpdate`
- one-way per-prefix breakdown for `S/N/W/U/D/R`

For now, treat these as follows:

- `S/N/W/U/D/R` are close to the raw fast-lane band unless their handler adds meaningful work
- `K/P` return-side behavior is close to the measured fast-lane roundtrip
- full business features should be measured again in their real scene if we suspect handler logic dominates transport

## Re-run

```powershell
chcp.com 65001 | Out-Null
powershell -ExecutionPolicy Bypass -File scripts/protocol_latency_cycle.ps1 -StopBusAfter -Json
```

If launcher-side benchmark hooks change, rebuild first:

```powershell
chcp.com 65001 | Out-Null
powershell -ExecutionPolicy Bypass -File launcher/build.ps1
```

To run the jitter sweep:

```powershell
chcp.com 65001 | Out-Null
powershell -ExecutionPolicy Bypass -File scripts/protocol_latency_sweep.ps1 -Runs 5 -Json
```

The sweep fails closed if any cycle exits nonzero or returns empty / invalid JSON; partial failure data is not included in percentile statistics.
