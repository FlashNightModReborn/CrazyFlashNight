param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination
)

$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$stageRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'tmp\workbench-live-e2e\cu-staging'))
$runRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'tmp\workbench-live-e2e\equipment'))
$sourcePath = [System.IO.Path]::GetFullPath($Source)
$destinationPath = [System.IO.Path]::GetFullPath($Destination)

function Assert-ChildPath([string]$Path, [string]$Parent, [string]$Label) {
    if (-not $Path.StartsWith($Parent + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label escaped its owned directory"
    }
}

Assert-ChildPath $sourcePath $stageRoot 'source capture'
Assert-ChildPath $destinationPath $runRoot 'destination capture'
if ([System.IO.Path]::GetExtension($sourcePath) -ne '.jpg' -or
    [System.IO.Path]::GetExtension($destinationPath) -ne '.png' -or
    -not (Test-Path -LiteralPath $sourcePath) -or
    (Test-Path -LiteralPath $destinationPath)) {
    throw 'capture conversion paths are invalid'
}

Add-Type -AssemblyName System.Drawing
$image = [System.Drawing.Image]::FromFile($sourcePath)
try {
    if ($image.Width -lt 320 -or $image.Height -lt 180) {
        throw 'capture is below the live evidence size floor'
    }
    $image.Save($destinationPath, [System.Drawing.Imaging.ImageFormat]::Png)
    [pscustomobject]@{
        path = $destinationPath
        width = $image.Width
        height = $image.Height
        bytes = (Get-Item -LiteralPath $destinationPath).Length
    } | ConvertTo-Json -Compress
}
finally {
    $image.Dispose()
}
