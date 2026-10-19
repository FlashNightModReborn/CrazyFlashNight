$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$taskRoot=(Get-Location).Path
$taskOut=Join-Path $taskRoot 'tmp/cf6-combat-calibration-20261017/host-r22-final'
if(Test-Path -LiteralPath $taskOut){throw 'Preserve existing host evidence'}
$taskArena=Get-Content -LiteralPath 'tmp/arena-worker-experiments/cf6-cal-r22-full-20261018/experiment-report.json' -Raw -Encoding utf8 | ConvertFrom-Json
if(-not $taskArena.qualified -or $taskArena.status -ne 'completed'){throw 'Current arena execution is still active or unqualified'}
New-Item -ItemType Directory -Path $taskOut | Out-Null
$taskPolicy=Get-Content -LiteralPath 'launcher/tests/xunit.runner.json' -Raw -Encoding utf8 | ConvertFrom-Json
if($taskPolicy.'$schema' -cne 'https://xunit.net/schema/v2.8/xunit.runner.schema.json' -or
   $taskPolicy.diagnosticMessages -isnot [bool] -or -not $taskPolicy.diagnosticMessages -or
   $taskPolicy.parallelizeTestCollections -isnot [bool] -or $taskPolicy.parallelizeTestCollections){throw 'Canonical serial runner policy is invalid'}
. (Join-Path $taskRoot 'launcher/resolve-dotnet.ps1')
& powershell -NoProfile -ExecutionPolicy Bypass -File 'launcher/tests/resolve-dotnet.tests.ps1' *> (Join-Path $taskOut 'sdk-contract.log')
if($LASTEXITCODE -ne 0){throw 'Exact SDK resolver contract failed'}
$taskDotnet=Resolve-Cf7Dotnet -ProjectRoot $taskRoot
$taskVersion=(& $taskDotnet --version | Out-String).Trim()
$taskFamilies=@('WorldCompositorTests','SceneTransitionResumeTests','SceneTransitionTaskTests','SceneTransitionPresentationPolicyTests','MapDomainSessionTests','MapAuthoringContentTests','LauncherCommandRouterTests','TaskRegistryStatusTests','RagTerminalServiceTests')
$taskFilter=($taskFamilies | ForEach-Object {'FullyQualifiedName~'+$_}) -join '|'
& python -X utf8 -B 'tmp/cf6-combat-calibration-20261017/snapshot-r22-host-inputs.py' --output (Join-Path $taskOut 'source-before.json')
if($LASTEXITCODE -ne 0){throw 'Host source snapshot failed'}
$taskStarted=(Get-Date).ToUniversalTime().ToString('o')
$ErrorActionPreference='Continue'
$taskOutput=@(& $taskDotnet test 'launcher/tests/Launcher.Tests.csproj' -c Release --no-restore --filter $taskFilter --logger 'console;verbosity=normal' --logger 'trx;LogFileName=focused.trx' --results-directory $taskOut 2>&1)
$taskCode=$LASTEXITCODE
$ErrorActionPreference='Stop'
$taskOutput | Out-File -LiteralPath (Join-Path $taskOut 'runner.log') -Encoding utf8
$taskMarker='Starting:    Launcher.Tests (parallel test collections = off, stop on fail = off)'
$taskMarkers=@($taskOutput | Where-Object {([string]$_).Contains($taskMarker)}).Count
& python -X utf8 -B 'tmp/cf6-combat-calibration-20261017/snapshot-r22-host-inputs.py' --output (Join-Path $taskOut 'source-after.json')
if($LASTEXITCODE -ne 0){throw 'Host source resnapshot failed'}
$taskSourceSame=(Get-FileHash -LiteralPath (Join-Path $taskOut 'source-before.json')).Hash -ceq (Get-FileHash -LiteralPath (Join-Path $taskOut 'source-after.json')).Hash
[ordered]@{exitCode=$taskCode;serialPolicyMarkerCount=$taskMarkers;sourceUnchanged=$taskSourceSame;dotnet=$taskDotnet;sdk=$taskVersion;filter=$taskFilter;families=$taskFamilies;startedAtUtc=$taskStarted;completedAtUtc=(Get-Date).ToUniversalTime().ToString('o');formalPromotion=$false} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $taskOut 'result.json') -Encoding utf8
if($taskMarkers -ne 1 -or -not $taskSourceSame){throw 'Host serial-policy or source binding failed'}
if($taskCode -ne 0){exit $taskCode}
& python -X utf8 -B 'tmp/cf6-combat-calibration-20261017/collect-r22-host-focused.py'
exit $LASTEXITCODE
