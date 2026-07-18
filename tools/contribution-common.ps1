Set-StrictMode -Version 2.0

$script:ContributionGitExecutablePath = $null

function New-ContributionError {
    param([Parameter(Mandatory = $true)][string]$Message)

    return (New-Object System.InvalidOperationException($Message))
}

function Invoke-ContributionNative {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [switch]$AllowFailure
    )

    $lines = @()
    $exitCode = 0
    $previousErrorActionPreference = $ErrorActionPreference
    $previousConsoleOutputEncoding = [Console]::OutputEncoding
    Push-Location -LiteralPath $WorkingDirectory
    try {
        # Windows PowerShell 5.1 会把原生命令的正常 stderr 包装为 ErrorRecord；
        # git push/fetch 即使成功也会写 stderr，因此只以进程退出码判定成败。
        $ErrorActionPreference = 'Continue'
        # Git 与 gh 都以 UTF-8 输出；显式设置解码，避免中文路径受系统代码页影响。
        [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
        $lines = @(& $FilePath @Arguments 2>&1 | ForEach-Object { [string]$_ })
        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) { $exitCode = 0 }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        [Console]::OutputEncoding = $previousConsoleOutputEncoding
        Pop-Location
    }

    $result = [pscustomobject]@{
        ExitCode = [int]$exitCode
        Lines = @($lines)
        Text = (@($lines) -join "`n").Trim()
    }
    if (-not $AllowFailure -and $result.ExitCode -ne 0) {
        $rendered = if ($result.Text) { $result.Text } else { "退出码 $($result.ExitCode)" }
        throw (New-ContributionError "命令执行失败：$FilePath $($Arguments -join ' ')。$rendered")
    }
    return $result
}

function Invoke-ContributionGit {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$GitExecutablePath,
        [switch]$AllowFailure
    )

    $resolvedGit = $GitExecutablePath
    if (-not $resolvedGit) { $resolvedGit = $script:ContributionGitExecutablePath }
    if (-not $resolvedGit) { $resolvedGit = Resolve-ContributionGitExecutable }
    return Invoke-ContributionNative -FilePath $resolvedGit -Arguments $Arguments -WorkingDirectory $ProjectRoot -AllowFailure:$AllowFailure
}

function Invoke-ContributionGh {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$GitHubCliPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    return Invoke-ContributionNative -FilePath $GitHubCliPath -Arguments $Arguments -WorkingDirectory $ProjectRoot -AllowFailure:$AllowFailure
}

