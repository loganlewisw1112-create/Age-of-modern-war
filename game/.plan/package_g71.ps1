# Build a Windows package from this checkout and keep earlier packages intact.
param(
  [string]$Note = "",
  [string]$Destination = (Join-Path ([Environment]::GetFolderPath("UserProfile")) "Downloads\Age of Modern War")
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$game = Join-Path $root "game"
$godot = (Get-Command "Godot*stable*win64_console.exe" -CommandType Application | Select-Object -First 1).Source
$godotWin = $godot.Replace("_console.exe", ".exe")
if (-not (Test-Path -LiteralPath $godotWin)) { throw "Godot Windows runner is missing." }

$sha = (git -C $root rev-parse --short HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw "Could not determine the package commit." }
$tag = "G71_{0}_{1}" -f (Get-Date -Format "yyyy-MM-dd"), $sha
$baseName = "RTS_Age_of_Modern_War_$tag"
$build = Join-Path $root "build"
$out = Join-Path $build $baseName
$dst = Join-Path $Destination $baseName
$zip = Join-Path $Destination "$baseName.zip"
foreach ($path in @($out, $dst, $zip)) {
  if (Test-Path -LiteralPath $path) { throw "Package path already exists: $path" }
}

New-Item -ItemType Directory -Path $out -Force | Out-Null
$docsPlay = Join-Path $game "docs\PLAY_ME_G71_2026-11-22.txt"
$play = Get-Content -LiteralPath $docsPlay -Raw
("Commit: $sha" + [Environment]::NewLine + [Environment]::NewLine + $play.TrimEnd()) |
  Set-Content -LiteralPath (Join-Path $out "PLAY_ME.txt") -Encoding utf8
if ($Note -ne "") {
  Add-Content -LiteralPath (Join-Path $out "PLAY_ME.txt") -Value $Note -Encoding utf8
}
$lookSrc = Join-Path $game ".plan\shots\G71_LOOK"
$lookDoc = Join-Path $game "docs\G71_LOOK_CHECKPOINT.md"
if (Test-Path -LiteralPath $lookSrc) {
  Copy-Item -LiteralPath $lookSrc -Destination (Join-Path $out "G71_LOOK_CHECKPOINT") -Recurse
}
if (Test-Path -LiteralPath $lookDoc) {
  Copy-Item -LiteralPath $lookDoc -Destination $out
}
$blueprint = Join-Path $game "docs\G10_1_DEFERRED_ART.md"
if (Test-Path -LiteralPath $blueprint) {
  $doc = (Get-Content -LiteralPath $blueprint -Raw).Replace("../.plan/shots/G71_LOOK/", "G71_LOOK_CHECKPOINT/")
  $doc | Set-Content -LiteralPath (Join-Path $out "G10_1_DEFERRED_ART.md") -Encoding utf8
}

$importLog = Join-Path $build "import_$tag.log"
$exportLog = Join-Path $build "export_$tag.log"
$pck = Join-Path $out "RTS_Age_of_Modern_War.pck"
& $godot --headless --path $game --import *> $importLog
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $importLog -Pattern "SCRIPT ERROR|^ERROR:" -Quiet)) {
  throw "Godot import failed. See $importLog"
}
& $godot --headless --path $game --export-pack "Windows Desktop" $pck *> $exportLog
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $pck)) { throw "Export failed. See $exportLog" }

Copy-Item -LiteralPath $godotWin -Destination (Join-Path $out "RTS_Age_of_Modern_War.exe")
Copy-Item -LiteralPath $godot -Destination (Join-Path $out "RTS_Age_of_Modern_War_console.exe")
Copy-Item -LiteralPath (Join-Path $game "bin\rts_core.dll") -Destination $out
$bin = Join-Path $out "bin"
New-Item -ItemType Directory -Path $bin | Out-Null
Copy-Item -LiteralPath (Join-Path $game "bin\rts_core.dll") -Destination $bin

New-Item -ItemType Directory -Path $Destination -Force | Out-Null
Copy-Item -LiteralPath $out -Destination $dst -Recurse
Compress-Archive -LiteralPath $dst -DestinationPath $zip
$sha256 = (Get-FileHash -LiteralPath $pck -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "PCK_SHA256 $sha256"
Write-Host "DOWNLOADS $dst"
Write-Host "ZIP $zip"
Write-Host "PACKAGE_DONE $tag"
