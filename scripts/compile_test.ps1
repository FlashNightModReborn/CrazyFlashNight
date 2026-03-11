# compile_test.ps1 - Agent 自动编译触发脚本 (PowerShell 版)

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$ScriptDir = Split-Path -Parent $PSCommandPath
$ProjectDir = Split-Path -Parent $ScriptDir
$Marker = Join-Path $ScriptDir 'publish_done.marker'
$ErrorMarker = Join-Path $ScriptDir 'publish_error.marker'
$CompileOutput = Join-Path $ScriptDir 'compile_output.txt'
$CompilerErrors = Join-Path $ScriptDir 'compiler_errors.txt'
$FlashLog = Join-Path $env:APPDATA 'Macromedia\Flash Player\Logs\flashlog.txt'
$LocalFlashLog = Join-Path $ScriptDir 'flashlog.txt'
$LoaderFileName = 'cf7_compile_loader.jsfl'

function Convert-ToJsflUri {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = (Resolve-Path $Path).Path.Replace('\', '/')
    return 'file:///' + $resolved.Replace(':', '|')
}

function Get-CommandsDirForProject {
    param([Parameter(Mandatory = $true)][string]$ProjectDir)

    $cfgBase = Join-Path $env:LOCALAPPDATA 'Adobe\Flash CS6'
    if (-not (Test-Path $cfgBase)) {
        return $null
    }

    $expectedUri = Convert-ToJsflUri $ProjectDir
    $candidates = @()
    Get-ChildItem $cfgBase -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $commandsDir = Join-Path $_.FullName 'Configuration\Commands'
        if (-not (Test-Path $commandsDir)) {
            return
        }

        $projectCfg = Join-Path $commandsDir 'flash_project_path.cfg'
        $projectUri = if (Test-Path $projectCfg) {
            (Get-Content -Raw -Encoding UTF8 $projectCfg).Trim()
        } else {
            $null
        }

        $candidates += [pscustomobject]@{
            Lang        = $_.Name
            CommandsDir = $commandsDir
            ProjectUri  = $projectUri
        }
    }

    $matched = $candidates | Where-Object { $_.ProjectUri -eq $expectedUri } | Select-Object -First 1
    if ($matched) {
        return $matched.CommandsDir
    }

    $fallback = $null
    $fallbackRank = [int]::MaxValue
    foreach ($candidate in $candidates) {
        $candidateRank = Get-LangRank $candidate.Lang
        if ((-not $fallback) -or $candidateRank -lt $fallbackRank -or ($candidateRank -eq $fallbackRank -and $candidate.Lang -lt $fallback.Lang)) {
            $fallback = $candidate
            $fallbackRank = $candidateRank
        }
    }

    if ($fallback) {
        return $fallback.CommandsDir
    }

    return $null
}

function Get-LangRank {
    param([string]$Lang)

    switch ($Lang) {
        'zh_CN' { return 0 }
        'en_US' { return 1 }
        default { return 2 }
    }
}

function Get-TaskMode {
    param(
        [Parameter(Mandatory = $true)]$Task,
        [Parameter(Mandatory = $true)][string]$ExpectedLoaderPath
    )

    $action = $Task.Actions | Select-Object -First 1
    $executeName = [System.IO.Path]::GetFileName(($action.Execute | Out-String).Trim())
    $arguments = ($action.Arguments | Out-String).Trim()

    $isDirect = $executeName -ieq 'cmd.exe' -and $arguments -eq ('/c start "" "{0}"' -f $ExpectedLoaderPath)
    $isLegacy = $executeName -ieq 'powershell.exe' -and $arguments -match 'trigger_compile\.ps1'

    return [pscustomobject]@{
        Execute   = $action.Execute
        Arguments = $arguments
        IsDirect  = $isDirect
        IsLegacy  = $isLegacy
    }
}

$commandsDir = Get-CommandsDirForProject -ProjectDir $ProjectDir
if (-not $commandsDir) {
    Write-Host '[ERROR] 找不到当前项目对应的 Flash Commands 目录，请先运行 scripts/setup_compile_env.bat'
    exit 1
}

$projectCfgPath = Join-Path $commandsDir 'flash_project_path.cfg'
$expectedProjectUri = Convert-ToJsflUri $ProjectDir
$actualProjectUri = if (Test-Path $projectCfgPath) {
    (Get-Content -Raw -Encoding UTF8 $projectCfgPath).Trim()
} else {
    $null
}
if ($actualProjectUri -ne $expectedProjectUri) {
    Write-Host '[ERROR] flash_project_path.cfg 与当前项目不匹配，请重新运行 scripts/setup_compile_env.bat'
    Write-Host ('        期望: {0}' -f $expectedProjectUri)
    Write-Host ('        当前: {0}' -f $actualProjectUri)
    exit 1
}

