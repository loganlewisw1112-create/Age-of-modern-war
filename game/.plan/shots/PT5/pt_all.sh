#!/bin/bash
# PT5 (G5): every UI playtest flow (G1-G4 + G5), at most 2 windowed Godot runs at once.
# Usage: bash .plan/shots/PT5/pt_all.sh [TAG] [flow ...]
#   flows (default all): h hb m s g4b ed air naval drone support med tutorial
# Shots + logs: .plan/shots/PT5/pt_<flow>_<TAG>/ and pt_<flow>_<TAG>.log
G=/c/Users/logan/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe
cd "/d/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game"
B="D:/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game/.plan/shots/PT5"
S=.plan/shots/PT5
TAG=${1:-r1}
shift
FLOWS=("$@")
[ ${#FLOWS[@]} -eq 0 ] && FLOWS=(h hb m s g4b ed air naval drone support med tutorial)
MAXJ=${PT_MAXJ:-2}

run_flow() {
	local f="$1" d="$B/pt_${1}_$TAG" log="$S/pt_${1}_$TAG.log"
	mkdir -p "$S/pt_${f}_$TAG"
	case "$f" in
		h) timeout 900 "$G" --path . -- --ui-playtest="$d" ;;
		hb) timeout 900 "$G" --path . -- --ui-playtest="$d" --ui-playtest-faction=human_b ;;
		m) timeout 900 "$G" --path . -- --ui-playtest="$d" --ui-playtest-faction=machine ;;
		s) timeout 900 "$G" --path . -- --ui-playtest="$d" --ui-playtest-stages ;;
		g4b) timeout 900 "$G" --path . -- --ui-playtest="$d" --ui-playtest-g4b ;;
		ed) timeout 900 "$G" --path . -s res://tools/editor_playtest.gd -- --shots="$d" ;;
		air|naval|drone|support|med|tutorial) timeout 1500 "$G" --path . -- --ui-playtest="$d" --ui-playtest-$f ;;
		*) echo "unknown flow $f"; return 2 ;;
	esac > "$log" 2>&1
}

for f in "${FLOWS[@]}"; do
	while [ "$(jobs -rp | wc -l)" -ge "$MAXJ" ]; do sleep 2; done
	run_flow "$f" &
	sleep 3
done
wait
for f in "${FLOWS[@]}"; do
	echo "== $f: $(grep -E 'PLAYTEST RESULT' "$S/pt_${f}_$TAG.log" | tail -1)"
	grep -E "SCRIPT ERROR|Parse Error|ok=false" "$S/pt_${f}_$TAG.log" | head -12
done
