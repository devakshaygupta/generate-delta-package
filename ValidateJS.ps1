$workingDir = "delta-changes"
$currentDir = Get-Location
$esLintOutputLogFile = Join-Path ${currentDir} "eslint_output.log"
$lwcDir = Join-Path ${workingDir} "src\lwc"
$auraDir = Join-Path ${workingDir} "src\aura"
$staticResourceDir = Join-Path ${workingDir} "src\staticresources"
$pattern = "<contentType>text/javascript</contentType>"
$jsPluginFiles = @()

if (Test-Path -Path "$lwcDir" -PathType Container) {
    $jsFiles = Get-ChildItem -Path "$lwcDir" -Filter "*.js" -File -Recurse

    if ($jsFiles.Count -ne 0) {
        Write-Host "Change(s) detected in Javascript file(s) in lwc"

        foreach ($file in $jsFiles) {
            Write-Host "Checking $($file.FullName)"
            npx eslint $($file.FullName) >> $esLintOutputLogFile
        }
    }
}

if (Test-Path -Path "$auraDir" -PathType Container) {
    $jsFiles = Get-ChildItem -Path "$auraDir" -Filter "*.js" -File -Recurse

    if ($jsFiles.Count -ne 0) {
        Write-Host "Change(s) detected in Javascript file(s) in aura"

        foreach ($file in $jsFiles) {
            Write-Host "Checking $($file.FullName)"
            npx eslint $($file.FullName) >> $esLintOutputLogFile
        }
    }
}

if (Test-Path -Path "$staticResourceDir" -PathType Container) {
    $staticResourceFiles = Get-ChildItem -Path "$staticResourceDir" -Filter "*.resource" -File -Recurse
    if ($staticResourceFiles.Count -ne 0) {
        foreach ($file in $staticResourceFiles) {
            $fileName = (Get-Item -Path $(Join-Path ${staticResourceDir} ${file}) ).Name
            $metaFile = Join-Path $staticResourceDir "${fileName}-meta.xml"
            $match = Select-String -Path $metaFile -Pattern $pattern
            if ($match) {
                $jsPluginFiles += ($file)
            }
        }
    }

    if ($jsPluginFiles.Count -gt 0) {
        Write-Host "Change(s) detected in Javascript file(s) in Static Resource"

        foreach ($file in $jsPluginFiles) {
            Write-Host "Checking $($file.FullName)"
            npx eslint $($file.FullName) >> $esLintOutputLogFile
        }
    }
}

$esLintOutputLogContent = Get-Content -Path $esLintOutputLogFile

foreach ($line in $esLintOutputLogContent) {
    if ($line -like "error" -or $line -like "Error") {
        Get-Content -Path $esLintOutputLogContent
        exit 1
    }
}
