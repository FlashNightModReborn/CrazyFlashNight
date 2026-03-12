param(
    [string]$FlashExe,
    [switch]$SkipCleanup
)

$ErrorActionPreference = 'Stop'

[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$ScriptDir = Split-Path -Parent $PSCommandPath
$ProjectDir = Split-Path -Parent $ScriptDir
$LoaderFileName = 'cf7_compile_loader.jsfl'
$FlashLog = Join-Path $env:APPDATA 'Macromedia\Flash Player\Logs\flashlog.txt'
$ExpectedMmCfg = @(
    'ErrorReportingEnable=1'
    'TraceOutputFileEnable=1'
    'MaxWarnings=0'
) -join [Environment]::NewLine

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Convert-ToJsflUri {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = (Resolve-Path $Path).Path.Replace('\', '/')
    return 'file:///' + $resolved.Replace(':', '|')
}

function Get-CommandsCandidates {
    $cfgBase = Join-Path $env:LOCALAPPDATA 'Adobe\Flash CS6'
    if (-not (Test-Path $cfgBase)) {
        return @()
    }

    $items = @()
    Get-ChildItem $cfgBase -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $commandsDir = Join-Path $_.FullName 'Configuration\Commands'
        if (-not (Test-Path $commandsDir)) {
            return
        }

        $projectCfg = Join-Path $commandsDir 'flash_project_path.cfg'
        $projectUri = $null
        if (Test-Path $projectCfg) {
            $projectUri = (Get-Content -Raw -Encoding UTF8 $projectCfg).Trim()
        }

        $items += [pscustomobject]@{
            Lang        = $_.Name
            CommandsDir = $commandsDir
            ProjectUri  = $projectUri
        }
    }

    return $items
}

function Get-CommandsDir {
    param([Parameter(Mandatory = $true)][string]$ProjectDir)

    $expectedUri = Convert-ToJsflUri $ProjectDir
    $candidates = Get-CommandsCandidates
    if (-not $candidates) {
        throw '找不到 Flash CS6 Commands 目录，请确认 Flash CS6 已安装并至少启动过一次。'
    }

    $matched = $candidates | Where-Object { $_.ProjectUri -eq $expectedUri } | Select-Object -First 1
    if ($matched) {
        return $matched.CommandsDir
    }

    $preferred = $null
    $preferredRank = [int]::MaxValue
    foreach ($candidate in $candidates) {
        $candidateRank = Get-LangRank $candidate.Lang
        if ((-not $preferred) -or $candidateRank -lt $preferredRank -or ($candidateRank -eq $preferredRank -and $candidate.Lang -lt $preferred.Lang)) {
            $preferred = $candidate
            $preferredRank = $candidateRank
        }
    }

    return $preferred.CommandsDir
}

function Get-LangRank {
    param([string]$Lang)

    if ($Lang -eq 'zh_CN') {
        return 0
    }
    if ($Lang -eq 'en_US') {
        return 1
    }
    return 2
}

function Get-LoaderContent {
@'
// cf7_compile_loader.jsfl - dynamic loader
var _cfg = fl.configURI + "Commands/flash_project_path.cfg";
var _proj = FLfile.read(_cfg);
if (_proj) {
	_proj = _proj.replace(/[\r\n]+$/, "");
	var _script = _proj + "/scripts/compile_action.jsfl";
	if (FLfile.exists(_script)) {
		eval(FLfile.read(_script));
	} else {
		fl.trace("[ERROR] not found: " + _script);
	}
} else {
	fl.trace("[ERROR] no project config");
}
'@
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content,
        [bool]$Bom = $false
    )

    $encoding = [System.Text.UTF8Encoding]::new($Bom)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Remove-PathIfExists {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (Test-Path $Path) {
        Remove-Item -Path $Path -Force -ErrorAction Stop
        Write-Host ('[HEAL] 已清理 {0}: {1}' -f $Label, $Path)
    }
}

function Resolve-FlashExeCandidate {
    param([string]$Candidate)

    if (-not $Candidate) {
        return $null
    }

    $trimmed = $Candidate.Trim()
    if (-not $trimmed) {
        return $null
    }

    $normalized = [Environment]::ExpandEnvironmentVariables($trimmed.Trim('"'))
    $variants = @($normalized)

    if (Test-Path $normalized -PathType Container) {
        $variants += (Join-Path $normalized 'Flash.exe')
    }

    foreach ($variant in $variants) {
        if (Test-Path $variant -PathType Leaf) {
            return (Resolve-Path $variant).Path
        }
    }

    return $null
}

function Find-FlashExeFromCommonRoots {
    $roots = @(
        (Join-Path $env:USERPROFILE 'Downloads')
        (Join-Path $env:USERPROFILE 'Desktop')
        (Join-Path $env:USERPROFILE 'Documents')
    )

    foreach ($root in $roots) {
        if (-not (Test-Path $root -PathType Container)) {
            continue
        }

        $matches = @(Get-ChildItem -Path $root -Filter 'Flash.exe' -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
            $_.FullName -match 'Adobe Flash CS6'
        })

        if ($matches.Count -gt 0) {
            $best = $matches | Sort-Object FullName | Select-Object -First 1
            return $best.FullName
        }
    }

    return $null
}