function Resolve-ContributionGitExecutable {
    param([string]$GitExecutablePath)

    if ($GitExecutablePath) {
        $explicit = [Environment]::ExpandEnvironmentVariables($GitExecutablePath)
        if (-not (Test-Path -LiteralPath $explicit -PathType Leaf)) {
            throw (New-ContributionError "找不到指定的 Git 可执行文件：$explicit")
        }
        return [IO.Path]::GetFullPath($explicit)
    }

    foreach ($commandName in @('git.exe', 'git')) {
        $command = Get-Command $commandName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) {
            $resolved = if ($command.Path) { $command.Path } else { $command.Source }
            if ($resolved -and (Test-Path -LiteralPath $resolved -PathType Leaf)) {
                return [IO.Path]::GetFullPath($resolved)
            }
        }
    }

    $known = New-Object Collections.Generic.List[string]
    if ($env:ProgramFiles) {
        $known.Add((Join-Path $env:ProgramFiles 'Git\cmd\git.exe'))
        $known.Add((Join-Path $env:ProgramFiles 'Git\bin\git.exe'))
    }
    ${programFilesX86} = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if (${programFilesX86}) {
        $known.Add((Join-Path ${programFilesX86} 'Git\cmd\git.exe'))
        $known.Add((Join-Path ${programFilesX86} 'Git\bin\git.exe'))
    }
    if ($env:LOCALAPPDATA) {
        $known.Add((Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe'))
        $known.Add((Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\git.exe'))
        $known.Add((Join-Path $env:LOCALAPPDATA 'GitHubDesktop\bin\git.exe'))
    }
    foreach ($candidate in $known) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }

    if ($env:LOCALAPPDATA) {
        $desktopRoot = Join-Path $env:LOCALAPPDATA 'GitHubDesktop'
        if (Test-Path -LiteralPath $desktopRoot -PathType Container) {
            $desktopApps = @(Get-ChildItem -LiteralPath $desktopRoot -Directory -Filter 'app-*' -ErrorAction SilentlyContinue |
                Sort-Object -Property Name -Descending)
            foreach ($desktopApp in $desktopApps) {
                foreach ($relativePath in @('resources\app\git\cmd\git.exe', 'resources\app\git\mingw64\bin\git.exe')) {
                    $candidate = Join-Path $desktopApp.FullName $relativePath
                    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                        return [IO.Path]::GetFullPath($candidate)
                    }
                }
            }
        }
    }

    throw (New-ContributionError '未找到 Git。请安装 Git for Windows 或 GitHub Desktop，重新打开本工具；也可以用 -GitExecutablePath 指定 git.exe。')
}

function Set-ContributionGitExecutable {
    param([string]$GitExecutablePath)

    $script:ContributionGitExecutablePath = Resolve-ContributionGitExecutable -GitExecutablePath $GitExecutablePath
    return $script:ContributionGitExecutablePath
}

function Resolve-ContributionProjectRoot {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
        throw (New-ContributionError "项目目录不存在：$ProjectRoot")
    }
    $candidate = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\', '/')
    $probe = Invoke-ContributionGit -ProjectRoot $candidate -Arguments @('rev-parse', '--show-toplevel') -AllowFailure
    if ($probe.ExitCode -ne 0 -or -not $probe.Text) {
        throw (New-ContributionError "该目录不是 Git 工作区：$candidate")
    }
    $actual = [IO.Path]::GetFullPath($probe.Text.Trim()).TrimEnd('\', '/')
    if (-not [string]::Equals($candidate, $actual, [StringComparison]::OrdinalIgnoreCase)) {
        throw (New-ContributionError "请从仓库根目录运行。检测到的根目录是：$actual")
    }
    return $actual
}

function Resolve-ContributionGitHubCli {
    param([string]$GitHubCliPath)

    if ($GitHubCliPath) {
        $explicit = [Environment]::ExpandEnvironmentVariables($GitHubCliPath)
        if (-not (Test-Path -LiteralPath $explicit -PathType Leaf)) {
            throw (New-ContributionError "找不到指定的 GitHub CLI：$explicit")
        }
        return [IO.Path]::GetFullPath($explicit)
    }

    foreach ($commandName in @('gh.exe', 'gh')) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) {
            $resolved = if ($command.Path) { $command.Path } else { $command.Source }
            if ($resolved) { return $resolved }
        }
    }

    $known = New-Object Collections.Generic.List[string]
    if ($env:LOCALAPPDATA) { $known.Add((Join-Path $env:LOCALAPPDATA 'Programs\GitHub CLI\gh.exe')) }
    if ($env:ProgramFiles) { $known.Add((Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe')) }
    ${programFilesX86} = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if (${programFilesX86}) { $known.Add((Join-Path ${programFilesX86} 'GitHub CLI\gh.exe')) }
    foreach ($candidate in $known) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return [IO.Path]::GetFullPath($candidate) }
    }

    throw (New-ContributionError '未找到 GitHub CLI（gh）。请安装并登录，或用 -GitHubCliPath 指定 gh.exe。')
}

function Get-ContributionCurrentBranch {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $result = Invoke-ContributionGit -ProjectRoot $ProjectRoot -Arguments @('symbolic-ref', '--quiet', '--short', 'HEAD') -AllowFailure
    if ($result.ExitCode -ne 0 -or -not $result.Text) {
        throw (New-ContributionError '当前处于 detached HEAD，无法安全提交贡献。请先切回 main。')
    }
    return $result.Text.Trim()
}

function Get-ContributionOid {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$Revision
    )

    $result = Invoke-ContributionGit -ProjectRoot $ProjectRoot -Arguments @('rev-parse', '--verify', "$Revision^{commit}") -AllowFailure
    if ($result.ExitCode -ne 0 -or -not $result.Text) {
        throw (New-ContributionError "找不到提交：$Revision")
    }
    return $result.Text.Trim()
}

function Test-ContributionAncestor {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$Ancestor,
        [Parameter(Mandatory = $true)][string]$Descendant
    )

    $result = Invoke-ContributionGit -ProjectRoot $ProjectRoot -Arguments @('merge-base', '--is-ancestor', $Ancestor, $Descendant) -AllowFailure
    if ($result.ExitCode -eq 0) { return $true }
    if ($result.ExitCode -eq 1) { return $false }
    throw (New-ContributionError "无法比较提交祖先关系：$Ancestor 与 $Descendant。$($result.Text)")
}

