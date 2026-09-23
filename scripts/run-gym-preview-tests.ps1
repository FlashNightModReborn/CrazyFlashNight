[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
if (-not (Test-Path -LiteralPath $commonRunner)) {
    throw "Focused TestLoader runner is missing: $commonRunner"
}

# Keep the TestLoader template transient so this focused task owns only its
# suite and runner files. The shared runner still owns the guarded TestLoader scratch transaction.
$templateLeaf = '.gym-preview-TestLoader-' + [Guid]::NewGuid().ToString('N') + '.as.template'
$templatePath = Join-Path $PSScriptRoot $templateLeaf
$templateRelativePath = 'scripts\' + $templateLeaf
$templateLines = @(
    '#include "../展现/UI交互/UI交互_aka_健身房训练.as"'
    'trace("FocusedTestRunId gym-preview Start: __FOCUSED_RUN_ID__");'
    'org.flashNight.arki.ui.GymPreviewProjectionTest.runAllTests();'
    'org.flashNight.arki.ui.GymTrainingPanelServiceTest.runAllTests();'
    'trace("FocusedTestRunId gym-preview Complete: __FOCUSED_RUN_ID__");'
)
$templateBody = ($templateLines -join [Environment]::NewLine) + [Environment]::NewLine
$utf8 = New-Object System.Text.UTF8Encoding($false)
$bodyBytes = $utf8.GetBytes($templateBody)
[byte[]]$bom = @(0xEF, 0xBB, 0xBF)
$templateBytes = New-Object byte[] ($bom.Length + $bodyBytes.Length)
[Array]::Copy($bom, 0, $templateBytes, 0, $bom.Length)
[Array]::Copy($bodyBytes, 0, $templateBytes, $bom.Length, $bodyBytes.Length)
$templateCreated = $false
$templateHash = $null

try {
    $stream = [System.IO.File]::Open(
        $templatePath,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None)
    try {
        $stream.Write($templateBytes, 0, $templateBytes.Length)
        $stream.Flush()
    } finally {
        $stream.Dispose()
    }
    $templateCreated = $true
    $templateHash = (Get-FileHash -LiteralPath $templatePath -Algorithm SHA256).Hash

    $focusedRun = @{
        DomainId = 'gym-preview'
        TemplateRelativePath = $templateRelativePath
        SuiteRelativePaths = @(
            'scripts\类定义\org\flashNight\arki\ui\GymPreviewProjectionTest.as',
            'scripts\类定义\org\flashNight\arki\ui\GymTrainingPanelServiceTest.as'
        )
        SuiteFqns = @(
            'org.flashNight.arki.ui.GymPreviewProjectionTest',
            'org.flashNight.arki.ui.GymTrainingPanelServiceTest'
        )
        AdditionalAsRelativePaths = @(
            'scripts\类定义\org\flashNight\arki\ui\GymPreviewProjection.as',
            'scripts\类定义\org\flashNight\arki\ui\GymTrainingPanelService.as',
            'scripts\展现\UI交互\UI交互_aka_健身房训练.as'
        )
        ExpectedTracePatterns = @(
            '(?m)^GymPreviewProjectionTest Tests Passed: [1-9][0-9]*\r?$',
            '(?m)^GymPreviewProjectionTest Tests Failed: 0\r?$',
            '(?m)^GymTrainingPanelServiceTest Tests Passed: [1-9][0-9]*\r?$',
            '(?m)^GymTrainingPanelServiceTest Tests Failed: 0\r?$'
        )
        SuccessSummary = 'gym preview projection assertions passed'
        TimeoutSeconds = $TimeoutSeconds
        SkipCompile = $SkipCompile
    }
    & $commonRunner @focusedRun
} finally {
    if ($templateCreated -and (Test-Path -LiteralPath $templatePath)) {
        $currentHash = (Get-FileHash -LiteralPath $templatePath -Algorithm SHA256).Hash
        if ($currentHash -ne $templateHash) {
            throw "Temporary gym preview TestLoader template changed during the run; preserved at $templatePath"
        }
        Remove-Item -LiteralPath $templatePath
    }
}
