# G7.1 Done-when smoke: headless suite of key stubs (not the 60-min soak; not owner look).
# Usage: powershell -NoProfile -File game/tools/g71_donewhen_smoke.ps1
$ErrorActionPreference = "Stop"
$G = "C:\Users\logan\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path (Join-Path $root "game\project.godot"))) {
  $root = "C:\CODING\PROJECTS - CURRENTLY WORKING ON\RTS Age of Modern Warfare"
}
Set-Location (Join-Path $root "game")
$tests = @(
  "test_hive71","test_fire71","test_fire71_block","test_death71","test_harvest71",
  "test_audio_h10","test_h9_score","test_capture71","test_evolve71","test_atmo_tide",
  "test_warmind71","test_recomplex71","test_fleet71"
)
$fail = 0
foreach ($t in $tests) {
  Write-Host "=== $t ==="
  & $G --headless --path . -s res://tests/run_tests.gd -- "--only=$t" 2>&1 | Select-String -Pattern "RESULT|FAIL "
  if ($LASTEXITCODE -ne 0) { $fail++ }
}
Write-Host "SMOKE_DONE fails=$fail / $($tests.Count)"
exit $fail
