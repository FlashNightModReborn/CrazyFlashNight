# Define source and destination folders
$sourceFolder = "C:\Program Files (x86)\Steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources"
$destinationFolder = "C:\Program Files (x86)\Steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\extracted_fla"

# Create the destination folder if it doesn't exist
if (-not (Test-Path $destinationFolder)) {
    New-Item -Path $destinationFolder -ItemType Directory
}

# Step 1: Recursively find all .fla files in the source folder
Get-ChildItem -Path $sourceFolder -Recurse -Filter *.fla | ForEach-Object {
    $flaFile = $_.FullName
    $relativePath = $_.FullName.Substring($sourceFolder.Length) -replace '\\', '/'
    $relativeDir = [System.IO.Path]::GetDirectoryName($relativePath)

    # Define the new folder path for extracted files
    $extractedFolder = Join-Path $destinationFolder $relativeDir

    # Create directory structure in the destination folder
    if (-not (Test-Path $extractedFolder)) {
        New-Item -Path $extractedFolder -ItemType Directory
    }

    # Rename .fla to .zip to extract
    $zipFile = [System.IO.Path]::ChangeExtension($flaFile, '.zip')
    Rename-Item -Path $flaFile -NewName $zipFile

    # Extract the renamed zip to the new folder
    Expand-Archive -Path $zipFile -DestinationPath $extractedFolder

    # Optionally rename .zip back to .fla
    Rename-Item -Path $zipFile -NewName $flaFile
}

Write-Host "Extraction complete! All files are extracted and stored in: $destinationFolder"
