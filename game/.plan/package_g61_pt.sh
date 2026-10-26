#!/bin/bash
# G6.1: clean-folder playtests only (package_g61.sh minus import/export).
ROOT="/d/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare"
OUT="$ROOT/build/RTS_Age_of_Modern_War_G61"
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
# the 14 G6.1 flows (PROGRESS G6.1 Done-when 2 + 6)
run company61 --ui-playtest-company61 & run market61 --ui-playtest-market61 & wait
run fuel61 --ui-playtest-fuel61 & run bearer61 --ui-playtest-bearer61 & wait
run squad61 --ui-playtest-squad61 & run officer61 --ui-playtest-officer61 & wait
run gen61 --ui-playtest-gen61 & run chain61 --ui-playtest-chain61 & wait
run real61 --ui-playtest-real61 & run plan61 --ui-playtest-plan61 & wait
run anim61 --ui-playtest-anim61 & run animb61 --ui-playtest-animb61 & wait
run vfx61 --ui-playtest-vfx61 & run audio61 --ui-playtest-audio61 & wait
for f in h hb m s g4b air naval drone support med tutorial ed elev company aicmd mines garrison naval6 airdef exo loadout market airfield2 survival live brush company61 market61 fuel61 bearer61 squad61 officer61 gen61 chain61 real61 plan61 anim61 animb61 vfx61 audio61; do
  echo "== $f | $(grep -E 'NATIVE rts_core' pt_$f.log | head -1) | $(grep -E 'PLAYTEST RESULT' pt_$f.log | tail -1) | errs=$(grep -c 'SCRIPT ERROR' pt_$f.log)"
done
echo PACKAGE_DONE