function Resolve-FlashExe {
    param([string]$Candidate)

    $resolvedCandidate = Resolve-FlashExeCandidate -Candidate $Candidate
    if ($resolvedCandidate) {
        Write-Host ('[HEAL] 使用传入的 Flash.exe 路径: {0}' -f $resolvedCandidate)
        return $resolvedCandidate
    }

    try {
        $task = Get-ScheduledTask -TaskName 'FlashCS6Task' -ErrorAction Stop
        $taskAction = $task.Actions | Select-Object -First 1
        $resolvedFromTask = Resolve-FlashExeCandidate -Candidate $taskAction.Execute
        if ($resolvedFromTask) {
            Write-Host ('[HEAL] 使用现有 FlashCS6Task 路径: {0}' -f $resolvedFromTask)
            return $resolvedFromTask
        }
        if ($taskAction.Execute) {
            Write-Host ('[WARN] 现有 FlashCS6Task 路径无效，忽略: {0}' -f $taskAction.Execute)
        }
    } catch {
    }

    $defaults = @(
        'C:\Program Files\Adobe\Adobe Flash CS6\Flash.exe'
        'C:\Program Files (x86)\Adobe\Adobe Flash CS6\Flash.exe'
    )
    foreach ($path in $defaults) {
        if (Test-Path $path) {
            return (Resolve-Path $path).Path
        }
    }

    $discovered = Find-FlashExeFromCommonRoots
    if ($discovered) {
        Write-Host ('[HEAL] 在常见目录中发现 Flash.exe: {0}' -f $discovered)
        return (Resolve-Path $discovered).Path
    }

    Write-Host '[INFO] 未能自动定位 Flash.exe。'
    $manual = Read-Host '请输入 Flash.exe 的完整路径'
    $resolvedManual = Resolve-FlashExeCandidate -Candidate $manual
    if ($resolvedManual) {
        return $resolvedManual
    }

    throw '未找到 Flash.exe，请重新运行 setup 并提供有效路径。'
}

function Clear-LegacyEnvironment {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptDir,
        [Parameter(Mandatory = $true)][string]$FlashLog
    )

    $repoArtifacts = @(
        @{ Path = (Join-Path $ScriptDir 'publish_done.marker'); Label = '旧完成标记' }
        @{ Path = (Join-Path $ScriptDir 'publish_error.marker'); Label = '旧错误标记' }
        @{ Path = (Join-Path $ScriptDir 'flashlog.txt'); Label = '旧本地 trace 日志' }
        @{ Path = (Join-Path $ScriptDir 'compile_output.txt'); Label = '旧输出面板日志' }
        @{ Path = (Join-Path $ScriptDir 'compile_env.sh'); Label = '旧 shell 环境文件' }
    )

    foreach ($artifact in $repoArtifacts) {
        Remove-PathIfExists -Path $artifact.Path -Label $artifact.Label
    }

    Remove-PathIfExists -Path $FlashLog -Label '全局 Flash trace 日志'
}

