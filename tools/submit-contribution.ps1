[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
    [string]$Remote = 'origin',
    [string]$BaseBranch = 'main',
    [string]$Title,
    [string]$GitExecutablePath,
    [string]$GitHubCliPath,
    [switch]$Json,
    [switch]$Wait,
    [ValidateRange(1, 86400)][int]$WaitTimeoutSeconds = 900
)

$ErrorActionPreference = 'Stop'
$commonPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'contribution-common.ps1'
. $commonPath

function New-SubmissionResult {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$RemoteName,
        [Parameter(Mandatory = $true)][string]$BaseName,
        [string]$Branch,
        [string]$Lane,
        [bool]$AutoMerge = $false,
        [string]$PrUrl,
        [string]$Head,
        [string]$RemoteBase,
        [string[]]$ChangedPaths = @()
    )

    return [pscustomobject][ordered]@{
        ok = $true
        status = $Status
        remote = $RemoteName
        baseBranch = $BaseName
        branch = $Branch
        lane = $Lane
        autoMerge = $AutoMerge
        prUrl = $PrUrl
        head = $Head
        remoteBase = $RemoteBase
        changedPaths = @($ChangedPaths)
    }
}

function Complete-MergedSubmission {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RemoteName,
        [Parameter(Mandatory = $true)][string]$BaseName,
        [Parameter(Mandatory = $true)][string]$Branch,
        [Parameter(Mandatory = $true)][string]$RemoteBaseRef,
        [string]$PrUrl,
        [string]$Lane,
        [string[]]$ChangedPaths = @()
    )

    $headBefore = Get-ContributionOid -ProjectRoot $Root -Revision 'HEAD'
    Remove-MergedContributionBranch -ProjectRoot $Root -Remote $RemoteName -BaseBranch $BaseName -ContributionBranch $Branch -RemoteBaseRef $RemoteBaseRef
    $baseOid = Get-ContributionOid -ProjectRoot $Root -Revision 'HEAD'
    return New-SubmissionResult -Status 'merged-cleaned' -RemoteName $RemoteName -BaseName $BaseName -Branch $Branch -Lane $Lane -PrUrl $PrUrl -Head $headBefore -RemoteBase $baseOid -ChangedPaths $ChangedPaths
}

function Wait-ContributionPullRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$GhPath,
        [Parameter(Mandatory = $true)][string]$PrUrl,
        [Parameter(Mandatory = $true)][datetime]$Deadline,
        [switch]$Quiet
    )

    if (-not $Quiet) {
        Write-Host "[CF7] Pull Request：$PrUrl"
        Write-Host '[CF7] 正在等待 GitHub 检查与自动合并，请保持此窗口打开。'
    }
    $nextProgressAt = [DateTime]::UtcNow
    while ([DateTime]::UtcNow -lt $Deadline) {
        $view = Invoke-ContributionGh -ProjectRoot $Root -GitHubCliPath $GhPath -Arguments @(
            'pr', 'view', $PrUrl, '--json', 'state,isDraft,url,mergedAt,autoMergeRequest'
        )
        try { $pr = $view.Text | ConvertFrom-Json }
        catch { throw (New-ContributionError "GitHub CLI 返回了无法识别的 PR 状态：$($view.Text)") }
        $state = ([string]$pr.state).ToUpperInvariant()
        if ($state -eq 'MERGED') { return $pr }
        if ($state -eq 'CLOSED') {
            throw (New-ContributionError "PR 已关闭但没有合并：$PrUrl")
        }
        if (-not $Quiet -and [DateTime]::UtcNow -ge $nextProgressAt) {
            Write-Host '[CF7] GitHub 检查尚未完成，继续等待……'
            $nextProgressAt = [DateTime]::UtcNow.AddSeconds(30)
        }
        Start-Sleep -Seconds 3
    }
    throw (New-ContributionError "等待 GitHub 合并超时（$WaitTimeoutSeconds 秒）。PR 仍然保留，可稍后重新运行：$PrUrl")
}

