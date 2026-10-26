#!/bin/bash
# ORCH helper: on a first GUARD STALE (count=1), post a status.nudge directive to that agent.
export AGENT_BOARD="/c/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game/.plan/board.jsonl"
cd /c/CODING/SKILLS/tools/agent-board
node guard.mjs --board "$AGENT_BOARD" 2>&1 | grep --line-buffered "GUARD STALE" | grep --line-buffered "count=1" | while read -r line; do
  a=$(echo "$line" | sed -n 's/.*agent=\([^ ]*\) .*/\1/p')
  [ -n "$a" ] && node post.mjs orch "$a" directive status.nudge '{"msg":"guard STALE: post a status now, then every 5 calls OR 4 minutes; wrap long runs in hb.sh"}' >/dev/null && echo "$(date +%H:%M:%S) ORCH NOTE auto-nudged $a" >> "/c/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game/.plan/bus.log"
done