function Assert-ContributionClean {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $operationMarkers = @(
        [pscustomobject]@{ Path = 'MERGE_HEAD'; Label = '合并' },
        [pscustomobject]@{ Path = 'CHERRY_PICK_HEAD'; Label = '拣选提交' },
        [pscustomobject]@{ Path = 'REVERT_HEAD'; Label = '撤销提交' },
        [pscustomobject]@{ Path = 'rebase-merge'; Label = '变基' },
        [pscustomobject]@{ Path = 'rebase-apply'; Label = '变基或补丁应用' },
        [pscustomobject]@{ Path = 'sequencer'; Label = '连续提交操作' },
        [pscustomobject]@{ Path = 'BISECT_LOG'; Label = '二分定位' },
        [pscustomobject]@{ Path = 'BISECT_START'; Label = '二分定位' }
    )
    $activeOperations = New-Object Collections.Generic.List[string]
    foreach ($marker in $operationMarkers) {
        $probe = Invoke-ContributionGit -ProjectRoot $ProjectRoot -Arguments @('rev-parse', '--git-path', [string]$marker.Path) -AllowFailure
        if ($probe.ExitCode -ne 0 -or -not $probe.Text) {
            throw (New-ContributionError "无法检查 Git 操作状态：$($marker.Path)。$($probe.Text)")
        }
        $metadataPath = [string]($probe.Lines | Select-Object -Last 1)
        $metadataPath = $metadataPath.Trim()
        if (-not [IO.Path]::IsPathRooted($metadataPath)) {
            $metadataPath = Join-Path $ProjectRoot $metadataPath
        }
        if ((Test-Path -LiteralPath $metadataPath) -and -not $activeOperations.Contains([string]$marker.Label)) {
            $activeOperations.Add([string]$marker.Label)
        }
    }
    if ($activeOperations.Count -gt 0) {
        throw (New-ContributionError "仓库仍处于未完成的 Git 操作状态（$($activeOperations -join '、')）。请先在 Git 客户端中完成或取消该操作，再运行一键工具。")
    }

    $status = Invoke-ContributionGit -ProjectRoot $ProjectRoot -Arguments @('status', '--porcelain=v1', '--untracked-files=all')
    if ($status.Lines.Count -gt 0) {
        $preview = @($status.Lines | Select-Object -First 8) -join '；'
        throw (New-ContributionError "工作区还有未提交的改动，请先在界面中完成提交再运行一键工具：$preview")
    }
}

function ConvertTo-ContributionRefPart {
    param([Parameter(Mandatory = $true)][string]$Value)

    $safe = [regex]::Replace($Value, '[^0-9A-Za-z._-]+', '-')
    $safe = $safe.Trim('.', '-', '_')
    if (-not $safe) { throw (New-ContributionError "分支名称无法转换为安全格式：$Value") }
    return $safe
}

function Get-ContributionAheadBehind {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$RemoteBaseRef,
        [string]$Head = 'HEAD'
    )

    $result = Invoke-ContributionGit -ProjectRoot $ProjectRoot -Arguments @('rev-list', '--left-right', '--count', "$RemoteBaseRef...$Head")
    $parts = $result.Text -split '\s+'
    if ($parts.Count -ne 2) { throw (New-ContributionError "无法解析 main 同步状态：$($result.Text)") }
    return [pscustomobject]@{ Behind = [int]$parts[0]; Ahead = [int]$parts[1] }
}

function Get-ContributionChangedPaths {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$BaseRevision,
        [string]$Head = 'HEAD'
    )

    $mergeBase = (Invoke-ContributionGit -ProjectRoot $ProjectRoot -Arguments @('merge-base', $BaseRevision, $Head)).Text.Trim()
    $result = Invoke-ContributionGit -ProjectRoot $ProjectRoot -Arguments @(
        '-c', 'core.quotepath=false', 'diff', '--name-only', '--no-renames', "$mergeBase..$Head", '--'
    )
    $paths = @($result.Lines | Where-Object { $_ })
    foreach ($path in $paths) { Assert-ContributionChangedPath -Path ([string]$path) }
    return $paths
}

