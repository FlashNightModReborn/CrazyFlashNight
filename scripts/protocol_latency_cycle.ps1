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
$CompileOutputPath = Join-Path $ScriptDir 'compile_output.txt'
$CompilerErrorsPath = Join-Path $ScriptDir 'compiler_errors.txt'
$UncertainMarker = Join-Path $ScriptDir 'compile_state_uncertain.marker'
$ScratchMarker = Join-Path $ScriptDir 'testloader_scratch_inflight.marker'
. (Join-Path $ScriptDir 'test-runners\testloader-scratch-transaction.ps1')
$BootstrapExe = Join-Path $ProjectRoot 'CRAZYFLASHER7MercenaryEmpire.exe'
$LauncherExe = Join-Path $ProjectRoot 'runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe'
$PortsFile = Join-Path $ProjectRoot 'launcher_ports.json'
. (Join-Path $ProjectRoot 'tools\dotnet-runtime-detect.ps1')

$BusPorts = @(1192, 1924, 9243, 2433, 4339, 3399, 3993, 11924, 19243, 24339, 43399, 33993, 3000)

function Write-ProtocolUncertain {
    param([Parameter(Mandatory = $true)][string]$Reason)

    $prior = if (Test-Path -LiteralPath $UncertainMarker) {
        [System.IO.File]::ReadAllText(
            $UncertainMarker, [System.Text.Encoding]::UTF8)
    } else {
        ''
    }
    $body = '{0:o} | protocol latency cycle: {1}' -f
        [System.DateTime]::UtcNow, $Reason
    if (-not [string]::IsNullOrWhiteSpace($prior)) {
        $body += "`nprevious_marker:`n" + $prior
    }
    [System.IO.File]::WriteAllText(
        $UncertainMarker, $body, [System.Text.UTF8Encoding]::new($false))
}

