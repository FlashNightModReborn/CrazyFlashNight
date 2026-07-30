# CrazyFlashNight Guardian Launcher CLI (PowerShell)
param(
    [Parameter(Position = 0)]
    [string]$Command = 'status',
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$CommandArgs
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'lib\LegacyHttpAuth.ps1')

function Test-Cf7HttpIdentity {
    param([Parameter(Mandatory = $true)][int]$Port)
    try {
        $response = Invoke-WebRequest `
            -Uri "http://localhost:$Port/testConnection" `
            -Method POST -Body '' -TimeoutSec 2 -UseBasicParsing `
            -ErrorAction Stop
        return $response.StatusCode -eq 200
    } catch {
        return $false
    }
}

function Get-Cf7ExactBusPorts {
    $context = Get-Cf7LegacyHttpContext -ProjectRoot $ProjectRoot
    if (-not (Test-Cf7HttpIdentity -Port $context.HttpPort)) {
        throw 'Exact launcher_ports.json HTTP listener is unavailable.'
    }
    return $context
}

function Get-Cf7AuthenticatedBus {
    $context = Get-Cf7LegacyHttpContext -ProjectRoot $ProjectRoot
    if (-not (Test-Cf7HttpIdentity -Port $context.HttpPort)) {
        throw 'Exact launcher_ports.json HTTP listener is unavailable.'
    }
    return $context
}

try {
    switch ($Command) {
        'status' {
            $context = Get-Cf7AuthenticatedBus
            $response = Invoke-WebRequest `
                -Uri "http://localhost:$($context.HttpPort)/status" `
                -Headers $context.Headers -Method GET -TimeoutSec 5 `
                -UseBasicParsing
            try {
                $response.Content | ConvertFrom-Json |
                    ConvertTo-Json -Depth 5
            } catch {
                $response.Content
            }
        }
        'console' {
            $commandText = $CommandArgs -join ' '
            if ([string]::IsNullOrWhiteSpace($commandText)) {
                throw 'Usage: cfn-cli.ps1 console <command>'
            }
            $context = Get-Cf7AuthenticatedBus
            $body = @{ command = $commandText } | ConvertTo-Json -Compress
            $response = Invoke-WebRequest `
                -Uri "http://localhost:$($context.HttpPort)/console" `
                -Headers $context.Headers -Method POST -Body $body `
                -ContentType 'application/json' -TimeoutSec 10 `
                -UseBasicParsing
            $response.Content
        }
        'toast' {
            $message = $CommandArgs -join ' '
            if ([string]::IsNullOrWhiteSpace($message)) {
                throw 'Usage: cfn-cli.ps1 toast <message>'
            }
            $context = Get-Cf7AuthenticatedBus
            $body = @{
                task = 'toast'
                payload = $message
            } | ConvertTo-Json -Compress
            Invoke-WebRequest `
                -Uri "http://localhost:$($context.HttpPort)/task" `
                -Headers $context.Headers -Method POST -Body $body `
                -ContentType 'application/json' -TimeoutSec 5 `
                -UseBasicParsing | Out-Null
            Write-Host "Toast sent: $message"
        }
        'log' {
            $message = $CommandArgs -join ' '
            if ([string]::IsNullOrWhiteSpace($message)) {
                throw 'Usage: cfn-cli.ps1 log <message>'
            }
            # /logBatch remains a public Flash compatibility endpoint.
            $ports = Get-Cf7ExactBusPorts
            if ($null -eq $ports) { throw 'Guardian Launcher is not running.' }
            Invoke-WebRequest `
                -Uri "http://localhost:$($ports.HttpPort)/logBatch" `
                -Method POST -Body "frame=0&messages=$message" `
                -TimeoutSec 5 -UseBasicParsing | Out-Null
            Write-Host "Logged: $message"
        }
        'port' {
            $ports = Get-Cf7ExactBusPorts
            if ($null -eq $ports) { throw 'Guardian Launcher is not running.' }
            Write-Output $ports.HttpPort
        }
        default {
            Write-Host 'cfn-cli.ps1 - Guardian Launcher CLI'
            Write-Host 'Usage: cfn-cli.ps1 <command> [args]'
            Write-Host ''
            Write-Host 'Commands:'
            Write-Host '  status              Show connection state and task list'
            Write-Host '  console <command>   Execute AS2 console command'
            Write-Host '  toast <message>     Send toast message'
            Write-Host '  log <message>       Send debug log'
            Write-Host '  port                Print exact HTTP port'
        }
    }
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