try {
    if (-not $Remote) { throw (New-ContributionError '远端名称不能为空。') }
    if (-not $BaseBranch) { throw (New-ContributionError '主线分支名称不能为空。') }

    [void](Set-ContributionGitExecutable -GitExecutablePath $GitExecutablePath)
    $root = Resolve-ContributionProjectRoot -ProjectRoot $ProjectRoot
    Assert-ContributionClean -ProjectRoot $root
    $ghPath = Resolve-ContributionGitHubCli -GitHubCliPath $GitHubCliPath
    $auth = Invoke-ContributionGh -ProjectRoot $root -GitHubCliPath $ghPath -Arguments @('auth', 'status') -AllowFailure
    if ($auth.ExitCode -ne 0) {
        throw (New-ContributionError "GitHub CLI 尚未登录。请先运行 gh auth login。$($auth.Text)")
    }

    [void](Invoke-ContributionGit -ProjectRoot $root -Arguments @('fetch', '--no-tags', $Remote, $BaseBranch))
    $remoteBaseRef = "refs/remotes/$Remote/$BaseBranch"
    $remoteBaseOid = Get-ContributionOid -ProjectRoot $root -Revision $remoteBaseRef
    $currentBranch = Get-ContributionCurrentBranch -ProjectRoot $root
    $headOid = Get-ContributionOid -ProjectRoot $root -Revision 'HEAD'
    $safeBase = ConvertTo-ContributionRefPart -Value $BaseBranch
    $contributionPrefix = "contrib/$safeBase/"
    $branch = $null

    if ([string]::Equals($currentBranch, $BaseBranch, [StringComparison]::OrdinalIgnoreCase)) {
        $sync = Get-ContributionAheadBehind -ProjectRoot $root -RemoteBaseRef $remoteBaseRef
        if ($sync.Behind -gt 0 -and $sync.Ahead -gt 0) {
            throw (New-ContributionError "$BaseBranch 已与远端分叉（本地领先 $($sync.Ahead)、落后 $($sync.Behind)）。工具不会自动改写提交，请先请维护者协助。")
        }
        if ($sync.Behind -gt 0) {
            throw (New-ContributionError "$BaseBranch 落后远端 $($sync.Behind) 个提交。请先使用界面中的“拉取”，再重新运行。")
        }
        if ($sync.Ahead -eq 0) {
            $noWork = New-SubmissionResult -Status 'up-to-date' -RemoteName $Remote -BaseName $BaseBranch -Head $headOid -RemoteBase $remoteBaseOid
            Write-ContributionResult -Result $noWork -Json:$Json
            exit 0
        }

        $aheadCommits = Invoke-ContributionGit -ProjectRoot $root -Arguments @('rev-list', '--reverse', "$remoteBaseRef..HEAD")
        $firstCommit = [string]($aheadCommits.Lines | Select-Object -First 1)
        if (-not $firstCommit) { throw (New-ContributionError '找不到待提交的本地提交。') }
        $branch = "$contributionPrefix$($firstCommit.Substring(0, 12).ToLowerInvariant())"
        $localContributionRef = "refs/heads/$branch"
        $existingLocal = Invoke-ContributionGit -ProjectRoot $root -Arguments @('show-ref', '--verify', '--quiet', $localContributionRef) -AllowFailure
        if ($existingLocal.ExitCode -eq 0) {
            $existingOid = Get-ContributionOid -ProjectRoot $root -Revision $localContributionRef
            if (-not [string]::Equals($existingOid, $headOid, [StringComparison]::OrdinalIgnoreCase)) {
                throw (New-ContributionError "本地已存在同名贡献分支 $branch，但它不指向当前提交。请联系维护者处理。")
            }
            [void](Invoke-ContributionGit -ProjectRoot $root -Arguments @('switch', $branch))
        }
        else {
            [void](Invoke-ContributionGit -ProjectRoot $root -Arguments @('switch', '-c', $branch))
        }
    }
    elseif ($currentBranch.StartsWith($contributionPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        $branch = $currentBranch
        if (Test-ContributionAncestor -ProjectRoot $root -Ancestor 'HEAD' -Descendant $remoteBaseRef) {
            $completed = Complete-MergedSubmission -Root $root -RemoteName $Remote -BaseName $BaseBranch -Branch $branch -RemoteBaseRef $remoteBaseRef
            Write-ContributionResult -Result $completed -Json:$Json
            exit 0
        }
    }
    else {
        throw (New-ContributionError "当前分支是 $currentBranch。请切回 $BaseBranch，或回到由本工具创建的 $contributionPrefix... 分支。")
    }

    $headOid = Get-ContributionOid -ProjectRoot $root -Revision 'HEAD'
    # 已合并分支在上面的祖先检查中先安全收尾；只有仍需提交/分类时才读取当前受信车道。
    $laneConfiguration = Read-ContributionLaneConfiguration -ProjectRoot $root -TrustedRevision $remoteBaseRef
    $changedPaths = @(Get-ContributionChangedPaths -ProjectRoot $root -BaseRevision $remoteBaseRef)
    if ($changedPaths.Count -eq 0) {
        throw (New-ContributionError '贡献分支与远端 main 之间没有可提交的文件变化。')
    }
    $lane = Get-ContributionLane -Paths $changedPaths -Configuration $laneConfiguration
    $autoMerge = $lane -eq 'docs' -or $lane -eq 'content'

    if (Test-ContributionRemoteBranch -ProjectRoot $root -Remote $Remote -Branch $branch) {
        [void](Invoke-ContributionGit -ProjectRoot $root -Arguments @('fetch', '--no-tags', $Remote, $branch))
        $remoteContributionOid = Get-ContributionOid -ProjectRoot $root -Revision 'FETCH_HEAD'
        if (-not (Test-ContributionAncestor -ProjectRoot $root -Ancestor $remoteContributionOid -Descendant 'HEAD')) {
            throw (New-ContributionError "远端贡献分支 $branch 含有本地没有的提交，已停止推送以保护协作者内容。")
        }
    }
    [void](Invoke-ContributionGit -ProjectRoot $root -Arguments @('push', '--set-upstream', $Remote, "HEAD:refs/heads/$branch"))

    $pr = Get-ContributionPullRequest -ProjectRoot $root -GitHubCliPath $ghPath -Branch $branch -BaseBranch $BaseBranch
    $created = $false
    if ($null -eq $pr) {
        $effectiveTitle = $Title
        if (-not $effectiveTitle) {
            $effectiveTitle = (Invoke-ContributionGit -ProjectRoot $root -Arguments @('log', '-1', '--pretty=%s')).Text.Trim()
        }
        if (-not $effectiveTitle) { $effectiveTitle = '提交项目贡献' }
        $body = "由一键贡献工具提交。`n`n变更通道：$lane`n文件数：$($changedPaths.Count)"
        [void](Invoke-ContributionGh -ProjectRoot $root -GitHubCliPath $ghPath -Arguments @(
            'pr', 'create', '--base', $BaseBranch, '--head', $branch, '--title', $effectiveTitle, '--body', $body
        ))
        $pr = Get-ContributionPullRequest -ProjectRoot $root -GitHubCliPath $ghPath -Branch $branch -BaseBranch $BaseBranch
        if ($null -eq $pr) { throw (New-ContributionError 'PR 创建命令已完成，但随后无法查询到 PR。请在 GitHub 网页中确认。') }
        $created = $true
    }

    $prState = ([string]$pr.state).ToUpperInvariant()
    if ($prState -eq 'CLOSED') {
        throw (New-ContributionError "已有 PR 已关闭且未合并，请在 GitHub 网页中重新打开或联系维护者：$($pr.url)")
    }
    if ($prState -eq 'MERGED') {
        [void](Invoke-ContributionGit -ProjectRoot $root -Arguments @('fetch', '--no-tags', $Remote, $BaseBranch))
        $remoteBaseOid = Get-ContributionOid -ProjectRoot $root -Revision $remoteBaseRef
        if (-not (Test-ContributionAncestor -ProjectRoot $root -Ancestor 'HEAD' -Descendant $remoteBaseRef)) {
            throw (New-ContributionError "GitHub 已记录 PR 合并，但本地暂未看到提交进入 $BaseBranch。请稍后复跑。")
        }
        $completed = Complete-MergedSubmission -Root $root -RemoteName $Remote -BaseName $BaseBranch -Branch $branch -RemoteBaseRef $remoteBaseRef -PrUrl ([string]$pr.url) -Lane $lane -ChangedPaths $changedPaths
        Write-ContributionResult -Result $completed -Json:$Json
        exit 0
    }

    if ([bool]$pr.isDraft) {
        [void](Invoke-ContributionGh -ProjectRoot $root -GitHubCliPath $ghPath -Arguments @('pr', 'ready', [string]$pr.url))
    }
    if ($autoMerge -and $null -eq $pr.autoMergeRequest) {
        [void](Invoke-ContributionGh -ProjectRoot $root -GitHubCliPath $ghPath -Arguments @('pr', 'merge', [string]$pr.url, '--auto', '--merge'))
    }

    if ($Wait -and $autoMerge) {
        $deadline = [DateTime]::UtcNow.AddSeconds($WaitTimeoutSeconds)
        [void](Wait-ContributionPullRequest -Root $root -GhPath $ghPath -PrUrl ([string]$pr.url) -Deadline $deadline -Quiet:$Json)
        [void](Invoke-ContributionGit -ProjectRoot $root -Arguments @('fetch', '--no-tags', $Remote, $BaseBranch))
        $remoteBaseOid = Get-ContributionOid -ProjectRoot $root -Revision $remoteBaseRef
        if (-not (Test-ContributionAncestor -ProjectRoot $root -Ancestor 'HEAD' -Descendant $remoteBaseRef)) {
            throw (New-ContributionError "PR 已合并，但远端 $BaseBranch 尚未显示该提交；请稍后复跑完成清理。")
        }
        $completed = Complete-MergedSubmission -Root $root -RemoteName $Remote -BaseName $BaseBranch -Branch $branch -RemoteBaseRef $remoteBaseRef -PrUrl ([string]$pr.url) -Lane $lane -ChangedPaths $changedPaths
        Write-ContributionResult -Result $completed -Json:$Json
        exit 0
    }

    $status = if ($created) { 'pr-created' } else { 'pr-existing' }
    $result = New-SubmissionResult -Status $status -RemoteName $Remote -BaseName $BaseBranch -Branch $branch -Lane $lane -AutoMerge $autoMerge -PrUrl ([string]$pr.url) -Head $headOid -RemoteBase $remoteBaseOid -ChangedPaths $changedPaths
    Write-ContributionResult -Result $result -Json:$Json
    exit 0
}
catch {
    $message = $_.Exception.Message
    if ($Json) {
        [pscustomobject][ordered]@{ ok = $false; status = 'error'; error = $message } | ConvertTo-Json -Compress
    }
    else {
        Write-Error $message
    }
    exit 1
}
