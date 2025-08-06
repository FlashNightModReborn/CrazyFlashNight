# PowerShell script to compress JSON and XML files in data folder
# Purpose: Remove whitespace and line breaks to optimize read performance

param(
    [switch]$WhatIf,
    [switch]$Backup
)

# Get current script directory and go up one level to resources folder
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ResourcesDir = Split-Path -Parent $ScriptDir
$DataDir = Join-Path $ResourcesDir "data"

Write-Host "Starting JSON and XML file compression..." -ForegroundColor Green
Write-Host "Data directory: $DataDir" -ForegroundColor Cyan

# Check if data folder exists
if (-not (Test-Path $DataDir)) {
    Write-Error "Data folder does not exist: $DataDir"
    exit 1
}

# Recursively find all JSON and XML files
$JsonFiles = Get-ChildItem -Path $DataDir -Filter "*.json" -Recurse
$XmlFiles = Get-ChildItem -Path $DataDir -Filter "*.xml" -Recurse
$AllFiles = $JsonFiles + $XmlFiles

if ($AllFiles.Count -eq 0) {
    Write-Warning "No JSON or XML files found in data folder"
    exit 0
}

Write-Host "Found $($JsonFiles.Count) JSON files and $($XmlFiles.Count) XML files" -ForegroundColor Yellow

$ProcessedCount = 0
$ErrorCount = 0
$TotalSizeBefore = 0
$TotalSizeAfter = 0

foreach ($File in $AllFiles) {
    try {
        Write-Host "Processing: $($File.FullName)" -ForegroundColor White
        
        # Read original file content
        $OriginalContent = Get-Content -Path $File.FullName -Raw -Encoding UTF8
        $OriginalSize = $File.Length
        $TotalSizeBefore += $OriginalSize
        
        if ([string]::IsNullOrWhiteSpace($OriginalContent)) {
            Write-Warning "Empty file, skipping: $($File.Name)"
            continue
        }
        
        $FileExtension = $File.Extension.ToLower()
        
        if ($FileExtension -eq ".json") {
            # Try to parse JSON to validate format
            try {
                $JsonObject = $OriginalContent | ConvertFrom-Json
            }
            catch {
                Write-Warning "Invalid JSON format, skipping: $($File.Name) - Error: $($_.Exception.Message)"
                continue
            }
            
            # Convert JSON object to compressed format (no indentation, no line breaks)
            $CompressedContent = $JsonObject | ConvertTo-Json -Depth 100 -Compress
        }
        elseif ($FileExtension -eq ".xml") {
            # Try to parse XML to validate format
            try {
                $XmlDoc = New-Object System.Xml.XmlDocument
                $XmlDoc.LoadXml($OriginalContent)
                
                # Create compressed XML (remove unnecessary whitespace)
                $StringWriter = New-Object System.IO.StringWriter
                $XmlWriter = New-Object System.Xml.XmlTextWriter($StringWriter)
                $XmlWriter.Formatting = [System.Xml.Formatting]::None
                $XmlDoc.WriteContentTo($XmlWriter)
                $CompressedContent = $StringWriter.ToString()
                $XmlWriter.Close()
                $StringWriter.Close()
            }
            catch {
                Write-Warning "Invalid XML format, skipping: $($File.Name) - Error: $($_.Exception.Message)"
                continue
            }
        }
        else {
            Write-Warning "Unsupported file type, skipping: $($File.Name)"
            continue
        }
        
        # If preview mode is enabled, only show information without modifying files
        if ($WhatIf) {
            $CompressedSize = [System.Text.Encoding]::UTF8.GetByteCount($CompressedContent)
            $TotalSizeAfter += $CompressedSize
            $SavedBytes = $OriginalSize - $CompressedSize
            $SavedPercent = if ($OriginalSize -gt 0) { [math]::Round(($SavedBytes / $OriginalSize) * 100, 2) } else { 0 }
            
            Write-Host "  [Preview] Original size: $OriginalSize bytes" -ForegroundColor Gray
            Write-Host "  [Preview] Compressed size: $CompressedSize bytes" -ForegroundColor Gray
            Write-Host "  [Preview] Saved: $SavedBytes bytes ($SavedPercent%)" -ForegroundColor Gray
            $ProcessedCount++
            continue
        }
        
        # Backup original file (if specified)
        if ($Backup) {
            $BackupPath = $File.FullName + ".backup"
            Copy-Item -Path $File.FullName -Destination $BackupPath -Force
            Write-Host "  Backup created: $BackupPath" -ForegroundColor Gray
        }
        
        # Write compressed content
        Set-Content -Path $File.FullName -Value $CompressedContent -Encoding UTF8 -NoNewline
        
        # Calculate compression effect
        $NewSize = (Get-Item $File.FullName).Length
        $TotalSizeAfter += $NewSize
        $SavedBytes = $OriginalSize - $NewSize
        $SavedPercent = if ($OriginalSize -gt 0) { [math]::Round(($SavedBytes / $OriginalSize) * 100, 2) } else { 0 }
        
        Write-Host "  Original size: $OriginalSize bytes" -ForegroundColor Gray
        Write-Host "  Compressed size: $NewSize bytes" -ForegroundColor Gray
        Write-Host "  Saved: $SavedBytes bytes ($SavedPercent%)" -ForegroundColor Green
        
        $ProcessedCount++
    }
    catch {
        Write-Error "Error processing file $($File.Name): $($_.Exception.Message)"
        $ErrorCount++
    }
}

# Display summary information
Write-Host "`nCompression completed!" -ForegroundColor Green
Write-Host "Total processed: $ProcessedCount files" -ForegroundColor Cyan
Write-Host "Errors: $ErrorCount files" -ForegroundColor $(if ($ErrorCount -eq 0) { 'Green' } else { 'Red' })

if ($ProcessedCount -gt 0) {
    $TotalSavedBytes = $TotalSizeBefore - $TotalSizeAfter
    $TotalSavedPercent = if ($TotalSizeBefore -gt 0) { [math]::Round(($TotalSavedBytes / $TotalSizeBefore) * 100, 2) } else { 0 }
    
    Write-Host "Total original size: $TotalSizeBefore bytes" -ForegroundColor Gray
    Write-Host "Total compressed size: $TotalSizeAfter bytes" -ForegroundColor Gray
    Write-Host "Total space saved: $TotalSavedBytes bytes ($TotalSavedPercent%)" -ForegroundColor Green
}

if ($WhatIf) {
    Write-Host "`nThis is preview mode, files were not modified." -ForegroundColor Yellow
    Write-Host "To actually compress files, run: .\compress_data_files.ps1" -ForegroundColor Yellow
    Write-Host "To create backups as well, run: .\compress_data_files.ps1 -Backup" -ForegroundColor Yellow
}