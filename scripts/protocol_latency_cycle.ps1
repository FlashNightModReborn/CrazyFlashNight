param(
    [int]$WaitTimeoutSec = 180,
    [switch]$Json,
    [switch]$NoBus,
    [switch]$StopBusAfter
)

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$ScriptDir = Split-Path -Parent $PSCommandPath
$ProjectRoot = Split-Path -Parent $ScriptDir
$CompileScript = Join-Path $ScriptDir 'compile_test.ps1'
$TestLoaderAs = Join-Path $ScriptDir 'TestLoader.as'
$FlashLog = Join-Path $env:APPDATA 'Macromedia\Flash Player\Logs\flashlog.txt'
$LocalFlashLog = Join-Path $ScriptDir 'protocol_latency_flashlog.txt'
$LauncherExe = Join-Path $ProjectRoot 'CRAZYFLASHER7MercenaryEmpire.exe'
$PortsFile = Join-Path $ProjectRoot 'launcher_ports.json'

$BusPorts = @(1192, 1924, 9243, 2433, 4339, 3399, 3993, 11924, 19243, 24339, 43399, 33993, 3000)

function Get-BusHttpPort {
    if (Test-Path $PortsFile) {
        try {
            $json = Get-Content -Raw -Encoding UTF8 $PortsFile | ConvertFrom-Json
            if ($json.httpPort) {
                return [int]$json.httpPort
            }
        } catch {}
    }

    foreach ($p in $BusPorts) {
        try {
            $r = Invoke-WebRequest -Uri "http://localhost:$p/testConnection" `
                -Method POST -Body '' -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
            if ($r.StatusCode -eq 200) {
                return [int]$p
            }
        } catch {}
    }
    return $null
}

function Test-BusRunning {
    return ($null -ne (Get-BusHttpPort))
}

function Stop-BusIfReachable {
    $httpPort = Get-BusHttpPort
    if ($null -eq $httpPort) { return }
    try {
        Invoke-WebRequest -Uri "http://localhost:$httpPort/shutdown" `
            -Method POST -Body '' -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop | Out-Null
    } catch {}
}

function Get-LatestBenchLines {
    param([string]$RawText)

    $startMarker = '=== PROTOCOL LATENCY BENCH ==='
    $endMarker = '[bench] done'
    $idx = $RawText.LastIndexOf($startMarker)
    if ($idx -lt 0) {
        return @()
    }

    $slice = $RawText.Substring($idx)
    $lines = $slice -split "`r?`n"
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        $result.Add($line)
        if ($line -eq $endMarker) {
            break
        }
    }
    return $result.ToArray()
}

function Parse-BenchSummary {
    param([string[]]$Lines)

    $result = [ordered]@{
        connect = [ordered]@{
            ports_file_ms = $null
            socket_port_ms = $null
            socket_connected_ms = $null
        }
        metrics = [ordered]@{}
        raw_samples = [ordered]@{}
        notes = [ordered]@{}
        failures = @()
    }

    foreach ($line in $Lines) {
        if ($line -match '^\[bench\] connect ports_file_ms=([0-9\-]+) socket_port_ms=([0-9\-]+) socket_connected_ms=([0-9\-]+)$') {
            $result.connect.ports_file_ms = [int]$matches[1]
            $result.connect.socket_port_ms = [int]$matches[2]
            $result.connect.socket_connected_ms = [int]$matches[3]
            continue
        }
        if ($line -match '^\[bench\] metric name=([^ ]+) count=(\d+) min=([0-9.\-]+) avg=([0-9.\-]+) max=([0-9.\-]+)$') {
            $name = $matches[1]
            $result.metrics[$name] = [ordered]@{
                count = [int]$matches[2]
                min_ms = [double]$matches[3]
                avg_ms = [double]$matches[4]
                max_ms = [double]$matches[5]
            }
            continue
        }
        if ($line -match '^\[bench\] sample name=([^ ]+) ms=([0-9.\-]+)(?: token=([^ ]+))?$') {
            $name = $matches[1]
            if (-not $result.raw_samples.Contains($name)) {
                $result.raw_samples[$name] = New-Object System.Collections.ArrayList
            }
            [void]$result.raw_samples[$name].Add([double]$matches[2])
            continue
        }
        if ($line -match '^\[bench\] note ([^=]+)=(.+)$') {
            $result.notes[$matches[1]] = $matches[2]
            continue
        }
        if ($line -match '^\[bench\] fail ') {
            $result.failures += $line
        }
    }

    return $result
}

