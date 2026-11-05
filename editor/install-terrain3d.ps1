# Restore native libraries for the checked-in Terrain3D 1.1.0 addon.
# Close Godot before running this script. Existing binaries are preserved.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$binaryDirectory = Join-Path $projectRoot 'addons\terrain_3d\bin'
if (Test-Path -LiteralPath $binaryDirectory) {
    Write-Output 'Terrain3D binaries already exist. No files changed.'
    exit 0
}
$archivePath = Join-Path ([IO.Path]::GetTempPath()) ('terrain3d-' + [guid]::NewGuid().ToString() + '.zip')
$extractPath = Join-Path ([IO.Path]::GetTempPath()) ('terrain3d-' + [guid]::NewGuid().ToString())
Invoke-WebRequest 'https://github.com/TokisanGames/Terrain3D/releases/download/v1.1.0-stable/Terrain3D_v1.1.0-stable.zip' -OutFile $archivePath
$expectedHash = '51B78BC758F5759CBC8EAAAB14E5CF4E8661717E265FDD760F5ABF945F15B243'
if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash -ne $expectedHash) {
    throw 'Terrain3D archive digest differs from the verified release. Nothing installed.'
}
Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath
Copy-Item -LiteralPath (Join-Path $extractPath 'addons\terrain_3d\bin') -Destination $binaryDirectory -Recurse
Write-Output 'Installed verified Terrain3D 1.1.0 native libraries. Restart Godot.'