function Assert-ContributionChangedPath {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Path)

    if (-not $Path) { throw (New-ContributionError 'Git 返回了空的变更路径，已停止自动分类。') }
    if ($Path.IndexOf('\') -ge 0) {
        throw (New-ContributionError "Git 返回了引用或含反斜杠的异常路径，已停止自动分类：$Path")
    }
    if ($Path.StartsWith('/', [StringComparison]::Ordinal) -or $Path -match '^[A-Za-z]:') {
        throw (New-ContributionError "Git 返回了非仓库相对路径，已停止自动分类：$Path")
    }
    foreach ($character in $Path.ToCharArray()) {
        if ([char]::IsControl($character)) {
            throw (New-ContributionError 'Git 变更路径含 CR、LF、NUL 或其他控制字符，已停止自动分类。')
        }
    }
    foreach ($segment in @($Path -split '/')) {
        if (-not $segment -or $segment -eq '.' -or $segment -eq '..') {
            throw (New-ContributionError "Git 变更路径含空段、. 或 ..，已停止自动分类：$Path")
        }
    }
}

function Test-ContributionPathPrefix {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Prefix
    )

    return $Path.StartsWith($Prefix, [StringComparison]::Ordinal)
}

function Assert-ContributionLanePrefix {
    param(
        [Parameter(Mandatory = $true)][string]$Prefix,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][Collections.Generic.HashSet[string]]$Seen
    )

    if (-not $Prefix) { throw (New-ContributionError '贡献车道前缀不能为空。') }
    if ($Prefix.IndexOf('\') -ge 0) { throw (New-ContributionError "贡献车道前缀只能使用正斜杠：$Prefix") }
    if ($Prefix.StartsWith('/', [StringComparison]::Ordinal) -or $Prefix -match '^[A-Za-z]:') {
        throw (New-ContributionError "贡献车道前缀必须是仓库相对路径：$Prefix")
    }
    if (-not $Prefix.EndsWith('/', [StringComparison]::Ordinal)) {
        throw (New-ContributionError "贡献车道前缀必须以 / 结尾：$Prefix")
    }
    $body = $Prefix.Substring(0, $Prefix.Length - 1)
    $segments = @($body -split '/')
    if ($segments.Count -eq 0) { throw (New-ContributionError "贡献车道前缀无效：$Prefix") }
    foreach ($segment in $segments) {
        if (-not $segment -or $segment -eq '.' -or $segment -eq '..') {
            throw (New-ContributionError "贡献车道前缀不能包含空段、. 或 ..：$Prefix")
        }
        foreach ($character in $segment.ToCharArray()) {
            if ([char]::IsControl($character)) {
                throw (New-ContributionError "贡献车道前缀不能包含控制字符：$Prefix")
            }
        }
    }
    foreach ($existing in $Seen) {
        if ($Prefix.StartsWith($existing, [StringComparison]::Ordinal) -or
                $existing.StartsWith($Prefix, [StringComparison]::Ordinal)) {
            throw (New-ContributionError "贡献车道前缀重复或互相包含：$existing 与 $Prefix")
        }
    }
    [void]$Seen.Add($Prefix)
}

function Read-ContributionLaneConfiguration {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [string]$TrustedRevision
    )

    $relativePath = 'config/build/contribution-lanes.v1.json'
    $configurationPath = Join-Path $ProjectRoot ($relativePath.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $configurationPath -PathType Leaf)) {
        throw (New-ContributionError "缺少贡献车道配置：$relativePath")
    }

    if ($TrustedRevision) {
        $trustedSpec = "${TrustedRevision}:$relativePath"
        $trusted = Invoke-ContributionGit -ProjectRoot $ProjectRoot -Arguments @('rev-parse', '--verify', $trustedSpec) -AllowFailure
        if ($trusted.ExitCode -ne 0 -or $trusted.Text -notmatch '^[0-9a-fA-F]{40,64}$') {
            throw (New-ContributionError "远端受信基线缺少贡献车道配置：$trustedSpec")
        }
        $working = Invoke-ContributionGit -ProjectRoot $ProjectRoot -Arguments @('hash-object', "--path=$relativePath", '--', $relativePath) -AllowFailure
        if ($working.ExitCode -ne 0 -or $working.Text -notmatch '^[0-9a-fA-F]{40,64}$') {
            throw (New-ContributionError "无法核对贡献车道配置：$relativePath")
        }
        if (-not [string]::Equals($trusted.Text.Trim(), $working.Text.Trim(), [StringComparison]::OrdinalIgnoreCase)) {
            throw (New-ContributionError '本地贡献车道配置与远端受信基线不一致；该配置不能通过普通贡献流程自行放宽。')
        }
    }

    $strictUtf8 = New-Object Text.UTF8Encoding($false, $true)
    try { $text = $strictUtf8.GetString([IO.File]::ReadAllBytes($configurationPath)) }
    catch { throw (New-ContributionError "贡献车道配置不是严格 UTF-8：$relativePath") }
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    try { $configuration = $text | ConvertFrom-Json }
    catch { throw (New-ContributionError "贡献车道配置不是有效 JSON：$($_.Exception.Message)") }
    if ($null -eq $configuration) { throw (New-ContributionError '贡献车道配置不能为空。') }

    $expectedFields = @('schema', 'docsPrefixes', 'contentPrefixes')
    $actualFields = @($configuration.PSObject.Properties | ForEach-Object { $_.Name })
    $fieldSet = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($field in $actualFields) { [void]$fieldSet.Add([string]$field) }
    if ($actualFields.Count -ne $expectedFields.Count) {
        throw (New-ContributionError '贡献车道配置只能包含 schema、docsPrefixes、contentPrefixes 三个字段。')
    }
    foreach ($field in $expectedFields) {
        if (-not $fieldSet.Contains($field)) {
            throw (New-ContributionError "贡献车道配置缺少精确字段：$field")
        }
    }
    if ([string]$configuration.schema -cne 'cf7-contribution-lanes.v1') {
        throw (New-ContributionError "贡献车道配置 schema 不受支持：$($configuration.schema)")
    }
    if ($configuration.docsPrefixes -isnot [Array] -or $configuration.contentPrefixes -isnot [Array]) {
        throw (New-ContributionError 'docsPrefixes 与 contentPrefixes 必须是 JSON 数组。')
    }
    $docsPrefixes = @($configuration.docsPrefixes)
    $contentPrefixes = @($configuration.contentPrefixes)
    if ($docsPrefixes.Count -eq 0 -or $contentPrefixes.Count -eq 0) {
        throw (New-ContributionError 'docsPrefixes 与 contentPrefixes 都不得为空。')
    }
    $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($prefix in @($docsPrefixes + $contentPrefixes)) {
        if ($prefix -isnot [string]) { throw (New-ContributionError '贡献车道前缀必须是字符串。') }
        Assert-ContributionLanePrefix -Prefix ([string]$prefix) -Seen $seen
    }

    return [pscustomobject][ordered]@{
        schema = 'cf7-contribution-lanes.v1'
        docsPrefixes = @($docsPrefixes)
        contentPrefixes = @($contentPrefixes)
    }
}