$benchAs2 = @'
import org.flashNight.neur.Server.*;
import org.flashNight.arki.render.*;

trace("=== PROTOCOL LATENCY BENCH ===");

if (_root.gameCommands == undefined) {
    _root.gameCommands = {};
}

var bench:Object = {};
bench.startedAt = getTimer();
bench.samples = {};
bench.failures = [];
bench.queue = [];
bench.pending = null;
bench.pendingSeq = 0;
bench.activeMetric = null;
bench.activeIndex = 0;
bench.httpPortReadyMs = null;
bench.socketPortReadyMs = null;
bench.socketConnectedMs = null;
bench.archiveFirstSlot = null;
bench.kEvents = {};
bench.cmdEvents = {};

_root.__protocolBench = bench;

_root.gameCommands["benchAck"] = function(params:Object):Void {
    var b:Object = _root.__protocolBench;
    if (params != undefined && params.token != undefined) {
        var token:String = String(params.token);
        b.cmdEvents[token] = getTimer();
        resolvePendingByToken(token, b.cmdEvents[token]);
    }
};

if (_root.gameworld == undefined) {
    var gw:MovieClip = _root.createEmptyMovieClip("gameworld", 1);
    gw._x = 0;
    gw._y = 0;
    gw._xscale = 100;
}

var sm:ServerManager = ServerManager.getInstance();
_root.server = sm;

bench.originalReceiveK = FrameBroadcaster.receiveK;
FrameBroadcaster.receiveK = function(payload:String):Void {
    var b:Object = _root.__protocolBench;
    var now:Number = getTimer();
    var token:String = "";
    var sep2:Number = payload != null ? payload.indexOf("\x02") : -1;
    if (sep2 >= 0 && sep2 < payload.length - 1) {
        token = payload.substring(sep2 + 1);
    }
    if (token.length > 0) {
        b.kEvents[token] = now;
        resolvePendingByToken(token, now);
    }
    b.originalReceiveK(payload);
};

function benchNow():Number {
    return getTimer();
}

function round2(v:Number):Number {
    return Math.round(v * 100) / 100;
}

function addSample(name:String, ms:Number, token:String):Void {
    if (bench.samples[name] == undefined) {
        bench.samples[name] = [];
    }
    bench.samples[name].push(ms);
    var line:String = "[bench] sample name=" + name + " ms=" + round2(ms);
    if (token != undefined && token != null && token.length > 0) {
        line += " token=" + token;
    }
    trace(line);
}

function addFailure(name:String, reason:String):Void {
    var msg:String = "[bench] fail name=" + name + " reason=" + reason;
    bench.failures.push(msg);
    trace(msg);
}

function metricSummary(name:String):Object {
    var arr:Array = bench.samples[name];
    if (arr == undefined || arr.length == 0) {
        return {count: 0, min: -1, avg: -1, max: -1};
    }
    var minV:Number = Number(arr[0]);
    var maxV:Number = Number(arr[0]);
    var sum:Number = 0;
    for (var i:Number = 0; i < arr.length; i++) {
        var n:Number = Number(arr[i]);
        if (n < minV) minV = n;
        if (n > maxV) maxV = n;
        sum += n;
    }
    return {
        count: arr.length,
        min: minV,
        avg: round2(sum / arr.length),
        max: maxV
    };
}

function logSummary(name:String):Void {
    var s:Object = metricSummary(name);
    trace("[bench] metric name=" + name
        + " count=" + s.count
        + " min=" + s.min
        + " avg=" + s.avg
        + " max=" + s.max);
}

function armPending(timeoutMs:Number, startedAt:Number, expectedToken:String,
                    successFn:Function, failFn:Function):Number {
    bench.pendingSeq++;
    bench.pending = {
        id: bench.pendingSeq,
        startedAt: startedAt,
        token: expectedToken,
        ok: successFn,
        fail: failFn,
        deadline: benchNow() + timeoutMs
    };
    return bench.pendingSeq;
}

