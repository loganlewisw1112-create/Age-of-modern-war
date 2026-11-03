#!/bin/bash
# Heartbeat wrapper for long single calls (godot runs > ~60 s, soak, bench).
# Posts the agent's LAST reported numbers every 90 s while the command runs.
# Usage: bash .plan/hb.sh <agent-id> <calls_used> <tokens_used_est> "<label>" -- <command...>
ID="$1"; CALLS="$2"; EST="$3"; LABEL="$4"; shift 4; [ "$1" = "--" ] && shift
export AGENT_BOARD="${AGENT_BOARD:-C:/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game/.plan/board_g71.jsonl}"  # G7.1: board_g71. G7: Windows path (node cannot open /c/...; heartbeats were silently lost)  # G7: default board_g7 (was board_g61)
POST=C:/CODING/SKILLS/tools/agent-board/post.mjs
beat(){ node "$POST" "$ID" orch status progress "{\"calls_used\":$CALLS,\"tokens_used_est\":$EST,\"next_action\":\"waiting: $LABEL\",\"done_so_far\":\"heartbeat during one long call\"}" >/dev/null 2>&1; }
( while true; do sleep 90; beat; done ) &
HB=$!
"$@"; RC=$?
kill "$HB" 2>/dev/null; wait "$HB" 2>/dev/null
exit $RC