function Get-ContributionLane {
    param(
        [Parameter(Mandatory = $true)][string[]]$Paths,
        [Parameter(Mandatory = $true)]$Configuration
    )

    if ($Paths.Count -eq 0) { return 'unknown' }

    $sawDocs = $false
    $sawContent = $false
    foreach ($path in $Paths) {
        Assert-ContributionChangedPath -Path ([string]$path)
        # reserved alias 在 Windows 上保守地按大小写不敏感拦截；canonical 允许前缀仍全部 Ordinal。
        if ($path.StartsWith('config/build/', [StringComparison]::OrdinalIgnoreCase)) { return 'restricted' }
        $matchedDocs = $false
        foreach ($prefix in @($Configuration.docsPrefixes)) {
            if (Test-ContributionPathPrefix -Path $path -Prefix ([string]$prefix)) {
                $matchedDocs = $true
                break
            }
        }
        if ($matchedDocs) {
            $sawDocs = $true
            continue
        }
        $matched = $false
        foreach ($prefix in @($Configuration.contentPrefixes)) {
            if (Test-ContributionPathPrefix -Path $path -Prefix ([string]$prefix)) {
                $matched = $true
                break
            }
        }
        if (-not $matched) {
            return 'mixed'
        }
        $sawContent = $true
    }
    if ($sawContent) { return 'content' }
    if ($sawDocs) { return 'docs' }
    return 'unknown'
}