function resolvePendingValue(id:Number, value:Number, token:String):Void {
    var pending:Object = bench.pending;
    if (pending == null || pending.id != id) return;
    bench.pending = null;
    pending.ok(value, token);
}

function resolvePendingByToken(token:String, nowMs:Number):Void {
    var pending:Object = bench.pending;
    if (pending == null) return;
    if (pending.token == null || pending.token != token) return;
    bench.pending = null;
    pending.ok(nowMs - pending.startedAt, token);
}

function rejectPending(id:Number, reason:String):Void {
    var pending:Object = bench.pending;
    if (pending == null || pending.id != id) return;
    bench.pending = null;
    pending.fail(reason);
}

function enqueueMetric(name:String, count:Number, launchFn:Function):Void {
    bench.queue.push({name: name, count: count, launch: launchFn});
}

function beginNextMetric():Void {
    if (bench.queue.length == 0) {
        finishBench();
        return;
    }
    bench.activeMetric = bench.queue.shift();
    bench.activeIndex = 0;
    if (bench.samples[bench.activeMetric.name] == undefined) {
        bench.samples[bench.activeMetric.name] = [];
    }
    launchCurrentIteration();
}

function finishCurrentMetricSample(ms:Number, token:String):Void {
    addSample(bench.activeMetric.name, ms, token);
    bench.activeIndex++;
    if (bench.activeIndex >= bench.activeMetric.count) {
        logSummary(bench.activeMetric.name);
        bench.activeMetric = null;
        beginNextMetric();
        return;
    }
    launchCurrentIteration();
}

function failCurrentMetricSample(reason:String):Void {
    addFailure(bench.activeMetric.name, reason);
    bench.activeIndex++;
    if (bench.activeIndex >= bench.activeMetric.count) {
        logSummary(bench.activeMetric.name);
        bench.activeMetric = null;
        beginNextMetric();
        return;
    }
    launchCurrentIteration();
}

function launchCurrentIteration():Void {
    var metric:Object = bench.activeMetric;
    metric.launch(bench.activeIndex, finishCurrentMetricSample, failCurrentMetricSample);
}

function finishBench():Void {
    trace("[bench] connect ports_file_ms=" + bench.httpPortReadyMs
        + " socket_port_ms=" + bench.socketPortReadyMs
        + " socket_connected_ms=" + bench.socketConnectedMs);
    if (bench.archiveFirstSlot != null) {
        trace("[bench] note archive_first_slot=" + bench.archiveFirstSlot);
    }
    trace("[bench] done");
    delete bench.clip.onEnterFrame;
}

function httpRequest(url:String, method:String, fields:Object, onDone:Function, onFail:Function):Void {
    var started:Number = benchNow();
    var sender:LoadVars = new LoadVars();
    var receiver:LoadVars = new LoadVars();
    var pendingId:Number = armPending(4000, started, null,
        function(ms:Number, token:String):Void {
            onDone(ms, token);
        },
        function(reason:String):Void {
            onFail(reason);
        });

    receiver.onLoad = function(success:Boolean):Void {
        if (success) {
            resolvePendingValue(pendingId, benchNow() - started, null);
        } else {
            rejectPending(pendingId, "http_failed");
        }
    };

    if (method == "GET") {
        receiver.load(url);
    } else {
        if (fields != null) {
            for (var k:String in fields) {
                sender[k] = fields[k];
            }
        }
        sender.sendAndLoad(url, receiver, "POST");
    }
}

function taskWithCallback(taskName:String, payload:Object, onDone:Function, onFail:Function):Void {
    var started:Number = benchNow();
    var pendingId:Number = armPending(6000, started, null,
        function(ms:Number, token:String):Void {
            onDone(ms, payload != undefined ? payload.__benchResp : undefined, token);
        },
        function(reason:String):Void {
            onFail(reason);
        });

    sm.sendTaskWithCallback(taskName, payload, null, function(resp:Object):Void {
        payload.__benchResp = resp;
        if (resp != undefined && resp.success == true) {
            resolvePendingValue(pendingId, benchNow() - started, null);
        } else if (resp != undefined && resp.error != undefined) {
            rejectPending(pendingId, String(resp.error));
        } else {
            rejectPending(pendingId, "task_failed");
        }
    });
}

