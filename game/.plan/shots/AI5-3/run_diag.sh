#!/bin/bash
# AI5-3: diagnose the 3 drawn soaks (same configs as AI5/run_soaks.sh) with --ai-breach-log
G=/c/Users/logan/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe
cd "/d/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game"
O=.plan/shots/AI5-3
F="--sides=3 --factions=human_a,human_b,machine"
T=${TAG:-d1}
MT=${MT:-120000}
"$G" --headless --path . -s tools/soak.gd -- --seed=2 --max-ticks=$MT --difficulty=normal --map=river_crossing_s $F --stages=7,8,9 --ai-breach-log --ai53soak > $O/soak_river_crossing_s_s2_$T.txt 2>&1 &
"$G" --headless --path . -s tools/soak.gd -- --seed=1 --max-ticks=$MT --difficulty=normal --map=valley_conquest_l $F --stages=9,7,8 --ai-breach-log --ai53soak > $O/soak_valley_conquest_l_s1_$T.txt 2>&1 &
"$G" --headless --path . -s tools/soak.gd -- --seed=2 --max-ticks=$MT --difficulty=normal --map=valley_conquest_l $F --stages=9,7,8 --ai-breach-log --ai53soak > $O/soak_valley_conquest_l_s2_$T.txt 2>&1 &
wait
echo ALL3_DONE
