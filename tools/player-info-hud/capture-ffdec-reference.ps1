[CmdletBinding()]
param(
    [string]$OutputDirectory = "tmp/player-info-hud-ffdec-binary-reference"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$Invariant = [System.Globalization.CultureInfo]::InvariantCulture
$FfdecRelative = "tools/ffdec/ffdec-cli.exe"
$SwfRelative = "flashswf/UI/玩家信息界面.swf"
$Ffdec = Join-Path $RepoRoot $FfdecRelative
$Swf = Join-Path $RepoRoot $SwfRelative

$ExpectedSwf = @{
    size = 104124
    sha256 = "450B1F9A8B445EE3E28C63682EA00124A191F56D05D759B8590210FC0066A615"
}
$ExpectedFfdec = @(
    @{ path = "tools/ffdec/ffdec-cli.exe"; size = 35854; sha256 = "C03AD5D22008246B9F2523A70830502ED0D01610F4054912B43AE70F58DDDD86" },
    @{ path = "tools/ffdec/ffdec-cli.jar"; size = 1554; sha256 = "3FE309A320F9136A46F5FF84E21E96903B8DD8D94B829DE4895BAAE9B486B6C7" },
    @{ path = "tools/ffdec/ffdec.jar"; size = 3542569; sha256 = "7F75B47152D955BE5CCC853EB259A1A7910EA9A0BD2B41CF9B9085BCFB003952" },
    @{ path = "tools/ffdec/lib/ffdec_lib.jar"; size = 4823329; sha256 = "49E4DA602A9000E3556C788A9653312A7B1E2EC0A7C6B8FF9E075C6B67B03630" }
)
$Cases = @(
    @{ id = "empty";    hp = 129; mp = 101 },
    @{ id = "min_step"; hp = 128; mp = 100 },
    @{ id = "p25";      hp = 97;  mp = 76 },
    @{ id = "p50";      hp = 65;  mp = 51 },
    @{ id = "p75";      hp = 33;  mp = 26 },
    @{ id = "p99";      hp = 3;   mp = 2 },
    @{ id = "full";     hp = 1;   mp = 1 },
    @{ id = "mp_vf34";  hp = 44;  mp = 34 },
    @{ id = "mp_vf35";  hp = 45;  mp = 35 },
    @{ id = "mp_vf70";  hp = 90;  mp = 70 },
    @{ id = "mp_vf91";  hp = 117; mp = 91 }
)

function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Hash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function TextHash([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Utf8NoBom.GetBytes($Text)))).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Identity([string]$Relative) {
    $path = Join-Path $RepoRoot $Relative
    Assert (Test-Path -LiteralPath $path -PathType Leaf) "Missing identity input: $Relative"
    $item = Get-Item -LiteralPath $path
    return [pscustomobject][ordered]@{
        path = $Relative.Replace("\", "/")
        sizeBytes = [long]$item.Length
        sha256 = Hash $path
    }
}

function RunFfdec([string[]]$Arguments, [string]$RequiredToken = "") {
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $lines = @(& $Ffdec @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldPreference
    }
    $text = $lines -join "`n"
    Assert ($code -eq 0) "FFDec failed ($code):`n$(($lines | Select-Object -Last 20) -join "`n")"
    if ($RequiredToken) {
        Assert $text.Contains($RequiredToken) "FFDec exited 0 without completion token '$RequiredToken'."
    }
    return [pscustomobject]@{ code = [int]$code; output = $text }
}

function InvariantDouble([string]$Text) {
    return [double]::Parse($Text, [System.Globalization.NumberStyles]::Float, $Invariant)
}

function Near([double]$A, [double]$B) {
    return [Math]::Abs($A - $B) -le 0.0000001
}

function Placement(
    [System.Xml.XmlElement]$Node,
    [int]$Id,
    [string]$Name,
    [int]$ScaleNumerator,
    [int]$Tx,
    [int]$Ty,
    [int]$RootTy
) {
    Assert ($null -ne $Node) "Missing placement '$Name'."
    Assert ([int]$Node.characterId -eq $Id -and $Node.name -eq $Name) "Placement '$Name' identity changed."
    $matrix = [System.Xml.XmlElement]$Node.SelectSingleNode("./matrix")
    Assert ($null -ne $matrix -and $matrix.hasScale -eq "true" -and $matrix.hasRotate -eq "false") "Placement '$Name' matrix flags changed."
    $scaleX = InvariantDouble $matrix.scaleX
    $scaleY = InvariantDouble $matrix.scaleY
    $exactScale = [double]$ScaleNumerator / 65536.0
    Assert ([Math]::Round($scaleX * 65536) -eq $ScaleNumerator) "Placement '$Name' X scale changed."
    Assert ([Math]::Round($scaleY * 65536) -eq $ScaleNumerator) "Placement '$Name' Y scale changed."
    Assert (Near $scaleX $exactScale -and Near $scaleY $exactScale) "Placement '$Name' scale is not its expected fixed16.16 value."
    Assert ([int]$matrix.translateX -eq $Tx -and [int]$matrix.translateY -eq $Ty) "Placement '$Name' translation changed."
    return [pscustomobject][ordered]@{
        characterId = $Id
        instanceName = $Name
        sourceMatrix = [ordered]@{
            fixed16_16ScaleNumerator = $ScaleNumerator
            translateXTwips = $Tx
            translateYTwips = $Ty
        }
        localMatrixPx = @($exactScale, 0.0, 0.0, $exactScale, ($Tx / 20.0), ($Ty / 20.0))
        stageMatrixPx = @($exactScale, 0.0, 0.0, $exactScale, ($Tx / 20.0), (($RootTy + $Ty) / 20.0))
    }
}

function FrameMap([string]$Root, [int]$Id, [string]$Extension, [int]$Count) {
    $directories = @(Get-ChildItem -LiteralPath $Root -Recurse -Directory | Where-Object { $_.Name -like "DefineSprite_$Id*" })
    Assert ($directories.Count -eq 1) "Expected one FFDec directory for sprite $Id; got $($directories.Count)."
    $files = @(Get-ChildItem -LiteralPath $directories[0].FullName -File -Filter "*.$Extension" | Where-Object { $_.BaseName -match "^[0-9]+$" })
    Assert ($files.Count -eq $Count) "Sprite $Id exported $($files.Count) .$Extension frames; expected $Count."
    $map = @{}
    foreach ($file in $files) {
        $number = [int]$file.BaseName
        Assert (-not $map.ContainsKey($number)) "Duplicate sprite $Id frame $number."
        $map[$number] = $file.FullName
    }
    foreach ($number in 1..$Count) {
        Assert $map.ContainsKey($number) "Missing sprite $Id frame $number."
    }
    return $map
}

function PngSize([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    Assert ($bytes.Length -ge 24) "Truncated PNG: $Path"
    Assert ([BitConverter]::ToString($bytes[0..7]) -eq "89-50-4E-47-0D-0A-1A-0A") "Invalid PNG: $Path"
    $width = ([uint32]$bytes[16] -shl 24) -bor ([uint32]$bytes[17] -shl 16) -bor ([uint32]$bytes[18] -shl 8) -bor $bytes[19]
    $height = ([uint32]$bytes[20] -shl 24) -bor ([uint32]$bytes[21] -shl 16) -bor ([uint32]$bytes[22] -shl 8) -bor $bytes[23]
    return [pscustomobject]@{ width = [int]$width; height = [int]$height }
}

function SvgCanvas([string]$Path) {
    $text = [IO.File]::ReadAllText($Path, $Utf8NoBom)
    $width = [regex]::Match($text, "<svg\b[^>]*\bwidth=`"([-+0-9.eE]+)px`"")
    $height = [regex]::Match($text, "<svg\b[^>]*\bheight=`"([-+0-9.eE]+)px`"")
    $matrix = [regex]::Match($text, "<g\s+transform=`"matrix\(\s*([-+0-9.eE]+)\s*,\s*([-+0-9.eE]+)\s*,\s*([-+0-9.eE]+)\s*,\s*([-+0-9.eE]+)\s*,\s*([-+0-9.eE]+)\s*,\s*([-+0-9.eE]+)\s*\)")
    Assert ($width.Success -and $height.Success -and $matrix.Success) "Cannot parse FFDec SVG canvas contract: $Path"
    $values = @(1..6 | ForEach-Object { InvariantDouble $matrix.Groups[$_].Value })
    Assert (Near $values[0] 1.0 -and Near $values[1] 0.0 -and Near $values[2] 0.0 -and Near $values[3] 1.0) "Unexpected FFDec SVG root transform: $Path"
    return [pscustomobject]@{
        width = InvariantDouble $width.Groups[1].Value
        height = InvariantDouble $height.Groups[1].Value
        originX = $values[4]
        originY = $values[5]
    }
}

function ConfirmCanvas([object]$Canvas, [double[]]$Expected, [string]$Label) {
    Assert (
        (Near $Canvas.width $Expected[0]) -and
        (Near $Canvas.height $Expected[1]) -and
        (Near $Canvas.originX $Expected[2]) -and
        (Near $Canvas.originY $Expected[3])
    ) "$Label FFDec logical canvas/origin changed."
}

Assert (-not [IO.Path]::IsPathRooted($OutputDirectory)) "OutputDirectory must be repository-relative."
$OutputRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputDirectory))
$TmpRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot "tmp")).TrimEnd("\") + "\"
Assert $OutputRoot.StartsWith($TmpRoot, [StringComparison]::OrdinalIgnoreCase) "OutputDirectory must be below ignored tmp/."
Assert (-not (Test-Path -LiteralPath $OutputRoot)) "OutputDirectory already exists; use a fresh path."

$FfdecIdentities = @()
foreach ($expected in $ExpectedFfdec) {
    $actual = Identity $expected.path
    Assert ($actual.sizeBytes -eq $expected.size) "FFDec closure size changed: $($expected.path)."
    Assert ($actual.sha256 -eq $expected.sha256.ToLowerInvariant()) "FFDec closure hash changed: $($expected.path)."
    $FfdecIdentities += $actual
}
$SwfIdentity = Identity $SwfRelative
Assert ($SwfIdentity.sizeBytes -eq $ExpectedSwf.size) "Target SWF size changed."
Assert ($SwfIdentity.sha256 -eq $ExpectedSwf.sha256.ToLowerInvariant()) "Target SWF hash changed."

$java = Get-Command java.exe -ErrorAction Stop
$oldPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = "Continue"
    $javaVersion = @(& $java.Source -version 2>&1 | ForEach-Object { $_.ToString() }) -join "`n"
    $javaExit = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $oldPreference
}
Assert ($javaExit -eq 0) "java.exe -version failed."
$javaFile = Get-Item -LiteralPath $java.Source
$JavaIdentity = [pscustomobject][ordered]@{
    executableName = $javaFile.Name
    sizeBytes = [long]$javaFile.Length
    sha256 = Hash $javaFile.FullName
    versionOutput = $javaVersion
}

