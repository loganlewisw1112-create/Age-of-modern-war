#!/bin/bash
# Render assets/fonts/specimen.png with Godot (windowed: needs a real renderer).
# Uses a throwaway project so the game's autoloads/import never run.
# Usage (from game/): bash tools/font/render_specimen.sh [godot_exe]
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
GAME="$(cd "$HERE/../.." && pwd)"
GODOT="${1:-/c/Users/logan/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe}"
TMP="$(mktemp -d)"
printf 'config_version=5\n[application]\nconfig/name="rts_mil_specimen"\n' > "$TMP/project.godot"
cp "$HERE/specimen.gd" "$TMP/specimen.gd"
FONTS="$(cygpath -m "$GAME/assets/fonts" 2>/dev/null || echo "$GAME/assets/fonts")"
"$GODOT" --path "$TMP" --resolution 640x360 -s res://specimen.gd -- "$FONTS" "$FONTS/specimen.png"
RC=$?
rm -rf "$TMP"
exit $RC