function buildToken(prefix:String, index:Number):String {
    return prefix + "_" + index + "_" + benchNow();
}

function measureFastLaneEcho(index:Number, onDone:Function, onFail:Function):Void {
    var token:String = buildToken("fastlane", index);
    var started:Number = benchNow();
    delete bench.kEvents[token];
    armPending(4000, started, token,
        function(ms:Number, doneToken:String):Void {
            onDone(ms, doneToken);
        },
        function(reason:String):Void {
            onFail(reason);
        });

    sm.sendSocketMessage("B" + token);
}

function measureFrameBroadcasterEcho(index:Number, onDone:Function, onFail:Function):Void {
    var token:String = buildToken("frame", index);
    var started:Number = benchNow();
    delete bench.kEvents[token];
    armPending(4000, started, token,
        function(ms:Number, doneToken:String):Void {
            onDone(ms, doneToken);
        },
        function(reason:String):Void {
            onFail(reason);
        });

    FrameBroadcaster.pushUiState("bench:" + token);
    FrameBroadcaster.send();
}

function measureBenchPushCmd(index:Number, onDone:Function, onFail:Function):Void {
    var token:String = buildToken("cmdpush", index);
    var started:Number = benchNow();
    delete bench.cmdEvents[token];
    armPending(4000, started, token,
        function(ms:Number, doneToken:String):Void {
            onDone(ms, doneToken);
        },
        function(reason:String):Void {
            onFail(reason);
        });

    sm.sendTaskToNode("bench_push", {mode: "cmd", token: token}, null);
}

