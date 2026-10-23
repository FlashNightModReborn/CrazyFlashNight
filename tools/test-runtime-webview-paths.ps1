param([string]$FixtureBase = [IO.Path]::GetTempPath())
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'runtime-webview-paths.ps1')
$fixture = Join-Path $FixtureBase ('w2-' + [guid]::NewGuid().ToString('N').Substring(0,8))
if (Test-Path -LiteralPath $fixture) { throw "Test fixture already exists: $fixture" }
[void][IO.Directory]::CreateDirectory($fixture)
$passed = 0
$caseNumber = 0
$spec = [pscustomobject]@{cabSha256=('A'*64); extractedDirectory='e'; files=@(@{path='a/data.bin'}); parts=@(@{path='000.cabpart'})}
function Assert-Test($Value, [string]$Message) { if (-not $Value) { throw $Message } }
function New-Case {
    $script:caseNumber++
    $path = Join-Path $fixture ([string]$script:caseNumber)
    [void][IO.Directory]::CreateDirectory($path)
    return $path
}
function Get-Snapshot {
    return (@(Get-ChildItem -LiteralPath $fixture -Recurse -Force | ForEach-Object {
        if ($_.PSIsContainer) { 'D:' + $_.FullName } else { 'F:' + $_.FullName + ':' + (Get-FileHash -LiteralPath $_.FullName).Hash }
    } | Sort-Object) -join "`n")
}
function Reject-WithoutWrites([string]$Name, [scriptblock]$Action, [string]$Expected = 'WebView2|Windows') {
    $before = Get-Snapshot
    $rejected = $false
    try { & $Action | Out-Null } catch {
        Assert-Test ($_.Exception.Message -match $Expected) "Unexpected rejection for $Name`: $($_.Exception.Message)"
        $rejected = $true
    }
    Assert-Test $rejected "Accepted invalid layout: $Name"
    Assert-Test ((Get-Snapshot) -ceq $before) "Rejected layout changed the fixture: $Name"
    $script:passed++
    Write-Host "[PASS] $Name (zero writes)"
}
try {
    $root = New-Case
    $layout = Get-Cf7WebViewLayout -ProjectRoot $root -Spec $spec
    Assert-Test ($layout.cache -ceq (Join-Path $root 'tmp\w2')) 'Wrong short default'
    $passed++; Write-Host '[PASS] default cache projection'
    foreach ($kind in @('cache','extraction','engine','destination')) {
        $root = New-Case
        $cache = Join-Path $root 'c'; $destination = Join-Path $root 'd'
        $layout = Get-Cf7WebViewLayout -ProjectRoot $root -Spec $spec -CacheDirectory $cache -DestinationDirectory $destination
        $target = $layout.$kind
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
        [IO.File]::WriteAllText($target, 'keep-file')
        Reject-WithoutWrites "existing file at $kind directory" { Get-Cf7WebViewLayout -ProjectRoot $root -Spec $spec -CacheDirectory $cache -DestinationDirectory $destination }
    }
    foreach ($kind in @('cab','engine-file','chunk')) {
        $root = New-Case; $cache = Join-Path $root 'c'; $destination = Join-Path $root 'd'
        $layout = Get-Cf7WebViewLayout -ProjectRoot $root -Spec $spec -CacheDirectory $cache -DestinationDirectory $destination
        $target = switch ($kind) { cab {$layout.cab} engine-file {Join-Path $layout.engine 'a\data.bin'} chunk {Join-Path $destination '000.cabpart'} }
        [void][IO.Directory]::CreateDirectory($target)
        Reject-WithoutWrites "existing directory at $kind file" { Get-Cf7WebViewLayout -ProjectRoot $root -Spec $spec -CacheDirectory $cache -DestinationDirectory $destination }
    }
    foreach ($paths in @(@('a','a/b'),@('a/b','a'),@('A/file','a/other'),@('same','SAME'))) {
        $bad = $spec | ConvertTo-Json -Depth 6 | ConvertFrom-Json
        $bad.files = @($paths | ForEach-Object { @{path=$_} })
        $root = New-Case
        Reject-WithoutWrites "lock structure $($paths -join ',')" { Get-Cf7WebViewLayout -ProjectRoot $root -Spec $bad }
        $bad.files = $spec.files; $bad.parts = @($paths | ForEach-Object { @{path=$_} })
        Reject-WithoutWrites "chunk structure $($paths -join ',')" { Get-Cf7WebViewLayout -ProjectRoot $root -Spec $bad -DestinationDirectory (Join-Path $root 'd') }
    }
    foreach ($path in @('relative','\\server\share\x','C:\NUL.txt','C:\bad.','C:\a\..\b','C:\a:b')) {
        Reject-WithoutWrites "invalid Windows root $path" { Assert-Cf7WebViewPath $path }
    }
    $boundary = 'C:\' + (([string][char]0x4e2d) * 237)
    [void](Assert-Cf7WebViewPath $boundary)
    $passed++; Write-Host '[PASS] 240 UTF-16 units accepted'
    Reject-WithoutWrites '241 UTF-16 units rejected' { Assert-Cf7WebViewPath ($boundary + 'x') }
    $surrogate = 'C:\' + ([char]0xd83d).ToString() + ([char]0xde00).ToString() + ('a'*236)
    Reject-WithoutWrites 'surrogate pair counts as two UTF-16 units' { Assert-Cf7WebViewPath $surrogate }
    $root = New-Case
    Reject-WithoutWrites 'deep default cache rejected before writes' { Get-Cf7WebViewLayout -ProjectRoot ('C:\'+('x'*160)) -Spec $spec }
    # Exercise the actual caller preflight/delete/create statements, never the build stages.
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'launcher\build-runtime-candidate.ps1'),[ref]$tokens,[ref]$errors)
    Assert-Test ($errors.Count -eq 0) 'Candidate builder does not parse'
    $statements = @($ast.EndBlock.Statements)
    $preflight = @($statements | Where-Object { $_.Extent.Text -match '^\[void\]\(Get-Cf7WebViewLayout.*-DeploymentRoot' })
    $replace = @($statements | Where-Object { $_.Extent.Text -match '^if \(Test-Path -LiteralPath \$deploymentRoot\)' })
    $create = @($statements | Where-Object { $_.Extent.Text -match '^New-Item -ItemType Directory -Path \$deploymentRoot ' })
    Assert-Test ($preflight.Count -eq 1 -and $replace.Count -eq 1 -and $create.Count -eq 1) 'Cannot isolate candidate replacement boundary'
    Assert-Test ($preflight[0].Extent.StartOffset -lt $replace[0].Extent.StartOffset) 'Preflight occurs after candidate deletion'
    $replaceCode = [scriptblock]::Create(($preflight[0].Extent.Text,$replace[0].Extent.Text,$create[0].Extent.Text -join "`n"))
    foreach ($case in @('cache-file','extraction-file','engine-file','destination-file','cache-inside-candidate','candidate-inside-cache','same-root')) {
        $root=New-Case; $projectRoot=$root; $webViewSpec=$spec; $ForceReplace=$true
        $deploymentRoot=Join-Path $root 'candidate'; [void][IO.Directory]::CreateDirectory($deploymentRoot)
        $sentinel=Join-Path $deploymentRoot 'sentinel'; [IO.File]::WriteAllText($sentinel,'keep-candidate')
        $WebView2CacheDirectory=Join-Path $root 'cache'
        $layout=Get-Cf7WebViewLayout -ProjectRoot $root -Spec $spec -CacheDirectory $WebView2CacheDirectory -DestinationDirectory (Join-Path $deploymentRoot 'runtime\webview2')
        if ($case -like '*-file') {
            $target = switch ($case) { cache-file {$layout.cache} extraction-file {$layout.extraction} engine-file {$layout.engine} destination-file {$layout.destination} }
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target)); [IO.File]::WriteAllText($target,'keep-file')
        } elseif ($case -eq 'cache-inside-candidate') { $WebView2CacheDirectory=Join-Path $deploymentRoot 'cache' }
        elseif ($case -eq 'candidate-inside-cache') { $WebView2CacheDirectory=$root }
        else { $WebView2CacheDirectory=$deploymentRoot }
        Reject-WithoutWrites "ForceReplace preserves candidate for $case" { & $replaceCode }
        Assert-Test ([IO.File]::ReadAllText($sentinel) -ceq 'keep-candidate') "Candidate sentinel deleted: $case"
    }
    $root = New-Case
    $target = Join-Path $root 'target'; [void][IO.Directory]::CreateDirectory($target)
    $junction = Join-Path $root 'link'
    try {
        [void](New-Item -ItemType Junction -Path $junction -Target $target)
        Reject-WithoutWrites 'reparse ancestor rejected' { Get-Cf7WebViewLayout -ProjectRoot $root -Spec $spec -CacheDirectory (Join-Path $junction 'cache') }
    } finally { if (Test-Path -LiteralPath $junction) { Remove-Item -LiteralPath $junction -Force } }
    $actual=Get-Content -LiteralPath (Join-Path $repoRoot 'launcher\webview2-runtime.lock.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    [void](Get-Cf7WebViewLayout -ProjectRoot C:\cf7v147 -Spec $actual)
    $passed++; Write-Host '[PASS] real locked 257-file default projection (no extraction)'
    # Exercise the actual worker argument/preflight function with the real lock,
    # including the request/worker/job/src nesting missed by the short-root case.
    $workerPath=Join-Path $repoRoot 'tools\invoke-runtime-build-worker.ps1'
    $workerTokens=$null; $workerErrors=$null
    $workerAst=[Management.Automation.Language.Parser]::ParseFile($workerPath,[ref]$workerTokens,[ref]$workerErrors)
    Assert-Test ($workerErrors.Count -eq 0) 'Runtime worker does not parse'
    $workerFunction=@($workerAst.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-Cf7WorkerProducerArguments'},$true))
    Assert-Test ($workerFunction.Count -eq 1) 'Missing unique worker path preflight'
    . ([scriptblock]::Create($workerFunction[0].Extent.Text))
    $root=New-Case
    $checkout=Join-Path $root 'runtime-build-checkouts\123456789abc-1234567890-12345678\src'
    [void][IO.Directory]::CreateDirectory((Join-Path $checkout 'tools'))
    [void][IO.Directory]::CreateDirectory((Join-Path $checkout 'launcher'))
    Copy-Item -LiteralPath (Join-Path $repoRoot 'tools\runtime-webview-paths.ps1') -Destination (Join-Path $checkout 'tools\runtime-webview-paths.ps1')
    Copy-Item -LiteralPath (Join-Path $repoRoot 'launcher\webview2-runtime.lock.json') -Destination (Join-Path $checkout 'launcher\webview2-runtime.lock.json')
    $candidate=Join-Path $root 'candidate'
    Reject-WithoutWrites 'real worker nested default rejects before producer launch' {
        Get-Cf7WorkerProducerArguments -Checkout $checkout -CandidateRoot $candidate -BuilderId 'fixture'
    } '240 UTF-16'
    $shortCache=Join-Path ([IO.Path]::GetPathRoot($fixture)) ('w2-ci-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    $before=Get-Snapshot
    $workerArguments=@(Get-Cf7WorkerProducerArguments -Checkout $checkout -CandidateRoot $candidate -BuilderId 'fixture' -WebView2CacheDirectory $shortCache)
    $cacheIndex=[Array]::IndexOf($workerArguments,'-WebView2CacheDirectory')
    Assert-Test ($cacheIndex -ge 0 -and $workerArguments[$cacheIndex+1] -ceq $shortCache) 'Worker did not forward the validated cache'
    Assert-Test ($workerArguments[[Array]::IndexOf($workerArguments,'-File')+1] -ceq (Join-Path $checkout 'launcher\build-runtime-candidate.ps1')) 'Worker selected a different producer'
    Assert-Test ((Get-Snapshot) -ceq $before -and -not (Test-Path -LiteralPath $shortCache)) 'Worker preflight wrote files'
    $passed++; Write-Host '[PASS] real worker nested layout with explicit short cache (zero writes)'
    Reject-WithoutWrites 'worker rejects overlong explicit cache before producer launch' {
        Get-Cf7WorkerProducerArguments -Checkout $checkout -CandidateRoot $candidate -BuilderId 'fixture' -WebView2CacheDirectory ('C:\'+('x'*100))
    } '240 UTF-16'
    Reject-WithoutWrites 'worker rejects cache inside candidate before producer launch' {
        Get-Cf7WorkerProducerArguments -Checkout $checkout -CandidateRoot 'C:\w2-ci-candidate' -BuilderId 'fixture' -WebView2CacheDirectory 'C:\w2-ci-candidate\cache'
    } 'overlap'
    $workerText=[IO.File]::ReadAllText($workerPath)
    Assert-Test ($workerText.Contains('$producerArguments = Get-Cf7WorkerProducerArguments -Checkout $checkout') -and
        $workerText.Contains('-Arguments $producerArguments -WorkingDirectory $checkout')) 'Default worker bypasses path preflight or validated producer arguments'
    $passed++; Write-Host '[PASS] default worker launch uses the checked arguments'
    $deepDevRoot = 'C:\' + ('r' * 89)
    $devCache = Join-Path $env:LOCALAPPDATA 'CF7BuildCache\w2'
    $before = Get-Snapshot
    $devLayout = Get-Cf7WebViewLayout -ProjectRoot $deepDevRoot -Spec $actual -CacheDirectory $devCache
    Assert-Test ($devLayout.cache -ceq $devCache) 'Explicit current-user dev cache was not preserved'
    Assert-Test ((Get-Snapshot) -ceq $before) 'Actual-lock dev preflight wrote filesystem state'
    $passed++; Write-Host '[PASS] 92-unit development root with user-local cache (no extraction)'
    Reject-WithoutWrites 'non-Windows cache remains rejected by lower preflight' { Get-Cf7WebViewLayout -ProjectRoot $repoRoot -Spec $actual -CacheDirectory '/not-a-windows-cache' }

    $inputs=Get-Content -LiteralPath (Join-Path $repoRoot 'config\build\runtime-inputs.v2.json') -Raw -Encoding UTF8|ConvertFrom-Json
    Assert-Test (@($inputs.domains.policy.fixedFiles | Where-Object {$_ -ceq 'tools/test-runtime-webview-paths.ps1'}).Count -eq 1) 'Test missing exact policy binding'
    $gate=Get-Content -LiteralPath (Join-Path $repoRoot 'config\build\native-change-gate.v1.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $workflow=[IO.File]::ReadAllText((Join-Path $repoRoot '.github\workflows\runtime-bundle-integrity.yml'))
    Assert-Test ('tools/test-runtime-' -cin $gate.protectedPrefixes -and $workflow.Contains('      - tools/test-runtime-**')) 'Maintained test missing native/CI prefix coverage'
    $passed++; Write-Host '[PASS] maintained policy/native/CI closure'
} finally {
    $resolved=[IO.Path]::GetFullPath($fixture)
    $base=[IO.Path]::GetFullPath($FixtureBase).TrimEnd('\')
    if ((Split-Path -Parent $resolved) -ieq $base -and (Split-Path -Leaf $resolved) -match '^w2-[0-9a-f]{8}$') { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
Write-Host "[WebViewPathTests] passed=$passed failed=0"
