param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$submitScript = Join-Path $repoRoot 'tools\submit-contribution.ps1'
$commonScript = Join-Path $repoRoot 'tools\contribution-common.ps1'
$launcherScript = Join-Path $repoRoot '一键提交到主线.cmd'
$powerShellExecutable = (Get-Process -Id $PID).Path
$gitExecutable = (Get-Command git.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Path
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("cf7-contribution-tests-" + [Guid]::NewGuid().ToString('N'))
$utf8NoBom = New-Object Text.UTF8Encoding($false)
$passed = 0
$failed = 0
$validLaneConfiguration = @'
{
  "schema": "cf7-contribution-lanes.v1",
  "docsPrefixes": ["docs/"],
  "contentPrefixes": [
    "flashswf/arts/",
    "flashswf/backgrounds/",
    "flashswf/images/",
    "flashswf/levels/",
    "flashswf/miniGames/",
    "flashswf/movies/",
    "flashswf/portraits/",
    "flashswf/skybox/",
    "flashswf/UI/",
    "music/",
    "sounds/",
    "闪7重置版字体/",
    "data/",
    "xml/",
    "config/"
  ]
}
'@

function Set-TestFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        [void](New-Item -ItemType Directory -Path $parent -Force)
    }
    [IO.File]::WriteAllText($Path, $Content, $script:utf8NoBom)
}

function Invoke-TestNative {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [switch]$AllowFailure
    )

    $previousErrorActionPreference = $ErrorActionPreference
    Push-Location -LiteralPath $WorkingDirectory
    try {
        $ErrorActionPreference = 'Continue'
        $lines = @(& $FilePath @Arguments 2>&1 | ForEach-Object { [string]$_ })
        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) { $exitCode = 0 }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        Pop-Location
    }
    $result = [pscustomobject]@{ ExitCode = [int]$exitCode; Lines = @($lines); Text = (@($lines) -join "`n").Trim() }
    if (-not $AllowFailure -and $result.ExitCode -ne 0) {
        throw "测试命令失败：$FilePath $($Arguments -join ' ')`n$($result.Text)"
    }
    return $result
}

function Invoke-TestGit {
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string[]]$Arguments, [switch]$AllowFailure)

    return Invoke-TestNative -FilePath $script:gitExecutable -Arguments $Arguments -WorkingDirectory $Root -AllowFailure:$AllowFailure
}

function Assert-Test {
    param([Parameter(Mandatory = $true)][bool]$Condition, [Parameter(Mandatory = $true)][string]$Message)

    if (-not $Condition) { throw $Message }
}

function Invoke-TestCase {
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][scriptblock]$Body)

    try {
        & $Body
        $script:passed++
        Write-Host "[PASS] $Name"
    }
    catch {
        $script:failed++
        Write-Host "[FAIL] $Name :: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function New-FakeGitHubCli {
    param([Parameter(Mandatory = $true)][string]$Path)

    Set-TestFile -Path $Path -Content @'
$ErrorActionPreference = 'Stop'
$statePath = $env:CF7_FAKE_GH_STATE
$logPath = $env:CF7_FAKE_GH_LOG
if (-not $statePath -or -not $logPath) { throw 'fake gh environment is missing' }
$arguments = @($args | ForEach-Object { [string]$_ })
[IO.File]::AppendAllText($logPath, (($arguments -join "`t") + "`n"))

function Read-State {
    if (-not (Test-Path -LiteralPath $statePath)) {
        return [pscustomobject][ordered]@{
            exists = $false
            number = 101
            state = 'OPEN'
            isDraft = $false
            url = 'https://example.invalid/pull/101'
            mergedAt = $null
            autoMerge = $false
        }
    }
    return Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
}

function Save-State($state) {
    [IO.File]::WriteAllText($statePath, (($state | ConvertTo-Json -Depth 6 -Compress) + "`n"), (New-Object Text.UTF8Encoding($false)))
}

function Convert-StateToPr($state) {
    return [pscustomobject][ordered]@{
        number = [int]$state.number
        state = [string]$state.state
        isDraft = [bool]$state.isDraft
        url = [string]$state.url
        mergedAt = $state.mergedAt
        autoMergeRequest = if ([bool]$state.autoMerge) { [pscustomobject]@{ mergeMethod = 'MERGE' } } else { $null }
    }
}

if ($arguments.Count -ge 2 -and $arguments[0] -eq 'auth' -and $arguments[1] -eq 'status') {
    'fake gh authenticated'
    exit 0
}
if ($arguments.Count -lt 2 -or $arguments[0] -ne 'pr') { throw "unsupported fake gh call: $($arguments -join ' ')" }
$state = Read-State
switch ($arguments[1]) {
    'list' {
        if ([bool]$state.exists) {
            $array = @((Convert-StateToPr $state))
            ConvertTo-Json -InputObject $array -Depth 6 -Compress
        }
        else { '[]' }
    }
    'create' {
        $state.exists = $true
        $state.state = 'OPEN'
        $state.isDraft = $false
        Save-State $state
        [string]$state.url
    }
    'ready' {
        $state.isDraft = $false
        Save-State $state
        [string]$state.url
    }
    'merge' {
        $state.autoMerge = $true
        if ($env:CF7_FAKE_GH_AUTO_COMPLETE -eq '1') {
            $branch = (& $env:CF7_FAKE_GIT -C $env:CF7_FAKE_GH_WORK symbolic-ref --quiet --short HEAD 2>&1 | Select-Object -Last 1)
            if ($LASTEXITCODE -ne 0 -or -not $branch) { throw 'fake gh could not resolve contribution branch' }
            & $env:CF7_FAKE_GIT "--git-dir=$($env:CF7_FAKE_GH_BARE)" update-ref refs/heads/main "refs/heads/$branch"
            if ($LASTEXITCODE -ne 0) { throw 'fake gh could not advance main' }
            $state.state = 'MERGED'
            $state.mergedAt = '2026-07-18T12:00:00Z'
        }
        Save-State $state
        'auto merge enabled'
    }
    'view' {
        ConvertTo-Json -InputObject (Convert-StateToPr $state) -Depth 6 -Compress
    }
    default { throw "unsupported fake gh pr call: $($arguments -join ' ')" }
}
'@
}

