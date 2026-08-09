param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDirectory,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'

function Resolve-ExistingDirectory([string]$PathValue, [string]$Label) {
    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        throw "$Label is empty."
    }
    $resolved = (Resolve-Path -LiteralPath $PathValue -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        throw "$Label is not a directory: $resolved"
    }
    return $resolved
}

function Invoke-NativeChecked([string]$Executable, [string[]]$Arguments, [string]$Label) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE."
    }
}

$sourceRoot = Resolve-ExistingDirectory $SourceDirectory 'Audio v2 source directory'
if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
}
$outputRoot = Resolve-ExistingDirectory $OutputDirectory 'Audio v2 output directory'

$manifestPath = Join-Path $sourceRoot 'audio-v2-build-inputs.v1.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Audio v2 build input manifest is missing: $manifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.schema -ne 'cf7.audio-v2.native-build-inputs.v1') {
    throw "Unexpected Audio v2 build input schema: $($manifest.schema)"
}
if ($manifest.output -ne 'miniaudio.dll') {
    throw "Unexpected Audio v2 output name: $($manifest.output)"
}

$objectRoot = Join-Path $outputRoot 'audio-v2-obj'
if (Test-Path -LiteralPath $objectRoot) {
    throw "Audio v2 object directory must not pre-exist: $objectRoot"
}
New-Item -ItemType Directory -Path $objectRoot | Out-Null

$objectFiles = [System.Collections.Generic.List[string]]::new()
$cleanupFiles = [System.Collections.Generic.List[string]]::new()
try {
    $commonArguments = [System.Collections.Generic.List[string]]::new()
    foreach ($argument in @(
        '/nologo',
        '/utf-8',
        '/experimental:deterministic',
        '/O2',
        '/GS',
        '/c',
        "/pathmap:$sourceRoot=C:\cf7-runtime-src"
    )) {
        $commonArguments.Add($argument)
    }
    foreach ($definition in $manifest.compileDefinitions) {
        if ($definition -notmatch '^[A-Za-z_][A-Za-z0-9_]*(?:=[A-Za-z0-9_]+)?$') {
            throw "Invalid compile definition: $definition"
        }
        $commonArguments.Add("/D$definition")
    }
    foreach ($includeDirectory in $manifest.includeDirectories) {
        $includePath = Join-Path $sourceRoot ([string]$includeDirectory)
        if (-not (Test-Path -LiteralPath $includePath -PathType Container)) {
            throw "Audio v2 include directory is missing: $includeDirectory"
        }
        $commonArguments.Add("/I$includePath")
    }
    $forceIncludePath = Join-Path $sourceRoot ([string]$manifest.forceInclude)
    if (-not (Test-Path -LiteralPath $forceIncludePath -PathType Leaf)) {
        throw "Audio v2 force-include header is missing: $($manifest.forceInclude)"
    }
    $commonArguments.Add("/FI$forceIncludePath")

    $index = 0
    foreach ($source in $manifest.compileSources) {
        $relativePath = [string]$source.path
        if ([string]::IsNullOrWhiteSpace($relativePath) -or
            [System.IO.Path]::IsPathRooted($relativePath) -or
            $relativePath -match '(^|[\\/])\.\.([\\/]|$)') {
            throw "Unsafe Audio v2 compile source path: $relativePath"
        }
        $sourcePath = Join-Path $sourceRoot $relativePath
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Audio v2 compile source is missing: $relativePath"
        }
        $extension = [System.IO.Path]::GetExtension($relativePath).ToLowerInvariant()
        $language = [string]$source.language
        if (($language -eq 'c17' -and $extension -ne '.c') -or
            ($language -eq 'cpp17' -and $extension -ne '.cpp')) {
            throw "Audio v2 source language/extension mismatch: $relativePath ($language)"
        }

        $objectName = '{0:D4}-{1}.obj' -f $index, [System.IO.Path]::GetFileNameWithoutExtension($relativePath)
        $objectPath = Join-Path $objectRoot $objectName
        $arguments = [System.Collections.Generic.List[string]]::new()
        foreach ($argument in $commonArguments) {
            $arguments.Add($argument)
        }
        if ($language -eq 'cpp17') {
            $arguments.Add('/TP')
            $arguments.Add('/std:c++17')
            $arguments.Add('/EHsc')
        } else {
            $arguments.Add('/TC')
            $arguments.Add('/std:c17')
        }
        if ($relativePath.StartsWith('third_party/', [StringComparison]::Ordinal) -or
            $relativePath.StartsWith('extras/', [StringComparison]::Ordinal) -or
            $relativePath -eq 'miniaudio.c') {
            $arguments.Add('/W2')
        } else {
            $arguments.Add('/W4')
        }
        $arguments.Add("/Fo$objectPath")
        $arguments.Add($sourcePath)
        Invoke-NativeChecked 'cl.exe' $arguments.ToArray() "compile $relativePath"
        $objectFiles.Add($objectPath)
        $cleanupFiles.Add($objectPath)
        $index++
    }

    $dllPath = Join-Path $outputRoot ([string]$manifest.output)
    $importLibraryPath = Join-Path $objectRoot 'miniaudio.lib'
    $linkArguments = [System.Collections.Generic.List[string]]::new()
    foreach ($argument in @(
        '/nologo',
        '/DLL',
        '/Brepro',
        '/INCREMENTAL:NO',
        '/MACHINE:X64',
        "/OUT:$dllPath",
        "/IMPLIB:$importLibraryPath"
    )) {
        $linkArguments.Add($argument)
    }
    foreach ($objectFile in $objectFiles) {
        $linkArguments.Add($objectFile)
    }
    foreach ($library in $manifest.linkLibraries) {
        if ($library -notmatch '^[A-Za-z0-9_.-]+\.lib$') {
            throw "Invalid Audio v2 link library: $library"
        }
        $linkArguments.Add([string]$library)
    }
    Invoke-NativeChecked 'link.exe' $linkArguments.ToArray() 'link miniaudio.dll'

    if (-not (Test-Path -LiteralPath $dllPath -PathType Leaf)) {
        throw "Audio v2 linker did not produce miniaudio.dll."
    }
    Write-Host "[OK] Audio v2 miniaudio.dll built: $dllPath"
} finally {
    foreach ($file in $cleanupFiles) {
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            Remove-Item -LiteralPath $file -Force
        }
    }
    foreach ($fileName in @('miniaudio.exp', 'miniaudio.lib')) {
        $file = Join-Path $objectRoot $fileName
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            Remove-Item -LiteralPath $file -Force
        }
    }
    if (Test-Path -LiteralPath $objectRoot -PathType Container) {
        $remaining = @(Get-ChildItem -LiteralPath $objectRoot -Force)
        if ($remaining.Count -eq 0) {
            Remove-Item -LiteralPath $objectRoot -Force
        }
    }
}
