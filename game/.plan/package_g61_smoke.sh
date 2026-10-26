#!/bin/bash
# G6.1 package + clean-folder verification (ORCH). PROGRESS G6.1 Done-when 2 and 5.
#   bash .plan/package_g61.sh            # import, export, clean-folder playtests (2 at a time)
# 1) import: the G6 art (assets/art/g6_*, g6_terrain) was never scanned by the editor, so it has no
#    .import files; without this step the exported pack would ship no G6 textures.
# 2) export the pack from the main tree, 3) copy into a clean folder (no project dir, no --path)
#    and run every playtest flow there with the GUI exe.
GD=/c/Users/logan/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe
G="$GD/Godot_v4.7.2-stable_win64_console.exe"
ROOT="/d/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare"
cd "$ROOT/game" || exit 1
mkdir -p "$ROOT/build"
timeout --kill-after=30 3000 "$G" --headless --path . --import > "$ROOT/build/import_G61.log" 2>&1
echo "import exit=$? errors=$(grep -c 'ERROR' "$ROOT/build/import_G61.log")"
OUT="$ROOT/build/RTS_Age_of_Modern_War_G61"
rm -rf "$OUT"; mkdir -p "$OUT"
timeout --kill-after=30 3000 "$G" --headless --path . --export-pack "Windows Desktop" "$OUT/RTS_Age_of_Modern_War.pck" > "$ROOT/build/export_G61.log" 2>&1
echo "export exit=$? pck=$(du -h "$OUT/RTS_Age_of_Modern_War.pck" | cut -f1)"
cp "$GD/Godot_v4.7.2-stable_win64.exe" "$OUT/RTS_Age_of_Modern_War.exe"
cp "$G" "$OUT/RTS_Age_of_Modern_War_console.exe"
cp bin/rts_core.dll "$OUT/rts_core.dll"
cp "$ROOT/build/PLAY_ME_G61.txt" "$OUT/PLAY_ME.txt" 2>/dev/null
CLEAN="$ROOT/build/_clean_G61_test"
rm -rf "$CLEAN"; cp -r "$OUT" "$CLEAN"
cp "$ROOT/game/.plan/shots/AI7-DOC/demo_start.save" "$CLEAN/demo_start.save" 2>/dev/null
cd "$CLEAN" || exit 1
E=./RTS_Age_of_Modern_War.exe
W="$(cygpath -m "$CLEAN")"
run() { # name, args...
  local n="$1"; shift; mkdir -p "pt_$n"
  timeout --kill-after=30 1500 $E -- --ui-playtest="$W/pt_$n" "$@" > "pt_$n.log" 2>&1
}
# smoke set (G6.1 follow-up 2): one at a time
for f in officer61 flick61 squad61 company61 air; do run $f --ui-playtest-$f; done
run h
for f in officer61 flick61 squad61 company61 air h; do
  echo "== $f | $(grep -E 'NATIVE rts_core' pt_$f.log | head -1) | $(grep -E 'PLAYTEST RESULT' pt_$f.log | tail -1) | errs=$(grep -c 'SCRIPT ERROR' pt_$f.log)"
done
echo PACKAGE_DONE
