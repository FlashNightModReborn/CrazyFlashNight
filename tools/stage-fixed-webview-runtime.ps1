param(
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [Parameter(Mandatory=$true)][string]$DestinationDirectory,
    [string]$CacheDirectory
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$spec = Get-Content -LiteralPath (Join-Path $ProjectRoot 'launcher\webview2-runtime.lock.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($spec.schema -ne 'cf7-fixed-webview2.v1' -or $spec.architecture -ne 'x64' -or
    $spec.cabSha256 -notmatch '^[A-F0-9]{64}$' -or [long]$spec.cabSize -le 0 -or
    ([uri]$spec.sourceUrl).Scheme -ne 'https' -or
    ([uri]$spec.sourceUrl).Host -ne 'msedge.sf.dl.delivery.mp.microsoft.com') {
    throw 'Invalid fixed WebView2 dependency lock.'
}
if (-not $CacheDirectory) { $CacheDirectory = Join-Path $env:LOCALAPPDATA 'CF7\runtime-dependencies\webview2' }
$cache = [IO.Path]::GetFullPath($CacheDirectory)
$destination = [IO.Path]::GetFullPath($DestinationDirectory)
function Assert-NoReparseAncestor([string]$Path) {
    $directory = New-Object IO.DirectoryInfo $Path
    while ($null -ne $directory) {
        if ($directory.Exists -and (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
            throw "Fixed WebView2 staging cannot use a reparse point: $($directory.FullName)"
        }
        $directory = $directory.Parent
    }
}
function Resolve-LockedPath([string]$Root, [string]$Relative) {
    if (-not $Relative -or $Relative.Contains('\') -or $Relative.Contains(':')) { throw "Invalid WebView2 path: $Relative" }
    foreach ($segment in $Relative.Split('/')) {
        if (-not $segment -or $segment -eq '.' -or $segment -eq '..' -or $segment.EndsWith('.') -or $segment.EndsWith(' ')) { throw "Invalid WebView2 path: $Relative" }
    }
    $full = [IO.Path]::GetFullPath((Join-Path $Root $Relative.Replace('/', '\')))
    if (-not $full.StartsWith($Root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'WebView2 path escaped its root.' }
    return $full
}
function Assert-LockedFile([string]$Path, [long]$Size, [string]$Hash) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or (Get-Item -LiteralPath $Path).Length -ne $Size -or
        ((Get-Item -LiteralPath $Path).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -cne $Hash) { throw "Fixed WebView2 file is missing or differs from lock: $Path" }
}
Assert-NoReparseAncestor $cache
Assert-NoReparseAncestor $destination
[IO.Directory]::CreateDirectory($cache) | Out-Null
$cab = Join-Path $cache ($spec.cabSha256 + '.cab')
if (-not (Test-Path -LiteralPath $cab -PathType Leaf)) {
    $download = $cab + '.download-' + [guid]::NewGuid().ToString('N')
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri $spec.sourceUrl -OutFile $download
    Assert-LockedFile $download $spec.cabSize $spec.cabSha256
    Move-Item -LiteralPath $download -Destination $cab -Force
}
Assert-LockedFile $cab $spec.cabSize $spec.cabSha256
# Each builder verifies the complete engine, including licenses, before creating the chunks.
$extraction = Join-Path $cache ($spec.cabSha256 + '-extracted')
Assert-NoReparseAncestor $extraction
if (-not (Test-Path -LiteralPath $extraction -PathType Container)) {
    [IO.Directory]::CreateDirectory($extraction) | Out-Null
    & "$env:SystemRoot\System32\expand.exe" '-F:*' $cab $extraction | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Fixed WebView2 CAB extraction failed.' }
}
$engine = Resolve-LockedPath $extraction $spec.extractedDirectory
Assert-NoReparseAncestor $engine
$entries = @(Get-ChildItem -LiteralPath $engine -Recurse -Force)
if (@($entries | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 }).Count -ne 0) { throw 'WebView2 extraction contains a reparse point.' }
if (@($entries | Where-Object { -not $_.PSIsContainer }).Count -ne @($spec.files).Count) { throw 'Fixed WebView2 extracted inventory differs from lock.' }
foreach ($file in $spec.files) { Assert-LockedFile (Resolve-LockedPath $engine $file.path) $file.size $file.sha256 }
$signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $engine 'msedgewebview2.exe')
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') { throw 'WebView2 browser lacks a valid Microsoft signature.' }
if ((Get-Item -LiteralPath (Join-Path $engine 'msedgewebview2.exe')).VersionInfo.ProductVersion -cne $spec.version) { throw 'WebView2 browser version differs from lock.' }
[IO.Directory]::CreateDirectory($destination) | Out-Null
$cabStream = [IO.File]::OpenRead($cab)
try {
    $buffer = New-Object byte[] ([int]$spec.partSize)
    foreach ($part in $spec.parts) {
        $remaining = [int]$part.size
        if ($remaining -le 0 -or $remaining -gt $buffer.Length) { throw 'Invalid WebView2 chunk size.' }
        $offset = 0
        while ($offset -lt $remaining) {
            $read = $cabStream.Read($buffer, $offset, $remaining - $offset)
            if ($read -eq 0) { throw 'WebView2 CAB ended before a locked chunk boundary.' }
            $offset += $read
        }
        $path = Resolve-LockedPath $destination $part.path
        $output = [IO.File]::Create($path)
        try { $output.Write($buffer, 0, $remaining) } finally { $output.Dispose() }
        Assert-LockedFile $path $part.size $part.sha256
    }
    if ($cabStream.Position -ne $cabStream.Length) { throw 'WebView2 chunks do not cover the entire CAB.' }
} finally { $cabStream.Dispose() }
Write-Host "[FixedWebView2] version=$($spec.version) cab=$($spec.cabSha256) files=$(@($spec.files).Count) chunks=$(@($spec.parts).Count)"
