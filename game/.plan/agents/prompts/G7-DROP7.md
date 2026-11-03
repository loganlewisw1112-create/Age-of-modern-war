# G7-DROP7: drone strike-drop lands on the squad (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board; status DIRECTLY every 5 tool calls; no git, no D:). Spec: docs/G7_REFERENCE.md drone
sections (the drone team: take control, drop, detonate; "drone_drop" J). Open miss since INTEG7 (packaged smoke and
PERF7D): windowed playtest flow pt7_drone7 check drone7_strike_drop fails: "blast ~6 tiles from the squad"
(tools/pt7_drone7.gd:155). Find the real cause: is the dropped munition's impact point computed from a stale drone
position, a hand-over / frame chaining delay (PERF7D tried --handover=frame), drift while falling, or a flow aiming
problem? Fix the cause (sim or flow), never by loosening the check's distance or conditions.
Run: G=<godot console exe>; windowed: "$G" --path . -- --ui-playtest=.plan/shots/DROP7/ptN --ui-playtest-drone7
(timeout 900). Also test_drone7 and any determinism test of the drone (record/replay) you touch: they stay green, and the
drone replay determinism (Done-when 2: "including the drone replay") must hold: if a recorded flight replay test
exists, run it and report; if none exists, say so.
Deliver: PLAYTEST RESULT 0 fail for drone7, shots of the drop (fact shots.best, plain caption), test RESULT lines.
Files: tools/pt7_drone7.gd, the drone sim/ui files you diagnose (post a claim fact first; BAL7 owns sentinels7 /
drone_bay7 (the defence hive, not the drone team), CIWS7-3 owns ciws7, PERF7G may claim sim systems: check claims).
