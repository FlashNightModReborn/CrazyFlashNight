param([string]$DotnetExe,[string]$GoExe,[string]$OutputRoot)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$repoRoot=Split-Path (Split-Path $PSScriptRoot)
if(!$DotnetExe){$DotnetExe=Join-Path $env:LOCALAPPDATA 'Microsoft/dotnet/dotnet.exe'}
if(!$GoExe){$GoExe=Join-Path $repoRoot 'tmp/field-support-build/go/bin/go.exe'}
if(!$OutputRoot){$OutputRoot=Join-Path $repoRoot 'tmp/field-support-packages'}
if((& $DotnetExe --version).Trim() -ne '10.0.300'){throw 'This candidate build uses .NET SDK 10.0.300'}
if((& $GoExe version) -notmatch 'go1\.27\.1 windows/amd64'){throw 'This candidate build uses Go 1.27.1 windows/amd64'}
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$version=([xml](Get-Content -LiteralPath (Join-Path $PSScriptRoot 'FieldSupport.csproj') -Raw)).Project.PropertyGroup.Version
$package=Join-Path $OutputRoot ('cf7-field-support-'+$version+'-'+$stamp+'-win-x64')
if(Test-Path -LiteralPath $package){throw 'Package already exists'}
New-Item -ItemType Directory -Path $package -Force | Out-Null
$env:GOCACHE=Join-Path $repoRoot 'tmp/field-support-build/go-cache'
$env:GOMODCACHE=Join-Path $repoRoot 'tmp/field-support-build/go-modules'
$env:CGO_ENABLED='0'
Push-Location (Join-Path $PSScriptRoot 'network')
try {
    & $GoExe mod verify
    if($LASTEXITCODE){throw 'Go module verification failed'}
    & $GoExe build -mod=readonly -trimpath '-ldflags=-s -w' -o (Join-Path $package 'cf7-network.exe') .
    if($LASTEXITCODE){throw 'Network helper build failed'}
    $modules=@(& $GoExe list -m -f '{{.Path}}|{{.Version}}|{{.Dir}}' all)
    if($LASTEXITCODE){throw 'Cannot enumerate network dependencies'}
} finally {Pop-Location}
& $DotnetExe publish (Join-Path $PSScriptRoot 'FieldSupport.csproj') -c Release -r win-x64 --self-contained true -p:RestoreLockedMode=true -o $package --nologo
if($LASTEXITCODE){throw 'C# publish failed'}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.md') -Destination (Join-Path $package '使用说明.md')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'acceptance.md') -Destination (Join-Path $package '双机验收清单.md')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'verify-package.ps1') -Destination $package
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'examples') -Destination $package -Recurse
[IO.File]::WriteAllText((Join-Path $package '启动现场助手.cmd'),"@echo off`r`nstart `"`" `"%~dp0cf7-support.exe`" gui`r`n",[Text.Encoding]::ASCII)
$notices=Join-Path $package 'third-party-notices'
New-Item -ItemType Directory -Path $notices | Out-Null
Copy-Item -LiteralPath (Join-Path (Split-Path $DotnetExe) 'ThirdPartyNotices.txt') -Destination (Join-Path $notices 'dotnet-ThirdPartyNotices.txt')
Copy-Item -LiteralPath (Join-Path (Split-Path $DotnetExe) 'LICENSE.txt') -Destination (Join-Path $notices 'dotnet-LICENSE.txt')
Copy-Item -LiteralPath (Join-Path (Split-Path (Split-Path $GoExe)) 'LICENSE') -Destination (Join-Path $notices 'go-LICENSE.txt')
foreach($module in $modules){
    $parts=$module.Split('|');if($parts.Length -lt 3 -or !$parts[2] -or $parts[0] -eq 'cf7-field-network'){continue}
    $folder=Join-Path $notices ($parts[0] -replace '[^A-Za-z0-9._-]','_')
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    Get-ChildItem -LiteralPath $parts[2] -File | Where-Object {$_.Name -match '^(LICENSE|COPYING|NOTICE)'} | Copy-Item -Destination $folder
}
$modules | Set-Content (Join-Path $notices 'modules.txt') -Encoding UTF8
# Do not leak local module-cache paths into the distributable inventory.
($modules | ForEach-Object { $p=$_.Split('|'); $p[0]+'|'+$p[1] }) | Set-Content (Join-Path $notices 'modules.txt') -Encoding UTF8
$source=@(Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -File | Where-Object {$_.FullName -notmatch '[\\/](bin|obj|dist)[\\/]' -and $_.Extension -notin @('.exe','.pdb')} | ForEach-Object {
    [ordered]@{path=$_.FullName.Substring($PSScriptRoot.Length+1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash;size=$_.Length}
})
$canonical=[string[]]@($source | ForEach-Object { $_.path+"`t"+$_.size+"`t"+$_.sha256 })
[Array]::Sort($canonical,[StringComparer]::Ordinal)
$hash=[Security.Cryptography.SHA256]::Create()
try{$sourceHash=([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes(($canonical -join "`n")+"`n")))).Replace('-','')}finally{$hash.Dispose()}
$head=(& git -C $repoRoot rev-parse HEAD).Trim()
$identity=[ordered]@{schema='cf7-field-support-build.v1';version=$version;buildId=$stamp;sourceBaseCommit=$head;sourceSnapshotSha256=$sourceHash;sourceState='uncommitted_candidate';sdk='10.0.300';go='1.27.1';tailscale='1.102.4';qualification='local_checks_only_pending_two_machine_acceptance';files=$source}
$identity | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $package 'build-info.json') -Encoding UTF8
$testOutput=Join-Path $OutputRoot ('checks-'+$stamp)
& (Join-Path $package 'cf7-support.exe') selftest --output $testOutput
if($LASTEXITCODE){throw 'Packaged executable self-test failed; do not distribute this directory'}
Copy-Item -LiteralPath (Join-Path $testOutput 'test-report.json') -Destination (Join-Path $package 'local-checks.json')
& (Join-Path $package 'cf7-support.exe') layout-check (Join-Path $testOutput 'layout-report.json')
if($LASTEXITCODE){throw 'Populated GUI layout check failed'}
Copy-Item -LiteralPath (Join-Path $testOutput 'layout-report.json') -Destination (Join-Path $package 'layout-checks.json')
$inventory=@(Get-ChildItem -LiteralPath $package -Recurse -File | ForEach-Object {
    [ordered]@{path=$_.FullName.Substring($package.Length+1).Replace('\','/');size=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
})
[ordered]@{schema='cf7-field-support-package.v1';files=$inventory} | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $package 'package-manifest.json') -Encoding UTF8
& (Join-Path $package 'verify-package.ps1') -PackageRoot $package
if($LASTEXITCODE){throw 'Package integrity check failed'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($package,$package+'.zip',[IO.Compression.CompressionLevel]::Optimal,$true)
$zip=Get-Item -LiteralPath ($package+'.zip')
[ordered]@{package=$package;zip=$zip.FullName;bytes=$zip.Length;sha256=(Get-FileHash -LiteralPath $zip.FullName -Algorithm SHA256).Hash;sourceSnapshotSha256=$sourceHash} | ConvertTo-Json