function Get-ContributionPullRequest {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$GitHubCliPath,
        [Parameter(Mandatory = $true)][string]$Branch,
        [Parameter(Mandatory = $true)][string]$BaseBranch
    )

    $result = Invoke-ContributionGh -ProjectRoot $ProjectRoot -GitHubCliPath $GitHubCliPath -Arguments @(
        'pr', 'list', '--head', $Branch, '--base', $BaseBranch, '--state', 'all', '--limit', '10',
        '--json', 'number,state,isDraft,url,mergedAt,autoMergeRequest'
    )
    try {
        $items = @($result.Text | ConvertFrom-Json)
    }
    catch {
        throw (New-ContributionError "GitHub CLI 返回了无法识别的 PR 信息：$($result.Text)")
    }
    if ($items.Count -gt 1) {
        throw (New-ContributionError "分支 $Branch 对应多个 PR，无法自动判断，请在 GitHub 网页中处理。")
    }
    if ($items.Count -eq 0) { return $null }
    return $items[0]
}

function Test-ContributionRemoteBranch {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$Remote,
        [Parameter(Mandatory = $true)][string]$Branch
    )

    $result = Invoke-ContributionGit -ProjectRoot $ProjectRoot -Arguments @('ls-remote', '--exit-code', '--heads', $Remote, "refs/heads/$Branch") -AllowFailure
    if ($result.ExitCode -eq 0) { return $true }
    if ($result.ExitCode -eq 2) { return $false }
    throw (New-ContributionError "无法查询远端贡献分支 $Branch：$($result.Text)")
}

function Remove-MergedContributionBranch {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$Remote,
        [Parameter(Mandatory = $true)][string]$BaseBranch,
        [Parameter(Mandatory = $true)][string]$ContributionBranch,
        [Parameter(Mandatory = $true)][string]$RemoteBaseRef
    )

    $localBaseRef = "refs/heads/$BaseBranch"
    $localBaseProbe = Invoke-ContributionGit -ProjectRoot $ProjectRoot -Arguments @('show-ref', '--verify', '--quiet', $localBaseRef) -AllowFailure
    if ($localBaseProbe.ExitCode -ne 0) {
        throw (New-ContributionError "本地不存在 $BaseBranch，无法自动收尾。贡献已在远端保留。")
    }
    if (-not (Test-ContributionAncestor -ProjectRoot $ProjectRoot -Ancestor $localBaseRef -Descendant $RemoteBaseRef)) {
        throw (New-ContributionError "本地 $BaseBranch 含有远端没有的提交，无法自动收尾。请人工确认后再处理。")
    }

    [void](Invoke-ContributionGit -ProjectRoot $ProjectRoot -Arguments @('switch', $BaseBranch))
    [void](Invoke-ContributionGit -ProjectRoot $ProjectRoot -Arguments @('merge', '--ff-only', $RemoteBaseRef))
    if (-not (Test-ContributionAncestor -ProjectRoot $ProjectRoot -Ancestor "refs/heads/$ContributionBranch" -Descendant $localBaseRef)) {
        throw (New-ContributionError "贡献分支尚未完整进入 $BaseBranch，已停止清理。")
    }
    [void](Invoke-ContributionGit -ProjectRoot $ProjectRoot -Arguments @('branch', '-d', $ContributionBranch))

    if (Test-ContributionRemoteBranch -ProjectRoot $ProjectRoot -Remote $Remote -Branch $ContributionBranch) {
        [void](Invoke-ContributionGit -ProjectRoot $ProjectRoot -Arguments @('fetch', '--no-tags', $Remote, $ContributionBranch))
        $remoteTip = Get-ContributionOid -ProjectRoot $ProjectRoot -Revision 'FETCH_HEAD'
        if (Test-ContributionAncestor -ProjectRoot $ProjectRoot -Ancestor $remoteTip -Descendant $RemoteBaseRef) {
            [void](Invoke-ContributionGit -ProjectRoot $ProjectRoot -Arguments @('push', $Remote, '--delete', $ContributionBranch))
        }
    }
}

function Write-ContributionResult {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [switch]$Json
    )

    if ($Json) {
        $Result | ConvertTo-Json -Depth 8 -Compress
        return
    }

    switch ($Result.status) {
        'up-to-date' { Write-Host 'main 当前没有待提交的新提交。' }
        'merged-cleaned' { Write-Host "贡献已经合并，本地已安全回到 $($Result.baseBranch) 并完成清理。" }
        default {
            Write-Host "贡献分支：$($Result.branch)"
            Write-Host "变更通道：$($Result.lane)"
            Write-Host "Pull Request：$($Result.prUrl)"
            if ($Result.autoMerge) {
                Write-Host '已启用自动合并；GitHub 检查全部通过后会自动进入 main。'
            }
            else {
                Write-Host 'PR 已创建并等待检查；这类变更不会自动合并。'
            }
        }
    }
}
