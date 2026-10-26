#!/bin/bash
# G6 package + clean-folder verification (ORCH). PLAN_G6 section 12 item 7.
#   bash .plan/package_g6.sh            # import, export, clean-folder playtests (2 at a time)
# 1) import: the G6 art (assets/art/g6_*, g6_terrain) was never scanned by the editor, so it has no
#    .import files; without this step the exported pack would ship no G6 textures.
# 2) export the pack from the main tree, 3) copy into a clean folder (no project dir, no --path)
#    and run every playtest flow there with the GUI exe.
GD=/c/Users/logan/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe
G="$GD/Godot_v4.7.2-stable_win64_console.exe"
ROOT="/d/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare"
cd "$ROOT/game" || exit 1
mkdir -p "$ROOT/build"
timeout --kill-after=30 3000 "$G" --headless --path . --import > "$ROOT/build/import_G6.log" 2>&1
echo "import exit=$? errors=$(grep -c 'ERROR' "$ROOT/build/import_G6.log")"
OUT="$ROOT/build/RTS_Age_of_Modern_War_G6"
rm -rf "$OUT"; mkdir -p "$OUT"
timeout --kill-after=30 3000 "$G" --headless --path . --export-pack "Windows Desktop" "$OUT/RTS_Age_of_Modern_War.pck" > "$ROOT/build/export_G6.log" 2>&1
echo "export exit=$? pck=$(du -h "$OUT/RTS_Age_of_Modern_War.pck" | cut -f1)"
cp "$GD/Godot_v4.7.2-stable_win64.exe" "$OUT/RTS_Age_of_Modern_War.exe"
cp "$G" "$OUT/RTS_Age_of_Modern_War_console.exe"
cp bin/rts_core.dll "$OUT/rts_core.dll"
cp "$ROOT/build/PLAY_ME_G6.txt" "$OUT/PLAY_ME.txt" 2>/dev/null
CLEAN="$ROOT/build/_clean_G6_test"
rm -rf "$CLEAN"; cp -r "$OUT" "$CLEAN"
cp "$ROOT/game/.plan/shots/AI7-DOC/demo_start.save" "$CLEAN/demo_start.save" 2>/dev/null
cd "$CLEAN" || exit 1
E=./RTS_Age_of_Modern_War.exe
W="$(cygpath -m "$CLEAN")"
run() { # name, args...
  local n="$1"; shift; mkdir -p "pt_$n"
  timeout --kill-after=30 1500 $E -- --ui-playtest="$W/pt_$n" "$@" > "pt_$n.log" 2>&1
}
ed() { # name, args...
  local n="$1"; shift; mkdir -p "pt_$n"
  timeout --kill-after=30 900 $E -s res://tools/editor_playtest.gd -- --shots="$W/pt_$n" "$@" > "pt_$n.log" 2>&1
}
# the 12 G5 flows
run h & run hb --ui-playtest-faction=human_b & wait
run m --ui-playtest-faction=machine & run s --ui-playtest-stages & wait
run g4b --ui-playtest-g4b & run air --ui-playtest-air & wait
run naval --ui-playtest-naval & run drone --ui-playtest-drone & wait
run support --ui-playtest-support & run med --ui-playtest-med & wait
run tutorial --ui-playtest-tutorial & ed ed & wait
# the 14 G6 flows (PLAN_G6 12.4)
run elev --ui-playtest-elev & run company --ui-playtest-company & wait
run aicmd --ui-playtest-aicmd & run mines --ui-playtest-mines & wait
run garrison --ui-playtest-garrison & run naval6 --ui-playtest-naval6 & wait
run airdef --ui-playtest-airdef & run exo --ui-playtest-exo & wait
run loadout --ui-playtest-loadout & run market --ui-playtest-market & wait
run airfield2 --ui-playtest-airfield2 & run survival --ui-playtest-survival & wait
ed live --g6=live & ed brush --g6=brush & wait
for f in h hb m s g4b air naval drone support med tutorial ed elev company aicmd mines garrison naval6 airdef exo loadout market airfield2 survival live brush; do
  echo "== $f | $(grep -E 'NATIVE rts_core' pt_$f.log | head -1) | $(grep -E 'PLAYTEST RESULT' pt_$f.log | tail -1) | errs=$(grep -c 'SCRIPT ERROR' pt_$f.log)"
done
echo PACKAGE_DONE
