[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$client = Join-Path $PSScriptRoot 'qualification-observer-client.ps1'
$powershell = (Get-Process -Id $PID -ErrorAction Stop).Path
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('cf7-audio-observer-client-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$passed = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Start-Client {
    param(
        [string]$PipeName,
        [int]$ExpectedPid,
        [string]$RequestBase64,
        [int]$TimeoutMilliseconds,
        [string]$Name,
        [switch]$UseBase64
    )
    $stdout = Join-Path $testRoot ($Name + '.stdout')
    $stderr = Join-Path $testRoot ($Name + '.stderr')
    $arguments = @(
        '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', ('"' + $client + '"'),
        '-PipeName', $PipeName,
        '-ExpectedServerPid', [string]$ExpectedPid
    )
    $startParameters = @{
        FilePath = $powershell
        RedirectStandardOutput = $stdout
        RedirectStandardError = $stderr
        WindowStyle = 'Hidden'
        PassThru = $true
    }
    if ($UseBase64) {
        $arguments += @('-RequestBase64', $RequestBase64)
    }
    else {
        $stdin = Join-Path $testRoot ($Name + '.stdin')
        [IO.File]::WriteAllBytes($stdin, [Convert]::FromBase64String($RequestBase64))
        $arguments += '-RequestFromStdin'
        $startParameters.RedirectStandardInput = $stdin
    }
    $arguments += @('-TimeoutMilliseconds', [string]$TimeoutMilliseconds)
    $startParameters.ArgumentList = $arguments
    $process = Start-Process @startParameters
    return [pscustomobject]@{ Process = $process; Stdout = $stdout; Stderr = $stderr }
}

function Wait-Client {
    param($Started)
    if (-not $Started.Process.WaitForExit(15000)) {
        try { $Started.Process.Kill() } catch { }
        throw 'qualification observer client test process timed out'
    }
    $Started.Process.WaitForExit()
    $Started.Process.Refresh()
    $exitCode = $Started.Process.ExitCode
    $Started.Process.Dispose()
    Start-Sleep -Milliseconds 50
    return [pscustomobject]@{
        ExitCode = $exitCode
        Stdout = if (Test-Path -LiteralPath $Started.Stdout) { [IO.File]::ReadAllText($Started.Stdout) } else { '' }
        Stderr = if (Test-Path -LiteralPath $Started.Stderr) { [IO.File]::ReadAllText($Started.Stderr) } else { '' }
    }
}

function New-Server {
    param([string]$PipeName)
    return [IO.Pipes.NamedPipeServerStream]::new(
        $PipeName,
        [IO.Pipes.PipeDirection]::InOut,
        1,
        [IO.Pipes.PipeTransmissionMode]::Byte,
        [IO.Pipes.PipeOptions]::Asynchronous)
}

function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    & $Body
    $script:passed++
    [Console]::Out.WriteLine("ok $script:passed - $Name")
}

