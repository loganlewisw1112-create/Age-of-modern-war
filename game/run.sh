#!/bin/bash
# Launch the game. On a fresh checkout Godot must build its import cache once (.godot/),
# otherwise global classes (SimWorld, Content, ...) are unknown.  Extra args go after `--`.
#   bash run.sh            -> main menu
#   bash run.sh --autostart
cd "$(dirname "$0")"
G="${GODOT:-/c/Users/logan/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64.exe}"
if [ ! -f .godot/global_script_class_cache.cfg ]; then
  echo "First run: importing project (one time)..."
  "${G%.exe}_console.exe" --headless --path . --import >/dev/null 2>&1 || "$G" --headless --path . --import >/dev/null 2>&1
fi
exec "$G" --path . -- "$@"
