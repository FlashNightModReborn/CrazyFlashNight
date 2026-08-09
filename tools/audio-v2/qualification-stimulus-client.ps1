[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^cf7-audio-v2-qualification-stimulus-[1-9][0-9]{0,9}-[0-9a-f]{32}$')]
    [string]$PipeName,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 2147483647)]
    [int]$ExpectedServerPid,

    [Parameter(Mandatory = $true, ParameterSetName = 'Base64')]
    [ValidatePattern('^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$')]
    [string]$RequestBase64,

    [Parameter(Mandatory = $true, ParameterSetName = 'Stdin')]
    [switch]$RequestFromStdin,

    [ValidateRange(100, 30000)]
    [int]$TimeoutMilliseconds = 5000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class Cf7AudioV2StimulusPipeNative
{
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetNamedPipeServerProcessId(
        IntPtr pipe,
        out uint serverProcessId);
}
'@

$pipe = $null
$reader = $null
$writer = $null

try {
    if ($RequestFromStdin) {
        $stdin = [Console]::OpenStandardInput()
        $memory = [IO.MemoryStream]::new()
        $buffer = [byte[]]::new(8192)
        do {
            $read = $stdin.Read($buffer, 0, $buffer.Length)
            if ($read -gt 0) {
                $memory.Write($buffer, 0, $read)
                if ($memory.Length -gt 65536) {
                    throw 'qualification stimulus request is outside the byte bound'
                }
            }
        } while ($read -gt 0)
        $requestBytes = $memory.ToArray()
        $memory.Dispose()
    }
    else {
        $requestBytes = [Convert]::FromBase64String($RequestBase64)
        if ([Convert]::ToBase64String($requestBytes) -cne $RequestBase64) {
            throw 'qualification stimulus request base64 is not canonical'
        }
    }
    if ($requestBytes.Length -lt 2 -or $requestBytes.Length -gt 65536) {
        throw 'qualification stimulus request is outside the byte bound'
    }

    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $request = $utf8.GetString($requestBytes)
    if ($request.IndexOf("`r") -ge 0 -or $request.IndexOf("`n") -ge 0) {
        throw 'qualification stimulus request must be one NDJSON record'
    }

    $pipe = [IO.Pipes.NamedPipeClientStream]::new(
        '.',
        $PipeName,
        [IO.Pipes.PipeDirection]::InOut,
        [IO.Pipes.PipeOptions]::None,
        [Security.Principal.TokenImpersonationLevel]::Identification)
    $pipe.Connect($TimeoutMilliseconds)

    [uint32]$serverPid = 0
    $handle = $pipe.SafePipeHandle.DangerousGetHandle()
    if (-not [Cf7AudioV2StimulusPipeNative]::GetNamedPipeServerProcessId($handle, [ref]$serverPid)) {
        $nativeError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "GetNamedPipeServerProcessId failed with Win32 error $nativeError"
    }
    if ([int64]$serverPid -ne [int64]$ExpectedServerPid) {
        throw "qualification stimulus pipe server PID mismatch: expected $ExpectedServerPid, actual $serverPid"
    }

    $reader = [IO.StreamReader]::new($pipe, $utf8, $false, 4096, $true)
    $writer = [IO.StreamWriter]::new($pipe, $utf8, 4096, $true)
    $writer.NewLine = "`n"
    $writer.AutoFlush = $true
    $writer.WriteLine($request)

    $readTask = $reader.ReadLineAsync()
    if (-not $readTask.Wait($TimeoutMilliseconds)) {
        throw 'qualification stimulus response timed out'
    }
    $response = $readTask.Result
    if ($null -eq $response) {
        throw 'qualification stimulus pipe closed without a response'
    }
    if ($response.IndexOf("`r") -ge 0 -or $response.IndexOf("`n") -ge 0) {
        throw 'qualification stimulus response must be one NDJSON record'
    }
    $responseBytes = $utf8.GetBytes($response)
    if ($responseBytes.Length -lt 2 -or $responseBytes.Length -gt 1048576) {
        throw 'qualification stimulus response is outside the byte bound'
    }

    $stdout = [Console]::OpenStandardOutput()
    $stdout.Write($responseBytes, 0, $responseBytes.Length)
    $stdout.Flush()
}
catch {
    [Console]::Error.WriteLine(
        'audio-v2 qualification stimulus client failed: ' +
        ($_.Exception.Message -replace '[\r\n]+', ' '))
    exit 3
}
finally {
    if ($null -ne $writer) { $writer.Dispose() }
    if ($null -ne $reader) { $reader.Dispose() }
    if ($null -ne $pipe) { $pipe.Dispose() }
}