function setupMetricQueue():Void {
    enqueueMetric("http_testConnection", 8, function(index:Number, onDone:Function, onFail:Function):Void {
        httpRequest("http://localhost:" + sm.currentPort + "/testConnection", "POST", {probe: "1"}, function(ms:Number):Void {
            onDone(ms);
        }, onFail);
    });

    enqueueMetric("http_getSocketPort", 8, function(index:Number, onDone:Function, onFail:Function):Void {
        httpRequest("http://localhost:" + sm.currentPort + "/getSocketPort", "GET", null, function(ms:Number):Void {
            onDone(ms);
        }, onFail);
    });

    enqueueMetric("http_logBatch", 8, function(index:Number, onDone:Function, onFail:Function):Void {
        httpRequest("http://localhost:" + sm.currentPort + "/logBatch", "POST",
            {frame: String(index), messages: "bench_http_" + index}, function(ms:Number):Void {
                onDone(ms);
            }, onFail);
    });

    enqueueMetric("xml_fastlane_B_to_K", 8, measureFastLaneEcho);
    enqueueMetric("frame_broadcaster_F_to_K", 8, measureFrameBroadcasterEcho);
    enqueueMetric("json_callback_sync", 8, function(index:Number, onDone:Function, onFail:Function):Void {
        var token:String = buildToken("jsync", index);
        taskWithCallback("bench_sync", {seq: index, token: token}, function(ms:Number):Void {
            onDone(ms, token);
        }, onFail);
    });

    enqueueMetric("json_callback_async", 8, function(index:Number, onDone:Function, onFail:Function):Void {
        var token:String = buildToken("jasync", index);
        taskWithCallback("bench_async", {seq: index, token: token}, function(ms:Number):Void {
            onDone(ms, token);
        }, onFail);
    });

    enqueueMetric("json_fire_to_cmd_push", 8, measureBenchPushCmd);

    enqueueMetric("archive_list", 4, function(index:Number, onDone:Function, onFail:Function):Void {
        taskWithCallback("archive", {op: "list"}, function(ms:Number, resp:Object):Void {
            if (bench.archiveFirstSlot == null && resp.slots != undefined && resp.slots.length > 0) {
                bench.archiveFirstSlot = String(resp.slots[0].slot);
            }
            onDone(ms);
        }, onFail);
    });

    enqueueMetric("archive_load_first_slot", 1, function(index:Number, onDone:Function, onFail:Function):Void {
        if (bench.archiveFirstSlot == null) {
            onFail("no_slot");
            return;
        }
        taskWithCallback("archive", {op: "load", slot: bench.archiveFirstSlot}, function(ms:Number):Void {
            onDone(ms);
        }, onFail);
    });

    enqueueMetric("data_query_merc_bundle_cold", 1, function(index:Number, onDone:Function, onFail:Function):Void {
        var started:Number = benchNow();
        org.flashNight.neur.Server.DataQueryService.query("merc_bundle", null, function(resp:Object):Void {
            if (resp != undefined && resp.success == true) {
                onDone(benchNow() - started);
            } else {
                onFail(resp != undefined ? String(resp.error) : "merc_bundle_failed");
            }
        });
    });

    enqueueMetric("data_query_merc_bundle_warm", 4, function(index:Number, onDone:Function, onFail:Function):Void {
        var started:Number = benchNow();
        org.flashNight.neur.Server.DataQueryService.query("merc_bundle", null, function(resp:Object):Void {
            if (resp != undefined && resp.success == true) {
                onDone(benchNow() - started);
            } else {
                onFail(resp != undefined ? String(resp.error) : "merc_bundle_failed");
            }
        });
    });

    enqueueMetric("data_query_npc_dialogue_cold", 1, function(index:Number, onDone:Function, onFail:Function):Void {
        var started:Number = benchNow();
        org.flashNight.neur.Server.DataQueryService.query("npc_dialogue", {key: "bench_missing", taskProgress: 0}, function(resp:Object):Void {
            if (resp != undefined && resp.success == true) {
                onDone(benchNow() - started);
            } else {
                onFail(resp != undefined ? String(resp.error) : "npc_dialogue_failed");
            }
        });
    });

    enqueueMetric("data_query_npc_dialogue_warm", 4, function(index:Number, onDone:Function, onFail:Function):Void {
        var started:Number = benchNow();
        org.flashNight.neur.Server.DataQueryService.query("npc_dialogue", {key: "bench_missing", taskProgress: 0}, function(resp:Object):Void {
            if (resp != undefined && resp.success == true) {
                onDone(benchNow() - started);
            } else {
                onFail(resp != undefined ? String(resp.error) : "npc_dialogue_failed");
            }
        });
    });
}

bench.clip = _root.createEmptyMovieClip("__protocolLatencyBench", 1048574);
bench.clip.onEnterFrame = function():Void {
    if (bench.httpPortReadyMs == null && sm.currentPort != null) {
        bench.httpPortReadyMs = benchNow() - bench.startedAt;
    }
    if (bench.socketPortReadyMs == null && sm.socketPort != null) {
        bench.socketPortReadyMs = benchNow() - bench.startedAt;
    }
    if (bench.socketConnectedMs == null && sm.isSocketConnected) {
        bench.socketConnectedMs = benchNow() - bench.startedAt;
        setupMetricQueue();
        beginNextMetric();
        return;
    }

    if (bench.pending != null) {
        var pending:Object = bench.pending;
        if (benchNow() >= pending.deadline) {
            rejectPending(pending.id, "timeout");
            return;
        }
    }
};
'@

$busStartedByUs = $false
$busProc = $null
$TestLoaderBackup = $null
$compileOutput = ''
$compileExit = $null
$summary = $null

