param([Parameter(Mandatory=$true)][string]$ProjectRoot)
# Emit a proof only for bytes that form exactly one committed set. This path
# runs only on an installed/receipt mismatch, never on the ordinary launch.
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
if (-not (Test-Path -LiteralPath (Join-Path $root '.git'))) { return }
function Get-Tree {
    $tree = & git --no-replace-objects -C $root rev-parse --verify 'HEAD^{tree}' 2>$null
    if ($LASTEXITCODE -eq 0) { return $tree }
}
function Digest([byte[]]$bytes, [int]$gitLength = 0) {
    $algorithm = if ($gitLength -eq 40) { [Security.Cryptography.SHA1]::Create() } else { [Security.Cryptography.SHA256]::Create() }
    try {
        if ($gitLength) {
            $header = [Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)" + [char]0)
            [void]$algorithm.TransformBlock($header, 0, $header.Length, $header, 0)
            [void]$algorithm.TransformFinalBlock($bytes, 0, $bytes.Length)
            $raw = $algorithm.Hash
        } else { $raw = $algorithm.ComputeHash($bytes) }
        return ([BitConverter]::ToString($raw)).Replace('-', '').ToLowerInvariant()
    } finally { $algorithm.Dispose() }
}
try {
    $previousEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    $top = & git --no-replace-objects -C $root rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or [IO.Path]::GetFullPath($top).TrimEnd('\') -ine $root) { return }
    $lockFile = & git --no-replace-objects -C $root rev-parse --path-format=absolute --git-path index.lock 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $lockFile -or [IO.File]::Exists($lockFile)) { return }
    $tree = Get-Tree
    if (-not $tree -or $tree -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') { return }
    $files = [ordered]@{resident='scripts/asLoader.swf'; shared='scripts/asLoaderShared.swf'; boot='scripts/asLoaderLogic.swf'}
    $oids = @{}
    $rows = & git --no-replace-objects -C $root ls-tree $tree -- $files.resident $files.shared $files.boot 2>$null
    if ($LASTEXITCODE -ne 0 -or @($rows).Count -ne 3) { return }
    foreach ($row in $rows) {
        if ($row -cnotmatch '^100(?:644|755) blob ([0-9a-f]+)\t(.+)$') { return }
        $oids[$Matches[2]] = $Matches[1]
    }
    $installed = [ordered]@{}
    foreach ($name in $files.Keys) {
        $rel = $files[$name]
        $path = Join-Path $root $rel
        if (-not [IO.File]::Exists($path) -or ([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint)) { return }
        $bytes = [IO.File]::ReadAllBytes($path)
        if ((Digest $bytes $tree.Length) -cne $oids[$rel]) { return }
        $installed[$name] = Digest $bytes
    }
    if ($tree -cne (Get-Tree) -or [IO.File]::Exists($lockFile)) { return }
    [ordered]@{tree=$tree; installed=$installed} | ConvertTo-Json -Compress
} catch {
    # Missing Git, inaccessible paths, or a changing checkout give no proof.
    return
} finally {
    if ($null -ne $previousEncoding) { [Console]::OutputEncoding = $previousEncoding }
}
