param(
    [string]$Browser = "edge",
    [string]$OutDir = "tmp/stage-select-visual-audit",
    [string[]]$FrameLabel = @(),
    [string]$Fixture = "allUnlocked",
    [switch]$SkipFfdec,
    [switch]$SkipCapture,
    [switch]$KeepRaw
)

$ErrorActionPreference = "Stop"
chcp.com 65001 | Out-Null

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Resolve-JavaExe {
    if ($env:JAVA_EXE -and (Test-Path -LiteralPath $env:JAVA_EXE)) {
        return $env:JAVA_EXE
    }
    $candidates = @(
        (Join-Path ${env:ProgramFiles} "Adobe\Adobe Animate 2024\jre\bin\java.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Common Files\Adobe\Adobe Flash CS6\jre\bin\java.exe")
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    $probe = Get-Command java -ErrorAction SilentlyContinue
    if ($probe) {
        return $probe.Source
    }
    throw "No Java runtime found. Set JAVA_EXE or install a JRE for FFDec export."
}

function Assert-ExitCode([string]$Label) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE"
    }
}

function Get-SafeFrameBaseName([string]$Label, [int]$Index) {
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $chars = foreach ($ch in $Label.ToCharArray()) {
        if ($invalid -contains $ch) { "_" } else { [string]$ch }
    }
    $safe = -join $chars
    $safe = [regex]::Replace($safe, '\s+', '_')
    return ("{0:D3}-{1}" -f $Index, $safe)
}

function Add-ImageHelperType {
    Add-Type -ReferencedAssemblies "System.Drawing" -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;

public static class StageSelectVisualAuditImages
{
    public static void CropPng(string sourcePath, string outputPath, int x, int y, int width, int height)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(outputPath));
        using (Bitmap source = new Bitmap(sourcePath))
        using (Bitmap output = new Bitmap(width, height, PixelFormat.Format32bppArgb))
        using (Graphics g = Graphics.FromImage(output))
        {
            g.Clear(Color.Transparent);
            g.DrawImage(source, new Rectangle(0, 0, width, height), new Rectangle(x, y, width, height), GraphicsUnit.Pixel);
            output.Save(outputPath, ImageFormat.Png);
        }
    }

    public static string MakeSheet(string ffdecPath, string webPath, string sheetPath, string title)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(sheetPath));
        using (Bitmap ffdec = new Bitmap(ffdecPath))
        using (Bitmap webSource = new Bitmap(webPath))
        using (Bitmap web = Normalize(webSource, ffdec.Width, ffdec.Height))
        using (Bitmap diff = new Bitmap(ffdec.Width, ffdec.Height, PixelFormat.Format32bppArgb))
        {
            long total = 0;
            long changed = 0;
            int max = 0;
            int width = ffdec.Width;
            int height = ffdec.Height;
            for (int yy = 0; yy < height; yy++)
            {
                for (int xx = 0; xx < width; xx++)
                {
                    Color a = ffdec.GetPixel(xx, yy);
                    Color b = web.GetPixel(xx, yy);
                    int dr = Math.Abs(a.R - b.R);
                    int dg = Math.Abs(a.G - b.G);
                    int db = Math.Abs(a.B - b.B);
                    int localMax = Math.Max(dr, Math.Max(dg, db));
                    if (localMax > max) max = localMax;
                    if (localMax > 18) changed++;
                    total += dr + dg + db;
                    diff.SetPixel(xx, yy, Color.FromArgb(255, Math.Min(255, dr * 4), Math.Min(255, dg * 4), Math.Min(255, db * 4)));
                }
            }

            double meanAbsDiff = total / (double)(width * height * 3);
            double changedRatio = changed / (double)(width * height);
            int gap = 16;
            int header = 64;
            int sheetWidth = width * 3 + gap * 4;
            int sheetHeight = height + header + gap;
            using (Bitmap sheet = new Bitmap(sheetWidth, sheetHeight, PixelFormat.Format32bppArgb))
            using (Graphics g = Graphics.FromImage(sheet))
            using (Font titleFont = new Font("Microsoft YaHei", 15, FontStyle.Bold, GraphicsUnit.Pixel))
            using (Font labelFont = new Font("Microsoft YaHei", 12, FontStyle.Regular, GraphicsUnit.Pixel))
            using (Brush titleBrush = new SolidBrush(Color.FromArgb(245, 248, 250)))
            using (Brush labelBrush = new SolidBrush(Color.FromArgb(203, 213, 225)))
            using (Pen borderPen = new Pen(Color.FromArgb(148, 163, 184), 1))
            {
                g.Clear(Color.FromArgb(2, 6, 23));
                g.DrawString(title, titleFont, titleBrush, gap, 10);
                string summary = "FFDec sprite crop vs Web stage capture | meanAbsDiff=" +
                    meanAbsDiff.ToString("0.00", CultureInfo.InvariantCulture) +
                    " changedRatio=" + (changedRatio * 100.0).ToString("0.00", CultureInfo.InvariantCulture) + "% maxChannelDiff=" + max.ToString(CultureInfo.InvariantCulture);
                g.DrawString(summary, labelFont, labelBrush, gap, 34);

                int leftX = gap;
                int midX = gap * 2 + width;
                int rightX = gap * 3 + width * 2;
                int y = header;
                g.DrawString("FFDec crop", labelFont, labelBrush, leftX, header - 18);
                g.DrawString("Web capture", labelFont, labelBrush, midX, header - 18);
                g.DrawString("Amplified absolute diff", labelFont, labelBrush, rightX, header - 18);
                g.DrawImage(ffdec, leftX, y, width, height);
                g.DrawImage(web, midX, y, width, height);
                g.DrawImage(diff, rightX, y, width, height);
                g.DrawRectangle(borderPen, leftX, y, width, height);
                g.DrawRectangle(borderPen, midX, y, width, height);
                g.DrawRectangle(borderPen, rightX, y, width, height);
                sheet.Save(sheetPath, ImageFormat.Png);
            }

            return "{" +
                "\"ffdecWidth\":" + ffdec.Width.ToString(CultureInfo.InvariantCulture) + "," +
                "\"ffdecHeight\":" + ffdec.Height.ToString(CultureInfo.InvariantCulture) + "," +
                "\"webWidth\":" + webSource.Width.ToString(CultureInfo.InvariantCulture) + "," +
                "\"webHeight\":" + webSource.Height.ToString(CultureInfo.InvariantCulture) + "," +
                "\"meanAbsDiff\":" + meanAbsDiff.ToString("0.####", CultureInfo.InvariantCulture) + "," +
                "\"changedRatio\":" + changedRatio.ToString("0.####", CultureInfo.InvariantCulture) + "," +
                "\"maxChannelDiff\":" + max.ToString(CultureInfo.InvariantCulture) +
            "}";
        }
    }

    private static Bitmap Normalize(Bitmap source, int width, int height)
    {
        Bitmap output = new Bitmap(width, height, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(output))
        {
            g.Clear(Color.Transparent);
            g.DrawImage(source, new Rectangle(0, 0, width, height), new Rectangle(0, 0, source.Width, source.Height), GraphicsUnit.Pixel);
        }
        return output;
    }
}
"@
}