$loaderPath = Join-Path $commandsDir $LoaderFileName
if (-not (Test-Path $loaderPath)) {
    Write-Host ('[ERROR] 缺少 Loader: {0}' -f $loaderPath)
    Write-Host '        请重新运行 scripts/setup_compile_env.bat'
    exit 1
}

try {
    $task = Get-ScheduledTask -TaskName 'CompileTriggerTask' -ErrorAction Stop
} catch {
    Write-Host '[ERROR] CompileTriggerTask 未找到，请先运行 scripts/setup_compile_env.bat'
    exit 1
}

$taskMode = Get-TaskMode -Task $task -ExpectedLoaderPath $loaderPath
if (-not ($taskMode.IsDirect -or $taskMode.IsLegacy)) {
    Write-Host '[ERROR] CompileTriggerTask 不是受支持的触发方式，请重新运行 scripts/setup_compile_env.bat'
    Write-Host ('        Execute  : {0}' -f $taskMode.Execute)
    Write-Host ('        Arguments: {0}' -f $taskMode.Arguments)
    exit 1
}

if ($taskMode.IsLegacy) {
    Write-Host '[WARN] CompileTriggerTask 仍在使用旧版 trigger_compile.ps1 包装器。当前仓库已兼容，但建议重新运行 setup 以切到直开 JSFL。'
}

Remove-Item -Path $Marker -ErrorAction SilentlyContinue
Remove-Item -Path $ErrorMarker -ErrorAction SilentlyContinue

$flashLogBefore = if (Test-Path $FlashLog) { (Get-Item $FlashLog).LastWriteTimeUtc } else { $null }
$compileOutputBefore = if (Test-Path $CompileOutput) { (Get-Item $CompileOutput).LastWriteTimeUtc } else { $null }

Write-Host '[INFO] 触发编译...'
Start-ScheduledTask -TaskName 'CompileTriggerTask'

for ($i = 1; $i -le 30; $i++) {
    if (Test-Path $Marker) {
        Write-Host ('[OK] 编译完成 ({0}s)' -f $i)
        Remove-Item -Path $Marker -ErrorAction SilentlyContinue

        if (Test-Path $FlashLog) {
            $flashLogItem = Get-Item $FlashLog
            if ($flashLogBefore -and $flashLogItem.LastWriteTimeUtc -le $flashLogBefore) {
                Write-Host '[WARN] flashlog.txt 未刷新，本次 trace 可能还是旧日志'
            } else {
                Write-Host '=== FLASH TRACE OUTPUT ==='
                Get-Content -Path $FlashLog -Encoding UTF8
                Write-Host '=== END ==='
                Copy-Item $FlashLog $LocalFlashLog -Force
            }
        } else {
            Write-Host '[INFO] 无 trace 输出 (publish 模式不执行 trace)'
        }

        if (Test-Path $CompileOutput) {
            $compileOutputItem = Get-Item $CompileOutput
            if ($compileOutputBefore -and $compileOutputItem.LastWriteTimeUtc -le $compileOutputBefore) {
                Write-Host '[WARN] compile_output.txt 未刷新；若本次需要看 Output Panel，请直接检查 Flash IDE 面板'
            } else {
                Write-Host ('[INFO] compile_output.txt 已刷新: {0}' -f $compileOutputItem.LastWriteTime)
            }
        }

        # 检查 Compiler Errors 面板输出
        $hasCompileError = $false
        if (Test-Path $CompilerErrors) {
            $errContent = Get-Content -Path $CompilerErrors -Raw -Encoding UTF8
            if ($errContent -and $errContent -notmatch '^\s*0 个错误' -and $errContent -notmatch '^\s*0 Errors') {
                Write-Host '=== COMPILER ERRORS ==='
                Write-Host $errContent
                Write-Host '=== END COMPILER ERRORS ==='
                $hasCompileError = $true
            }
        }

        if ($hasCompileError) {
            exit 1
        }
        exit 0
    }

    if (Test-Path $ErrorMarker) {
        Write-Host '[ERROR] 编译失败:'
        Get-Content -Path $ErrorMarker -Encoding UTF8
        Remove-Item -Path $ErrorMarker -ErrorAction SilentlyContinue
        exit 1
    }

    Start-Sleep -Seconds 1
}

Write-Host '[TIMEOUT] 30 秒未完成，可能原因：'
Write-Host '  - Flash CS6 未运行'
Write-Host '  - TestLoader 未在 Flash 中打开'
Write-Host '  - CompileTriggerTask 计划任务未创建'
Write-Host '  - 仍在弹 UAC 或旧任务卡住'
exit 1