function Get-BusHttpPort {
    param([int]$ExpectedPid = 0)

    if (Test-Path -LiteralPath $PortsFile) {
        try {
            $json = Get-Content -LiteralPath $PortsFile -Raw -Encoding UTF8 |
                ConvertFrom-Json
            $httpPort = [int]$json.httpPort
            if (($ExpectedPid -eq 0 -or [int]$json.pid -eq $ExpectedPid) -and
                $httpPort -ge 1 -and $httpPort -le 65535) {
                $response = Invoke-WebRequest `
                    -Uri "http://localhost:$httpPort/testConnection" `
                    -Method POST -Body '' -TimeoutSec 2 -UseBasicParsing `
                    -ErrorAction Stop
                if ($response.StatusCode -eq 200) {
                    return $httpPort
                }
            }
        } catch {}
    }
    if ($ExpectedPid -gt 0) { return $null }

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

function Get-EvidenceIdentity {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $item = Get-Item -LiteralPath $Path
    $digest = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    return '{0}|{1}|{2}' -f $item.LastWriteTimeUtc.Ticks, $item.Length, $digest
}

function Stop-BusIfReachable {
    param([int]$ExpectedPid = 0)

    $httpPort = Get-BusHttpPort -ExpectedPid $ExpectedPid
    if ($null -eq $httpPort) { return }
    try {
        Invoke-WebRequest -Uri "http://localhost:$httpPort/shutdown" `
            -Method POST -Body '' -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop | Out-Null
    } catch {}
}

function Get-ClosedBenchLines {
    param(
        [string]$RawText,
        [Parameter(Mandatory = $true)][string]$RunId
    )

    $startMarker = '[CF7_PROTOCOL_RUN_START id=' + $RunId + ']'
    $endMarker = '[CF7_PROTOCOL_RUN_END id=' + $RunId + ']'
    $startPattern = '(?m)^' + [regex]::Escape($startMarker) + '\r?$'
    $endPattern = '(?m)^' + [regex]::Escape($endMarker) + '\r?$'
    if ([regex]::Matches($RawText, $startPattern).Count -ne 1 -or
        [regex]::Matches($RawText, $endPattern).Count -ne 1) {
        return @()
    }
    $blockPattern = '(?ms)^' + [regex]::Escape($startMarker) +
        '\r?\n.*?^' + [regex]::Escape($endMarker) + '\r?$'
    $blocks = [regex]::Matches($RawText, $blockPattern)
    if ($blocks.Count -ne 1) { return @() }
    return ($blocks[0].Value -split "`r?`n")
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
        parse_counts = [ordered]@{
            connect = 0
            metric_summaries = [ordered]@{}
        }
    }

    foreach ($line in $Lines) {
        if ($line -match '^\[bench\] connect ports_file_ms=([0-9\-]+) socket_port_ms=([0-9\-]+) socket_connected_ms=([0-9\-]+)$') {
            $result.parse_counts.connect++
            $result.connect.ports_file_ms = [int]$matches[1]
            $result.connect.socket_port_ms = [int]$matches[2]
            $result.connect.socket_connected_ms = [int]$matches[3]
            continue
        }
        if ($line -match '^\[bench\] metric name=([^ ]+) count=(\d+) min=([0-9.\-]+) avg=([0-9.\-]+) max=([0-9.\-]+)$') {
            $name = $matches[1]
            if (-not $result.parse_counts.metric_summaries.Contains($name)) {
                $result.parse_counts.metric_summaries[$name] = 0
            }
            $result.parse_counts.metric_summaries[$name]++
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

function Test-NonNegativeFiniteNumber {
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return $false }
    try {
        $number = [System.Convert]::ToDouble(
            $Value, [System.Globalization.CultureInfo]::InvariantCulture)
    } catch {
        return $false
    }
    return -not [double]::IsNaN($number) -and
        -not [double]::IsInfinity($number) -and $number -ge 0
}

function Get-BenchSummaryValidationErrors {
    param([Parameter(Mandatory = $true)]$Summary)

    $errors = New-Object System.Collections.Generic.List[string]
    if ([int]$Summary.parse_counts.connect -ne 1) {
        $errors.Add("Connect summary must occur exactly once; found $($Summary.parse_counts.connect).")
    }
    foreach ($name in @('ports_file_ms', 'socket_port_ms', 'socket_connected_ms')) {
        if (-not (Test-NonNegativeFiniteNumber $Summary.connect[$name])) {
            $errors.Add("connect.$name is missing or non-finite.")
        }
    }

    $actualMetricNames = @($Summary.metrics.Keys)
    $actualRawNames = @($Summary.raw_samples.Keys)
    foreach ($name in $actualMetricNames) {
        if (-not $ExpectedMetricCounts.Contains($name)) {
            $errors.Add("Unexpected metric summary '$name'.")
        }
    }
    foreach ($name in $actualRawNames) {
        if (-not $ExpectedMetricCounts.Contains($name)) {
            $errors.Add("Unexpected raw metric '$name'.")
        }
    }

    foreach ($name in $ExpectedMetricCounts.Keys) {
        $expectedCount = [int]$ExpectedMetricCounts[$name]
        $metricSummaryCount = if (
            $Summary.parse_counts.metric_summaries.Contains($name)) {
            [int]$Summary.parse_counts.metric_summaries[$name]
        } else {
            0
        }
        if ($metricSummaryCount -ne 1) {
            $errors.Add("Metric '$name' summary must occur exactly once; found $metricSummaryCount.")
        }
        if (-not $Summary.metrics.Contains($name)) {
            $errors.Add("Missing metric summary '$name'.")
            continue
        }
        if (-not $Summary.raw_samples.Contains($name)) {
            $errors.Add("Missing raw samples '$name'.")
            continue
        }
        $metric = $Summary.metrics[$name]
        $samples = @($Summary.raw_samples[$name])
        if ([int]$metric.count -ne $expectedCount) {
            $errors.Add("Metric '$name' count is $($metric.count), expected $expectedCount.")
        }
        if ($samples.Count -ne $expectedCount) {
            $errors.Add("Metric '$name' raw sample count is $($samples.Count), expected $expectedCount.")
        }
        foreach ($field in @('min_ms', 'avg_ms', 'max_ms')) {
            if (-not (Test-NonNegativeFiniteNumber $metric[$field])) {
                $errors.Add("Metric '$name' field '$field' is missing or non-finite.")
            }
        }
        foreach ($sample in $samples) {
            if (-not (Test-NonNegativeFiniteNumber $sample)) {
                $errors.Add("Metric '$name' contains a missing or non-finite raw sample.")
                break
            }
        }
        if ($samples.Count -gt 0 -and
            @($samples | Where-Object {
                    -not (Test-NonNegativeFiniteNumber $_)
                }).Count -eq 0) {
            $measure = $samples | Measure-Object -Minimum -Maximum -Average
            $expected = [ordered]@{
                min_ms = [double]$measure.Minimum
                avg_ms = [Math]::Floor(([double]$measure.Average * 100) + 0.5) / 100
                max_ms = [double]$measure.Maximum
            }
            foreach ($field in $expected.Keys) {
                if ([Math]::Abs(
                        [double]$metric[$field] - [double]$expected[$field]) -gt 0.001) {
                    $errors.Add(
                        "Metric '$name' $field=$($metric[$field]) disagrees with raw samples ($($expected[$field])).")
                }
            }
        }
    }
    return $errors.ToArray()
}

$benchAs2 = @'
import org.flashNight.neur.Server.*;
import org.flashNight.arki.render.*;

trace("[CF7_PROTOCOL_RUN_START id=__CF7_PROTOCOL_RUN_ID__]");

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
    trace("[CF7_PROTOCOL_RUN_END id=__CF7_PROTOCOL_RUN_ID__]");
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

$ExpectedMetricCounts = [ordered]@{}
$metricSpecs = [regex]::Matches(
    $benchAs2,
    '(?m)^\s*enqueueMetric\("([A-Za-z0-9_]+)",\s*(\d+),')
if ($metricSpecs.Count -ne 14) {
    throw "Protocol latency contract requires exactly 14 literal metric specifications; found $($metricSpecs.Count)."
}
foreach ($metricSpec in $metricSpecs) {
    $metricName = $metricSpec.Groups[1].Value
    $metricCount = [int]$metricSpec.Groups[2].Value
    if ($metricCount -le 0) {
        throw "Protocol latency metric '$metricName' must request at least one sample."
    }
    if ($ExpectedMetricCounts.Contains($metricName)) {
        throw "Protocol latency scratch source defines metric '$metricName' more than once."
    }
    $ExpectedMetricCounts[$metricName] = $metricCount
}

$busStartedByUs = $false
$busProc = $null
$busReady = $false
$selfStartedBusPid = $null
$selfStartedBusHttpPort = $null
$installedTestLoaderHash = $null
$scratchTransaction = $null
$compileOutput = ''
$compileExit = $null
$summary = $null
$summaryValidationErrors = @()
$runId = [System.Guid]::NewGuid().ToString('N')
$normalizedProjectRoot = [System.IO.Path]::GetFullPath(
    $ProjectRoot).TrimEnd('\').ToUpperInvariant()
$compileHasher = [System.Security.Cryptography.SHA256]::Create()
try {
    $compileRepoHash = ([System.BitConverter]::ToString(
        $compileHasher.ComputeHash(
            [System.Text.Encoding]::UTF8.GetBytes($normalizedProjectRoot)))).
        Replace('-', '').Substring(0, 24)
} finally {
    $compileHasher.Dispose()
}
$compileMutex = [System.Threading.Mutex]::new(
    $false, 'Local\CF7_FlashCompile_' + $compileRepoHash)
$compileMutexAcquired = $false
$compileLease = $null
$behaviorStarted = $false
$behaviorClosed = $false
$runCompletedCleanly = $false

try {
    try {
        $compileMutexAcquired = $compileMutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        $compileMutexAcquired = $true
        Write-ProtocolUncertain `
            -Reason 'protocol cycle observed abandoned compile mutex'
        throw 'A previous compile abandoned the repository mutex. Confirm Flash/JSFL stopped and clear late markers before retrying.'
    }
    if (-not $compileMutexAcquired) {
        throw 'Another Flash compile is using this repository; refusing to replace TestLoader.as.'
    }
    if (Test-Path -LiteralPath $UncertainMarker) {
        throw 'Compile state is uncertain. Confirm Flash/JSFL stopped, inspect late evidence, then remove scripts/compile_state_uncertain.marker.'
    }
    $compileLease = 'v1:{0}:{1}:{2}' -f $compileRepoHash, $PID,
        [System.Guid]::NewGuid().ToString('N')

    if (-not $NoBus) {
        if (Test-BusRunning) {
            $busReady = $true
            Write-Host '[bus] Already running'
        } else {
            if (-not (Test-Path -LiteralPath $BootstrapExe -PathType Leaf)) {
                throw "Bootstrap integrity probe not found: $BootstrapExe"
            }
            $verifyProc = Start-Process -FilePath $BootstrapExe `
                -ArgumentList '--verify-only' -PassThru -Wait `
                -WindowStyle Hidden
            try {
                if ($verifyProc.ExitCode -ne 0) {
                    throw (
                        'Runtime bundle integrity verification failed with ' +
                        "exit code $($verifyProc.ExitCode).")
                }
            } finally {
                $verifyProc.Dispose()
            }
            if (-not (Test-Path -LiteralPath $LauncherExe -PathType Leaf)) {
                throw "Launcher not found: $LauncherExe"
            }
            if (-not (Set-DotnetRootForCore)) {
                throw 'Unable to locate the required .NET Desktop runtime.'
            }
            Write-Host '[bus] Starting launcher --bus-only...'
            $busProc = Start-Process -FilePath $LauncherExe `
                -ArgumentList @('--bus-only', '--project-root', $ProjectRoot) `
                -PassThru -WindowStyle Hidden
            $busStartedByUs = $true
            $selfStartedBusPid = $busProc.Id

            $busDeadline = (Get-Date).AddSeconds(15)
            while ((Get-Date) -lt $busDeadline) {
                Start-Sleep -Milliseconds 500
                $busProc.Refresh()
                if ($busProc.HasExited) { break }
                $ownedPort = Get-BusHttpPort `
                    -ExpectedPid $selfStartedBusPid
                if ($null -ne $ownedPort) {
                    $selfStartedBusHttpPort = [int]$ownedPort
                    $busReady = $true
                    break
                }
            }
            if (-not $busReady) {
                throw "Bus PID $selfStartedBusPid failed exact readiness within 15 seconds."
            }
            Write-Host (
                "[bus] Ready pid=$selfStartedBusPid " +
                "http=$selfStartedBusHttpPort")
        }
    }

    $runIdPlaceholder = '__CF7_PROTOCOL_RUN_ID__'
    if ([regex]::Matches(
            $benchAs2, [regex]::Escape($runIdPlaceholder)).Count -ne 2) {
        throw 'Protocol latency scratch source must contain exactly two runId placeholders.'
    }
    $installedBenchAs2 = $benchAs2.Replace($runIdPlaceholder, $runId)
    $scratchTransaction = New-Cf7TestLoaderScratchTransaction `
        -MarkerPath $ScratchMarker -RunnerPath $TestLoaderAs `
        -RepoHash $compileRepoHash -CompileLease $compileLease `
        -OwnerKind 'protocol-latency'
    Assert-Cf7TestLoaderScratchReadyToInstall -Transaction $scratchTransaction

    $beforeTime = if (Test-Path $FlashLog) { (Get-Item $FlashLog).LastWriteTimeUtc } else { [datetime]::MinValue }
    $beforeLength = if (Test-Path $FlashLog) { (Get-Item $FlashLog).Length } else { 0 }

    $bom = [byte[]]@(0xEF, 0xBB, 0xBF)
    $codeBytes = [System.Text.Encoding]::UTF8.GetBytes($installedBenchAs2)
    $allBytes = New-Object byte[] ($bom.Length + $codeBytes.Length)
    [Array]::Copy($bom, 0, $allBytes, 0, $bom.Length)
    [Array]::Copy($codeBytes, 0, $allBytes, $bom.Length, $codeBytes.Length)
    [System.IO.File]::WriteAllBytes($TestLoaderAs, $allBytes)
    $installedTestLoaderHash = (Get-FileHash -LiteralPath $TestLoaderAs -Algorithm SHA256).Hash

    $compileEvidenceBefore = [ordered]@{}
    foreach ($path in @($CompileOutputPath, $CompilerErrorsPath)) {
        $compileEvidenceBefore[$path] = Get-EvidenceIdentity -Path $path
    }
    $compileStartedUtc = [System.DateTime]::UtcNow
    $previousCompileLease = $env:CF7_FLASH_COMPILE_LEASE
    try {
        $env:CF7_FLASH_COMPILE_LEASE = $compileLease
        $compileOutput = (& powershell.exe -NoProfile -ExecutionPolicy Bypass `
            -File $CompileScript -Target test `
            -TimeoutSeconds $WaitTimeoutSec *>&1 | Out-String)
        $compileExit = $LASTEXITCODE
    } finally {
        if ($null -eq $previousCompileLease) {
            Remove-Item Env:CF7_FLASH_COMPILE_LEASE -ErrorAction SilentlyContinue
        } else {
            $env:CF7_FLASH_COMPILE_LEASE = $previousCompileLease
        }
    }
    if ($compileExit -ne 0) {
        $freshCompilerDiagnostics = (Test-Path -LiteralPath $CompilerErrorsPath) -and
            (Get-EvidenceIdentity -Path $CompilerErrorsPath) -ne
                $compileEvidenceBefore[$CompilerErrorsPath] -and
            (Get-Item -LiteralPath $CompilerErrorsPath).LastWriteTimeUtc -ge
                $compileStartedUtc.AddSeconds(-1)
        $freshCompileOutput = (Test-Path -LiteralPath $CompileOutputPath) -and
            (Get-EvidenceIdentity -Path $CompileOutputPath) -ne
                $compileEvidenceBefore[$CompileOutputPath] -and
            (Get-Item -LiteralPath $CompileOutputPath).LastWriteTimeUtc -ge
                $compileStartedUtc.AddSeconds(-1)
        $compilerWasClean = $freshCompilerDiagnostics -and
            (Get-Content -LiteralPath $CompilerErrorsPath -Raw -Encoding UTF8) -match
                '^\s*0\s+[^,\r\n]+,\s*0\s+[^,\r\n]+\s*$'
        if ($compilerWasClean -or
            (-not $freshCompilerDiagnostics -and $freshCompileOutput)) {
            # A post-testMovie gate can fail while the asynchronous bench
            # remains alive; retain the behavior uncertainty barrier.
            $behaviorStarted = $true
        }
        Write-Host $compileOutput.TrimEnd()
        throw "Protocol latency TestLoader compile failed with exit code $compileExit."
    }
    $behaviorStarted = $true
    foreach ($path in @($CompileOutputPath, $CompilerErrorsPath)) {
        if (-not (Test-Path -LiteralPath $path) -or
            (Get-EvidenceIdentity -Path $path) -eq $compileEvidenceBefore[$path] -or
            (Get-Item -LiteralPath $path).LastWriteTimeUtc -lt
                $compileStartedUtc.AddSeconds(-1)) {
            throw "Protocol compile evidence was not freshly replaced: $path"
        }
    }
    $compilerErrors = Get-Content -LiteralPath $CompilerErrorsPath -Raw -Encoding UTF8
    if ($compilerErrors -notmatch '^\s*0\s+[^,\r\n]+,\s*0\s+[^,\r\n]+\s*$') {
        throw 'Protocol compiler diagnostics are not 0 errors / 0 warnings.'
    }
    $compileEvidence = Get-Content -LiteralPath $CompileOutputPath -Raw -Encoding UTF8
    $retryCount = [regex]::Matches(
        $compileEvidence, 'cold ASO 32K branch detected').Count
    if ($retryCount -ne 0) {
        throw "Protocol compile required $retryCount 32K retry; refusing a duplicate behavior run."
    }

    $deadline = (Get-Date).AddSeconds($WaitTimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $FlashLog) {
            $item = Get-Item $FlashLog
            if ($item.LastWriteTimeUtc -gt $beforeTime -or $item.Length -gt $beforeLength) {
                $raw = Get-Content -Raw -Encoding UTF8 $FlashLog
                $lines = Get-ClosedBenchLines -RawText $raw -RunId $runId
                if ($lines.Length -gt 0) {
                    $behaviorClosed = $true
                    Copy-Item $FlashLog $LocalFlashLog -Force
                    $summary = Parse-BenchSummary -Lines $lines
                    $summaryValidationErrors = @(
                        Get-BenchSummaryValidationErrors -Summary $summary)
                    foreach ($validationError in $summaryValidationErrors) {
                        $summary.failures +=
                            ('[runner] schema validation: ' + $validationError)
                    }
                    $runCompletedCleanly =
                        $summaryValidationErrors.Count -eq 0 -and
                        $summary.failures.Count -eq 0
                    break
                }
            }
        }
        Start-Sleep -Milliseconds 500
    }
}
finally {
    $cleanupErrors = New-Object System.Collections.Generic.List[string]
    if ($behaviorStarted -and -not $behaviorClosed) {
        try {
            Write-ProtocolUncertain (
                "behavior did not reach one exact terminal block; runId=$runId; " +
                'the old test player may still append to the global Flash log')
        } catch {
            $cleanupErrors.Add("uncertain marker: $($_.Exception.Message)")
        }
    }
    # 持有 compile mutex 到 scratch 恢复与本轮自启 bus 停止完成。
    if ($scratchTransaction -and $installedTestLoaderHash) {
        try {
            Restore-Cf7TestLoaderScratchTransaction `
                -Transaction $scratchTransaction `
                -InstalledHash $installedTestLoaderHash
        } catch {
            $cleanupErrors.Add("scratch restore: $($_.Exception.Message)")
        }
    }
    if ($busStartedByUs -and ($StopBusAfter -or -not $runCompletedCleanly)) {
        try {
            Stop-BusIfReachable -ExpectedPid $selfStartedBusPid
            $busProc.Refresh()
            if (-not $busProc.HasExited -and
                -not $busProc.WaitForExit(10000)) {
                $busProc.Kill()
                if (-not $busProc.WaitForExit(5000)) {
                    throw "Self-started bus PID $selfStartedBusPid did not exit after Kill()."
                }
                Write-Host (
                    "[bus] Forced exact PID $selfStartedBusPid " +
                    'after graceful timeout')
            } else {
                Write-Host (
                    "[bus] Graceful stop confirmed for exact PID " +
                    $selfStartedBusPid)
            }
            if (Test-Path -LiteralPath $PortsFile) {
                try {
                    $ports = Get-Content -LiteralPath $PortsFile `
                        -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ([int]$ports.pid -eq $selfStartedBusPid -and
                        [int]$ports.httpPort -eq $selfStartedBusHttpPort) {
                        Remove-Item -LiteralPath $PortsFile -Force
                    }
                } catch {
                    Write-Warning (
                        'Could not prove launcher_ports.json belongs to the ' +
                        'self-started protocol bus; leaving it untouched.')
                }
            }
            $busProc.Dispose()
            $busStartedByUs = $false
        } catch {
            $cleanupErrors.Add("bus stop: $($_.Exception.Message)")
        }
    }
    if ($compileMutexAcquired) {
        try { $compileMutex.ReleaseMutex() } catch {
            $cleanupErrors.Add("compile mutex release: $($_.Exception.Message)")
        }
    }
    try { $compileMutex.Dispose() } catch {
        $cleanupErrors.Add("compile mutex dispose: $($_.Exception.Message)")
    }
    if ($scratchTransaction -and
        (Test-Path -LiteralPath $scratchTransaction.MarkerPath)) {
        Write-Warning ("TestLoader scratch transaction remains blocked; recovery backup: {0}" -f
            $scratchTransaction.BackupPath)
    }
    if ($cleanupErrors.Count -gt 0) {
        throw ('Protocol latency cleanup failed: ' + ($cleanupErrors -join ' | '))
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
    run_id = $runId
    connect = $summary.connect
    metrics = $summary.metrics
    raw_samples = $summary.raw_samples
    notes = $summary.notes
    failures = $summary.failures
    validation_errors = $summaryValidationErrors
}
$protocolFailed = $summary.failures.Count -gt 0

if ($Json) {
    $result | ConvertTo-Json -Depth 8
    if ($protocolFailed) { exit 1 }
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
if ($protocolFailed) { exit 1 }