function New-TestFixture {
    $fixtureRoot = Join-Path $script:testRoot ([Guid]::NewGuid().ToString('N'))
    $bare = Join-Path $fixtureRoot 'origin.git'
    $seed = Join-Path $fixtureRoot 'seed'
    $work = Join-Path $fixtureRoot 'work'
    [void](New-Item -ItemType Directory -Path $fixtureRoot -Force)
    [void](New-Item -ItemType Directory -Path $seed -Force)
    [void](Invoke-TestGit -Root $seed -Arguments @('init'))
    [void](Invoke-TestGit -Root $seed -Arguments @('config', 'user.name', 'CF7 Test Seed'))
    [void](Invoke-TestGit -Root $seed -Arguments @('config', 'user.email', 'seed@example.invalid'))
    [void](Invoke-TestGit -Root $seed -Arguments @('config', 'core.autocrlf', 'false'))
    Set-TestFile -Path (Join-Path $seed 'baseline.txt') -Content "baseline`n"
    Set-TestFile -Path (Join-Path $seed 'config\build\contribution-lanes.v1.json') -Content ($script:validLaneConfiguration + "`n")
    [void](Invoke-TestGit -Root $seed -Arguments @('add', '-A'))
    [void](Invoke-TestGit -Root $seed -Arguments @('commit', '-m', 'baseline'))
    [void](Invoke-TestGit -Root $seed -Arguments @('branch', '-M', 'main'))
    [void](Invoke-TestGit -Root $fixtureRoot -Arguments @('init', '--bare', $bare))
    [void](Invoke-TestGit -Root $seed -Arguments @('remote', 'add', 'origin', $bare))
    [void](Invoke-TestGit -Root $seed -Arguments @('push', '-u', 'origin', 'main'))
    [void](Invoke-TestGit -Root $fixtureRoot -Arguments @('--git-dir', $bare, 'symbolic-ref', 'HEAD', 'refs/heads/main'))
    [void](Invoke-TestGit -Root $fixtureRoot -Arguments @('-c', 'core.autocrlf=false', 'clone', $bare, $work))
    [void](Invoke-TestGit -Root $work -Arguments @('config', 'user.name', 'CF7 Test Contributor'))
    [void](Invoke-TestGit -Root $work -Arguments @('config', 'user.email', 'contributor@example.invalid'))
    [void](Invoke-TestGit -Root $work -Arguments @('config', 'core.autocrlf', 'false'))

    $state = Join-Path $fixtureRoot 'fake-gh-state.json'
    $log = Join-Path $fixtureRoot 'fake-gh.log'
    Set-TestFile -Path $state -Content '{"exists":false,"number":101,"state":"OPEN","isDraft":false,"url":"https://example.invalid/pull/101","mergedAt":null,"autoMerge":false}'
    Set-TestFile -Path $log -Content ''
    return [pscustomobject]@{ Root = $fixtureRoot; Bare = $bare; Seed = $seed; Work = $work; State = $state; Log = $log }
}