function Register-CompileTask {
    param(
        [Parameter(Mandatory = $true)][string]$LoaderPath,
        [Parameter(Mandatory = $true)][string]$FlashExe
    )

    $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value) -LogonType Interactive -RunLevel Highest

    $flashSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
    $flashAction = New-ScheduledTaskAction -Execute $FlashExe
    Register-ScheduledTask -TaskName 'FlashCS6Task' -Action $flashAction -Principal $principal -Settings $flashSettings -Description 'Launch Flash CS6 without UAC prompt' -Force | Out-Null

    $compileSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Seconds 30)
    $compileAction = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument ('/c start "" "{0}"' -f $LoaderPath)
    Register-ScheduledTask -TaskName 'CompileTriggerTask' -Action $compileAction -Principal $principal -Settings $compileSettings -Description 'Trigger Flash CS6 compile by opening the CF7 loader JSFL directly' -Force | Out-Null
}

function Write-CompileEnvSh {
    param(
        [Parameter(Mandatory = $true)][string]$EnvPath,
        [Parameter(Mandatory = $true)][string]$LoaderPath,
        [Parameter(Mandatory = $true)][string]$ScriptDir,
        [Parameter(Mandatory = $true)][string]$FlashLog
    )

    $content = @(
        '#!/bin/bash'
        '# Auto-generated by setup_compile_env.ps1'
        ('FLASH_LOG="{0}"' -f ($FlashLog -replace '\\', '/'))
        ('JSFL_PATH="{0}"' -f ($LoaderPath -replace '\\', '/'))
        ('MARKER="{0}"' -f ((Join-Path $ScriptDir 'publish_done.marker') -replace '\\', '/'))
        ('ERROR_MARKER="{0}"' -f ((Join-Path $ScriptDir 'publish_error.marker') -replace '\\', '/'))
        ('SCRIPTS_DIR="{0}"' -f ($ScriptDir -replace '\\', '/'))
    ) -join [Environment]::NewLine

    Write-Utf8File -Path $EnvPath -Content ($content + [Environment]::NewLine)
}

function Assert-SetupHealthy {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectUri,
        [Parameter(Mandatory = $true)][string]$ProjectCfgPath,
        [Parameter(Mandatory = $true)][string]$LoaderPath,
        [Parameter(Mandatory = $true)][string]$FlashExe,
        [Parameter(Mandatory = $true)][string]$MmCfgPath
    )

    $issues = @()

    if (-not (Test-Path $MmCfgPath)) {
        $issues += 'mm.cfg 未生成'
    } else {
        $mmCfg = Get-Content -Raw -Encoding UTF8 $MmCfgPath
        foreach ($line in $ExpectedMmCfg -split [Environment]::NewLine) {
            if ($mmCfg -notmatch [regex]::Escape($line)) {
                $issues += ('mm.cfg 缺少配置: {0}' -f $line)
            }
        }
    }

    if (-not (Test-Path $ProjectCfgPath)) {
        $issues += 'flash_project_path.cfg 未生成'
    } else {
        $actualUri = (Get-Content -Raw -Encoding UTF8 $ProjectCfgPath).Trim()
        if ($actualUri -ne $ProjectUri) {
            $issues += ('flash_project_path.cfg 不匹配: {0}' -f $actualUri)
        }
    }

    if (-not (Test-Path $LoaderPath)) {
        $issues += 'CF7 Loader 未生成'
    }

    try {
        $compileTask = Get-ScheduledTask -TaskName 'CompileTriggerTask' -ErrorAction Stop
        $compileAction = $compileTask.Actions | Select-Object -First 1
        $expectedArgs = '/c start "" "{0}"' -f $LoaderPath
        if ($compileAction.Execute -ne 'cmd.exe' -or $compileAction.Arguments -ne $expectedArgs) {
            $issues += 'CompileTriggerTask 不是期望的直开 JSFL 动作'
        }
    } catch {
        $issues += 'CompileTriggerTask 不存在'
    }

    try {
        $flashTask = Get-ScheduledTask -TaskName 'FlashCS6Task' -ErrorAction Stop
        $flashAction = $flashTask.Actions | Select-Object -First 1
        if ($flashAction.Execute -ne $FlashExe) {
            $issues += 'FlashCS6Task 路径与当前 Flash.exe 不一致'
        }
    } catch {
        $issues += 'FlashCS6Task 不存在'
    }

    if ($issues.Count -gt 0) {
        throw ("环境自检失败:`n - " + ($issues -join "`n - "))
    }
}