try {
    if (-not $NoBus) {
        if (Test-BusRunning) {
            Write-Host '[bus] Already running'
        } else {
            if (-not (Test-Path $LauncherExe)) {
                Write-Host "[bus] ERROR: Launcher not found: $LauncherExe" -ForegroundColor Red
                exit 1
            }
            Write-Host '[bus] Starting launcher --bus-only...'
            $busProc = Start-Process -FilePath $LauncherExe -ArgumentList '--bus-only' -PassThru -WindowStyle Minimized
            $busStartedByUs = $true

            $busDeadline = (Get-Date).AddSeconds(15)
            while ((Get-Date) -lt $busDeadline) {
                Start-Sleep -Milliseconds 500
                if (Test-BusRunning) { break }
            }
            if (-not (Test-BusRunning)) {
                Write-Host '[bus] ERROR: Bus failed to start within 15s' -ForegroundColor Red
                exit 1
            }
            Write-Host '[bus] Ready'
        }
    }

    if (Test-Path $TestLoaderAs) {
        $TestLoaderBackup = [System.IO.File]::ReadAllBytes($TestLoaderAs)
    }

    $beforeTime = if (Test-Path $FlashLog) { (Get-Item $FlashLog).LastWriteTimeUtc } else { [datetime]::MinValue }
    $beforeLength = if (Test-Path $FlashLog) { (Get-Item $FlashLog).Length } else { 0 }

    $bom = [byte[]]@(0xEF, 0xBB, 0xBF)
    $codeBytes = [System.Text.Encoding]::UTF8.GetBytes($benchAs2)
    $allBytes = New-Object byte[] ($bom.Length + $codeBytes.Length)
    [Array]::Copy($bom, 0, $allBytes, 0, $bom.Length)
    [Array]::Copy($codeBytes, 0, $allBytes, $bom.Length, $codeBytes.Length)
    [System.IO.File]::WriteAllBytes($TestLoaderAs, $allBytes)

    $compileOutput = (& $CompileScript *>&1 | Out-String)
    $compileExit = $LASTEXITCODE

    $deadline = (Get-Date).AddSeconds($WaitTimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $FlashLog) {
            $item = Get-Item $FlashLog
            if ($item.LastWriteTimeUtc -gt $beforeTime -or $item.Length -gt $beforeLength) {
                $raw = Get-Content -Raw -Encoding UTF8 $FlashLog
                $lines = Get-LatestBenchLines -RawText $raw
                if ($lines.Length -gt 0 -and ($lines -contains '[bench] done')) {
                    Copy-Item $FlashLog $LocalFlashLog -Force
                    $summary = Parse-BenchSummary -Lines $lines
                    break
                }
            }
        }
        Start-Sleep -Milliseconds 500
    }
}
finally {
    if ($null -ne $TestLoaderBackup) {
        [System.IO.File]::WriteAllBytes($TestLoaderAs, $TestLoaderBackup)
    }

    if ($busStartedByUs -and $StopBusAfter) {
        Stop-BusIfReachable
        Start-Sleep -Milliseconds 500
        if ($busProc -and -not $busProc.HasExited) {
            try { $busProc.Kill() } catch {}
        }
    }
}

if ($summary -eq $null) {
    Write-Host '[ERROR] Fresh protocol latency summary not found.'
    if ($compileOutput) {
        Write-Host '=== compile_test output ==='
        Write-Host $compileOutput.TrimEnd()
        Write-Host '=== end compile_test output ==='
    }
    exit 1
}

$result = [ordered]@{
    compile_exit = $compileExit
    connect = $summary.connect
    metrics = $summary.metrics
    raw_samples = $summary.raw_samples
    notes = $summary.notes
    failures = $summary.failures
}

if ($Json) {
    $result | ConvertTo-Json -Depth 8
    exit 0
}

Write-Host ('[protocol-latency] compile_exit={0}' -f $compileExit)
Write-Host ('connect ports_file={0}ms socket_port={1}ms socket_connected={2}ms' -f `
    $summary.connect.ports_file_ms, $summary.connect.socket_port_ms, $summary.connect.socket_connected_ms)
foreach ($entry in $summary.metrics.GetEnumerator()) {
    $value = $entry.Value
    Write-Host ('{0}: count={1} min={2} avg={3} max={4}' -f `
        $entry.Key, $value.count, $value.min_ms, $value.avg_ms, $value.max_ms)
}
if ($summary.notes.Count -gt 0) {
    foreach ($entry in $summary.notes.GetEnumerator()) {
        Write-Host ('note {0}={1}' -f $entry.Key, $entry.Value)
    }
}
if ($summary.failures.Count -gt 0) {
    Write-Host 'failures:'
    foreach ($line in $summary.failures) {
        Write-Host ('  ' + $line)
    }
}
