param([string]$PackageRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
$PackageRoot=(Resolve-Path -LiteralPath $PackageRoot).Path.TrimEnd('\')
$manifest=Get-Content -LiteralPath (Join-Path $PackageRoot 'package-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($manifest.schema -cne 'cf7-field-support-package.v1'){throw 'Unknown package manifest'}
$seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach($file in $manifest.files){
    $path=[IO.Path]::GetFullPath((Join-Path $PackageRoot $file.path))
    if(!$path.StartsWith($PackageRoot+'\',[StringComparison]::OrdinalIgnoreCase) -or !$seen.Add($path)){throw 'Unsafe or duplicate package path'}
    $item=Get-Item -LiteralPath $path
    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Package contains a link'}
    if($item.Length -ne $file.size -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $file.sha256){throw "Package integrity mismatch: $($file.path)"}
}
foreach($item in Get-ChildItem -LiteralPath $PackageRoot -Recurse -File){
    if($item.Name -ne 'package-manifest.json' -and !$seen.Contains($item.FullName)){throw "Undeclared package file: $($item.FullName)"}
}
Write-Output "Package integrity OK: $($seen.Count) files"
