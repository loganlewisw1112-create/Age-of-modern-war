#!/bin/bash
# G5 package + clean-folder verification (ORCH). Export from the main tree (warm import cache).
#   bash .plan/package_g5.sh
GD=/c/Users/logan/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe
G="$GD/Godot_v4.7.2-stable_win64_console.exe"
ROOT="/d/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare"
cd "$ROOT/game" || exit 1
OUT="$ROOT/build/RTS_Age_of_Modern_War_G5"
rm -rf "$OUT"; mkdir -p "$OUT"
"$G" --headless --path . --export-pack "Windows Desktop" "$OUT/RTS_Age_of_Modern_War.pck" > "$ROOT/build/export_G5.log" 2>&1
echo "export exit=$? pck=$(du -h "$OUT/RTS_Age_of_Modern_War.pck" | cut -f1)"
cp "$GD/Godot_v4.7.2-stable_win64.exe" "$OUT/RTS_Age_of_Modern_War.exe"
cp "$G" "$OUT/RTS_Age_of_Modern_War_console.exe"
cp bin/rts_core.dll "$OUT/rts_core.dll"
cp "$ROOT/build/PLAY_ME_G5.txt" "$OUT/PLAY_ME.txt" 2>/dev/null
# clean-folder copy, run from there (no project dir, no --path); GUI exe (console wrapper fails from git-bash)
CLEAN="$ROOT/build/_clean_G5_test"
rm -rf "$CLEAN"; cp -r "$OUT" "$CLEAN"
cd "$CLEAN" || exit 1
E=./RTS_Age_of_Modern_War.exe
W="$(cygpath -m "$CLEAN")"
run() { # name, args...  (2 at a time)
  local n="$1"; shift; mkdir -p "pt_$n"
  timeout 1500 $E -- --ui-playtest="$W/pt_$n" "$@" > "pt_$n.log" 2>&1
}
run h & run hb --ui-playtest-faction=human_b & wait
run m --ui-playtest-faction=machine & run s --ui-playtest-stages & wait
run g4b --ui-playtest-g4b & run air --ui-playtest-air & wait
run naval --ui-playtest-naval & run drone --ui-playtest-drone & wait
run support --ui-playtest-support & run med --ui-playtest-med & wait
run tutorial --ui-playtest-tutorial &
mkdir -p pt_ed; timeout 900 $E -s res://tools/editor_playtest.gd -- --shots="$W/pt_ed" > pt_ed.log 2>&1 &
wait
for f in h hb m s g4b air naval drone support med tutorial ed; do echo "== $f $(grep -E 'NATIVE rts_core' pt_$f.log | head -1) | $(grep -E 'PLAYTEST RESULT' pt_$f.log | tail -1) | errs=$(grep -c 'SCRIPT ERROR' pt_$f.log)"; done
echo PACKAGE_DONE
