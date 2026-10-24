#!/bin/bash
# G4 package + clean-folder verification (ORCH).
#   bash .plan/package_g4.sh
GD=/c/Users/logan/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe
G="$GD/Godot_v4.7.2-stable_win64_console.exe"
ROOT="/d/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare"
cd "$ROOT/game" || exit 1
OUT="$ROOT/build/RTS_Age_of_Modern_War_G4"
rm -rf "$OUT"; mkdir -p "$OUT"
"$G" --headless --path . --export-pack "Windows Desktop" "$OUT/RTS_Age_of_Modern_War.pck" > "$ROOT/build/export_G4.log" 2>&1
echo "export exit=$? pck=$(du -h "$OUT/RTS_Age_of_Modern_War.pck" | cut -f1)"
cp "$GD/Godot_v4.7.2-stable_win64.exe" "$OUT/RTS_Age_of_Modern_War.exe"
cp "$G" "$OUT/RTS_Age_of_Modern_War_console.exe"
cp bin/rts_core.dll "$OUT/rts_core.dll"
(cd "$ROOT" && git apply build/_ai5-4_wip/ai5-4_uncommitted.patch && echo "AI5-4 WIP restored")
cp "$ROOT/build/PLAY_ME_G4.txt" "$OUT/PLAY_ME.txt" 2>/dev/null
# clean-folder copy, run from there (no project dir, no --path)
CLEAN="$ROOT/build/_clean_G4_test"
rm -rf "$CLEAN"; cp -r "$OUT" "$CLEAN"
cd "$CLEAN" || exit 1
E=./RTS_Age_of_Modern_War.exe   # the console wrapper fails from git-bash (CreateProcess 193)
W="$(cygpath -m "$CLEAN")"
for f in h hb m s g4b; do mkdir -p "pt_$f"; done
timeout 900 $E -- --ui-playtest="$W/pt_h" > pt_h.log 2>&1 &
timeout 900 $E -- --ui-playtest="$W/pt_hb" --ui-playtest-faction=human_b > pt_hb.log 2>&1 &
timeout 900 $E -- --ui-playtest="$W/pt_m" --ui-playtest-faction=machine > pt_m.log 2>&1 &
timeout 900 $E -- --ui-playtest="$W/pt_s" --ui-playtest-stages > pt_s.log 2>&1 &
timeout 900 $E -- --ui-playtest="$W/pt_g4b" --ui-playtest-g4b > pt_g4b.log 2>&1 &
wait
mkdir -p pt_ed
timeout 900 $E -s res://tools/editor_playtest.gd -- --shots="$W/pt_ed" > pt_ed.log 2>&1
for f in h hb m s g4b ed; do echo "== $f"; grep -E "NATIVE|SIM_THREAD|PLAYTEST RESULT|SCRIPT ERROR|Parse Error" "pt_$f.log" | head -6; done
echo PACKAGE_DONE
