[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$tool = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'list-playback-endpoints.ps1'))
$toolText = [IO.File]::ReadAllText($tool)
$script:Passed = 0

function Assert-Cf7Test {
    param(
        [Parameter(Mandatory=$true)][bool]$Condition,
        [Parameter(Mandatory=$true)][string]$Message
    )
    if (-not $Condition) { throw "assertion failed: $Message" }
}

function Invoke-Cf7Test {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][scriptblock]$Body
    )
    & $Body
    $script:Passed++
    Write-Output ("ok {0} - {1}" -f $script:Passed, $Name)
}

function Get-Cf7Sha256 {
    param([Parameter(Mandatory=$true)][string]$Value)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)))).Replace('-', '')
    } finally {
        $algorithm.Dispose()
    }
}

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($tool, [ref]$tokens, [ref]$parseErrors)

Invoke-Cf7Test 'PowerShell source parses without errors' {
    Assert-Cf7Test ($null -ne $ast) 'parser returned no AST'
    $message = [string]::Join('; ', @($parseErrors | ForEach-Object { $_.Message }))
    if (-not $message) { $message = 'PowerShell parser returned an unspecified error' }
    Assert-Cf7Test ($parseErrors.Count -eq 0) $message
}

Invoke-Cf7Test 'embedded Core Audio inventory implementation compiles' {
    $sourceMatch = [regex]::Match($toolText, "(?s)\`$source = @'\r?\n(?<source>.*?)\r?\n'@")
    Assert-Cf7Test $sourceMatch.Success 'embedded endpoint inventory source was not found'
    Add-Type -TypeDefinition $sourceMatch.Groups['source'].Value -Language CSharp -ErrorAction Stop
    Assert-Cf7Test ($null -ne ('Cf7.AudioV2.EndpointInventory.EndpointReader' -as [type])) 'embedded endpoint reader type was not loaded'
}

Invoke-Cf7Test 'inventory is active-render, local, and read-only' {
    Assert-Cf7Test ($toolText -match 'EnumAudioEndpoints\(EDataFlow\.Render, DeviceStateActive') 'active render enumeration is absent'
    Assert-Cf7Test ($toolText -match 'GetDefaultAudioEndpoint\(EDataFlow\.Render') 'default role annotation is absent'
    Assert-Cf7Test ([regex]::Matches($toolText, '\bActivate\s*\(').Count -eq 1) 'an audio endpoint is activated outside the COM interface declaration'
    Assert-Cf7Test ($toolText -notmatch '(?i)SetDefault|PolicyConfig|Start-Process|Invoke-WebRequest|Invoke-RestMethod|HttpClient|Registry|New-Item|WriteAll|WriteFile|Set-Content|Out-File|Export-') 'mutation, persistence, process launch, network, or registry surface is present'
    Assert-Cf7Test ($toolText -match 'PKEY_Device_FriendlyName') 'friendly-name property binding is absent'
    Assert-Cf7Test ($toolText -match 'EndpointId') 'raw EndpointId output is absent'
}

Invoke-Cf7Test 'tool source is canonical UTF-8 LF without BOM' {
    $bytes = [IO.File]::ReadAllBytes($tool)
    Assert-Cf7Test ($bytes.Length -gt 0 -and $bytes[$bytes.Length - 1] -eq 10) 'tool lacks terminal LF'
    Assert-Cf7Test (-not ($bytes -contains 13)) 'tool contains CR bytes'
    Assert-Cf7Test (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) 'tool contains UTF-8 BOM'
}

Invoke-Cf7Test 'actual invocation emits exactly one valid inventory record and no stderr' {
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = (Get-Command powershell.exe -ErrorAction Stop).Source
    $escapedTool = $tool.Replace('"', '\"')
    $startInfo.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $escapedTool + '"'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        Assert-Cf7Test $process.Start() 'child PowerShell did not start'
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        Assert-Cf7Test ($process.WaitForExit(30000)) 'endpoint inventory timed out'
        Assert-Cf7Test ($process.ExitCode -eq 0) "endpoint inventory exited $($process.ExitCode): $stderr"
    } finally {
        if (-not $process.HasExited) { $process.Kill() }
        $process.Dispose()
    }
    Assert-Cf7Test ($stderr.Length -eq 0) "endpoint inventory wrote stderr: $stderr"
    $records = @($stdout -split "`r?`n" | Where-Object { $_.Length -gt 0 })
    Assert-Cf7Test ($records.Count -eq 1) 'stdout is not exactly one JSON record'
    $value = $records[0] | ConvertFrom-Json
    Assert-Cf7Test ($value.schema -ceq 'cf7.audio-v2.playback-endpoint-inventory.v1') 'inventory schema mismatch'
    Assert-Cf7Test ($null -ne $value.endpoints) 'inventory endpoints array is missing'
    $ids = @()
    foreach ($endpoint in @($value.endpoints)) {
        Assert-Cf7Test ([string[]]$endpoint.PSObject.Properties.Name -join ',' -ceq 'defaultRoles,deviceIdDigest,endpointId,friendlyName,state') 'endpoint record keys/order differ'
        Assert-Cf7Test ($endpoint.endpointId -is [string] -and $endpoint.endpointId.Length -gt 0) 'raw EndpointId is empty'
        Assert-Cf7Test ($endpoint.friendlyName -is [string]) 'friendlyName is not a string'
        Assert-Cf7Test ($endpoint.state -ceq 'active') 'non-active endpoint was emitted'
        Assert-Cf7Test ($endpoint.deviceIdDigest -ceq (Get-Cf7Sha256 -Value $endpoint.endpointId)) 'EndpointId SHA-256 mismatch'
        $roles = @($endpoint.defaultRoles)
        Assert-Cf7Test ([string]::Join(',', $roles) -ceq [string]::Join(',', @($roles | Sort-Object -Unique))) 'default roles are not sorted/unique'
        Assert-Cf7Test (@($roles | Where-Object { $_ -notin @('communications','console','multimedia') }).Count -eq 0) 'unknown default role emitted'
        $ids += $endpoint.endpointId
    }
    for ($index = 1; $index -lt $ids.Count; $index++) {
        Assert-Cf7Test ([StringComparer]::Ordinal.Compare($ids[$index - 1], $ids[$index]) -lt 0) 'EndpointIds are not ordinal-sorted and unique'
    }
}

Write-Output ("1..{0}" -f $script:Passed)
