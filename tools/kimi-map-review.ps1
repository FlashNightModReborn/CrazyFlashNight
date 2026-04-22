param(
    [Parameter(Mandatory = $true)]
    [string[]]$ImagePaths,

    [string[]]$ContextFiles = @(),

    [string]$Focus = 'Review hotspot-vs-component drift, avatar crop, and avatar position issues. Estimate pixel corrections when possible.',

    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null

function Resolve-ExistingPath {
    param([string]$InputPath)
    if ([string]::IsNullOrWhiteSpace($InputPath)) {
        return $null
    }

    $resolved = Resolve-Path -LiteralPath $InputPath -ErrorAction Stop
    return $resolved.ProviderPath
}

function Expand-PathItems {
    param([string[]]$Items)

    $result = @()
    foreach ($item in $Items) {
        if ([string]::IsNullOrWhiteSpace($item)) {
            continue
        }

        foreach ($part in ($item -split ',')) {
            if (-not [string]::IsNullOrWhiteSpace($part)) {
                $result += $part.Trim()
            }
        }
    }

    return $result
}

$resolvedImages = @()
foreach ($item in (Expand-PathItems $ImagePaths)) {
    $resolvedImages += Resolve-ExistingPath $item
}

$resolvedContext = @()
foreach ($item in (Expand-PathItems $ContextFiles)) {
    $resolvedContext += Resolve-ExistingPath $item
}

$promptLines = @(
    'You are helping calibrate the CF7 map WebView migration.',
    'Focus:',
    "- $Focus",
    '',
    'Please inspect the listed local image files and context files directly from the workspace.',
    'Return a concise review with:',
    '1. concrete issue list',
    '2. approximate pixel corrections when possible',
    '3. a short confidence note',
    '',
    'Image files:'
)

foreach ($item in $resolvedImages) {
    $promptLines += "- $item"
}

if ($resolvedContext.Count -gt 0) {
    $promptLines += ''
    $promptLines += 'Context files:'
    foreach ($item in $resolvedContext) {
        $promptLines += "- $item"
    }
}

$prompt = ($promptLines -join [Environment]::NewLine)
$result = & kimi.exe --print --output-format text --final-message-only -p $prompt

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    Set-Content -LiteralPath $OutputPath -Value $result -Encoding utf8
}

$result