try {
    Test-Case 'exact server PID permits one request and exact stdout response' {
        $runId = '1' * 32
        $pipeName = "cf7-audio-v2-qualification-$PID-$runId"
        $request = '{"a":1}'
        $response = '{"candidate":"exact"}'
        $server = New-Server $pipeName
        try {
            $accept = $server.BeginWaitForConnection($null, $null)
            $started = Start-Client $pipeName $PID ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($request))) 5000 'positive'
            $server.EndWaitForConnection($accept)
            $utf8 = [Text.UTF8Encoding]::new($false, $true)
            $reader = [IO.StreamReader]::new($server, $utf8, $false, 4096, $true)
            $writer = [IO.StreamWriter]::new($server, $utf8, 4096, $true)
            $writer.NewLine = "`n"
            $writer.AutoFlush = $true
            $received = $reader.ReadLine()
            if ($null -eq $received) {
                $failed = Wait-Client $started
                throw ("positive client closed before request: " + $failed.Stderr)
            }
            Assert-True ($received -ceq $request) ("server did not receive the exact request record: received=<" + $received + "> expected=<" + $request + ">")
            $writer.WriteLine($response)
            $result = Wait-Client $started
            Assert-True ($result.Stdout -ceq $response) 'client stdout was not the exact response record'
            Assert-True ($result.Stderr.Length -eq 0) 'positive client emitted stderr'
            $writer.Dispose()
            $reader.Dispose()
        }
        finally { $server.Dispose() }
    }

    Test-Case 'wrong server PID fails before any request byte is written' {
        $runId = '2' * 32
        $pipeName = "cf7-audio-v2-qualification-$PID-$runId"
        $server = New-Server $pipeName
        try {
            $accept = $server.BeginWaitForConnection($null, $null)
            $request = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"mustNotArrive":true}'))
            $started = Start-Client $pipeName ($PID + 1) $request 5000 'wrong-pid'
            $server.EndWaitForConnection($accept)
            $result = Wait-Client $started
            $reader = [IO.StreamReader]::new($server, [Text.UTF8Encoding]::new($false, $true), $false, 4096, $true)
            $line = $reader.ReadLine()
            Assert-True ($null -eq $line) 'wrong-PID client wrote request bytes before rejecting the server'
            Assert-True ($result.Stdout.Length -eq 0) 'wrong-PID client emitted stdout'
            Assert-True ($result.Stderr -match 'server PID mismatch') 'wrong-PID diagnostic missing'
            $reader.Dispose()
        }
        finally { $server.Dispose() }
    }

    Test-Case 'server close without response fails closed' {
        $runId = '3' * 32
        $pipeName = "cf7-audio-v2-qualification-$PID-$runId"
        $server = New-Server $pipeName
        $accept = $server.BeginWaitForConnection($null, $null)
        $request = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"a":1}'))
        $started = Start-Client $pipeName $PID $request 5000 'server-close'
        $server.EndWaitForConnection($accept)
        $server.Dispose()
        $result = Wait-Client $started
        Assert-True ($result.Stdout.Length -eq 0) 'closed server emitted stdout'
        Assert-True ($result.Stderr.Length -gt 0) ("closed-server diagnostic missing: " + $result.Stderr)
    }

    Test-Case 'missing pipe timeout fails closed' {
        $runId = '4' * 32
        $pipeName = "cf7-audio-v2-qualification-$PID-$runId"
        $request = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"a":1}'))
        $result = Wait-Client (Start-Client $pipeName $PID $request 100 'timeout')
        Assert-True ($result.Stdout.Length -eq 0) 'missing pipe emitted stdout'
        Assert-True ($result.Stderr.Length -gt 0) 'missing-pipe diagnostic missing'
    }

    Test-Case 'invalid UTF8 newline oversize and base64 requests fail before connect' {
        $cases = @(
            [pscustomobject]@{ Name = 'invalid-utf8'; Value = [Convert]::ToBase64String([byte[]](0xC3, 0x28)) },
            [pscustomobject]@{ Name = 'newline'; Value = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("{}`n")) },
            [pscustomobject]@{ Name = 'oversize'; Value = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(('a' * 65537))) },
            [pscustomobject]@{ Name = 'invalid-base64'; Value = '!!!!' }
        )
        foreach ($case in $cases) {
            $runId = '5' * 32
            $pipeName = "cf7-audio-v2-qualification-$PID-$runId"
            $result = Wait-Client (Start-Client $pipeName $PID $case.Value 100 $case.Name -UseBase64:($case.Name -eq 'invalid-base64'))
            Assert-True ($result.Stdout.Length -eq 0) ($case.Name + ' emitted stdout')
            Assert-True ($result.Stderr.Length -gt 0) ($case.Name + ' diagnostic missing')
        }
    }

    [Console]::Out.WriteLine("qualification-observer-client tests passed: $passed")
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