function Add-TestCommit {
    param(
        [Parameter(Mandatory = $true)]$Fixture,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Content
    )

    Set-TestFile -Path (Join-Path $Fixture.Work ($RelativePath -replace '/', '\')) -Content $Content
    [void](Invoke-TestGit -Root $Fixture.Work -Arguments @('add', '--', $RelativePath))
    [void](Invoke-TestGit -Root $Fixture.Work -Arguments @('commit', '-m', "change $RelativePath"))
}

function Invoke-SubmitTest {
    param(
        [Parameter(Mandatory = $true)]$Fixture,
        [switch]$Wait,
        [switch]$AutoComplete,
        [switch]$HumanOutput,
        [switch]$AllowFailure
    )

    $oldState = $env:CF7_FAKE_GH_STATE
    $oldLog = $env:CF7_FAKE_GH_LOG
    $oldAutoComplete = $env:CF7_FAKE_GH_AUTO_COMPLETE
    $oldWork = $env:CF7_FAKE_GH_WORK
    $oldBare = $env:CF7_FAKE_GH_BARE
    $oldGit = $env:CF7_FAKE_GIT
    $env:CF7_FAKE_GH_STATE = $Fixture.State
    $env:CF7_FAKE_GH_LOG = $Fixture.Log
    $env:CF7_FAKE_GH_AUTO_COMPLETE = if ($AutoComplete) { '1' } else { '0' }
    $env:CF7_FAKE_GH_WORK = $Fixture.Work
    $env:CF7_FAKE_GH_BARE = $Fixture.Bare
    $env:CF7_FAKE_GIT = $script:gitExecutable
    try {
        $submitArguments = @(
            '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:submitScript,
            '-ProjectRoot', $Fixture.Work, '-GitExecutablePath', $script:gitExecutable,
            '-GitHubCliPath', $script:fakeGh
        )
        if (-not $HumanOutput) { $submitArguments += '-Json' }
        if ($Wait) { $submitArguments += @('-Wait', '-WaitTimeoutSeconds', '2') }
        $result = Invoke-TestNative -FilePath $script:powerShellExecutable -Arguments $submitArguments -WorkingDirectory $Fixture.Work -AllowFailure:$AllowFailure
    }
    finally {
        $env:CF7_FAKE_GH_STATE = $oldState
        $env:CF7_FAKE_GH_LOG = $oldLog
        $env:CF7_FAKE_GH_AUTO_COMPLETE = $oldAutoComplete
        $env:CF7_FAKE_GH_WORK = $oldWork
        $env:CF7_FAKE_GH_BARE = $oldBare
        $env:CF7_FAKE_GIT = $oldGit
    }
    $jsonLine = @($result.Lines | Where-Object { $_ -match '^\s*\{' } | Select-Object -Last 1)
    $payload = $null
    if ($jsonLine.Count -eq 1) {
        try { $payload = $jsonLine[0] | ConvertFrom-Json }
        catch { throw "无法解析工具 JSON：$($result.Text)" }
    }
    return [pscustomobject]@{ ExitCode = $result.ExitCode; Text = $result.Text; Payload = $payload }
}

[void](New-Item -ItemType Directory -Path $testRoot -Force)
$fakeGh = Join-Path $testRoot 'fake-gh.ps1'
New-FakeGitHubCli -Path $fakeGh
. $commonScript

try {
    Invoke-TestCase 'PowerShell AST 与危险命令静态检查' {
        foreach ($path in @($script:commonScript, $script:submitScript)) {
            $tokens = $null
            $errors = $null
            [void][Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
            Assert-Test ($errors.Count -eq 0) "$path 存在 PowerShell 语法错误：$($errors | ForEach-Object Message -join '; ')"
        }
        $productionText = [IO.File]::ReadAllText($script:commonScript) + "`n" + [IO.File]::ReadAllText($script:submitScript) + "`n" + [IO.File]::ReadAllText($script:launcherScript)
        $forbiddenPatterns = @(
            '(?im)(?:^|[\s,''"])reset(?:$|[\s,''"])',
            '(?im)(?:^|[\s,''"])rebase(?:$|[\s,''"])',
            '(?im)--force(?:-with-lease)?\b',
            '(?m)[''"]branch[''"][^\r\n]*[''"]-D[''"]'
        )
        foreach ($pattern in $forbiddenPatterns) {
            Assert-Test (-not [regex]::IsMatch($productionText, $pattern)) "生产入口命中了危险命令模式：$pattern"
        }
        $launcherText = [IO.File]::ReadAllText($script:launcherScript)
        Assert-Test ($launcherText -match '(?i)-Wait(?:\s|%)') '根双击入口没有默认启用快速通道等待与收尾'
    }

    Invoke-TestCase '根双击入口在带空格路径中完整传递 ProjectRoot 与 Wait' {
        $launcherFixtureRoot = Join-Path $script:testRoot 'cmd root with spaces'
        $launcherFixture = Join-Path $launcherFixtureRoot '一键提交到主线.cmd'
        $probeScript = Join-Path $launcherFixtureRoot 'tools\submit-contribution.ps1'
        [void](New-Item -ItemType Directory -Path $launcherFixtureRoot -Force)
        Copy-Item -LiteralPath $script:launcherScript -Destination $launcherFixture
        Set-TestFile -Path $probeScript -Content @'
param(
    [string]$ProjectRoot,
    [switch]$Wait
)

$expectedRoot = [IO.Path]::GetFullPath((Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))).TrimEnd([char[]]@('\', '/'))
$actualRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd([char[]]@('\', '/'))
if (-not [string]::Equals($expectedRoot, $actualRoot, [StringComparison]::OrdinalIgnoreCase)) {
    Write-Error "ProjectRoot mismatch: <$ProjectRoot>"
    exit 23
}
if (-not $Wait) {
    Write-Error 'Wait missing'
    exit 24
}
Write-Host "PROBE_ROOT=$actualRoot"
'@

        $oldNoPause = $env:CF7_NO_PAUSE
        try {
            $env:CF7_NO_PAUSE = '1'
            $result = Invoke-TestNative -FilePath $launcherFixture -Arguments @() -WorkingDirectory $launcherFixtureRoot
        }
        finally {
            $env:CF7_NO_PAUSE = $oldNoPause
        }

        $normalizedFixtureRoot = [IO.Path]::GetFullPath($launcherFixtureRoot).TrimEnd([char[]]@('\', '/'))
        Assert-Test ($result.ExitCode -eq 0) "根双击入口探针失败：$($result.Text)"
        Assert-Test ($result.Text -match ('(?m)^PROBE_ROOT=' + [regex]::Escape($normalizedFixtureRoot) + '$')) "根双击入口没有原样传递项目根路径：$($result.Text)"
    }

    Invoke-TestCase 'Git 可执行文件支持显式路径与 GitHub Desktop 自动发现' {
        $originalPath = $env:PATH
        $originalProgramFiles = $env:ProgramFiles
        $originalProgramFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
        $originalLocalAppData = $env:LOCALAPPDATA
        try {
            $explicit = Resolve-ContributionGitExecutable -GitExecutablePath $script:gitExecutable
            Assert-Test ([string]::Equals($explicit, [IO.Path]::GetFullPath($script:gitExecutable), [StringComparison]::OrdinalIgnoreCase)) '显式 Git 路径解析错误'

            $fakeLocalAppData = Join-Path $script:testRoot 'fake-local-app-data'
            $bundledGit = Join-Path $fakeLocalAppData 'GitHubDesktop\app-9.9.9\resources\app\git\cmd\git.exe'
            Set-TestFile -Path $bundledGit -Content 'fake git fixture'
            $env:PATH = ''
            $env:ProgramFiles = Join-Path $script:testRoot 'missing-program-files'
            [Environment]::SetEnvironmentVariable('ProgramFiles(x86)', (Join-Path $script:testRoot 'missing-program-files-x86'), 'Process')
            $env:LOCALAPPDATA = $fakeLocalAppData
            $desktopResolved = Resolve-ContributionGitExecutable
            Assert-Test ([string]::Equals($desktopResolved, [IO.Path]::GetFullPath($bundledGit), [StringComparison]::OrdinalIgnoreCase)) '未自动发现 GitHub Desktop bundled Git'

            $env:LOCALAPPDATA = Join-Path $script:testRoot 'missing-local-app-data'
            $missingMessage = $null
            try { [void](Resolve-ContributionGitExecutable) }
            catch { $missingMessage = $_.Exception.Message }
            Assert-Test ([string]$missingMessage -match '未找到 Git') "Git 缺失诊断不是中文明确错误：$missingMessage"
            Assert-Test ([string]$missingMessage -match 'Git for Windows|GitHub Desktop|-GitExecutablePath') "Git 缺失诊断没有给出解决办法：$missingMessage"
        }
        finally {
            $env:PATH = $originalPath
            $env:ProgramFiles = $originalProgramFiles
            [Environment]::SetEnvironmentVariable('ProgramFiles(x86)', $originalProgramFilesX86, 'Process')
            $env:LOCALAPPDATA = $originalLocalAppData
        }
    }

    Invoke-TestCase 'PATH 中没有 Git 时提交入口仍全程使用显式 Git 路径' {
        $fixture = New-TestFixture
        Add-TestCommit -Fixture $fixture -RelativePath 'docs/explicit-git.md' -Content "explicit git`n"
        $originalPath = $env:PATH
        try {
            $env:PATH = ''
            $result = Invoke-SubmitTest -Fixture $fixture
        }
        finally {
            $env:PATH = $originalPath
        }
        Assert-Test ($result.ExitCode -eq 0) "显式 Git 路径没有贯穿提交流程：$($result.Text)"
        Assert-Test ($result.Payload.status -eq 'pr-created' -and $result.Payload.lane -eq 'docs') '无 PATH 提交结果错误'
    }

    Invoke-TestCase '未完成 Git 操作状态在文件干净时仍被显式阻断' {
        $operationMarkers = @(
            [pscustomobject]@{ Path = 'MERGE_HEAD'; Directory = $false },
            [pscustomobject]@{ Path = 'CHERRY_PICK_HEAD'; Directory = $false },
            [pscustomobject]@{ Path = 'REVERT_HEAD'; Directory = $false },
            [pscustomobject]@{ Path = 'rebase-merge'; Directory = $true },
            [pscustomobject]@{ Path = 'rebase-apply'; Directory = $true },
            [pscustomobject]@{ Path = 'sequencer'; Directory = $true },
            [pscustomobject]@{ Path = 'BISECT_LOG'; Directory = $false },
            [pscustomobject]@{ Path = 'BISECT_START'; Directory = $false }
        )
        foreach ($marker in $operationMarkers) {
            $fixture = New-TestFixture
            $metadataPath = (Invoke-TestGit -Root $fixture.Work -Arguments @('rev-parse', '--git-path', [string]$marker.Path)).Text.Trim()
            if (-not [IO.Path]::IsPathRooted($metadataPath)) { $metadataPath = Join-Path $fixture.Work $metadataPath }
            if ([bool]$marker.Directory) { [void](New-Item -ItemType Directory -Path $metadataPath -Force) }
            else { Set-TestFile -Path $metadataPath -Content "fixture`n" }

            $message = $null
            try { Assert-ContributionClean -ProjectRoot $fixture.Work }
            catch { $message = $_.Exception.Message }
            Assert-Test ([string]$message -match '未完成的 Git 操作状态') "操作标记 $($marker.Path) 未被显式阻断：$message"
        }

        $submissionFixture = New-TestFixture
        $sequencerPath = (Invoke-TestGit -Root $submissionFixture.Work -Arguments @('rev-parse', '--git-path', 'sequencer')).Text.Trim()
        if (-not [IO.Path]::IsPathRooted($sequencerPath)) { $sequencerPath = Join-Path $submissionFixture.Work $sequencerPath }
        [void](New-Item -ItemType Directory -Path $sequencerPath -Force)
        $submission = Invoke-SubmitTest -Fixture $submissionFixture -AllowFailure
        Assert-Test ($submission.ExitCode -ne 0) '未完成 Git 操作意外进入提交流程'
        Assert-Test ([string]$submission.Payload.error -match '未完成的 Git 操作状态') "提交入口错误不清楚：$($submission.Payload.error)"
        Assert-Test ((Get-ContributionCurrentBranch -ProjectRoot $submissionFixture.Work) -eq 'main') '操作状态阻断后分支发生变化'
    }

    Invoke-TestCase '路径通道分类完整且 config/build 提升检查级别' {
        $fixture = New-TestFixture
        $configuration = Read-ContributionLaneConfiguration -ProjectRoot $fixture.Work -TrustedRevision 'refs/remotes/origin/main'
        Assert-Test ((Get-ContributionLane -Paths @('docs/note.md', 'docs/assets/diagram.png') -Configuration $configuration) -eq 'docs') 'docs 通道分类错误'
        Assert-Test ((Get-ContributionLane -Paths @('flashswf/arts/item.fla', 'flashswf/UI/panel.fla', 'data/items.xml') -Configuration $configuration) -eq 'content') 'content 通道分类错误'
        Assert-Test ((Get-ContributionLane -Paths @('config/build/runtime.json') -Configuration $configuration) -eq 'restricted') 'config/build 未提升检查级别'
        Assert-Test ((Get-ContributionLane -Paths @('docs/note.md', 'data/items.xml') -Configuration $configuration) -eq 'content') 'docs + content 联合快速通道分类错误'
        Assert-Test ((Get-ContributionLane -Paths @('flashswf/_ruffle/tool.js') -Configuration $configuration) -eq 'mixed') 'flashswf 未知子树不应进入内容快速通道'
        Assert-Test ((Get-ContributionLane -Paths @('UI/panel.fla') -Configuration $configuration) -eq 'mixed') '不存在的根级 UI 不应进入内容快速通道'
        Assert-Test ((Get-ContributionLane -Paths @('Docs/note.md') -Configuration $configuration) -eq 'mixed') '大小写伪装的 Docs 不应进入快速通道'
        Assert-Test ((Get-ContributionLane -Paths @('Data/items.xml') -Configuration $configuration) -eq 'mixed') '大小写伪装的 Data 不应进入快速通道'
        Assert-Test ((Get-ContributionLane -Paths @('Config/build/runtime.json') -Configuration $configuration) -eq 'restricted') '大小写伪装的 config/build 必须被保守拦截'
        foreach ($abnormalPath in @("data/a`rb.xml", "data/a`nb.xml", ("data/a" + [char]0 + 'b.xml'), 'data\quoted.xml')) {
            $threw = $false
            try { [void](Get-ContributionLane -Paths @($abnormalPath) -Configuration $configuration) }
            catch { $threw = $true }
            Assert-Test $threw 'CR/LF/NUL/反斜杠异常路径意外进入自动分类'
        }
    }

    Invoke-TestCase 'canonical 车道配置缺失或非法时 fail closed' {
        $fixture = New-TestFixture
        $configurationPath = Join-Path $fixture.Work 'config\build\contribution-lanes.v1.json'
        $invalidConfigurations = @(
            '{"schema":"cf7-contribution-lanes.v1","docsPrefixes":["docs/"],"contentPrefixes":["data/"],"extra":true}',
            '{"schema":"cf7-contribution-lanes.v1","docsPrefixes":"docs/","contentPrefixes":["data/"]}',
            '{"schema":"cf7-contribution-lanes.v1","docsPrefixes":["docs\\"],"contentPrefixes":["data/"]}',
            '{"schema":"cf7-contribution-lanes.v1","docsPrefixes":["docs/../"],"contentPrefixes":["data/"]}',
            '{"schema":"cf7-contribution-lanes.v1","docsPrefixes":["docs"],"contentPrefixes":["data/"]}',
            '{"schema":"cf7-contribution-lanes.v1","docsPrefixes":["docs/"],"contentPrefixes":["docs/"]}',
            '{"schema":"cf7-contribution-lanes.v1","docsPrefixes":["docs/","docs/private/"],"contentPrefixes":["data/"]}',
            '{"schema":"cf7-contribution-lanes.v1","docsPrefixes":["docs/private/"],"contentPrefixes":["docs/"]}'
        )
        foreach ($invalid in $invalidConfigurations) {
            Set-TestFile -Path $configurationPath -Content $invalid
            $threw = $false
            try { [void](Read-ContributionLaneConfiguration -ProjectRoot $fixture.Work) }
            catch { $threw = $true }
            Assert-Test $threw "非法配置意外通过：$invalid"
        }

        Remove-Item -LiteralPath $configurationPath -Force
        $missingThrew = $false
        try { [void](Read-ContributionLaneConfiguration -ProjectRoot $fixture.Work) }
        catch { $missingThrew = $true }
        Assert-Test $missingThrew '缺失 canonical 配置意外通过'

        [void](Invoke-TestGit -Root $fixture.Work -Arguments @('add', '-A'))
        [void](Invoke-TestGit -Root $fixture.Work -Arguments @('commit', '-m', 'remove lane config'))
        $submission = Invoke-SubmitTest -Fixture $fixture -AllowFailure
        Assert-Test ($submission.ExitCode -ne 0) '删除 canonical 配置后提交工具意外通过'
        Assert-Test ([string]$submission.Payload.error -match '车道配置') "缺失配置错误不清楚：$($submission.Payload.error)"
    }

    $successfulFixture = $null
    $successfulBranch = $null
    Invoke-TestCase 'docs 贡献成功创建 ready PR、启用 MERGE auto-merge 且复跑幂等' {
        $script:successfulFixture = New-TestFixture
        Add-TestCommit -Fixture $script:successfulFixture -RelativePath 'docs/note.md' -Content "test note`n"
        $first = Invoke-SubmitTest -Fixture $script:successfulFixture
        Assert-Test ($first.ExitCode -eq 0) "首次提交失败：$($first.Text)"
        Assert-Test ($null -ne $first.Payload -and [bool]$first.Payload.ok) '首次提交没有成功 JSON'
        Assert-Test ($first.Payload.status -eq 'pr-created') "首次状态错误：$($first.Payload.status)"
        Assert-Test ($first.Payload.lane -eq 'docs' -and [bool]$first.Payload.autoMerge) 'docs 未进入自动合并通道'
        $script:successfulBranch = [string]$first.Payload.branch
        Assert-Test ($script:successfulBranch -match '^contrib/main/[0-9a-f]{12}$') "贡献分支名不稳定：$($script:successfulBranch)"
        Assert-Test ((Get-ContributionCurrentBranch -ProjectRoot $script:successfulFixture.Work) -eq $script:successfulBranch) '未停留在唯一贡献分支'
        $remoteProbe = Invoke-TestGit -Root $script:successfulFixture.Work -Arguments @('ls-remote', '--exit-code', '--heads', 'origin', "refs/heads/$($script:successfulBranch)") -AllowFailure
        Assert-Test ($remoteProbe.ExitCode -eq 0) '远端贡献分支不存在'

        $second = Invoke-SubmitTest -Fixture $script:successfulFixture
        Assert-Test ($second.ExitCode -eq 0) "复跑失败：$($second.Text)"
        Assert-Test ($second.Payload.status -eq 'pr-existing') "复跑状态错误：$($second.Payload.status)"
        Assert-Test ([string]$second.Payload.branch -eq $script:successfulBranch) '复跑创建了不同贡献分支'
        $logLines = @(Get-Content -LiteralPath $script:successfulFixture.Log)
        Assert-Test (@($logLines | Where-Object { $_ -match '^pr\s+create\s+' }).Count -eq 1) '复跑重复创建 PR'
        Assert-Test (@($logLines | Where-Object { $_ -match '^pr\s+merge\s+' }).Count -eq 1) '复跑重复设置 auto-merge'
        Assert-Test (@($logLines | Where-Object { $_ -match '^pr\s+merge\s+.*--auto\s+--merge$' }).Count -eq 1) '未固定使用 MERGE auto-merge'
    }

    Invoke-TestCase '纯内容资产同样进入自动合并通道' {
        $fixture = New-TestFixture
        Add-TestCommit -Fixture $fixture -RelativePath 'flashswf/arts/test-asset.txt' -Content "asset`n"
        $result = Invoke-SubmitTest -Fixture $fixture
        Assert-Test ($result.ExitCode -eq 0) "内容提交失败：$($result.Text)"
        Assert-Test ($result.Payload.lane -eq 'content' -and [bool]$result.Payload.autoMerge) '内容资产没有进入快速通道'
    }

    Invoke-TestCase '快速通道 Wait 在合并后安全快进并清理回 main' {
        $fixture = New-TestFixture
        Add-TestCommit -Fixture $fixture -RelativePath 'docs/wait-cleanup.md' -Content "wait cleanup`n"
        $headBefore = (Invoke-TestGit -Root $fixture.Work -Arguments @('rev-parse', 'HEAD')).Text.Trim()
        $contributionBranch = "contrib/main/$($headBefore.Substring(0, 12).ToLowerInvariant())"
        $result = Invoke-SubmitTest -Fixture $fixture -Wait -AutoComplete -HumanOutput
        Assert-Test ($result.ExitCode -eq 0) "快速通道等待收尾失败：$($result.Text)"
        Assert-Test ($result.Text -match '正在等待 GitHub 检查与自动合并') "快速通道没有显示等待提示：$($result.Text)"
        Assert-Test ($result.Text -match 'https://example\.invalid/pull/101') "等待提示没有显示 PR URL：$($result.Text)"
        Assert-Test ($result.Text -match '贡献已经合并') "快速通道没有完成自动收尾：$($result.Text)"
        Assert-Test ((Get-ContributionCurrentBranch -ProjectRoot $fixture.Work) -eq 'main') '快速通道完成后没有回到 main'
        $localMain = (Invoke-TestGit -Root $fixture.Work -Arguments @('rev-parse', 'main')).Text.Trim()
        $remoteMain = (Invoke-TestGit -Root $fixture.Work -Arguments @('rev-parse', 'origin/main')).Text.Trim()
        Assert-Test ($localMain -eq $remoteMain) '快速通道完成后 main 没有 ff-only 对齐远端'
        $localProbe = Invoke-TestGit -Root $fixture.Work -Arguments @('show-ref', '--verify', '--quiet', "refs/heads/$contributionBranch") -AllowFailure
        Assert-Test ($localProbe.ExitCode -ne 0) '快速通道完成后仍残留本地贡献分支'
        $remoteProbe = Invoke-TestGit -Root $fixture.Work -Arguments @('ls-remote', '--exit-code', '--heads', 'origin', "refs/heads/$contributionBranch") -AllowFailure
        Assert-Test ($remoteProbe.ExitCode -eq 2) '快速通道完成后仍残留远端贡献分支'
    }

    Invoke-TestCase '软件或混合通道即使请求 Wait 也只创建 PR 后立即返回' {
        $fixture = New-TestFixture
        Add-TestCommit -Fixture $fixture -RelativePath 'tools/software-change.txt' -Content "software`n"
        $result = Invoke-SubmitTest -Fixture $fixture -Wait
        Assert-Test ($result.ExitCode -eq 0) "软件通道被 Wait 阻塞或报错：$($result.Text)"
        Assert-Test ($result.Payload.status -eq 'pr-created') "软件通道没有停在待审 PR：$($result.Payload.status)"
        Assert-Test ($result.Payload.lane -eq 'mixed' -and -not [bool]$result.Payload.autoMerge) '软件通道错误进入自动合并'
        $logLines = @(Get-Content -LiteralPath $fixture.Log)
        Assert-Test (@($logLines | Where-Object { $_ -match '^pr\s+view\s+' }).Count -eq 0) '软件通道不应进入 PR 轮询等待'
        Assert-Test (@($logLines | Where-Object { $_ -match '^pr\s+merge\s+' }).Count -eq 0) '软件通道不应请求自动合并'
    }

    Invoke-TestCase '中文内容根与空格文件名保持原样分类' {
        $fixture = New-TestFixture
        $relativePath = '闪7重置版字体/测试 字体.txt'
        Add-TestCommit -Fixture $fixture -RelativePath $relativePath -Content "font fixture`n"
        $result = Invoke-SubmitTest -Fixture $fixture
        Assert-Test ($result.ExitCode -eq 0) "中文路径提交失败：$($result.Text)"
        Assert-Test ($result.Payload.lane -eq 'content' -and [bool]$result.Payload.autoMerge) '中文内容根没有进入快速通道'
        Assert-Test (@($result.Payload.changedPaths | Where-Object { [string]$_ -ceq $relativePath }).Count -eq 1) "中文路径被转义或损坏：$($result.Payload.changedPaths -join ',')"
    }

    Invoke-TestCase '脏工作区被中文错误阻断' {
        $fixture = New-TestFixture
        Add-TestCommit -Fixture $fixture -RelativePath 'docs/dirty.md' -Content "committed`n"
        Set-TestFile -Path (Join-Path $fixture.Work 'not-committed.txt') -Content "dirty`n"
        $result = Invoke-SubmitTest -Fixture $fixture -AllowFailure
        Assert-Test ($result.ExitCode -ne 0) '脏工作区意外通过'
        Assert-Test ($null -ne $result.Payload -and -not [bool]$result.Payload.ok) '脏工作区没有错误 JSON'
        Assert-Test ([string]$result.Payload.error -match '未提交') "脏工作区错误不清楚：$($result.Payload.error)"
        Assert-Test ((Get-ContributionCurrentBranch -ProjectRoot $fixture.Work) -eq 'main') '阻断后分支发生变化'
    }

    Invoke-TestCase 'main 分叉被阻断且不改写历史' {
        $fixture = New-TestFixture
        Add-TestCommit -Fixture $fixture -RelativePath 'docs/local.md' -Content "local`n"
        Set-TestFile -Path (Join-Path $fixture.Seed 'remote.txt') -Content "remote`n"
        [void](Invoke-TestGit -Root $fixture.Seed -Arguments @('add', '--', 'remote.txt'))
        [void](Invoke-TestGit -Root $fixture.Seed -Arguments @('commit', '-m', 'remote advance'))
        [void](Invoke-TestGit -Root $fixture.Seed -Arguments @('push', 'origin', 'main'))
        $headBefore = (Invoke-TestGit -Root $fixture.Work -Arguments @('rev-parse', 'HEAD')).Text.Trim()
        $result = Invoke-SubmitTest -Fixture $fixture -AllowFailure
        Assert-Test ($result.ExitCode -ne 0) '分叉 main 意外通过'
        Assert-Test ([string]$result.Payload.error -match '分叉') "分叉错误不清楚：$($result.Payload.error)"
        $headAfter = (Invoke-TestGit -Root $fixture.Work -Arguments @('rev-parse', 'HEAD')).Text.Trim()
        Assert-Test ($headAfter -eq $headBefore) '分叉阻断改写了 HEAD'
        Assert-Test ((Get-ContributionCurrentBranch -ProjectRoot $fixture.Work) -eq 'main') '分叉阻断切换了分支'
    }

    Invoke-TestCase '合并后按祖先关系与 ff-only 安全收尾' {
        Assert-Test ($null -ne $script:successfulFixture -and $script:successfulBranch) '成功 fixture 不可用'
        [void](Invoke-TestGit -Root $script:successfulFixture.Seed -Arguments @('fetch', 'origin', $script:successfulBranch))
        [void](Invoke-TestGit -Root $script:successfulFixture.Seed -Arguments @('merge', '--no-ff', 'FETCH_HEAD', '-m', 'merge contribution'))
        $upgradedConfiguration = $script:validLaneConfiguration | ConvertFrom-Json
        $upgradedConfiguration.contentPrefixes += 'new-content/'
        Set-TestFile -Path (Join-Path $script:successfulFixture.Seed 'config\build\contribution-lanes.v1.json') -Content (($upgradedConfiguration | ConvertTo-Json -Depth 6) + "`n")
        [void](Invoke-TestGit -Root $script:successfulFixture.Seed -Arguments @('add', '--', 'config/build/contribution-lanes.v1.json'))
        [void](Invoke-TestGit -Root $script:successfulFixture.Seed -Arguments @('commit', '-m', 'upgrade contribution lanes after merge'))
        [void](Invoke-TestGit -Root $script:successfulFixture.Seed -Arguments @('push', 'origin', 'main'))
        $state = Get-Content -LiteralPath $script:successfulFixture.State -Raw | ConvertFrom-Json
        $state.state = 'MERGED'
        $state.mergedAt = '2026-07-18T12:00:00Z'
        Set-TestFile -Path $script:successfulFixture.State -Content (($state | ConvertTo-Json -Depth 6 -Compress) + "`n")

        $result = Invoke-SubmitTest -Fixture $script:successfulFixture
        Assert-Test ($result.ExitCode -eq 0) "合并收尾失败：$($result.Text)"
        Assert-Test ($result.Payload.status -eq 'merged-cleaned') "合并收尾状态错误：$($result.Payload.status)"
        Assert-Test ((Get-ContributionCurrentBranch -ProjectRoot $script:successfulFixture.Work) -eq 'main') '合并后没有回到 main'
        $localProbe = Invoke-TestGit -Root $script:successfulFixture.Work -Arguments @('show-ref', '--verify', '--quiet', "refs/heads/$($script:successfulBranch)") -AllowFailure
        Assert-Test ($localProbe.ExitCode -ne 0) '合并后的本地贡献分支未清理'
        $remoteProbe = Invoke-TestGit -Root $script:successfulFixture.Work -Arguments @('ls-remote', '--exit-code', '--heads', 'origin', "refs/heads/$($script:successfulBranch)") -AllowFailure
        Assert-Test ($remoteProbe.ExitCode -eq 2) '合并后的远端贡献分支未清理'
        $localMain = (Invoke-TestGit -Root $script:successfulFixture.Work -Arguments @('rev-parse', 'main')).Text.Trim()
        $remoteMain = (Invoke-TestGit -Root $script:successfulFixture.Work -Arguments @('rev-parse', 'origin/main')).Text.Trim()
        Assert-Test ($localMain -eq $remoteMain) '本地 main 未安全快进到远端 main'
    }
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
        $resolvedTest = [IO.Path]::GetFullPath($testRoot)
        if ($resolvedTest.StartsWith($resolvedTemp + '\', [StringComparison]::OrdinalIgnoreCase) -and $resolvedTest -ne $resolvedTemp) {
            Remove-Item -LiteralPath $resolvedTest -Recurse -Force
        }
    }
}

Write-Host "submit-contribution tests: $passed passed, $failed failed"
if ($failed -ne 0) { exit 1 }
