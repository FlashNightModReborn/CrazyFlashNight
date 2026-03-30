# cfn-cli.ps1 — CrazyFlashNight Guardian Launcher CLI (PowerShell)
# 用法:
#   .\cfn-cli.ps1 status              查看连接状态和 task 清单
#   .\cfn-cli.ps1 console <command>   执行 AS2 控制台命令
#   .\cfn-cli.ps1 toast <message>     发送 toast 消息
#   .\cfn-cli.ps1 log <message>       发送调试日志

param(
    [Parameter(Position=0)]
    [string]$Command = "status",
    [Parameter(Position=1, ValueFromRemainingArguments)]
    [string[]]$Args
)

# 端口文件（launcher 启动时写入，优先读取）
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$PortsFile = Join-Path $ProjectRoot 'launcher_ports.json'

# 盲扫候选列表（fallback）
$Ports = @(1192, 1924, 9243, 2433, 4339, 3399, 3993, 11924, 19243, 24339, 43399, 33993, 3000)

function Test-HttpPort($p) {
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:$p/testConnection" `
            -Method POST -Body "" -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
        return ($r.StatusCode -eq 200)
    } catch { return $false }
}

function Find-Port {
    # 优先从端口文件读取
    if (Test-Path $PortsFile) {
        try {
            $json = Get-Content -Raw $PortsFile | ConvertFrom-Json
            if ($json.httpPort -and (Test-HttpPort $json.httpPort)) {
                return $json.httpPort
            }
        } catch {}
    }
    # Fallback: 盲扫
    foreach ($p in $Ports) {
        if (Test-HttpPort $p) { return $p }
    }
    return $null
}

$Port = Find-Port
if ($null -eq $Port) {
    Write-Error "Guardian Launcher not found on any candidate port."
    exit 1
}

switch ($Command) {
    "status" {
        $resp = Invoke-WebRequest -Uri "http://localhost:$Port/status" `
            -Method GET -TimeoutSec 5 -UseBasicParsing
        try {
            $resp.Content | ConvertFrom-Json | ConvertTo-Json -Depth 5
        } catch {
            $resp.Content
        }
    }
    "console" {
        $cmd = $Args -join " "
        if ([string]::IsNullOrEmpty($cmd)) {
            Write-Error "Usage: cfn-cli.ps1 console <command>"
            exit 1
        }
        $body = @{ command = $cmd } | ConvertTo-Json
        $resp = Invoke-WebRequest -Uri "http://localhost:$Port/console" `
            -Method POST -Body $body -ContentType "application/json" `
            -TimeoutSec 10 -UseBasicParsing
        $resp.Content
    }
    "toast" {
        $msg = $Args -join " "
        if ([string]::IsNullOrEmpty($msg)) {
            Write-Error "Usage: cfn-cli.ps1 toast <message>"
            exit 1
        }
        $body = @{ task = "toast"; payload = $msg } | ConvertTo-Json
        Invoke-WebRequest -Uri "http://localhost:$Port/task" `
            -Method POST -Body $body -ContentType "application/json" `
            -TimeoutSec 5 -UseBasicParsing | Out-Null
        Write-Host "Toast sent: $msg"
    }
    "log" {
        $msg = $Args -join " "
        if ([string]::IsNullOrEmpty($msg)) {
            Write-Error "Usage: cfn-cli.ps1 log <message>"
            exit 1
        }
        Invoke-WebRequest -Uri "http://localhost:$Port/logBatch" `
            -Method POST -Body "frame=0&messages=$msg" -TimeoutSec 5 -UseBasicParsing | Out-Null
        Write-Host "Logged: $msg"
    }
    "port" {
        Write-Host $Port
    }
    default {
        Write-Host "cfn-cli.ps1 - Guardian Launcher CLI"
        Write-Host "Usage: cfn-cli.ps1 <command> [args]"
        Write-Host ""
        Write-Host "Commands:"
        Write-Host "  status              Show connection state and task list"
        Write-Host "  console <command>   Execute AS2 console command"
        Write-Host "  toast <message>     Send toast message"
        Write-Host "  log <message>       Send debug log"
        Write-Host "  port                Print discovered HTTP port"
        Write-Host ""
        Write-Host "Discovered port: $Port"
    }
}