New-Item -ItemType Directory -Path $OutputRoot | Out-Null
$Scratch = Join-Path $OutputRoot "._ffdec-scratch"
New-Item -ItemType Directory -Path $Scratch | Out-Null

$Report = $null
try {
    $version = RunFfdec @("-help")
    $versionMatch = [regex]::Match($version.output, "JPEXS Free Flash Decompiler v\.([0-9.]+)")
    Assert ($versionMatch.Success -and $versionMatch.Groups[1].Value -eq "21.1.1") "Expected FFDec 21.1.1."

    $xmlPath = Join-Path $Scratch "player-info-hud.xml"
    $xmlRun = RunFfdec @("-swf2xml", $Swf, $xmlPath)
    Assert (Test-Path -LiteralPath $xmlPath -PathType Leaf) "FFDec produced no swf2xml file."
    $XmlIdentity = [pscustomobject][ordered]@{
        sizeBytes = [long](Get-Item -LiteralPath $xmlPath).Length
        sha256 = Hash $xmlPath
        retained = $false
    }
    [xml]$xml = [IO.File]::ReadAllText($xmlPath, $Utf8NoBom)

    $exports = @($xml.SelectNodes("//item[@type='ExportAssetsTag' and names/item='玩家信息界面']"))
    Assert ($exports.Count -eq 1) "Expected one ExportAssets linkage named 玩家信息界面."
    $tags = @($exports[0].SelectNodes("./tags/item"))
    $names = @($exports[0].SelectNodes("./names/item"))
    Assert ($tags.Count -eq 1 -and $names.Count -eq 1 -and $names[0].InnerText -eq "玩家信息界面") "Root linkage mapping is ambiguous."
    $rootId = [int]$tags[0].InnerText
    Assert ($rootId -eq 454) "Root linkage character changed from 454."

    $rootSprites = @($xml.SelectNodes("//item[@type='DefineSpriteTag' and @spriteId='454']"))
    Assert ($rootSprites.Count -eq 1 -and [int]$rootSprites[0].frameCount -eq 1) "Root sprite 454 topology changed."
    $rootSprite = [System.Xml.XmlElement]$rootSprites[0]
    $rootPlaces = @($xml.SelectNodes("/swf/tags/item[(@type='PlaceObject2Tag' or @type='PlaceObject3Tag') and @characterId='454']"))
    Assert ($rootPlaces.Count -eq 1) "Expected one stage placement of root sprite 454."
    $rootPlace = [System.Xml.XmlElement]$rootPlaces[0]
    $rootMatrix = [System.Xml.XmlElement]$rootPlace.SelectSingleNode("./matrix")
    Assert ($rootMatrix.hasScale -eq "false" -and $rootMatrix.hasRotate -eq "false") "Root stage matrix flags changed."
    Assert ([int]$rootMatrix.translateX -eq 0 -and [int]$rootMatrix.translateY -eq 60) "Root stage translation changed from (0, 60) twips."

    $hpNodes = @($rootSprite.SelectNodes("./subTags/item[(@type='PlaceObject2Tag' or @type='PlaceObject3Tag') and @name='主角hp显示界面']"))
    $mpNodes = @($rootSprite.SelectNodes("./subTags/item[(@type='PlaceObject2Tag' or @type='PlaceObject3Tag') and @name='主角mp显示界面']"))
    Assert ($hpNodes.Count -eq 1 -and $mpNodes.Count -eq 1) "HP/MP named placement cardinality changed."
    $hpPlacement = Placement $hpNodes[0] 380 "主角hp显示界面" 55523 755 53 60
    $mpPlacement = Placement $mpNodes[0] 119 "主角mp显示界面" 70848 1802 -86 60

    $hpSprite = $xml.SelectSingleNode("//item[@type='DefineSpriteTag' and @spriteId='380']")
    $mpSprite = $xml.SelectSingleNode("//item[@type='DefineSpriteTag' and @spriteId='119']")
    Assert ($null -ne $hpSprite -and [int]$hpSprite.frameCount -eq 130) "HP timeline changed from 130 frames."
    Assert ($null -ne $mpSprite -and [int]$mpSprite.frameCount -eq 101) "MP timeline changed from 101 frames."

    $pngRoot = Join-Path $Scratch "png"
    $svgRoot = Join-Path $Scratch "svg"
    $pngRun = RunFfdec @("-onerror", "abort", "-exportTimeout", "180", "-selectid", "119,380", "-format", "sprite:png", "-export", "sprite", $pngRoot, $Swf) "OK"
    $svgRun = RunFfdec @("-onerror", "abort", "-exportTimeout", "180", "-selectid", "119,380", "-format", "sprite:svg", "-export", "sprite", $svgRoot, $Swf) "OK"
    $hpPng = FrameMap $pngRoot 380 "png" 130
    $mpPng = FrameMap $pngRoot 119 "png" 101
    $hpSvg = FrameMap $svgRoot 380 "svg" 130
    $mpSvg = FrameMap $svgRoot 119 "svg" 101

    $hpFrames = @($Cases | ForEach-Object { [int]$_.hp } | Sort-Object -Unique)
    $mpFrames = @($Cases | ForEach-Object { [int]$_.mp } | Sort-Object -Unique)
    Assert ($Cases.Count -eq 11 -and $hpFrames.Count -eq 11 -and $mpFrames.Count -eq 11) "Expected 11 corpus cases with 11 unique HP and MP frames."
    $hpCanvas = $null
    foreach ($frame in $hpFrames) {
        $canvas = SvgCanvas $hpSvg[$frame]
        ConfirmCanvas $canvas @(110.3, 180.3, 55.15, 55.2) "HP frame $frame"
        if ($null -eq $hpCanvas) { $hpCanvas = $canvas }
    }
    $mpCanvas = $null
    foreach ($frame in $mpFrames) {
        $canvas = SvgCanvas $mpSvg[$frame]
        ConfirmCanvas $canvas @(214.95, 131.75, 39.55, 5.45) "MP frame $frame"
        if ($null -eq $mpCanvas) { $mpCanvas = $canvas }
    }

    $Artifacts = @()
    $ArtifactByPath = @{}
    foreach ($component in @(
        @{ id = "hp"; frames = $hpFrames; files = $hpPng; width = 110; height = 180 },
        @{ id = "mp"; frames = $mpFrames; files = $mpPng; width = 214; height = 131 }
    )) {
        $destinationRoot = Join-Path $OutputRoot "components\$($component.id)"
        New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
        foreach ($frame in $component.frames) {
            $name = "frame-{0:D3}.png" -f $frame
            $destination = Join-Path $destinationRoot $name
            Copy-Item -LiteralPath $component.files[$frame] -Destination $destination
            $size = PngSize $destination
            Assert ($size.width -eq $component.width -and $size.height -eq $component.height) "$($component.id) frame $frame dimensions changed."
            $relative = "components/$($component.id)/$name"
            $artifact = [pscustomobject][ordered]@{
                path = $relative
                component = $component.id
                frame = [int]$frame
                encodedWidthPx = $size.width
                encodedHeightPx = $size.height
                sizeBytes = [long](Get-Item -LiteralPath $destination).Length
                sha256 = Hash $destination
            }
            $Artifacts += $artifact
            $ArtifactByPath[$relative] = $artifact
        }
    }
    $Artifacts = @($Artifacts | Sort-Object path)
    $CaseRecords = @(
        foreach ($case in $Cases) {
            $hpPath = "components/hp/frame-{0:D3}.png" -f $case.hp
            $mpPath = "components/mp/frame-{0:D3}.png" -f $case.mp
            [pscustomobject][ordered]@{
                id = $case.id
                hp = [ordered]@{ frame = [int]$case.hp; artifact = $hpPath; sha256 = $ArtifactByPath[$hpPath].sha256 }
                mp = [ordered]@{ frame = [int]$case.mp; artifact = $mpPath; sha256 = $ArtifactByPath[$mpPath].sha256 }
            }
        }
    )

    $revisionLines = @(
        "schema=player-info-hud-ffdec-reference/v1",
        "ffdecVersion=21.1.1",
        "ffdecCli=$($FfdecIdentities[0].sha256)",
        "ffdecEngine=$($FfdecIdentities[2].sha256)",
        "ffdecCore=$($FfdecIdentities[3].sha256)",
        "swf=$($SwfIdentity.sha256)",
        "swfXml=$($XmlIdentity.sha256)",
        "root=454,0,60",
        "hp=380,55523,755,53,110.3,180.3,55.15,55.2",
        "mp=119,70848,1802,-86,214.95,131.75,39.55,5.45"
    )
    foreach ($artifact in $Artifacts) {
        $revisionLines += "artifact=$($artifact.path),$($artifact.sha256)"
    }
    $revision = "sha256:" + (TextHash ($revisionLines -join "`n"))

    $hpScale = [double]$hpPlacement.stageMatrixPx[0]
    $mpScale = [double]$mpPlacement.stageMatrixPx[0]
    $Report = [pscustomobject][ordered]@{
        schemaVersion = "player-info-hud-ffdec-reference/v1"
        status = "ffdec_binary_reference_frozen"
        scope = "selected_component_frames_with_exact_stage_compositor_contract"
        referenceSetRevision = $revision
        source = [ordered]@{
            swf = $SwfIdentity
            ffdecVersion = "21.1.1"
            ffdecClosure = $FfdecIdentities
            javaRuntime = $JavaIdentity
            swf2xml = $XmlIdentity
        }
        topology = [ordered]@{
            linkage = [ordered]@{ name = "玩家信息界面"; characterId = 454; rootSpriteFrameCount = 1 }
            rootStagePlacement = [ordered]@{
                characterId = 454
                depth = [int]$rootPlace.depth
                translateXTwips = 0
                translateYTwips = 60
                stageMatrixPx = @(1.0, 0.0, 0.0, 1.0, 0.0, 3.0)
            }
            hp = $hpPlacement
            mp = $mpPlacement
        }
        componentCanvasContract = [ordered]@{
            hp = [ordered]@{
                logicalCanvasPx = [ordered]@{ width = $hpCanvas.width; height = $hpCanvas.height }
                encodedPngPixels = [ordered]@{ width = 110; height = 180 }
                localOriginPx = [ordered]@{ x = $hpCanvas.originX; y = $hpCanvas.originY }
                stageTopLeftPx = [ordered]@{
                    x = [double]$hpPlacement.stageMatrixPx[4] - $hpScale * $hpCanvas.originX
                    y = [double]$hpPlacement.stageMatrixPx[5] - $hpScale * $hpCanvas.originY
                }
                stageDrawSizePx = [ordered]@{ width = $hpScale * $hpCanvas.width; height = $hpScale * $hpCanvas.height }
            }
            mp = [ordered]@{
                logicalCanvasPx = [ordered]@{ width = $mpCanvas.width; height = $mpCanvas.height }
                encodedPngPixels = [ordered]@{ width = 214; height = 131 }
                localOriginPx = [ordered]@{ x = $mpCanvas.originX; y = $mpCanvas.originY }
                stageTopLeftPx = [ordered]@{
                    x = [double]$mpPlacement.stageMatrixPx[4] - $mpScale * $mpCanvas.originX
                    y = [double]$mpPlacement.stageMatrixPx[5] - $mpScale * $mpCanvas.originY
                }
                stageDrawSizePx = [ordered]@{ width = $mpScale * $mpCanvas.width; height = $mpScale * $mpCanvas.height }
            }
            composition = "Map each encoded PNG onto its logical canvas; place logical top-left at stageTranslation - stageScale * localOrigin; then crop to 1024x64."
            stageCompositeGenerated = $false
        }
        selectedCases = $CaseRecords
        artifacts = $Artifacts
        execution = [ordered]@{
            swf2xmlExitCode = $xmlRun.code
            pngExportExitCode = $pngRun.code
            svgExportExitCode = $svgRun.code
            fullTimelineScratchDeleted = $true
            retainedFilePolicy = "Only 22 selected PNGs and this report remain below ignored tmp/."
        }
        oracleBoundary = [ordered]@{
            flashPlayerRuntimeOracleEquivalent = $false
            closesOracleFrozenGate = $false
            permittedUse = "Deterministic binary-SWF cross-reference for geometry, human visual review, Web, and Svg.Skia comparison."
            limitation = "FFDec neither executes the AS2 fixture nor reproduces Adobe Flash Player rendering/timing; this status is not oracle_frozen."
        }
    }

    foreach ($expected in $ExpectedFfdec) {
        $actual = Identity $expected.path
        Assert ($actual.sizeBytes -eq $expected.size -and $actual.sha256 -eq $expected.sha256.ToLowerInvariant()) "FFDec input changed during capture."
    }
    $swfAfter = Identity $SwfRelative
    Assert ($swfAfter.sizeBytes -eq $SwfIdentity.sizeBytes -and $swfAfter.sha256 -eq $SwfIdentity.sha256) "SWF changed during capture."
}
finally {
    if (Test-Path -LiteralPath $Scratch) {
        $scratchFull = [IO.Path]::GetFullPath($Scratch)
        $outputPrefix = [IO.Path]::GetFullPath($OutputRoot).TrimEnd("\") + "\"
        Assert $scratchFull.StartsWith($outputPrefix, [StringComparison]::OrdinalIgnoreCase) "Refusing to clean scratch outside the fresh output."
        Remove-Item -LiteralPath $scratchFull -Recurse -Force
    }
}

Assert ($null -ne $Report) "Capture produced no report."
$ReportPath = Join-Path $OutputRoot "ffdec-reference-report.json"
$json = ($Report | ConvertTo-Json -Depth 16).Replace("`r`n", "`n").TrimEnd() + "`n"
[IO.File]::WriteAllText($ReportPath, $json, $Utf8NoBom)
$retained = @(Get-ChildItem -LiteralPath $OutputRoot -Recurse -File)
Assert ($retained.Count -eq 23) "Expected 23 retained files; got $($retained.Count)."
Assert (@($retained | Where-Object { $_.Extension -notin @(".png", ".json") }).Count -eq 0) "Unexpected retained file type."

$reportRelative = $ReportPath.Substring($RepoRoot.TrimEnd("\").Length + 1).Replace("\", "/")
Write-Host "[player-info-hud/ffdec] status: $($Report.status)"
Write-Host "[player-info-hud/ffdec] reference set: $($Report.referenceSetRevision)"
Write-Host "[player-info-hud/ffdec] report: $reportRelative"
