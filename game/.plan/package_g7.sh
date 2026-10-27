#!/bin/bash
# G7 package + clean-folder smoke (ORCH, INTEG7 fast path). Same steps as package_g61.sh, C: tree (G7 runs on C:).
GD=/c/Users/logan/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe
G="$GD/Godot_v4.7.2-stable_win64_console.exe"
ROOT="/c/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare"
cd "$ROOT/game" || exit 1
mkdir -p "$ROOT/build"
timeout --kill-after=30 1200 "$G" --headless --path . --import > "$ROOT/build/import_G7.log" 2>&1
echo "import exit=$? errors=$(grep -c 'ERROR' "$ROOT/build/import_G7.log")"
OUT="$ROOT/build/RTS_Age_of_Modern_War_G7"
rm -rf "$OUT"; mkdir -p "$OUT"
timeout --kill-after=30 1200 "$G" --headless --path . --export-pack "Windows Desktop" "$OUT/RTS_Age_of_Modern_War.pck" > "$ROOT/build/export_G7.log" 2>&1
echo "export exit=$? pck=$(du -h "$OUT/RTS_Age_of_Modern_War.pck" | cut -f1) md5=$(md5sum "$OUT/RTS_Age_of_Modern_War.pck" | cut -c1-32)"
cp "$GD/Godot_v4.7.2-stable_win64.exe" "$OUT/RTS_Age_of_Modern_War.exe"
cp "$G" "$OUT/RTS_Age_of_Modern_War_console.exe"
cp bin/rts_core.dll "$OUT/rts_core.dll"
cp "$ROOT/build/PLAY_ME_G7.txt" "$OUT/PLAY_ME.txt"
CLEAN="$ROOT/build/_clean_G7_test"
rm -rf "$CLEAN"; cp -r "$OUT" "$CLEAN"
cd "$CLEAN" || exit 1
E=./RTS_Age_of_Modern_War.exe
W="$(cygpath -m "$CLEAN")"
run() { local n="$1"; shift; mkdir -p "pt_$n"; timeout --kill-after=30 900 $E -- --ui-playtest="$W/pt_$n" "$@" > "pt_$n.log" 2>&1; }
run lpmode7 --ui-playtest-lpmode7 & run cnfac7 --ui-playtest-cnfac7 & wait
run drone7 --ui-playtest-drone7 & run h & wait
for f in lpmode7 cnfac7 drone7 h; do
  echo "== $f | $(grep -E 'NATIVE rts_core' pt_$f.log | head -1) | $(grep -E 'PLAYTEST RESULT' pt_$f.log | tail -1) | errs=$(grep -c 'SCRIPT ERROR' pt_$f.log)"
done
echo PACKAGE_DONE
