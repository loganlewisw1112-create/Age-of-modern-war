# G7.1 playable package: import -> export-pack -> exe+dll+PLAY_ME -> build/ + Downloads + zip.
# Usage: powershell -NoProfile -File game/.plan/package_g71.ps1
param([string]$Note = "")
$ErrorActionPreference = "Stop"
$root = "C:\CODING\PROJECTS - CURRENTLY WORKING ON\RTS Age of Modern Warfare"
$godot = "C:\Users\logan\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"
$godotWin = "C:\Users\logan\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe"
$sha = (git -C $root rev-parse --short HEAD).Trim()
$day = Get-Date -Format "yyyy-MM-dd"
$tag = "G71_${day}_$sha"
# Keep only the newest KeepN packages so disk does not fill with ~100MB pcks each commit.
$KeepN = 2
$dstParent = "C:\Users\logan\Downloads\Age of Modern War"
foreach ($parent in @((Join-Path $root "build"), $dstParent)) {
  if (-not (Test-Path $parent)) { continue }
  $dirs = @(Get-ChildItem $parent -Directory -Filter "RTS_Age_of_Modern_War_G71_*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
  if ($dirs.Count -gt $KeepN) {
    $dirs | Select-Object -First ($dirs.Count - $KeepN) | ForEach-Object {
      Write-Host "PRUNE $($_.FullName)"
      Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  $zips = @(Get-ChildItem $parent -Filter "RTS_Age_of_Modern_War_G71_*.zip" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
  if ($zips.Count -gt $KeepN) {
    $zips | Select-Object -First ($zips.Count - $KeepN) | ForEach-Object {
      Write-Host "PRUNE $($_.FullName)"
      Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
    }
  }
}
$out = Join-Path $root "build\RTS_Age_of_Modern_War_$tag"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$docsPlay = Join-Path $root "game\docs\PLAY_ME_G71_2026-11-22.txt"
$playPath = Join-Path $root "build\PLAY_ME_G71.txt"
if (Test-Path $docsPlay) {
  Copy-Item $docsPlay $playPath -Force
} elseif (-not (Test-Path $playPath)) {
  @(
    "RTS: Age of Modern War - G7.1 playable ($sha)"
    "PLAY: double-click RTS_Age_of_Modern_War.exe"
    "Keep RTS_Age_of_Modern_War.pck AND rts_core.dll next to it."
    "LAST PROTOCOL: main menu > Last Protocol."
  ) | Set-Content -Path $playPath -Encoding ascii
}
if ($Note -ne "") {
  Add-Content -Path $playPath -Value $Note -Encoding ascii
}
$play = Get-Content $playPath -Raw
if ($play -notmatch [regex]::Escape($sha)) {
  Set-Content -Path $playPath -Value ("Commit: $sha`r`n`r`n" + $play) -Encoding ascii
}
Copy-Item $playPath (Join-Path $out "PLAY_ME.txt") -Force
$lookSrc = Join-Path $root "game\.plan\shots\G71_LOOK"
$lookDoc = Join-Path $root "game\docs\G71_LOOK_CHECKPOINT.md"
if (Test-Path $lookDoc) {
  Copy-Item $lookDoc (Join-Path $out "G71_LOOK_CHECKPOINT.md") -Force
}
if (Test-Path $lookSrc) {
  $lookOut = Join-Path $out "G71_LOOK_CHECKPOINT"
  New-Item -ItemType Directory -Force -Path $lookOut | Out-Null
  Copy-Item (Join-Path $lookSrc "*") $lookOut -Force
  $lookDstParent = Join-Path $dstParent "G71_LOOK_CHECKPOINT"
  New-Item -ItemType Directory -Force -Path $lookDstParent | Out-Null
  Copy-Item (Join-Path $lookSrc "*") $lookDstParent -Force
}
Set-Location (Join-Path $root "game")
Write-Host "IMPORT_START $sha -> $out"
& $godot --headless --path . --import *> (Join-Path $root "build\import_G71.log")
Write-Host "IMPORT_EXIT $LASTEXITCODE"
$pck = Join-Path $out "RTS_Age_of_Modern_War.pck"
& $godot --headless --path . --export-pack "Windows Desktop" $pck *> (Join-Path $root "build\export_G71.log")
Write-Host "EXPORT_EXIT $LASTEXITCODE"
if (-not (Test-Path $pck)) { throw "export failed: no pck" }
Copy-Item $godotWin (Join-Path $out "RTS_Age_of_Modern_War.exe") -Force
Copy-Item $godot (Join-Path $out "RTS_Age_of_Modern_War_console.exe") -Force
Copy-Item (Join-Path $root "game\bin\rts_core.dll") (Join-Path $out "rts_core.dll") -Force
$md5 = (Get-FileHash $pck -Algorithm MD5).Hash.ToLower()
$len = (Get-Item $pck).Length
Write-Host "PCK_MD5 $md5 SIZE $len"
New-Item -ItemType Directory -Force -Path $dstParent | Out-Null
$dst = Join-Path $dstParent "RTS_Age_of_Modern_War_$tag"
if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
Copy-Item $out $dst -Recurse -Force
$zip = Join-Path $dstParent "RTS_Age_of_Modern_War_$tag.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $dst -DestinationPath $zip -Force
Write-Host "DOWNLOADS $dst"
Write-Host "ZIP $zip"
Write-Host "PACKAGE_DONE $tag"
