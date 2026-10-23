@echo off
rem Launch RTS: Age of Modern War (G0+G1 slice). First run imports the project once.
cd /d "%~dp0"
if "%GODOT%"=="" set "GODOT=%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe"
if not exist ".godot\global_script_class_cache.cfg" (
  echo First run: importing project, one time...
  "%GODOT:.exe=_console.exe%" --headless --path . --import
)
start "" "%GODOT%" --path . -- %*