$AuditRoot = Join-Path $RepoRoot $OutDir
$RawDir = Join-Path $AuditRoot "ffdec-raw"
$FfdecDir = Join-Path $AuditRoot "ffdec-crop"
$WebDir = Join-Path $AuditRoot "web"
$SheetDir = Join-Path $AuditRoot "sheets"
$ManifestPath = Join-Path $AuditRoot "manifest.json"
$IndexPath = Join-Path $AuditRoot "visual-audit-index.json"

New-Item -ItemType Directory -Force -Path $AuditRoot, $FfdecDir, $WebDir, $SheetDir | Out-Null

$manifestRel = $ManifestPath.Substring($RepoRoot.Length + 1)
& node tools\export-stage-select-manifest.js --write-module --output $manifestRel
Assert-ExitCode "stage-select manifest export"
$manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$sourceSwfRel = ($manifest.sourceRefs.xflDir + ".swf").Replace("/", "\")
$sourceSwfPath = Join-Path $RepoRoot $sourceSwfRel

$frames = @($manifest.frames)
if ($FrameLabel.Count -gt 0) {
    $requested = @{}
    foreach ($label in $FrameLabel) { $requested[$label] = $true }
    $frames = @($frames | Where-Object { $requested.ContainsKey($_.frameLabel) })
    foreach ($label in $FrameLabel) {
        if (-not ($frames | Where-Object { $_.frameLabel -eq $label })) {
            throw "Unknown frame label: $label"
        }
    }
}

if (-not $SkipFfdec) {
    if (Test-Path -LiteralPath $RawDir) {
        Remove-Item -LiteralPath $RawDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $RawDir | Out-Null
    $java = Resolve-JavaExe
    & $java -jar tools\ffdec\ffdec.jar -format sprite:png -selectid 330 -export sprite $RawDir $sourceSwfPath
    Assert-ExitCode "FFDec stage-select sprite export"
} elseif (-not (Test-Path -LiteralPath $RawDir)) {
    throw "Missing FFDec raw directory: $RawDir. Rerun without -SkipFfdec or use -KeepRaw from an earlier run."
}

if (-not $SkipCapture) {
    $captureArgs = @("tools\capture-stage-select-web-frames.js", "--browser", $Browser, "--out-dir", (Resolve-Path -LiteralPath $WebDir).Path.Replace($RepoRoot + "\", ""), "--fixture", $Fixture)
    foreach ($frame in $frames) {
        $captureArgs += @("--frame", [string]$frame.frameLabel)
    }
    & node @captureArgs | Out-Host
    Assert-ExitCode "stage-select web capture"
}

Add-ImageHelperType

$spriteOrigin = [ordered]@{
    svgX = 526.6
    svgY = 206.95
    cropX = 527
    cropY = 207
    width = 1024
    height = 576
}
$rows = @()

foreach ($frame in $frames) {
    $sourceIndex = [int]$frame.sourceFrameIndex
    $ffdecIndex = if ($sourceIndex -le 1) { 1 } else { $sourceIndex + 1 }
    $baseName = Get-SafeFrameBaseName -Label ([string]$frame.frameLabel) -Index $sourceIndex
    $rawFile = Get-ChildItem -LiteralPath $RawDir -Recurse -File -Filter "$ffdecIndex.png" | Select-Object -First 1
    if (-not $rawFile) {
        throw "Missing FFDec raw sprite frame for ffdecFrameIndex=$ffdecIndex ($($frame.frameLabel)) under $RawDir"
    }

    $ffdecCrop = Join-Path $FfdecDir ($baseName + ".png")
    $webCapture = Join-Path $WebDir ($baseName + ".png")
    $sheet = Join-Path $SheetDir ($baseName + "-compare.png")
    if (-not (Test-Path -LiteralPath $webCapture)) {
        throw "Missing Web capture: $webCapture"
    }

    [StageSelectVisualAuditImages]::CropPng($rawFile.FullName, $ffdecCrop, $spriteOrigin.cropX, $spriteOrigin.cropY, $spriteOrigin.width, $spriteOrigin.height)
    $metrics = [StageSelectVisualAuditImages]::MakeSheet($ffdecCrop, $webCapture, $sheet, ("{0} | sprite frame {1}" -f $frame.frameLabel, $ffdecIndex)) | ConvertFrom-Json
    $rows += [pscustomobject]@{
        frameLabel = $frame.frameLabel
        sourceFrameIndex = $sourceIndex
        ffdecFrameIndex = $ffdecIndex
        ffdecRaw = $rawFile.FullName.Replace($RepoRoot + "\", "").Replace("\", "/")
        ffdecCrop = $ffdecCrop.Replace($RepoRoot + "\", "").Replace("\", "/")
        webCapture = $webCapture.Replace($RepoRoot + "\", "").Replace("\", "/")
        compareSheet = $sheet.Replace($RepoRoot + "\", "").Replace("\", "/")
        metrics = $metrics
    }
}

$indexPayload = [ordered]@{
    generatedAt = (Get-Date).ToString("o")
    sprite = [ordered]@{
        characterId = 330
        symbolClass = ($manifest.sourceRefs.xflDir -split "/")[-1]
        sourceSwf = $sourceSwfRel.Replace("\", "/")
        origin = $spriteOrigin
    }
    browser = $Browser
    fixture = $Fixture
    frames = $rows
}
$indexPayload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $IndexPath -Encoding UTF8

if (-not $KeepRaw) {
    Remove-Item -LiteralPath $RawDir -Recurse -Force
    foreach ($row in $rows) {
        $row.ffdecRaw = "(removed; rerun with -KeepRaw to preserve raw FFDec sprite frames)"
    }
    $indexPayload.frames = $rows
    $indexPayload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $IndexPath -Encoding UTF8
}

$worst = $rows | Sort-Object { $_.metrics.changedRatio } -Descending | Select-Object -First 1
Write-Host ("[stage-select-visual-audit] wrote {0} frame comparisons -> {1}" -f $rows.Count, $OutDir)
if ($worst) {
    Write-Host ("[stage-select-visual-audit] worst changedRatio={0:P2} meanAbsDiff={1} frame={2}" -f [double]$worst.metrics.changedRatio, $worst.metrics.meanAbsDiff, $worst.frameLabel)
}
