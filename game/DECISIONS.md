# DECISIONS (G7.1 onward)

One line per non-obvious choice: decision, reason, rejected alternative. Owner words quoted where the owner decided.
Evidence lives on the board `.plan/board_g71.jsonl` (seq numbers below) and in `docs/NATIVE_COMBAT71.md`.

| Date | Decision | Reason | Rejected |
|---|---|---|---|
| 2026-11-04 | Sim gate unchanged (2k sim ms/tick <= G6); native combat port (board seq 210) | Owner | Restating the gate |
| 2026-11-05 | "Full native combat port" (seq 358) | Owner, after prefilter ports saved ~0.03 ms | Per-unit-of-work gate; accept cost; approximations |
| 2026-11-08 | "Yes, keep going" through phase 2 measurement (seq 461) | Owner, after phase 1 saved ~0 | Stop and rethink |
| 2026-11-08 | "Yes, start phase 3" (seq 562) | Owner, after phase 2 saved 1.5 of 2.0 ms (1.85x G6) | Pause the port |
| 2026-11-08 | CR 467 minimap incoming markers reassigned to PERFDRAW71 (seq 470) | CONTROL71 finished; 10k draw calls 242 vs G7 132 | Leave the 10k regression |
| 2026-11-08 | LP peak: "Cache now, native later" (seq 599) | Owner; LP peak p10 22 vs gate 60 | Native only; cache only; lower the bar |
| 2026-11-09 | Frame-record cache (PD71_RC) OFF by default, code kept (seq 698) | rc8: 2 diffs in 3000 frames at 2k, no measured fps gain anywhere | Ship it on |
| 2026-11-09 | "Probe other systems first" (seq 699); combat port paused after phase 3a | Owner; phase 3a landed at ~50% of estimate, G7.1 1.67x G6, gate projection out of sight | Keep porting combat; new bar; approximations |
| 2026-11-09 | "New bar, move on": E2 sim gate amended to final build <= 1.7x G6 on 2k, later waves add ~0 (G71_SCOPE.md Pre-start decisions); native combat port stopped after phase 3a; start wave 2 | Owner, after the phase-6 probe (seq 743): non-combat gap is mostly new features, exact cuts ~1-2 ms | Keep G6 bar; finish combat port; approximations. Form chosen: ratio (measurable) over "per unit of work" |
| 2026-11-09 | LP-peak native machine-drawing builder unblocked (native/ free now the port stopped) | Owner's "native later" waited only on the combat port | Leave LP peak at 22 fps |
| 2026-11-08 | G7.1 stays on agent-board v1 | v2 README: never switch a run in flight; RTS switches at the next slice | Switch mid-run |
| 2026-11-09 | Wave 2 roster: DAMAGE71, FIRES71, ARMY71, BASTION71 now; CNOPS71 after RAMP71 (.plan/orch71/wave2_roster.md) | Max 6 live with SWARMNAT71 + RAMP71 | One agent per scope part (too many) |
| 2026-11-09 | Wave 2 features are Last Protocol only (roster 5A Q1) | Frozen GOAL Out-of-scope: "skirmish changes beyond what A1-A5 touch" | Every mode (ROADMAP G9/G12 carry those) |
| 2026-11-09 | PROVISIONAL: J10 gas from CN gas munitions + facility vents at breach lockdown; minimal deterministic wind now, I3 extends it (5A Q7) | Scope says what gas does, not its source | Gas as a radial fire mission only |
| 2026-11-09 | PROVISIONAL: 70 s gate = Done-when 8 team airlock cycle; ward-kept soldiers excluded and reported; 8-APC exit measured, not gated (5A Q8) | Done-when 8 wording is the frozen check | Gate the 8-APC exit |
| 2026-11-09 | Callouts text now, voiced in the wave-5 sound pass (5A Q13) | Sound pass is wave 5 (H10/E1) | Voice every line now |
| 2026-11-09 | Wave-2 agents add only new files until wave 1 is committed | Keeps the wave-1 commit clean | Pause wave 2 until the commit |
| 2026-11-09 | Wave-1 gate suite run per file, 6 lanes (G7's suite_g7.sh method), not tests/run.sh in one process | run.sh crawled 8.4 h with no output; G7's gate used per-file | Keep waiting on run.sh |
| 2026-11-09 | rts_core 0.6.3: prep_mirror adds cd_ticks as a StringName (mirror.rs k_cd_ticks) | 0.6.2 added it as a String: same value, different var_to_bytes, test_airfield native on != off; bench hashes + test_hot_state unchanged | Guard in GDScript; re-baseline |
| 2026-11-09 | "Fix all 18 first": commit wave 1 only when all 177 test files are green on the frozen copy, incl. the 13 broken by A5 (+20% speed) before wave 1 | Owner, after the wave-1 suite (157/177) | Fix wave 1's 5 then commit; commit now with failures listed |
| 2026-11-09 | "Bar >=30 fps, build native": LP-peak fps gate amended to p10 >= 30 and >= 2x G7 (2k/10k/LP pan/zoom-out stay >= 60) (G71_SCOPE.md) | Owner, after swarmnat71.split: frame stays ~23 ms even with free unit drawing; native best case ~33-36 | Keep 60 + whole-frame push; beat G7 only; defer to wave 6 |
| 2026-11-10 | 4 wave-1 fixers, not 3: the 13 A5 files split into SPEEDFIX71 (core sim, 7) and SPEEDCN71 (CN / soldiers, 6); file claims on the board (`fact claim.file`) keep them off each other's files | 13 diagnoses with 2-7 min test runs would take one agent several generations; max 6 live still leaves 2 slots | One SPEEDFIX71 for all 13 (the plan as written) |
| 2026-11-10 | Fixers never edit tests/; a speed-coupled expectation goes to ORCH as `change_request testfix.<test>` and to the owner before any change | Done-when frozen, "never weaken a test" | Let fixers update speed-coupled numbers themselves |
| 2026-11-13 | "Yes, as recommended": apply 9 test changes as proposed (board seq 1067 cnsuits7, 1069 wound7, 1076 content_g6, 1094 real61, 1120 gen61, 1077 perf, 1134 drone_team, 1191 cards8c, 1223 sent7); test_naval_g6 fixed in the SIM instead (sweep rate scales with g71_speed_mult so one pass still clears the lane; test unchanged); test_cnrole7 gets a setup where the parked soldier survives (not "tolerate his death") | Owner, after per-test evidence (each proposed test passes on G7 3a66ffc and live); A5 is owner-locked and the game behaves correctly in the 9 | Fix the sim for all 13; leave tests red; naval test stops at the field edge (1141); cnrole7 breaks out on death (1122) |
| 2026-11-13 | test_cnrole7: "Both A and B": (A) the test's walker sits at a_pos + (-4,-1) (4.1 tiles, in the soldier's 4.5 shotgun range, off his own side's lines of fire); (B) sim: a CN unit parked at home (CnRole7.parked) is never picked for an AUTOMATIC buddy-aid job (wounds.gd _auto_pass buddy branch; medic jobs, evac and player orders unchanged) | TESTFIX71 (need 1330): two causes (own-side strays; auto buddy aid moved the parked man), original setup already failed 5/6 tick shifts on G7; A alone = live/HEAD 6/6, G7 5/6 | A only; B only; tolerate death (rejected 2026-11-13) |
