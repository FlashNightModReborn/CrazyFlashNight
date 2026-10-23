[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 360, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $projectDir 'tools/cf6-scene-completion/interactive-art-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$allowedActions = @('stop();', 'stop();this.blendMode="layer";', 'stop();content.setMask(maskShape);', 'stop();content.cacheAsBitmap=true;maskShape.cacheAsBitmap=true;content.setMask(maskShape);')
foreach ($asset in $manifest.assets) {
    $assetDir = Split-Path -Parent (Join-Path $projectDir $asset.xfl)
    foreach ($source in Get-ChildItem -LiteralPath $assetDir -Filter '*.xml' -Recurse -File) {
        $relative = $source.FullName.Substring($projectDir.Length + 1).Replace('\','/')
        $identity = $manifest.outputs.PSObject.Properties[$relative].Value
        if ($null -eq $identity -or (Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -ne $identity.sha256) {
            throw "Interactive source identity changed: $relative"
        }
        [xml]$xml = Get-Content -LiteralPath $source.FullName -Raw -Encoding UTF8
        foreach ($script in $xml.SelectNodes("//*[local-name()='Actionscript']/*[local-name()='script']")) {
            if ($allowedActions -cnotcontains $script.InnerText) { throw "Unexpected business/action script: $relative" }
        }
    }
    $swf = Join-Path $projectDir $asset.swf
    $info = Get-Item -LiteralPath $swf
    Write-Host ('Cf6InteractiveAssets ActualSwf: {0} bytes={1} sha256={2}' -f $swf,$info.Length,(Get-FileHash -LiteralPath $swf -Algorithm SHA256).Hash)
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-interactive-assets' `
    -TemplateRelativePath 'scripts/test-runners/cf6-interactive-assets/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6InteractiveAssetsTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6InteractiveAssetsTest') `
    -ExpectedTracePatterns @('(?m)^Cf6InteractiveAssetsTest Tests Passed: 37\r?$', '(?m)^Cf6InteractiveAssetsTest Tests Failed: 0\r?$') `
    -SuccessSummary '37 assertions over 73 actual native interactive-art frames; alpha bounds, empty endings, stop behavior and bounded business probes; no full-game acceptance' `
    -AsyncBehaviorTimeoutSeconds 120 -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
