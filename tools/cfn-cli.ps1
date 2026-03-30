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

# 端口候选列表（与 PortAllocator 种子 "1192433993" 一致）
$Ports = @(1192, 1924, 9243, 2433, 4339, 3399, 3993, 11924, 19243, 24339, 43399, 33993, 3000)

function Find-Port {
    foreach ($p in $Ports) {
        try {
            $r = Invoke-WebRequest -Uri "http://localhost:$p/testConnection" `
                -Method POST -Body "" -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
            if ($r.StatusCode -eq 200) { return $p }
        } catch {}
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
        Invoke-WebRequest -Uri "http://localhost:$Port/logBatch" `
            -Method POST -Body "frame=0&messages=$msg" -TimeoutSec 5 -UseBasicParsing | Out-Null
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
