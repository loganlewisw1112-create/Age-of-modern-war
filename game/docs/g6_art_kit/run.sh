#!/bin/bash
# Render one or more G6 art modules with the game's own art code. Usage: bash run.sh <module> [<module> ...]
# Prints G6ART result lines plus any SCRIPT ERROR / Parse Error lines; times out after 300 s (Godot hangs on exit after a parse error).
S="$(cd "$(dirname "$0")" && pwd -W 2>/dev/null || pwd)"
G=/c/Users/logan/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe
cd "/d/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game" || exit 2
timeout 300 "$G" --headless --path . -s "$S/gd/g6_gen.gd" -- "$@" 2>&1 | grep -E "G6ART|SCRIPT ERROR|Parse Error|   at: "
