# G7-REGFIX7: fix the facility playtest regressions FACINT7 found (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board; status every 5 calls, never 10 min silent: heartbeat .plan/hb.sh; no git, no D:).
FACINT7 re-ran every facility flow windowed on the current tree (.plan/facint7_flows.log, logs .plan/facint7_logs/):
- turret7: apc_rear_gun (0 rear-pod shots at a target behind the APC), apc_muzzle_on_foe_side (cos -1.00) - APC rear gun
  traverse regression (13.9c-28a / 13.9c-30); check CIWS7-5's batch_art.gd turret bearing stamp change (32 steps + band).
- muzzle7: poses_flash (0 flash shots at zoom 2.5), apc_idle_travel, all_measured (1 fallback "gone").
- seq7: wash_spray, stretcher, decon_clean, quarantine, parked all 0 - the return / decon sequence never ran.
- cnops7: relief_arrived empty - maybe same root as seq7.
- sent7: casualty_in_cover ("cover 0.30 where he was dragged").
- dronebay7: rockets_intercepted 0 (guess: roof CIWS now takes rockets first; if that is correct behaviour, fix the
  flow's oracle to accept either interceptor ONLY if the spec says both defend; else fix the cause).
- ciws7 3 fails were a transient parse error in a then-mid-edit lp_reserve7.gd: just re-run.
For each: find the real cause (bisect against git HEAD 4a30917 if useful: `git show 4a30917:<path>` read-only is OK, no
other git), fix it at the cause, re-run the flow windowed to 0 fail, run the matching unit test. Never weaken a check.
If a cause sits in a live agent's file (CIWS7-6: ciws7 / g7_ciws7 / muzzle7 / fx CIWS branch; WALLFIRE7: damage / combat
line-of-fire; LPSHRINK7 / LPRES7-2: LP files; PERF7I: formations7 / senses7 / shrapnel), post a `need` to that agent and
orch with the evidence instead of editing. Final report: per flow, cause, fix, RESULT line before/after.
