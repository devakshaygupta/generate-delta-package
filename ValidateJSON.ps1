$workingDir = "delta-changes"
$currentDir = Get-Location
$jsonLintOutputLogFile = Join-Path ${currentDir} "jsonlint_output.log"
$staticResourceDir = Join-Path ${workingDir} "src\staticresources"
$pattern = "<contentType>application/json</contentType>"
$jsonDataFiles = @()

if (Test-Path -Path "$staticResourceDir" -PathType Container) {
    $staticResourceFiles = Get-ChildItem -Path "$staticResourceDir" -Filter "*.resource" -File -Recurse
    if ($staticResourceFiles.Count -ne 0) {
        foreach ($file in $staticResourceFiles) {
            $fileName = (Get-Item -Path $(Join-Path ${staticResourceDir} ${file}) ).Name
            $metaFile = Join-Path $staticResourceDir "${fileName}-meta.xml"
            $match = Select-String -Path $metaFile -Pattern $pattern
            if ($match) {
                $jsonDataFiles += ($file)
            }
        }
    }

    if ($jsonDataFiles.Count -gt 0) {
        Write-Host "Change(s) detected in JSON file(s) in Static Resource"

        foreach ($file in $jsonDataFiles) {
            Write-Host "Checking $($file.FullName)"
            npx jsonlint $($file.FullName) >> $jsonLintOutputLogFile
        }
    }
}

$jsonLintOutputLogContent = Get-Content -Path $jsonLintOutputLogFile

foreach ($line in $jsonLintOutputLogContent) {
    if ($line -like "*error*" -or $line -like "*Error*") {
        exit 1
    }
}