if (-not (Test-IsAdministrator)) {
    throw '请右键以管理员身份运行 scripts/setup_compile_env.bat。'
}

Write-Host '========================================'
Write-Host ' Flash CS6 自动化编译环境配置'
Write-Host '========================================'
Write-Host ('[INFO] 项目目录: {0}' -f $ProjectDir)

if (-not $SkipCleanup) {
    Clear-LegacyEnvironment -ScriptDir $ScriptDir -FlashLog $FlashLog
}

$mmCfgPath = Join-Path $env:USERPROFILE 'mm.cfg'
Write-Utf8File -Path $mmCfgPath -Content ($ExpectedMmCfg + [Environment]::NewLine)
Write-Host ('[OK] mm.cfg: {0}' -f $mmCfgPath)

$commandsDir = Get-CommandsDir -ProjectDir $ProjectDir
$projectUri = Convert-ToJsflUri $ProjectDir
$projectCfgPath = Join-Path $commandsDir 'flash_project_path.cfg'
Write-Utf8File -Path $projectCfgPath -Content ($projectUri + [Environment]::NewLine)
Write-Host ('[OK] Flash Commands: {0}' -f $commandsDir)
Write-Host ('[OK] 项目路径配置: {0}' -f $projectCfgPath)

$loaderPath = Join-Path $commandsDir $LoaderFileName
Write-Utf8File -Path $loaderPath -Content (Get-LoaderContent)
Write-Host ('[OK] JSFL Loader: {0}' -f $loaderPath)

$legacyLoaderPath = Join-Path $commandsDir 'compile.jsfl'
if (-not (Test-Path $legacyLoaderPath)) {
    Write-Utf8File -Path $legacyLoaderPath -Content (Get-LoaderContent)
    Write-Host ('[OK] 兼容 Loader: {0}' -f $legacyLoaderPath)
} else {
    Write-Host ('[INFO] 保留已有兼容 Loader: {0}' -f $legacyLoaderPath)
}

$flashExe = Resolve-FlashExe -Candidate $FlashExe
Write-Host ('[OK] Flash.exe: {0}' -f $flashExe)

Register-CompileTask -LoaderPath $loaderPath -FlashExe $flashExe
Write-Host '[OK] 计划任务 FlashCS6Task 已更新'
Write-Host '[OK] 计划任务 CompileTriggerTask 已更新'

$compileEnvPath = Join-Path $ScriptDir 'compile_env.sh'
Write-CompileEnvSh -EnvPath $compileEnvPath -LoaderPath $loaderPath -ScriptDir $ScriptDir -FlashLog $FlashLog
Write-Host ('[OK] Shell 环境配置: {0}' -f $compileEnvPath)

Assert-SetupHealthy -ProjectUri $projectUri -ProjectCfgPath $projectCfgPath -LoaderPath $loaderPath -FlashExe $flashExe -MmCfgPath $mmCfgPath
Write-Host '[OK] 环境自检通过'

if (Get-Process -Name Flash -ErrorAction SilentlyContinue) {
    Write-Host '[INFO] Flash 当前正在运行。若刚更新了 Commands 目录中的旧 Loader，请重启 Flash 后再验证。'
}

Write-Host '========================================'
Write-Host ' 配置完成'
Write-Host '========================================'
