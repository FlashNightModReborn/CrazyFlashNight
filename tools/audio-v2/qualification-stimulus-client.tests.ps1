[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$client = Join-Path $PSScriptRoot 'qualification-stimulus-client.ps1'
$powershell = (Get-Process -Id $PID -ErrorAction Stop).Path
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('cf7-audio-stimulus-client-' + [Guid]::NewGuid().ToString('N'))
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
        [byte[]]$Request,
        [int]$TimeoutMilliseconds,
        [string]$Name,
        [switch]$UseBase64,
        [string]$Base64Override
    )
    $stdout = Join-Path $testRoot ($Name + '.stdout')
    $stderr = Join-Path $testRoot ($Name + '.stderr')
    $arguments = @(
        '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', ('"' + $client + '"'),
        '-PipeName', $PipeName,
        '-ExpectedServerPid', [string]$ExpectedPid
    )
    $start = @{
        FilePath = $powershell
        RedirectStandardOutput = $stdout
        RedirectStandardError = $stderr
        WindowStyle = 'Hidden'
        PassThru = $true
    }
    if ($UseBase64) {
        $encoded = if ($null -ne $Base64Override) { $Base64Override } else { [Convert]::ToBase64String($Request) }
        $arguments += @('-RequestBase64', $encoded)
    }
    else {
        $stdin = Join-Path $testRoot ($Name + '.stdin')
        [IO.File]::WriteAllBytes($stdin, $Request)
        $arguments += '-RequestFromStdin'
        $start.RedirectStandardInput = $stdin
    }
    $arguments += @('-TimeoutMilliseconds', [string]$TimeoutMilliseconds)
    $start.ArgumentList = $arguments
    $process = Start-Process @start
    return [pscustomobject]@{ Process = $process; Stdout = $stdout; Stderr = $stderr }
}

function Wait-Client {
    param($Started)
    if (-not $Started.Process.WaitForExit(15000)) {
        try { $Started.Process.Kill() } catch { }
        throw 'qualification stimulus client test process timed out'
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
    Test-Case 'exact server PID round trips exact single records' {
        $runId = '1' * 32
        $pipeName = "cf7-audio-v2-qualification-stimulus-$PID-$runId"
        $request = [Text.Encoding]::UTF8.GetBytes('{"command":"dispatch"}')
        $response = '{"result":"ok"}'
        $server = New-Server $pipeName
        try {
            $accept = $server.BeginWaitForConnection($null, $null)
            $started = Start-Client $pipeName $PID $request 5000 'positive'
            $server.EndWaitForConnection($accept)
            $utf8 = [Text.UTF8Encoding]::new($false, $true)
            $reader = [IO.StreamReader]::new($server, $utf8, $false, 4096, $true)
            $writer = [IO.StreamWriter]::new($server, $utf8, 4096, $true)
            $writer.NewLine = "`n"
            $writer.AutoFlush = $true
            Assert-True ($reader.ReadLine() -ceq [Text.Encoding]::UTF8.GetString($request)) 'server received different request bytes'
            $writer.WriteLine($response)
            $result = Wait-Client $started
            Assert-True ($result.Stdout -ceq $response -and $result.Stderr.Length -eq 0) ("positive client did not preserve exact response: stdout=<" + $result.Stdout + "> stderr=<" + $result.Stderr + ">")
            $writer.Dispose()
            $reader.Dispose()
        }
        finally { $server.Dispose() }
    }

    Test-Case 'wrong server PID rejects before writing request bytes' {
        $runId = '2' * 32
        $pipeName = "cf7-audio-v2-qualification-stimulus-$PID-$runId"
        $server = New-Server $pipeName
        try {
            $accept = $server.BeginWaitForConnection($null, $null)
            $started = Start-Client $pipeName ($PID + 1) ([Text.Encoding]::UTF8.GetBytes('{"mustNotArrive":true}')) 5000 'wrong-pid'
            $server.EndWaitForConnection($accept)
            $result = Wait-Client $started
            $reader = [IO.StreamReader]::new($server, [Text.UTF8Encoding]::new($false, $true), $false, 4096, $true)
            Assert-True ($null -eq $reader.ReadLine()) 'wrong-PID client wrote request bytes'
            Assert-True ($result.Stdout.Length -eq 0 -and $result.Stderr -match 'server PID mismatch') 'wrong-PID client did not fail closed'
            $reader.Dispose()
        }
        finally { $server.Dispose() }
    }

    Test-Case 'missing pipe and server-close paths fail closed' {
        $runId = '3' * 32
        $missingName = "cf7-audio-v2-qualification-stimulus-$PID-$runId"
        $missing = Wait-Client (Start-Client $missingName $PID ([Text.Encoding]::UTF8.GetBytes('{"a":1}')) 100 'missing')
        Assert-True ($missing.ExitCode -ne 0 -and $missing.Stdout.Length -eq 0 -and $missing.Stderr.Length -gt 0) 'missing pipe did not fail closed'

        $runId = '4' * 32
        $pipeName = "cf7-audio-v2-qualification-stimulus-$PID-$runId"
        $server = New-Server $pipeName
        $accept = $server.BeginWaitForConnection($null, $null)
        $started = Start-Client $pipeName $PID ([Text.Encoding]::UTF8.GetBytes('{"a":1}')) 5000 'closed'
        $server.EndWaitForConnection($accept)
        $server.Dispose()
        $closed = Wait-Client $started
        Assert-True ($closed.ExitCode -ne 0 -and $closed.Stdout.Length -eq 0 -and $closed.Stderr.Length -gt 0) 'closed server did not fail closed'
    }

    Test-Case 'invalid UTF8 framing size and base64 fail before connect' {
        $pipeName = "cf7-audio-v2-qualification-stimulus-$PID-$('5' * 32)"
        $cases = @(
            [pscustomobject]@{ Name='utf8'; Bytes=[byte[]](0xC3,0x28); Base64=$false; Override=$null },
            [pscustomobject]@{ Name='newline'; Bytes=[Text.Encoding]::UTF8.GetBytes("{}`n"); Base64=$false; Override=$null },
            [pscustomobject]@{ Name='oversize'; Bytes=[Text.Encoding]::UTF8.GetBytes(('a' * 65537)); Base64=$false; Override=$null },
            [pscustomobject]@{ Name='base64'; Bytes=[byte[]]::new(0); Base64=$true; Override='!!!!' }
        )
        foreach ($case in $cases) {
            $result = Wait-Client (Start-Client $pipeName $PID $case.Bytes 100 $case.Name -UseBase64:$case.Base64 -Base64Override $case.Override)
            Assert-True ($result.ExitCode -ne 0 -and $result.Stdout.Length -eq 0 -and $result.Stderr.Length -gt 0) ($case.Name + ' did not fail before connect')
        }
    }

    [Console]::Out.WriteLine("qualification-stimulus-client tests passed: $passed")
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
