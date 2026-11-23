# PROGRESS: RTS: Age of Modern War

## SLICE STOP (2026-11-22) — packaged as-is. Read this first. Next slice starts below this line.
Branch `g71` at `24f68b4`. Wave 1 is the commit `82a887a` (suite 177/177). Wave 2 is in the working tree and is
**not** a closed wave. After the Vanta2 checkpoint, the hive director C1–C6 stubs landed (dread, feints,
breaking-point, logistics, regrow, adapt, C3/C4 units, sync, reclaim, wreck cover, glass camo). The package is
`build/RTS_Age_of_Modern_War_G71_2026-11-22/` and the same folder under
`C:/Users/logan/Downloads/Age of Modern War/` (+ zip). Pack: import exit 0, export exit 0, pck md5
`0d9b68a59f6abc40372bc40486bcb1d7` (97,889,260 bytes). Player note: `build/PLAY_ME_G71.txt`.

**In this package, on top of the 2026-10-30 G7 build**
- Wave 1: aircraft home pads, air ops, fewer steps to battle, control, the sim/render perf work from `82a887a`.
- Wave 2 as far as the six lines got on 2026-11-22: firepower (Conductor + wingmen, ammo tiers, kill zones, fires),
  soldiers / vehicles / defences (crews, walls, turrets, discipline), counter-nanite ops (grenades, shield drone,
  hospital, gas and masks, 41.5 s airlock cycle on seed 77), gore and casualty care. Army, Damage, and Bastion
  lines had handed off. Fires, counter-nanite ops, and the drawing line were still open when the agents stopped.
- Vanta2 (this slice): the gunship keeps momentum, banks, strafes through the target, and fires the twin front
  guns. `sim/systems/vanta7.gd` `_flight2`. A chase step is no longer treated as a teleport. Attack orders drop
  the chase path. A large heading error slows and pivots. The run-out flies straight through before the next pass.
  Tests: gear / momentum / strafe failures=[], `test_vanta7` 7/0, full `test_cnops71` 16/0 (includes the purge-cannon
  and save/load checks). The strafe test holds the target outside the base
  (a core hit deletes the machine) and keeps its part hp up.

**Left for the next slice. Do not treat these as done.**
- C1 dread meter is in (2026-11-22, after the checkpoint package): `director71.gd` records hive pressure from time, creep, fallen rings and lost teams. The HUD shows it. Tide assault gaps are longer while dread is low and return to the written base at full dread. Phase timing is unchanged. `test_director71` 2/0.
- C1 breaking-point + C2 feint assaults (2026-11-22): first siege-band crossing emits `LpBreakingPoint` once; Tide waves split onto a main face and a feint face via `Director71.pick_push`. HUD exposes `break_point`. `test_director71` 3/0.
- C2 late logistics peels + retreat/regrow (2026-11-22): at high dread, a slice of each Tide wave peels onto FARP/radar/power/hospital/depot; wounded machines fall back to the hive spawn, heal, and return. Events `LpLogisticsStrike` / `LpRetreat` / `LpRegrow`. `test_director71` 4/0; `test_lpmode7` 18/0.
- C2 adapt counters (2026-11-22): Machine deaths bucket into armour/emp/smoke/disperse from the killing weapon class; AssaultWave + HUD expose the current counter; `LpAdapt` events. Damage events carry `cls`/`weapon`. `test_director71` 5/0; `test_lpmode7` 18/0.
- C3 siege stubs (2026-11-22): all four C3 defs (`g71_m_brute`, `g71_m_siege_walker`, `g71_m_turret_eater`, `g71_m_sapper`); Tide assaults spawn the roster once dread hits mixed/siege (`LpSiegeSpawn`). Sapper reuses burrower `t7` AI. Latch / jammer polish still open. `test_director71` 6/0; `test_lpmode7` 18/0.
- C4 special stubs + Overmind line (2026-11-22): `g71_m_reclaimer`, `g71_m_hive_conductor`, `g71_m_glass_stalker` defs; siege roster includes them; breaking-point emits `OvermindSay`. Eat/print, sync aura, camo polish still open. `test_director71` 6/0; `test_lpmode7` 18/0.
- Overmind adapts on the radio (2026-11-22): when the adapt counter flips, `OvermindSay` fires the matching adapt_* line.
- LP HUD shows BREAKING POINT and the current hive counter next to dread (`lp_hud.lines`).
- Adapt spawn bias (2026-11-22): the current counter peels one bonus C3/C4 unit onto each Tide siege roster (`adapt_spawn`).
- Hive Conductor sync aura (2026-11-22): machines inside `sync_radius` get `lp_sync`; count changes emit `LpHiveSync`; synced shooters deal `sync_damage` (1.12×) via Damage.
- Reclaimer eat/print (2026-11-22): reclaimers destroy a wreck in reach and spawn `reclaim_print` (`LpReclaim`). Body piles still open.
- C6 wreck cover (2026-11-22): in Last Protocol, units next to a wreck count as in cover (`wreck_cover_r`); wreck positions cached on `lp.wreck_pos`.
- C4 Glass stalker camo (2026-11-22): stalkers spawn with Fog `hid`; a hit clears it and emits `LpGlassReveal`. Thermal / rain polish still open.
- Frame rate. Last Protocol peak p10 was about 24 fps (gate 30). The 2,000-unit case p10 was about 35 fps (gate 60).
  Exact drawing cuts did not close it. The swarm kernel is parked (it was slower). A visible quality cut was ruled
  out (`docs/SWARM_NATIVE71.md` sections 10–11).
- Waves 3–6 are not started: hive director, robot fleet, core raids, save/resume, the look checkpoint, animation,
  the long soaks, a final package that claims the frozen Done-when.
- Skirmish still has the 120 population cap (parked, 13.9c-40).
- The 8-APC airlock under pressure is still about 83 s (target was ~70 s). The headless counter-nanite cycle on
  seed 77 was 41.5 s.
- Quiet-PC 60-minute body run, wave-2 gate suite, and the owner's yes before a wave-2 commit were not done.
  This save is a checkpoint of the tree, not that yes.

## Active goal (G7.1 "Tide Line", owner-LOCKED 2026-10-31; execution ordered 2026-11-02 "Start G7.1"; branch `g71`)
Scope authority: `docs/G71_SCOPE.md` (parts A–J, Pre-start decisions 2026-11-02, Done-when frozen). Plan + roster:
`docs/PLAN_G71.md`; briefs `.plan/agents/prompts/G71-*.md` + `G71_COMMON.md`; board `.plan/board_g71.jsonl`.
Full roadmap after it: `docs/ROADMAP.md` (G8–G18).
**CURRENT STATE (ORCH, 2026-11-21 18:15Z; read this first, history below):** wave 1 committed 82a887a (177/177). Owner
2026-11-21: "Start wave 2". ORCH wiring DONE, uncommitted (backups .plan/orch71/wire_orig/): sim/world.gd (10 wave-2 systems
in SYSTEM_ORDER, 17 commands), sim/systems/g6_hooks.gd (DAMAGE71 CR 955: p71spd / p71acc), sim/systems/lp_setup.gd
(build_g71: Q15 LP-base hook, reads content/g71_lp/lp_base_<agent>.json; no file = no change). Not registered yet (handler
not ready): turret_revive, hosp_medevac, fac_upgrade, cn_search / cn_abort / cn_roe + CnMission71, Conductor71, Discipline71.
Verified after wiring (logs C:/CODING/orch71_check/wire71/): parse clean; hashes 8fd794b3 / a1e5af17 / 41b5f765 == ref;
test_lpmode7 18/0, test_lpmap7 18/0, test_lpreserve7 7/0, test_lpperf7 9/0, test_perfsim71 6/0, test_mil 13/0, test_content_g6
7/0, test_damage71 11/0, test_bastion71 9/0, test_fires71 10/0, test_army71 5/0, test_swarmnat71 1/0; test_gas71 9/3 + 16
script errors = CNOPS71-1's known open item (same before wiring); test_hot_state 17/0.
**LAUNCHED 2026-11-21 18:25Z (all Opus, caps 750k/140 registered, guard + board watcher under Monitor, keep-awake on):
DAMAGE71-2, FIRES71-2, ARMY71-3, BASTION71-2, CNOPS71-2, SWARMNAT71-2 = 6 live (the cap). On resume after a break: read
each agent's last `status` on the board; a dead agent (API error) gets a successor from its handoff or last status.**
2026-11-21 ~19:00Z: connection drop killed DAMAGE71-2, FIRES71-2, SWARMNAT71-2 (API ENOTFOUND); all three RESUMED in place
with SendMessage (same context, same caps). First LP-base file live: content/g71_lp/lp_base_fires.json (2 FO teams outer
ring, 2 MLRS core ring), ORCH-approved (owner may tune at the look checkpoint); LP tests after it: lpmode7 18/0, lpmap7
18/0, lpreserve7 7/0, lpperf7 9/0; export filter `*.json` already covers the new dir.
**PARKED 2026-11-21 19:50Z (ORCH): the internet connection dropped 3 times in an hour (API ENOTFOUND / ECONNRESET /
timeouts) and killed all six agents each time; resumed twice, third time not resumed. Wave 2 waits for a stable
connection.** Nothing is lost: every agent can be resumed in place with SendMessage (same context) or respawned from its
last board status. State at the park (last real status per agent):
- DAMAGE71-2 (45 calls, ~280k): damage.gd Parts71 hook INSTALLED (hashes == ref posted 19:02); gore71.gd J1 written but
  STAGED (.plan/damage71/stage2); next: rules_g71_gore.json + care71.gd + rules_g71_care.json, install with the damage /
  wounds / medical hooks after test_hot_state + test_lpmode7.
- FIRES71-2 (43 calls, ~335k): art group g71_fires registered; LP base file live + approved; conductor71.gd written (ORCH
  fixed its one parse error, line 130, and it is now LF), NOT tested, no tests/test_conductor71.gd yet, not in world.gd;
  must rerun test_lpmode7 + test_lpreserve7 (its runs had 56 / 58 lp_home script errors, fixed by ORCH); then handoff.
- ARMY71-3 (34 calls, ~215k): combat.gd / squad_ai.gd D4 hooks + DAMAGE71 CR 956 installed; combat.gd ammo hooks (LP only)
  + tests/test_ammo71.gd (6 tests) written; hashes / hot_state / test_ammo71 results NOT collected.
- BASTION71-2 (31 calls, ~245k): build_rail X hotkey clash FIXED (reports test_ui_panels 5/0, test_ui6b 5/0; ORCH has not
  re-run them); art generator tools/art/g71_defences.gd written, NOT run / registered; test_art + test_icons7 still owed.
- CNOPS71-2 (47 calls, ~420k = at its handoff line): test_gas71 12/0; cnmission71.gd installed + fix; turnaround built;
  test_facility71 + test_cnops71 r2 results NOT collected; must write its handoff file first on resume.
- SWARMNAT71-2 (38 calls, ~275k): verify harness fixed; statics-only verify (rsv r2) result NOT collected;
  native/rts_core/src/swarm_draw.rs not started.
- ORCH fix 19:20Z: lp_setup.gd build_g71 sets lp_home (+ lp_ring >= 0) on placed units (LpDefence.think threw ~160 script
  errors per LP run; found by CNOPS71-2 seq 1478). NOT yet verified by a clean LP run: run test_lpmode7 + test_lpreserve7
  and grep `lp_home` = 0 before anything else.
- Parse sweep of the 40 changed / new .gd files: C:/CODING/orch71_check/park71/ (only conductor71.gd failed; fixed).
- **Owner note 2026-11-21: the Godot windows that pop up during agent testing look "SUPER laggy; should have next to zero
  lag".** At that moment the PC was at 100% CPU (8 Godot test processes of six agents), so those windows do not show the
  game's own frame rate; agents are now told: windowed runs only for screenshots, one at a time. Owed to the owner: a
  quiet-PC fps run (2k / 10k / LP peak) + a windowed demo, before the wave-2 gate. Known real gap: LP peak ~22 fps vs the
  amended gate >= 30 (SWARMNAT71).
**RESUMED 2026-11-21 22:20Z (owner "Resume now"): connection 12/12 probes OK; all six agents resumed in place (SendMessage,
same contexts; CNOPS71-2 for its handoff only); guard + watcher re-armed; keep-awake on. ORCH health checks running on the
live tree: C:/CODING/orch71_check/resume71/ (hashes, test_hot_state, test_lpmode7, test_lpreserve7, test_ui_panels,
test_ui6b, test_lpmap7, test_lpperf7, test_perfsim71; ends with HEALTH_DONE).**
22:30Z: CNOPS71-2 handed off (audit OK, real 236k; handoff .plan/handoff/CNOPS71-2.json): gas71 12/0; cnmission71 installed
(test_cnops71 4/2: nest seeds queued as separate nodes; skip reason overwritten); cn_mission8 KEEP fix (player Extract was
cancelled); H8 turnaround built in cn_facility.gd but **Done-when 8 (70 s) NOT MEASURED**: queued cn_rollout refused "The
team is not in its garage." (test_facility71 1/1); hospital still a stub (its Write of the ward code was refused by the
tool check). **CNOPS71-3 launched** (Opus, cap 750k/140): 70 s gate first, then test_cnops71, hashes, hospital.
BASTION71-2: all its ids pass test_art; left red there: a_g71_conductor + a_g71_wingman (FIRES71's new ids, need seq 1613).
**HEALTH (ORCH, live tree, 22:35Z, all partial wave-2 work in): hashes == ref, test_hot_state 17/0, test_lpmode7 18/0,
test_lpmap7 18/0, test_lpreserve7 7/0, test_lpperf7 9/0, test_perfsim71 6/0, test_ui_panels 5/0, test_ui6b 5/0; 0 script
errors, 0 lp_home errors (logs C:/CODING/orch71_check/resume71/). So: lp_home fix confirmed, BASTION71's hotkey fix confirmed.**
22:45Z ORCH world.gd: + `turret_revive` -> Turrets71 (CR 1644), + `ammo_tier` -> Ammo71 with its preload (CR 1651); parse
clean, test_ammo71 6/0, test_bastion71 10/0.
**4th connection drop ~22:27Z: DAMAGE71-2, BASTION71-2, SWARMNAT71-2, CNOPS71-3 dead (NOT resumed: owner asked whether to
keep auto-resuming); ARMY71-3 still live (guard armed for it); FIRES71-2 handed off cleanly (audit OK, real 222k).** Where
each stands (resume in place with SendMessage, or successor from handoff):
- FIRES71-3 TO LAUNCH from .plan/handoff/FIRES71-2.json: test_conductor71 6/1 (home + hot-pit), then CR world71 for
  Conductor71, art for a_g71_conductor / a_g71_wingman, CRs to ARMY71 / BASTION71 / DAMAGE71, all presentation + flows.
- DAMAGE71-2 (67 calls, ~410k: near its handoff line): gore / care hooks applied to COPIES (stage2), tests/test_gore71.gd
  written; next: test_care71.gd, install stage2, run tests + hashes; then handoff.
- BASTION71-2 (51 calls, ~360k): art done (all its ids pass test_art), hotkey fixed, turret_revive done; test_walls71 6/0
  with 1 script error (crawler killed by the LP garrison); next: Turrets71.blocked guard in turrets7 / wallturret7.
- SWARMNAT71-2 (45 calls, ~360k): statics-only record cache verified clean and ON by default; swarm_draw.rs written (cargo
  check clean), rts_core 0.6.4 bump NOT built / installed (bin has 0.6.3; backup bin/rts_core.v063_keep.dll); entity_layer
  glue inserted (toggle default off); next: _sw_* helpers, parse-check, cargo build --stage.
- CNOPS71-3 (12 calls, ~95k): Done-when 8 refusal cause = the TEST submitted cn_rollout while cn_return was still pending;
  test_facility71 rerun was in flight (.plan/cnops71/t2_test_facility71.log): read its `RESULT cycle` vs 70 s first.
- ARMY71-3 HANDED OFF 22:44Z (audit OK, real 248k; .plan/handoff/ARMY71-3.json): D4 hooks live (+ DAMAGE71 CR 956), B5
  ammo tiers complete (test_ammo71 7/0), G1 NVG / thermal, G2 flame tank + art, I2 wall melee (test_army71 7/0). Its hashes /
  hot_state / perfsim were NOT re-run after the later combat.gd / accuracy8.gd / senses7.gd edits: ORCH is running them
  (C:/CODING/orch71_check/army71/, ends ARMY_CHECK_DONE). ARMY71-4 TO LAUNCH: B3 crew71, rest of D4, ammo_panel, flows.
  RESULT 23:00Z, ALL GREEN, 0 script errors: hashes == ref, test_hot_state 17/0, test_perfsim71 6/0, test_lpmode7 18/0,
  test_lpreserve7 7/0, test_army71 7/0, test_ammo71 7/0, test_mil 13/0, test_squad61 14/0, test_accuracy8 20/0.
- No agent live after 22:44Z. ORCH queued a quiet-PC fps run after the checks: `.plan/perfdraw71/base.sh q1121 g7 g71`
  (2k, 10k, lpz, lppan, lppeak) -> .plan/perfdraw71/q1121.out (the owner's lag question; first numbers with wave-2 code in).
**23:15Z (ORCH): owner "yes auto resume and continue seamlessly" (DECISIONS.md; memory auto-resume-after-drops): after
every drop resume each dead agent at once, no asking. LIVE NOW (6): DAMAGE71-2, BASTION71-2, SWARMNAT71-2, CNOPS71-3
(resumed in place), FIRES71-3, ARMY71-4 (new, Opus, caps 750k/140). Agent ids for SendMessage resumes:
.plan/orch71/live_agents.txt. Guard + watcher under Monitor (30 min each: re-arm), keep-awake on.**
- **LIVE TREE VIEW BROKEN since ~22:24Z: presentation/view/entity_layer.gd does not compile** (SWARMNAT71-2 cut mid-edit:
  line 1144 calls _sw_begin / ids_of, helpers never appended). Headless tests are unaffected (all green 23:00Z), every
  windowed run fails. SWARMNAT71-2 resumed with this as its first job; it posts `fact swarmnat71.view_ok`. Until then no
  windowed run / fps number of g71 is valid. New rule appended to G71-W2_GEN2.md (multi-part edits via a staged copy;
  windowed smoke run after presentation edits).
  **FIXED 23:14Z** (fact swarmnat71.view_ok seq 1730: helpers appended, windowed 90 s smoke 0 script errors; ORCH
  re-checked the parse: 0 errors). The g71 fps re-run still needs a quiet PC (six agents testing now).
  23:20Z: DAMAGE71-2 and BASTION71-2 told to hand off (budget line); caps registered for DAMAGE71-3 / BASTION71-3; launch
  each from its handoff file as soon as it is posted. SWARMNAT71-2 also plans its handoff after `cargo build --stage`.
**23:30Z, all gen changes done (audits OK: DAMAGE71-2 244k, SWARMNAT71-2 283k; BASTION71-2 usage not yet received).
LIVE (6): CNOPS71-3, FIRES71-3, ARMY71-4, BASTION71-3, DAMAGE71-3, SWARMNAT71-3 (ids: .plan/orch71/live_agents.txt).**
- **Done-when 8 (70 s CN airlock cycle): MET in the headless test, 41.5 s vs 70 s (was 102.1 s), one seed (LP seed 77);
  riders healed 0.40 -> 1.00, APCs rearmed, no garage stop** (fact cnops71.dw8 seq 1732; test_facility71 2/0, 0 script
  errors; .plan/cnops71/t3_test_facility71_raw.log). Still to do for the gate: more seeds + the packaged-build flow.
  CNOPS71-3 is writing its handoff (hospital71 5/0; test_cnops71 run 4 + hashes + hot_state in flight); cap registered for
  CNOPS71-4.
- **2026-11-22 01:45Z (ORCH): 5th connection drop at ~23:45Z; ORCH's own resume calls were refused once by the tool
  safety check (no verdict), owner said "Try again". Connection 6/6; world.gd / match_view.gd / entity_layer.gd / combat.gd
  parse clean. LIVE (6): FIRES71-4, BASTION71-3, DAMAGE71-3, SWARMNAT71-3 (resumed in place), CNOPS71-4, ARMY71-5 (new,
  Opus, caps 750k/140). Ids: .plan/orch71/live_agents.txt. Guard + watcher re-armed; keep-awake on.**
  - CNOPS71-3 handed off cleanly (audit OK, real 213k): DW8 41.5 s (one seed), test_cnops71 6/0, hospital ward machine
    (test_hospital71 5/0), hashes == ref, hot_state 17/0. ORCH rerun WITH CnMission71 registered: test_cnops71 6/0 but
    **6 script errors** ('tid' / 'why' / 'roe' key access, cnmission71.gd _sig:449) = CNOPS71-4's first job; test_cnmission8 7/0.
  - ARMY71-4 handoff (.plan/handoff/ARMY71-4.json; audit UNVERIFIED: died on the drop after posting it): crew71 built
    (test_crew71 7/0), crew art, lp_base_army71.json, radio_feed, ammo_panel; other agents' combat.gd lines (BASTION71
    1720, FIRES71 1827 items 1/2/4) installed parse-clean but NOT verified (revert copy .plan/army71/stage/combat.gd.pre_cr)
    = ARMY71-5's first job.
  - **View attach point (ORCH, 23:40Z):** new presentation/view/g71_attach.gd (LAYERS list, load() so a broken layer is
    skipped) + 4 edits in match_view.gd (backup .plan/orch71/wire_orig/match_view.gd.pre_g71attach); in: gore71_layer
    (under units), triage_tags (over units). 60 s windowed smoke: 0 SCRIPT ERROR. Agents request entries with
    `need change_request.match_view71`.
  - PROVISIONAL (ORCH, DECISIONS.md): fire-support radial on the backquote key held, not F (F = Formation).
- **02:58Z (ORCH; later sub-bullets carry their own times): BASTION71-4 handed off (audit OK 215k / 54 calls) -> BASTION71-5 launched. LIVE (6): BASTION71-5,
  SWARMNAT71-5, ARMY71-6 (handoff file written, cap ARMY71-7 registered), CNOPS71-5 (cap CNOPS71-6 registered),
  DAMAGE71-5, FIRES71-6.**
  - **LP-base wall anchors (ORCH, lp_setup.gd `_g71_points`):** new `near: "outer_wall"` / `"core_wall"` = the map wall
    stations of that ring (`L0.posts[<ring>]`, offset between the posts the G7 army took; falls back to the ring
    perimeter). Reason (ARMY71-6 seq 2414): crews placed on `outer_ring` stand 3 tiles inside the wall on the ground and
    drew 0 shots in 600 ticks at machines outside it. lp_base_army71.json now puts MG / AT / AM crews + grenadiers on
    `outer_wall`, flame tank `core_ring`, counts unchanged. **NOT yet proven or re-tested** (ARMY71-7's first job: the
    outside-the-wall diag, the 4 LP tests, test_crew71 / test_army71, re-post `fact lp_base71.added`).
  - ARMY71-6 also: SquadAI no longer kites emplaced MG / AM crews in LP (they walked off their post and fired once; after:
    9 bursts); signals71_layer provider-owner fix; flow army71 setup reworked (checks unchanged). Batch (hashes,
    hot_state, perfsim71, army71, crew71) was running at handoff.
  - BASTION71-4: 8 generators out of lp_base_bastion71.json (ORCH hook powers the base), 4 LP tests green; turret look
    layer built + attached (not yet seen in game); towers covered by disable; idle engineers / maint drones are called to
    disabled defences but in a real wave only 1 of 20 disabled was revived (uptime 0.903 on vs 0.888 off) -> BASTION71-5
    finds why, then flows + shots. test_bastion71 13/0 last run; tower case went red once (flake check owed).
  - CNOPS71-5: `VehDrive7._clear_hulls` -> test_path7 6/0 with all base files (one run); acceptance chain6 running.
  - FIRES71-6: test_fo_call setup hardened (11/0); CR to ARMY71 for Combat._pick (next enemy inside the painted sector +
    keep-branch allow check) = what turns `test_pick_next_in_sector` green.
  - **test_path7 fixed in the sim (CNOPS71-5, fact path7.fix71 seq 2446):** `VehDrive7._clear_hulls` moves an own foot
    unit off the hull of a moving facility APC; 6/0 with all base files and with each single file and `G71_LP_BASE=0`
    (.plan/cnops71/g6_path7_*.log). Regression chain6 (apcmov7, facexit8, facreturn8, cnfac7, cnsim7, sent7, hot_state,
    hashes) not yet reported.
  - **lp_base_fires.json (FIRES71-6 seq 2455): conductor 1 + wingmen 4 approved PROVISIONAL** (lpmode7 18/0, lpmap7
    18/0, lpreserve7 7/0, lpperf7 9/0, conductor71 7/0, fires71 11/0, path7 6/0). Grenadiers will be excluded from fire
    missions (range 7, counted as mortars by mistake).
  - **OWNER QUESTION OPEN (seq 2456, asked 03:05Z): FPF reach.** Measured on the real LP start: strips are 61-tile lines
    40.5 tiles from the base centre; 8 of 25 indirect guns reach a strip centre (east 5, south 1, west 1, north 1); the 2
    SP howitzers reach none. Options: A fire-support guns placed near each face in the base file (no rule change);
    B an FPF-only range bonus (~+12 tiles); C strips closer to the wall (30 m out). Nothing changed pending the answer;
    FIRES71-6 stages option A only.
  - **03:03Z: ARMY71-6 handed off (audit OK 209k / 90 calls) -> ARMY71-7; CNOPS71-5 handed off (audit OK 225k / 73
    calls) -> CNOPS71-6. LIVE (6): BASTION71-5, FIRES71-6, SWARMNAT71-5, ARMY71-7, CNOPS71-6, DAMAGE71-5.**
    ARMY71-6's last batch was killed by a timeout: only the hashes finished (== ref); test_hot_state, test_perfsim71,
    test_army71, test_crew71 are UNVERIFIED after the squad_ai kite guard (ARMY71-7 step 1). CNOPS71-5's chain6 was still
    running at handoff (facreturn8 2/0 so far; cnfac7, cnsim7, sent7, hot_state, hashes owed: CNOPS71-6 step 1).
    hospital71.gd live (roof pad, LP-start registration, inert patients, abstract hosp_medevac); its 2 new tests were
    red 5/2 before a wait helper, not re-run.
  - **03:06Z: DAMAGE71-5 handed off (181k / 81 calls) -> DAMAGE71-6.** Triage layer provider bug fixed (flow gore71
    14/0); care71 hospital routing installed in medical.gd (tests green, hashes == ref, hot_state 17/0). **Open:
    Care71 costs 1.56 ms/tick at LP peak (64 casualties; busy PC, rough)** -> DAMAGE71-6 step 1 (spread the medic scan
    over ticks); only red triage tags appear (2 of 16-17 casualties tagged) -> step 2; 60-min body run needs a quiet PC
    (agent posts the command as `fact damage71.quiet_cmd`).
  - **03:08Z: FIRES71-6 handed off (audit OK 216k / 89 calls) -> FIRES71-7. LIVE (6): BASTION71-5, FIRES71-7,
    SWARMNAT71-5, ARMY71-7, CNOPS71-6, DAMAGE71-6 (.plan/orch71/live_agents.txt).** Fires71.gun_kind excludes grenadiers
    (test_fires71 12/0; hashes NOT run yet: FIRES71-7 step 1). World markers drawn at z 5 over the night tint (smoke
    clean, not yet seen in an LP shot). test_killzone71 8/1 = the known red until ARMY71-7 installs
    change_request.combat71 (seq 2426). FIRES71-7 stages FPF option A only (owner question open). ARMY71-7 is probing
    whether the outer_wall stations give a line of fire (may post need change_request.lp_setup71).
  - **03:15Z, two LP-base placement defects found by the new agents (both OPEN):**
    (1) ARMY71-7 seq 2516: the `outer_wall` stations are on the ground 1-2 tiles INSIDE the wall; by owner rule
    13.9c-35 nobody fires through a wall from inside, the outer ring has no wall-walk, so all 10 crews were blocked
    (0 shots in 600 ticks). ORCH fix in lp_setup.gd (parse-clean, NOT yet tested): a unit entry may carry
    `"port": true`; `_g71_port` fits a Walls71 firing port on the nearest own wall segment within 3 tiles, which
    WallFire7 already honours. ARMY71-7 proves it + reruns the LP tests. Rejected: crews outside the wall.
    (2) CNOPS71-6 seq 2524: with late placement lp_base_cnops.json places NOTHING: site A (centre + (-6,-20) / (0,-20))
    is blocked by obstacles + non-buildable rows; the earlier early placement had landed inside the facility rect. No
    free 6x6 inside the rings. So the earlier \"test_path7 6/0 with all base files\" ran without the hospital. CNOPS71-6
    surveys what blocks site A (fact cnops71.site_a); then ORCH adds a clear-obstacles option, or the hospital replaces
    an existing base medical building, or (owner call) two 4x4 blocks. The LP-base-hospital test stays red until then.
  - **OWNER ANSWER (FPF reach): option A, "Guns near each face".** Directive to FIRES71-7: >= 3 indirect guns in reach
    of every face strip, fewest added units, guns inside the wall; stage -> measure -> install lp_base_fires.json ->
    LP tests -> fact lp_base71.added. No range bonus, no strip move. Exact added counts go back to the owner.
  - **03:15Z: SWARMNAT71-5 DONE (audit OK 213k / 70 calls); no successor until the timing is in.** rts_core 0.6.5 live
    (backups bin/rts_core.v064_keep.dll, v063_keep.dll): Machines + anim61 infantry drawn by the native kernel; verify
    0 real diffs (lp / lpw / lppan / 2k); LP peak 244 of ~592 drawn units native (was 56), kernel calls/frame 696 ->
    343; hashes == ref, hot_state 17/0, perfsim71 6/0, swarmnat71 1/0, perfdraw71 7/0. Toggle SWARMNAT71 still default
    OFF. Not native: FLAG_S7 soldiers (~218/frame at LP, every soldier in 2k); MOTION_CAP 700 switches motion layer +
    kernel off above ~700 drawn units (lpw ~863, pan peaks ~807). Next scope (S7 port, MOTION_CAP) is decided by timing.
  - **03:17Z ORCH QUIET WINDOW (directive seq 2588, flag .plan/orch71/QUIET):** all 5 agents finish their current run,
    then wait in .plan/orch71/quietwait.sh; .plan/orch71/quietrun.sh waits for a quiet PC, runs base.sh kernel off
    (q1122off) and on (q1122on) for 2k / 10k / lpz / lppan / lppeak, removes the flag at exit. Results:
    .plan/perfdraw71/q1122off.out, q1122on.out; log .plan/orch71/quietrun.log. If ORCH dies mid-window: delete the
    QUIET flag so the agents resume.
  - **03:38Z FPS OF THE CURRENT BUILD (ORCH, agents paused, godot=0, background CPU 12-45%; the strict quiet.sh gate
    never passed in 13 min so it was dropped; G7 ref q1121 ran at 8-43%). fact swarmnat71.fps; logs
    .plan/perfdraw71/q1122off.out / q1122on.out, 0 script errors in all 10 runs.**

    | case | p10 kernel off | p10 kernel on | G7 ref p10 | gate |
    |---|---|---|---|---|
    | 2k | 35.2 (avg 77.4) | 35.0 (avg 56.8) | 62.7 | 60 **FAIL** |
    | 10k | 192.2 | 200.8 | 228.0 | 30 pass |
    | LP zoomed out | 84.0 | 85.6 | 62.8 | 60 pass |
    | LP pan | 62.8 | 65.4 | 39.9 | 60 pass |
    | LP peak | 23.9 | 23.6 | 24.5 | 30 and 2x G7 (49) **FAIL** |

    Reading: the native swarm kernel changes nothing measurable (on == off within noise). 2k p10 is far under G7 on
    the same PC = a regression to find (wave 1 or wave 2: no valid wave-1 2k number exists, the 11-21 g71 run was
    invalid). LP peak is at G7's level. SWARMNAT71-6 is launched as a perf DIAGNOSIS agent (2k regression first, then
    what bounds LP peak), not for the S7 soldier port. Agents released (directive quiet_window off).
  - 03:22Z: `hosp_medevac` registered in world.gd COMMANDS (CNOPS71-6 CR seq 2622; check-only clean; backup
    .plan/orch71/wire_orig/world.gd.pre_medevac). test_path7 fix regression chain6 all green (apcmov7 16/0, facexit8
    4/0, facreturn8 2/0, cnfac7 36/0, cnsim7 27/0, sent7 13/0, hot_state 17/0, 0 script errors; hashes == ref).
    BASTION71-5 CR seq 2613 (Machines do not auto-target a disabled turret, LP only) approved PROVISIONAL, relayed to
    ARMY71-7 with FIRES71's CR 2426 for one staged combat.gd pass.
  - **03:50Z: ARMY71-7 handed off (audit OK 205k / 85 calls) -> ARMY71-8; SWARMNAT71-6 launched as perf diagnosis.
    LIVE (6): BASTION71-5, FIRES71-7, CNOPS71-6, DAMAGE71-6, ARMY71-8, SWARMNAT71-6.**
    Firing ports: 9 of 10 crews proven not blocked at 4 / 8 / 14 tiles outside (a rifleman 6 tiles inside stays
    blocked; MG fires 20 ticks into an attack-move run, 62 bursts). The 10th (mg at (53,104), port 3.0 > 2.5) fixed by
    ORCH: `LpSetup._g71_port_cell` moves a ported post one cell toward its wall when the wall is > 2 tiles away
    (parse-clean, NOT yet re-probed: ARMY71-8 step 3; backup .plan/orch71/wire_orig/lp_setup.gd.pre_portstep).
    combat.gd: FIRES71 CR 2426 (next enemy inside the painted sector) + BASTION71 CR 2613 (disabled turret not an
    auto target, LP only) INSTALLED from a staged copy (orig .plan/army71/stage/combat.gd.orig): test_killzone71 9/0,
    test_fires71 12/0, test_crew71 7/0, test_bastion71 13/0, test_turret7 18/0, test_path7 6/0; test_army71 10/1 (the
    new test's own setup check); hashes / hot_state / perfsim71 after the install were still running (ARMY71-8 step 1).
    FPF option A staged (fact fires71.fpf_option_a seq 2683): +5 MLRS, the 2 base MLRS re-anchored; per-face guns in
    reach 5/1/1/1 -> 4/3/3/3; FIRES71-7 installs + tests it.
  - **03:56Z: DAMAGE71-6 handed off (audit OK 200k / 105 calls) -> DAMAGE71-7 (first agent on the larger cap 1,000k /
    190, DECISIONS.md). LIVE (6): BASTION71-5, FIRES71-7, CNOPS71-6, ARMY71-8, SWARMNAT71-6, DAMAGE71-7.**
    care71.gd final version is live but UNVERIFIED (hashes / hot_state / perfsim71 / cost not run on it): per-side
    medic list instead of the combat grid (also fixes medics not found), new state `st.trk` (patched-up soldiers turn
    green), morphine keeps a black tag; test_care71 5/0. Casings decal staged, not installed.
  - **OPEN RED (gate): tests/test_lpreserve7.gd `test_save_load_mid_release` 6/1 on the live tree** (hash mismatch after
    load; green at 03:00Z). Candidates: care71 `st.trk`, Walls71 port fits from LpSetup._g71_port, the combat.gd CR
    install, base file changes. CNOPS71-6 bisects (fact lpreserve7.red); DAMAGE71-7 checks care71 save / load.
  - **Hospital site (ORCH, PROVISIONAL, to report to the owner):** site A cannot take 12x6 (the gate approach road x
    79-81 and the E-W road y 64-65 cross it; fact cnops71.site_a seq 2539). Decision: two 4x4 blocks astride the
    gate road at (74,60) and (82,60) in the off-road rows y 60-63; defs 6 -> 4. Not built yet (CNOPS71-6 / -7).
  - **04:00Z: BASTION71-5 handed off (audit OK 217k / 92 calls) -> BASTION71-6 (cap 1,000k / 190). LIVE (6):
    FIRES71-7, CNOPS71-6, ARMY71-8, SWARMNAT71-6, DAMAGE71-7, BASTION71-6.**
    BASTION71-5: tower test was a real setup problem (turret slew time), fixed in the test setup (assertion
    unchanged), 13/0; real bug fixed: an engineer could not take over a drone revive; Walls71.port_exempt answers
    from a per-tick cell cache (equivalence test); hashes == ref + hot_state 17/0 after those.
  - **OPEN RED (gate): tests/test_walls71.gd 7/2 on the live tree.** `test_unused_is_stateless`: a NON-LP world has
    walls71 / turrets71 / sensors71 state after 20 ticks = some wave-2 code creates state off Last Protocol (not the
    port cache: bisected). Plus the gate-guns case. BASTION71-6 step 1 (also relevant to the 2k fps regression).
  - **04:05Z: FIRES71-7 handed off (audit OK 214k / 79 calls); FIRES71-8 (cap registered 1,000k / 190) launches when
    -7 has closed out.** gun_kind change: hashes == ref, hot_state 17/0, perfsim71 6/0, fires71 12/0.
    **FPF option A is STAGED, NOT LIVE** (.plan/fires71/stage/lp_base_fires.A.json: 2 base MLRS re-anchored + 5 MLRS;
    per-face guns in reach 5/1/1/1 -> 4/3/3/3). Live install turned test_lpreserve7 `test_save_load_mid_release` RED
    twice (6/1), restored both times (live file == pre-A backup). This explains the lpreserve7 red seen at 03:44Z.
  - **OPEN DEFECT (gate, latent, exposed by option A; seq 2789): save / load target-pick divergence.** One tick after a
    load, a_laser_tank 564 (attack_move, north of the base) takes a target (Machine rifleman 1042, 3.3 tiles) in the
    loaded copy that the original world does not take: an input of the target choice is not in to_dict. Fires71 caches
    ruled out (removed, same failing hash). Repro without touching the live tree: .plan/fires71/probe_div.gd. Owner:
    ARMY71-8 (combat.gd), posts fact saveload.pick; then FIRES71-8 installs option A. Never edit test_lpreserve7.
  - **04:10Z: CNOPS71-6 handed off (audit OK 219k / 88 calls) -> CNOPS71-7; FIRES71-8 launched (both cap 1,000k /
    190). LIVE (6): ARMY71-8, SWARMNAT71-6, DAMAGE71-7, BASTION71-6, CNOPS71-7, FIRES71-8.**
  - **CORRECTION to the 03:38Z fps reading (fact perf71.2k_regress seq 2833, SWARMNAT71-6): there is NO 2k regression.**
    4 alternating triples G7 / wave 1 (82a887a worktree /c/CODING/sw6_w1) / live in one session (busy PC, 4-8 other
    Godot, load 5-48%): p10 medians G7 46.2, wave 1 51.6, live 47.6; live / G7 pair ratio median 1.11 (1.01-1.24).
    View 9.7-10.5 ms/frame and sim worker ~62-65 ms/step in all three trees. The 35.2 vs 62.7 gap compared two
    different sessions (q1122 vs q1121). The 2k gate (p10 >= 60) is still UNPROVEN either way: it needs a quiet PC with
    G7 alternating in the same session. LP peak (23.9 vs G7 24.5, gate 30 / 49) stands: SWARMNAT71-6 step 2.
  - test_lpreserve7 is 7/0 on the live tree (CNOPS71-6 rerun; its 6/1 ran while FPF option A was briefly live).
    Hospital card wired by ORCH: g71_attach.gd HUD list + `G71Attach.attach_hud(self)` in match_view.gd (parse-clean,
    windowed smoke owed by CNOPS71-7; backups .plan/orch71/wire_orig/*.pre_hud71). test_hospital71 9/1 (only the
    LP-base-site test red until the 4x4 site is built: CNOPS71-7 step 1).
  - **04:25Z: combat.gd CR install VERIFIED (ARMY71-8 fact cr_installed seq 2869):** hashes == ref, hot_state 17/0,
    perfsim71 6/0, killzone71 9/0, fires71 12/0, army71 11/0, crew71 7/0, bastion71 13/0, turret7 18/0, path7 6/0,
    lpmode7 18/0, lpmap7 18/0, lpreserve7 7/0, lpperf7 9/0.
  - **Port crew 10 of 10 (ORCH, lp_setup.gd, parse-clean):** the mg post at (53,104) was moved but BASTION71's 2x2 rail
    turret was then placed on it and pushed the crew back. Now a ported post is reserved in the occupancy map (+ a
    fallback cell search). ORCH probe .plan/orch71/port_probe2.gd: all 8 ported crews port_exempt, distances 1.0-2.0,
    0 stacked. LP start changed by one crew cell + one turret cell: ARMY71-8 / BASTION71-6 rerun the LP tests.
  - FIRES71-7 closed (final audit 223k). Its last batch: hashes == ref with the Fires71 cache removal, Fires71 /
    KillZone71 / Conductor71 0.004-0.005 ms/tick on 2k; FPF burst inconclusive (+15.6 / -4.9 ms); test_hot_state +
    test_fires71 after the cache change UNVERIFIED (FIRES71-8 overwrote the running batch11.sh; reruns as batch12).
    FIRES71-8 `need orch.refused` (seq 2865: an overwrite of that script, refused by the classifier): not done by
    anyone, not needed.
  - **04:30Z SAVE / LOAD TARGET-PICK DEFECT FIXED (ARMY71-8, fact saveload.pick seq 2965).** Cause: the unsaved combat
    cache `w.cache.cmb_tabs` kept a stale def index (dx 0 = the first def, engineer) for units whose team / flags row
    was filled outside the native fill (37 ids in the repro, e.g. AT gunners, an IFV, the laser tank): the native prep
    used the wrong range / scan radius for them; a loaded world rebuilt the table correctly, hence the divergence.
    Fix in sim/systems/combat.gd (`_dx_fill`; staged swap, prior copy .plan/army71/stage/combat.gd.pre_dx). Acceptance:
    FIRES71's probe with the staged option A file: no divergence in 200 ticks; test_lpreserve7 7/0; test_army71 11/0;
    test_perfsim71 6/0; hashes == ref; test_hot_state 17/0 (.plan/army71/w8_dx.txt). FIRES71-8 may now install FPF
    option A (must rerun test_lpreserve7 with it).
  - **04:32Z HOSPITAL PLACED (CNOPS71-7 fact lp_base71.added seq 2978; approved PROVISIONAL):** two 4x4 blocks at
    (74,60) and (82,60), same on seeds 77 / 5 / 1234; gate road and E-W road passable for foot + vehicles; the 7 late
    generators are off the roads. test_hospital71 10/0 (the LP-base test is green), art 7/0, icons7 1/0, lpmode7 18/0,
    lpmap7 18/0, lpreserve7 7/0, lpperf7 9/0, path7 6/0 (first run with the hospital really placed), apcmov7 16/0,
    sent7 13/0, 0 script errors (.plan/cnops71/a7_*.log). Timing slot: directive orch.timing_lock gives SWARMNAT71-6
    the next slot (it had waited 20 min).
  - **04:38Z WALL CREWS PROVEN (ARMY71-8 fact lp_base71.added seq 2998; approved PROVISIONAL):** all 8 ported crews
    not blocked at 4 / 8 / 14 tiles outside, a rifleman 6 tiles inside still blocked, 0 stacked, MG fires from tick 20
    in the attack-move run; army71 11/0, crew71 7/0, bastion71 13/0, path7 6/0, lpmode7 18/0, lpmap7 18/0, lpreserve7
    7/0, lpperf7 9/0 on the final placement. Hospital shots (card + site) forwarded to the owner (CNOPS71-7 seq 2988:
    flow hospital71 11/0, windowed smoke clean).
  - **04:46Z: ARMY71-8 handed off (audit OK 224k / 79 calls) -> ARMY71-9 (cap 1,000k / 190). LIVE (6): SWARMNAT71-6,
    DAMAGE71-7, BASTION71-6, CNOPS71-7, FIRES71-8, ARMY71-9.** Flow army71 14/0, 0 script errors; shots forwarded to
    the owner (MG crew firing through its port; BASTION71-6 rail tracking laser + wall tiers). Weak: hand-signal /
    radio-feed shot (unreadable at that zoom): ARMY71-9 step 1. ARMY71-9's main job: the D4 writers (cover hug / peek
    / bound, door stacking, formation catch-up, radio sources).
  - **04:55Z LP PEAK, PARTIAL DIAGNOSIS (SWARMNAT71-6 fact perf71.lp_peak seq 3072, from the q1122 logs; its own --prof
    batch has not run: timing lock):** frame ~40 ms = view ~19 ms (entity layer ~15) + ~21 ms other; the sim worker
    takes ~110-130 ms per step (combat.gd ~39%) so the LP-peak game runs at ~5 of 20 ticks/s (about quarter speed);
    EVERY sim hand-over is a FORCED JOIN (5 per s): something on the main thread reads match_view.world mid-step and
    blocks until the step ends. That is why the native kernel buys 0 fps. Ranked, bounded: (1) find + remove that
    main-thread world read; (2) LP sim step cost; (3) soldier kernel port, worth up to ~+60% only after (1). Ceiling
    while forced joins remain: ~25-26 fps. No best-reachable number yet. test_walls71 8/0 (BASTION71-6: the stateless
    check used an LP world by default; a skirmish world creates no wave-2 state; fact bastion71.stateless seq 2844).
    gas71_layer.gd added to G71Attach.LAYERS (CR seq 3041). Timing lock: BASTION71-6 jumped the slot (batch6d opened
    04:34Z inside DAMAGE71-7's batch): ms numbers of that window are noisy; told to yield to SWARMNAT71-6.
  - **05:00Z LP PEAK, CORRECTION (SWARMNAT71-6 fact perf71.lp_peak v2 seq 3126; the 04:55Z forced-join reading is
    WRONG):** the forced_joins counter is cumulative (5 = startup joins, not 5 per s); a backtrace run found 6 forced
    joins in a whole 30 s run (harness setup, ops_panel.gd:98 x3, lp_hud.gd:89 x1). The main thread does NOT wait on
    the sim at LP peak; the slow sim (~110-130 ms per step, ~5 of 20 ticks/s) sets GAME SPEED, not fps. Main-thread
    frame 53-71 ms in that (busy-PC, pre-04:27Z) run: entity layer 24-27 ms (units ~14, other entities ~9-10),
    terrain ~4, other draws ~6, and an UNMEASURED remainder of 20-35 ms (render-server CPU / HUD / GPU wait). The
    kernel covers part of the ~14 ms unit share only, so its gain is inside the noise. Bounded outlook: non-unit
    entity cost + the remaining GDScript unit draw give ~30-35 fps; 49 (2x G7) needs the unmeasured remainder to be
    small or fixable. Not proven: its live off / on --prof pairs are running. Hand-signal close shot forwarded to the
    owner (ARMY71-9, flow 15/0).
  - **05:20Z STATE FOR A RESUME (read this first after a /clear):** LIVE (6), ids in .plan/orch71/live_agents.txt:
    BASTION71-7, FIRES71-8, ARMY71-9, CNOPS71-8, DAMAGE71-7, SWARMNAT71-7 (all cap 1,000k / 190; hand-off line 700k /
    133 calls). 05:08Z connection drop killed DAMAGE71-7, ARMY71-9, SWARMNAT71-7, BASTION71-7: resumed in place at
    05:15Z (owner rule: auto-resume). Audits OK: BASTION71-6 268k, SWARMNAT71-6 197k, CNOPS71-7 282k.
    Monitors to re-arm every 30 min: guard.mjs (filter the live generations) + the board watcher.
    **No known red on the live tree except** tests/test_bastion71.gd `test_turret_obeys_painted_sector` (waits for
    FIRES71-8 to widen KillZone71._wrange to turret weapons; routed). **Open, in order:** (1) FIRES71-8 installs FPF
    option A (staged .plan/fires71/stage/lp_base_fires.A.json; lpreserve7 must be 7/0) + the _wrange CR; (2)
    SWARMNAT71-7 final LP-peak split + best-reachable p10 -> then the owner's LP-peak gate question (p10 ~24 vs 30 /
    49); (3) CNOPS71-8: fleet batch result + `fact lp_base71.added` (+2 medevac helis, +2 drone ambulances: NOT yet
    approved), gas shot, mission card; (4) ARMY71-9: D4 writers (cover / stacking / catch-up / radio sources); (5)
    BASTION71-7: revive moves, FPF aim for wall guns, engineer / dozer; (6) DAMAGE71-7: care71 verification + cost,
    tag-mix shot, casings, fx; (7) quiet-PC runs owed: 2k gate with G7 alternating, DAMAGE71's 60-min body run;
    (8) wave-2 gate: refresh C:/CODING/g71_clean, --import, `bash C:/CODING/orch71_check/suite71.sh 6`, all green + 0
    script errors; (9) ask the owner before the wave-2 commit. Owner items to raise: hospital 4x4 x2 (told), +5 MLRS
    (owner chose A), fleet +4 units, provisional counts, QUOTELEFT radial key, minimap 198 px, hand-signal plate
    small / radio line small, /c/CODING/sw6_w1 worktree to remove (SWARMNAT71-7).
  - **05:24Z: DAMAGE71-7 handed off (audit OK 247k / 112 calls) -> DAMAGE71-8 (LIVE list in live_agents.txt).**
    care71 VERIFIED: 0.344 ms/tick at LP peak (was 1.562), hashes == ref, hot_state 17/0, perfsim71 6/0, save / load
    test green; casings + part / ricochet / silver fx installed (smoke clean); flows care71 + damage71 6/6; shots
    forwarded (triage cards yellow / red / black, crawler losing a part). **NEW BLOCKER (Done-when 3 + 9): 3000
    settled bodies -> LP p10 7.9 fps vs ~30 with none; hiding gore71_layer.gd restores 30.4 = the body layer redraws
    every body every frame.** DAMAGE71-8 step 1: chunk-baked textures. gore71 flow tag-mix step still unmet (never 3
    kinds at one moment in a real fight; check NOT to be relaxed). Ricochets never fire in a real fight (rule may be
    too strict: numbers to ORCH as need owner.ricochet). CNOPS71-8 `need orch.refused` seq 3201 (Stop-Process on the
    predecessor's test chain refused): not done by anyone; chain left to end by itself.
  - **05:31Z FPF OPTION A IS LIVE (FIRES71-8 fact lp_base71.added seq 3279; approved PROVISIONAL):** 7 base MLRS (2
    re-anchored + 5 new: 3 W, 1 S, 1 N), per-face guns in reach E / S / W / N 4 / 3 / 3 / 3 (was 5 / 1 / 1 / 1)
    measured on the live placement; lpreserve7 7/0 (the save / load case is green WITH option A), lpmode7 18/0, lpmap7
    18/0, lpperf7 9/0, conductor71 7/0, fires71 12/0, killzone71 9/0, path7 6/0 (.plan/fires71/w13_g8_tests.log). FPF
    burst cost: below this PC's run-to-run noise, no number claimable. Shots forwarded to the owner: medevac helis on
    the hospital pad, gas cloud + mask glyphs (CNOPS71-8).
  - **05:43Z:** hospital fleet verified + approved PROVISIONAL (seq 3339 / 3341: +2 medevac helis, +2 drone
    ambulances; path7 6/0, hospital71 11/0, lpmode7 18/0, lpmap7 18/0, lpreserve7 7/0, lpperf7 9/0, apcmov7 16/0, sent7
    13/0, hot_state 17/0, art 7/0, icons7 1/0, hashes == ref). World.gd COMMANDS + `berm_build`, `doze_clear` ->
    Walls71 (BASTION71-7 CR seq 3323; check-only clean; test_walls71 10/0; hash check owed by the agent; no UI yet).
    DAMAGE71-8: gore71_layer.gd rebuilt as chunk-baked meshes (3000 bodies: ~7.5 fps -> p10 28.2 at zoom 1 in
    non-timing runs; before / after shot forwarded; the alternating comparison is owed); gore71 flow 15/0 with green /
    red / yellow at one moment (fight shaped, check unchanged). All LP-base files are now live and approved
    PROVISIONAL: fires (option A), army71 (ported wall crews), bastion71, damage71 (tent), cnops (hospital + fleet).
  - **06:16Z STATE (newest; supersedes the 05:20Z block where they differ):** second outage 05:45-06:08Z killed all
    6 agents; all resumed in place at 06:10Z; ORCH parse sweep of every .gd edited in the last hour: 0 bad. LIVE (6):
    BASTION71-7, CNOPS71-8, DAMAGE71-8, SWARMNAT71-7 (resumed), FIRES71-9, ARMY71-10 (new; ids in live_agents.txt).
    Audits OK: FIRES71-8 206k, ARMY71-9 247k.
    ARMY71-9 done: D4 writers in the sim, LP only (cover hug / peek / bound in `e.d71c`, hug = incoming accuracy x0.55;
    formation catch-up beyond 3 tiles; door stacking before entering an own building; radio sources already wired);
    gas-mask accuracy / sight cost (CNOPS71 CR 3042); hand signals on a z-6 plate; test_army71 15/0, flow 15/0, LP
    tests green, hashes == ref, hot_state 17/0, perfsim71 6/0. NOT visible yet: the poses (ARMY71-10 step 1).
    FIRES71-8 done: option A live; `KillZone71._wrange` reads turret weapons (INSTALLED, UNTESTED: FIRES71-9 step 1;
    BASTION71's `test_turret_obeys_painted_sector` should turn green). World.gd COMMANDS + `fac_upgrade` -> CnFacility
    (CNOPS71-8 CR seq 3459; check-only clean; backup world.gd.pre_facupg). Timing lock: SWARMNAT71-7 since 06:11Z.
  - **06:25Z:** third drop ~06:18Z killed ARMY71-10, SWARMNAT71-7, DAMAGE71-8, FIRES71-9: resumed in place 06:22Z,
    all posting again. CNOPS71-8 handed off (audit OK 272k / 116 calls) -> CNOPS71-9. LIVE (6): BASTION71-7,
    FIRES71-9, ARMY71-10, CNOPS71-9, DAMAGE71-8, SWARMNAT71-7 (live_agents.txt).
    **No known red on the live tree:** FIRES71-9 fact cr_installed seq 3507: turret sectors tested (test_killzone71
    10/0, test_bastion71 18/0 incl. test_turret_obeys_painted_sector, test_turret7 18/0, test_fires71 12/0; hashes
    pending its timing batch). CNOPS71-8 built (determinism check chainG8 still queued = UNVERIFIED): hosp_medevac
    retasks a real fleet heli; contact reaction by ROE (stealth / standard calls a fire mission / aggressive) with the
    team card line; facility upgrades (bays heal / decon x1.5 / x2.0; foundry numbers stored, not hooked); gas flow
    11/0; hospital flow 12/0; test_hospital71 12/0, test_cnops71 7/0, test_facility71 3/0, test_cnfac7 36/0.
  - **06:28Z LP-PEAK SIM PROFILE (SWARMNAT71-7 fact perf71.lp_sim seq 3511; headless, 600 ticks, busy PC, after the
    combat fix):** 106.4 ms per tick avg (p50 90.5, p95 178): combat.gd 40.6 (38%), squad_ai.gd 7.4, movement.gd 6.4,
    air.gd 6.3, **turrets71.gd 5.2 (wave 2: BASTION71-7 told to cut it, target < 1 ms)**, fog 4.3, sentinels7 3.4,
    supply 2.5, cn_facility 2.1, morale 2.0. Tick rate: headless ceiling ~9.4 of 20 ticks/s, in game ~3.8-3.9. 20
    ticks/s needs <= 50 ms per tick (about -55%). Findings only; no sim change.
  - **06:32Z LP PEAK, FINAL DIAGNOSIS (SWARMNAT71-7 fact perf71.lp_peak seq 3516; busy PC, ratios are the finding).
    OWNER QUESTION ASKED 06:32Z: which LP-peak target for this slice (30 only, or keep 2x G7 = 49).**
    Frame ~52 ms busy (quiet-PC p10 frame ~42 ms = 23.9 fps): process step ~46 ms = entity layer refresh 22-25 (units
    15-18, non-unit entities 5-7), terrain 4-5, fx ~1, draws ~3.5, unattributed 12-14 (43 presentation scripts'
    _process + ~1,700-1,850 draw calls); render server 4.5-9.4 (HUD 3-5 of it); NOT GPU-bound; the main thread does
    not wait on the sim. Kernel off / on p10 18.3 / 17.7: the kernel only runs when <= MOTION_CAP 700 units are drawn
    and LP peak draws ~1,470-2,030 items, so its gain there is 0 BY CONSTRUCTION. Ranked: (1) native path for the
    over-cap unit refresh, <= 15-18 ms, realistic 9-13 (entity_layer.gd + Rust kernel, not started); (2) non-unit
    entity refresh <= 5-7; (3) unattributed _process / draw calls <= 12-14, unproven; (4) HUD 3-5; (5) terrain 4-5.
    **Best reachable: p10 >= 30 needs -9 ms: reachable with (1) alone, range 30-38 fps with (1)+(2) on a quiet PC
    (unproven scaling). p10 >= 49 needs -21 of ~42 ms: NOT supported by any measurement this slice.** Separate
    problem: game speed at LP peak ~3.8-3.9 of 20 ticks/s in game (sim 106 ms per tick, combat 38%).
  - **OWNER DECISION ("30 fps only"): the LP-peak gate for G7.1 is p10 >= 30 fps; the 2x G7 half is dropped
    (DECISIONS.md; directive owner.lp_peak_gate).** SWARMNAT71-7 builds rank 1 (native path for the over-MOTION_CAP
    unit refresh) then rank 2 (non-unit entity refresh), kernel default stays OFF until verify is clean and pairs show
    the gain (it posts need orch.swarmnat_default). The gate proof = ORCH's quiet-PC run. Still separate and unowned:
    LP-peak game speed ~4 of 20 ticks/s (sim 106 ms per tick, combat 38%).
  - **06:35Z CORRECTION to the 06:32Z diagnosis (SWARMNAT71-7 fact perf71.lp_peak_correction seq 3531, measured):**
    the "kernel never runs at LP peak (MOTION_CAP)" reason was WRONG. In the gate's case the motion layer IS on and
    the kernel runs when enabled, but it draws 0 units; the entity layer's unit counter reads 0 drawn units per
    frame while the unit loop still costs 15-18 ms per frame. So the old rank 1 (native over-cap path) targets a
    path that does not run here. NEW rank 1: find why the unit loop spends 15-18 ms and draws 0 units (work done
    before a cull, or a draw path the counter misses) in entity_layer.gd. Under investigation. The owner's gate
    decision (30 fps only) stands; the route to it is open again.
  - **06:40Z SECOND CORRECTION (SWARMNAT71-7 seq 3546; the 06:35Z entry is WRONG too: its runs lacked --fps-log):**
    valid run with the exact gate args and SWARMNAT71=1: kernel ran 501 / 501 frames and drew ~257 of ~605 drawn
    units (same as SWARM_NATIVE71 s9); ~350 units per frame still go through GDScript (FLAG_S7 soldiers ~218). The
    over-cap path does not run at the gate case. Candidate rank 1 = native coverage of the remaining GDScript units
    (the S7 soldier port), bound not yet timed. **OPEN ANOMALY: the same harness without --fps-log shows ~40 fps with
    ~167 snapshot units and 0 units drawn; with it ~1,478 units and ~18-24 fps: which one is the real game at LP peak
    is not known.** ORCH told the agent: explain the anomaly first, then time kernel vs GDScript units, then ONE
    final fact (perf71.lp_peak_final2); no fix work before that. Treat every LP-peak cause above as unsettled.
  - **06:45Z: BASTION71-7 handed off (audit OK 278k / 131 calls) -> BASTION71-8. LIVE (6): BASTION71-8, FIRES71-9,
    ARMY71-10, CNOPS71-9, DAMAGE71-8, SWARMNAT71-7.** BASTION71-7 done (hashes == ref, hot_state 17/0, perfsim71 6/0,
    4 LP tests green after all of it): wall guns fire at the FPF strip (test red first; a wall HMG range 9 lands just
    short of a strip 10 out: PROVISIONAL); dozer berm_build / doze_clear (test_walls71 11/0); mid-wave save / load
    test of its state (green); laser CIWS range by weather (fog x0.45; test not seen red); nanite-coated walls take
    0.6x from Machines (the damage.gd hook waits on DAMAGE71, CR seq 3364); casings per rotary shot (not yet seen on
    screen); test_bastion71 18/0. Revive check on the current tree: 0 drops from move orders; 12 of 16 drops =
    turret destroyed before the engineer arrived; 4 revives. BASTION71-8 first job: Turrets71.tick 5.24 ms per tick at
    LP peak -> well under 1 ms (profile first, behaviour unchanged).
  - **06:50Z LP PEAK, FINAL STATEMENT (SWARMNAT71-7 fact perf71.lp_peak_final2 seq 3673; supersedes every LP-peak
    cause above).** MEASURED: (a) the --fps-log anomaly = without an --fps* / --autostart arg the LP intro cinematic
    plays (match paused, camera flying): the gate runs measure the real post-intro state; (b) at the gate case the
    kernel runs every frame and draws ~257 of ~605 units; **kernel ON is WORSE: p10 15.6 / 18.0 on vs 19.9 / 24.3 off
    (alternating pairs); it costs 4.5-5.2 ms to save ~1-2 ms = a net loss of 3-6 ms -> SWARMNAT71 stays OFF and the
    kernel is PARKED for this slice**; (c) frame split, kernel off: unit loop 10.5-12.2 ms (~605 units, ~18-20 us
    each), non-unit entities 4.1-5.1, terrain 3.1-3.5, HUD 3-5, render server 4.5-9.4 (not GPU-bound), unattributed
    8-14, sim wait 0. INFERRED: ranks 1 (cheaper GDScript unit loop, realistic 3-5 ms) + 2 (skip unchanged non-unit
    entities, 2-3) + 3 (HUD 3-5) give ~8-13 ms; p10 30 needs -9 ms on a quiet PC: plausible, NOT proven. ORCH order:
    build ranks 1 + 2 in entity_layer.gd / motion.gd, HUD as a change request; gate proof = ORCH quiet-PC run:
    `SWARMNAT71=0 ... perf71_draw_lp.gd -- --fps-log --fps-quit=30 --no-vsync --lpz=0.5 --peak=1000` x3, median p10.
    Timing-slot reservation (orch.timing_batch + .plan/orch71/reserve_release.sh) worked: use it again when a line is
    starved.
  - **06:52Z: SWARMNAT71-7 handed off (audit OK 246k / 120 calls; worktree /c/CODING/sw6_w1 removed) -> SWARMNAT71-8,
    which BUILDS rank 1 (GDScript unit loop) + rank 2 (non-unit entities); kernel parked (DECISIONS.md). LIVE (6):
    BASTION71-8, FIRES71-9, ARMY71-10, CNOPS71-9, DAMAGE71-8, SWARMNAT71-8 (live_agents.txt).** CNOPS71-9 shots
    posted (seq 3668 / 3669: gas cloud brighter + larger mask glyphs, before / after; mission card en route / contact
    / exfil): NOT yet looked at or forwarded by ORCH.
  - **07:15Z:** connection drops continue (about 06:55Z and 07:05Z): BASTION71-8 (twice) and DAMAGE71-8 died and were
    resumed in place; SWARMNAT71-8 silent since 06:54Z, messaged. The measured Turrets71 split (seq 3694): 5.5 ms
    per tick = rotary 2.5 (lane query 1.8) + laser aim 1.5 + maintenance scans ~0.5; bookkeeping is small. Body layer
    comparison ran (.plan/damage71/gen8/timing_g8.out, batch done 07:00Z): 3000 bodies p10 32.9 vs 3000 with the
    layer hidden 33.3 in run 2 = the baked layer costs ~nothing (DAMAGE71-8 posts the full fact). ARMY71-10 shots
    forwarded (bounding markers, wall bayonets, flame tank); its cover / NVG shots not looked at by ORCH. CNOPS71-8
    closed (final audit 273k). Stray board topic orch.timing_lock_stale closed.
  - **07:20Z DAMAGE71 LINE NEARLY CLOSED (DAMAGE71-8 final report; audit OK 264k / 104 calls; resumed for two small
    items):** body layer chunk-baked and timed (p10 0 / 3000 / 3000-hidden: r1 34.9 / 31.4 / 34.3, r2 33.9 / 32.9 /
    33.3; was 7.5-7.9 with 3000); gore71 flow 15/0 with 3 tag kinds at one moment; ricochets DO fire (1.01% of hits on
    part-layout Machines at LP peak; rule set A 50/60/75 deg would give 5.4%: owner taste, unchanged); medics recover
    bodies when no casualty is listed (LP only; test_care71 7/0); Trampled71 fx drawn (no shot yet); hashes == ref,
    hot_state 17/0. Left with DAMAGE71-8: BASTION71's nanite-coat hook in damage.gd (CR seq 3364) + a tank-crush shot.
    ORCH quiet-PC job: the 60-minute body run (`.plan/damage71/body60_fps.gd --fps-log --fps-quit=3600 --no-vsync
    --peak=1000 --bodies=0` and `--bodies=3000`). Its Done-when 3 still names 60 fps at LP peak: the owner's gate is
    now 30.
  - **07:33Z STATE (newest; read this first after a /clear):** outage 07:15-07:29Z killed BASTION71-8, DAMAGE71-8,
    FIRES71-9, SWARMNAT71-8, ARMY71-10: all resumed in place 07:31Z. CNOPS71-9 handed off -> CNOPS71-10. LIVE (6) with
    ids + current jobs in .plan/orch71/live_agents.txt.
    **KNOWN RED (gate blocker): tests/test_cards8c.gd `test_aid_options`** (CNOPS71-9 fact seq 3743: menders never take
    the c8c_med / casualty jobs; green in the wave-1 suite, so a wave-2 change broke it; CNOPS71-10 bisects, never
    edit the test).
    CNOPS71-9 done (g8 installs verified: hashes == ref, hot_state 17/0): fac_upgrade / hosp_medevac tested through
    submit; cn71 radio lines file + overwatch element + casualties back to the APC; flow cnops71 20/0; gas contrast;
    facility siege stages (alert -> lockdown -> evac) + upgrade buttons on the facility card (shots posted seq 3795,
    NOT looked at by ORCH). Its own chain_g9 determinism check was still queued at handoff = UNVERIFIED.
    Order of what is left: (1) SWARMNAT71-8 unit-loop fix -> ORCH quiet-PC gate run (LP peak p10 >= 30); (2)
    test_cards8c red; (3) BASTION71-8 turret cost; (4) FIRES71-9 hashes + shots; (5) ARMY71-10 batch + radio CR; (6)
    DAMAGE71-8 nanite hook, then that line is closed; (7) ORCH quiet-PC: 2k gate with G7 alternating, 60-min body
    run; (8) wave-2 gate suite on a refreshed frozen copy; (9) owner's yes before the commit.
  - **07:42Z ARMY71 LINE DONE (ARMY71-10 final report; audit OK 248k / 121 calls; no successor launched). LIVE (5):
    BASTION71-8, FIRES71-9, CNOPS71-10, DAMAGE71-8 (two leftovers), SWARMNAT71-8 (timing slot reserved 07:35Z).**
    Cover poses visible as markers when zoomed in >= 0.55 (hug shadow + chevron, peek lean, green bounding arrow, cyan
    overwatch arc; unit sprites unchanged); NVG / thermal glints at night; melee clash stars; flow army71 20/0 twice;
    CnRadio case in radio_feed.gd (CNOPS71 CR 3541; test red first; smoke clean). Own bug fixed: Discipline71.poses
    tested technique 3, bounding is 2 (LP-only behaviour change; LP batch green). Cost: 2k hash-identical; LP peak
    +2.42 ms per tick (3.2%; on / off are different fights); view provider 0.17 ms per snapshot. Open for ORCH: full
    suite, LP soak, fps with the pose overlay. **Finding for the owner: the view never gets darker at night (Senses7
    light changes the sim only), so NVG shows over a daylight scene; a night tint is a design call.**
  - **08:05Z DAMAGE71 LINE DONE (addendum; 121 calls). LIVE (4): BASTION71-8, FIRES71-9, CNOPS71-10, SWARMNAT71-8.**
    Nanite-coat hook installed in damage.gd apply_hit (BASTION71 CR 3364; acts only on buildings carrying `nres`):
    test_walls71 11/0, test_bastion71 18/0, test_damage71 12/0, hashes == ref, hot_state 17/0 (BASTION71-8 adds its
    hp-loss test). Tank-crush shot forwarded (effect is subtle). SWARMNAT71-8: SWN8 cuts in entity_layer.gd (unit-loop
    locals, drawn7 rows reused, static cull record), default OFF, SWN8_VERIFY 0 real diffs on lp / lpw / lppan / 2k
    (fact seq 3990); A/B timing running in a reserved slot (07:57Z); its HUD / terrain change requests (seq 3995 /
    3996) have no live owner: ORCH hands them to SWARMNAT71-8 if the A/B leaves the gate short.
  - **08:10Z test_cards8c RED FIXED IN THE SIM (CNOPS71-10 fact seq 4026; test file unmodified, checked with git
    status): no known red on the live tree again.** Cause: the MEDICS order's post found no Mender in a quiet LP
    opening (the 3 on duty hold wall / QRF jobs, 6 are barracks reserve); in wave 1 it passed only because a Machine
    scout raised the alarm by tick ~480; the combined wave-2 LP base changes the opening (no alarm). Bisect: wave-1
    tree 7/0, live red, any one of army71 / cnops / fires dropped = green. Fix in sim/systems/cards8c.gd adjust_jobs:
    while a MEDICS order holds, non-care jobs drop the mender role. test_cards8c 7/0 (also with no base files).
    Hashes after it: queued with CNOPS71-10's profile batch = UNVERIFIED. DAMAGE71-8 final audit OK 283k.
  - **08:12Z LP PEAK: THE FIRST FIX GAVE NOTHING (SWARMNAT71-8 fact perf71.lp_peak_fix seq 4033).** The exact unit-loop
    cuts + static cull record (verify 0 real diffs) measured p10 off / on 20.5 / 18.9, 22.2 / 23.1, 23.8 / 23.9; unit
    loop 10.55 -> 10.50 ms. Reverted byte-exact (entity_layer.gd == pre-change copy; staged copies kept in
    .plan/swarmnat71/g8/stage/). Why: the per-unit cost (~18 us) is flat over 9 steps (largest Motion.step 2.7 ms);
    no few-line GDScript cut removes ms. Gate gap: ~9-10 ms of a ~42 ms p10 frame. Remaining EXACT candidates: HUD
    3-5 ms (controls not identified), terrain group ~3 ms (split unmeasured): SWARMNAT71-8 is on both. What would
    close it otherwise: a native per-unit step (kernel design lost to marshal cost; parked) or a VISIBLE trade at peak
    (lower animation rate / LOD at zoom 0.5; forbidden unless the owner allows it). **OWNER QUESTION ASKED 08:12Z:
    allow a visible trade at peak as a fallback, or keep visuals and park the gate.**
  - **13:55Z: THE PC SLEPT 08:24Z -> 13:46Z (5 h 22 min; board seq 4121 -> 4122).** The keep-awake hold (session_idle)
    lapses ~5 min after ORCH's last turn; with no event for ORCH nothing kept the PC up. On wake the agents' scripts and
    sessions carried on (BASTION71-8 posted at 13:49Z). Keep-awake re-requested, monitors re-armed. Owner told: needs
    a Windows power setting or an approved keep-awake script for unattended runs.
    BASTION71-8 fact bastion71.cost (seq 4138): Turrets71 at LP peak 5.29-5.49 -> 3.08 ms per tick (1.32 when the
    shared T7 unit grid build is counted outside it); rotary lane query ~1.8 -> ~0.3, laser aim 1.55 -> 0.94; target
    "well under 1 ms" NOT reached (left: the per-tick unit grid build ~1.3 ms + real weapon work). Behaviour
    unchanged: LP-peak 600-tick hash equal before / after, hashes == ref, hot_state 17/0, perfsim71 6/0, bastion71
    18/0, walls71 11/0, turret7 18/0, 4 LP tests green. LIVE (4): BASTION71-8, FIRES71-9, CNOPS71-10 (holds the timing
    lock since 13:48Z), SWARMNAT71-8 (HUD / terrain A/B running). Owner question still open: visible trade at peak.
  - **14:00Z: BASTION71-8 handed off (audit OK 283k / 128 calls) -> BASTION71-9 (Sonnet, bounded close-out). LIVE (4):
    BASTION71-9, FIRES71-9, CNOPS71-10, SWARMNAT71-8.** Survey after all fixes: disable on = uptime 0.901, 17 died, 25
    disabled, 4 revived; off = uptime 0.900, 28 died (disabling cuts deaths 28 -> 17, uptime flat: disabled time
    replaces dead time; a design note for the owner). Its 4 new shots are weak (too far out): NOT forwarded; flow
    walls71 15/1 (`walls71_gate_guns_choke_sealed` false: BASTION71-9 fixes the setup). Turrets71 stays at 3.08 ms per
    tick (no further cut this slice).
  - **14:10Z: SWARMNAT71-8 handed off (audit OK 270k / 123 calls) -> SWARMNAT71-9. LIVE (4): BASTION71-9 (Sonnet),
    FIRES71-9, CNOPS71-10, SWARMNAT71-9.** Terrain-group split (seq 4215): world7_layer.refresh 2.4-2.75 ms (same on a
    static and a panning camera), fac_atmo7 0.6-0.7, creep 0.2-0.3, terrain 0.1-0.3. Unit-loop split: flat (~18 us per
    drawn unit over 9 steps). SWARMNAT71-9: exact skips in world7_layer.refresh and the HUD, a _process census of the
    unattributed 8-14 ms. Gate still ~9-10 ms short; owner question on a visible trade still open.
    **ORCH fix: script error at sim/render_snap.gd:352 "Invalid access to key 'care71'"** (seen once at the end of a
    pan run): the g71 provider loop re-read the static table per key and raced with a main-thread unregister at match
    end; it now reads the table once into a local (check-only clean; display-only; backup
    .plan/orch71/wire_orig/render_snap.gd.pre_provfix). Not yet re-run in a windowed quit: watch the gate suite and
    flows for that line. BASTION71-9 shots: the dozer berm forwarded; casing piles are ~4 px and not visible.
  - **14:20Z: CNOPS71-10 handed off (audit OK 261k / 121 calls) -> CNOPS71-11. LIVE (4): BASTION71-9, FIRES71-9,
    CNOPS71-11, SWARMNAT71-9.** Owner: "I'll set sleep to Never" (their Windows setting). CNOPS71-10 done: chain_g9 +
    chain_g10 verified (hashes == ref, hot_state 17/0, perfsim71 6/0, incl. the cards8c MEDICS fix); LP-peak cost of
    its systems 1.4-1.5 ms per tick (Gas71 0.9, CnFacility 0.5); nanite grenades + shield drone (test_cnops71 12/0);
    purge cannon coded but PARKED (pc_r 0: a stand-off purge during travel stalls CnMission8's deploy; its own new
    cannon test was dropped with it); cn71 radio subtitles live (flow cnops71 20/0; shot forwarded). MEDICS now pulls
    every on-duty Mender off watch while it holds (PROVISIONAL behaviour change). CNOPS71-11: cannon stall, Vanta 2,
    gear availability, LP soak, closing batch + done_when.
  - **14:35Z BASTION71 LINE DONE (BASTION71-9 final report; audit OK 187k / 75 calls; Sonnet). LIVE (3): FIRES71-9,
    CNOPS71-11, SWARMNAT71-9.** Flows walls71 16/0 and bastion71 15/0 (choke step fixed in the flow setup: 4 crawlers
    at the choke wall; check unchanged); `test_nanite_coat_hp_loss` red first then green (test_walls71 12/0); 2k
    profile: Turrets71 0.009, Sensors71 0.007, Walls71 0.003 ms per tick; hashes == ref; hot_state 17/0; minimap sensor
    contact marker 6 -> 10 px (presentation/hud/minimap.gd, `_s71` block only). Open by design: Turrets71 3.08 ms per
    tick at LP peak; casing piles not visible (1 decal ~4 px: a look change in fx61_engine.gd, owner taste); the wall
    gun's muzzle fire at the FPF strip is not obvious. Its teardown SCRIPT ERROR at render_snap.gd:352 (key
    'bastion71') is in a log written 14:00Z = BEFORE the ORCH fix of 14:07Z (same race); not seen since, still to be
    confirmed by the gate suite + flows.
  - **14:50Z LP PEAK, FIRST MEASURED GAIN (SWARMNAT71-9 fact perf71.lp_peak_fix2 seq 4374, part 1 of 2; LIVE):**
    fissure_layer.gd refresh() returns early when the fissure snapshot is the same object as last frame (it rebuilt a
    loop over every creep cell EVERY frame at LP peak); world7_layer.gd step_herds reads event positions once per
    call, not once per herd. Exact: headless old / new differential over 500 + 700 LP-peak ticks, every drawn field
    compared, 0 diffs; test_lpmap7 18/0, test_fissure7 12/0, test_perfdraw71 7/0; flows fissure7 19/0, lpmap7 45/0,
    vis7 17/0; 0 script errors in 12 windowed runs. Measured: terrain group 3.11 -> 1.16 ms (-1.95 ms per frame); gate
    p10 pairs old / new 21.4 / 24.3, 23.8 / 24.9, 23.2 / 23.3 (median 23.2 -> 24.3, inside the spread); pan pairs inside
    noise. Still missing for a 33.3 ms p10 frame: ~7.8 ms (busy PC). Next: HUD per-control split + skips, _process
    census.
  - **15:05Z:** FIRES71-9 (seq 4454 / 4455): turret sectors (`KillZone71._wrange`) installed + tested + HASH-CHECKED
    (killzone71 10/0, bastion71 18/0, turret7 18/0, fires71 12/0, hot_state 17/0, hashes == ref). Fires71 cache
    removal: correct (hot_state 17/0, lpreserve7 7/0); cost at LP peak 0.19-0.24 ms per tick vs 0.04 with the old
    unsaved cache; a save-safe per-def memo brings it to ~0.10 (LP hash identical); the full list cache is not
    restored (cannot be made save-identical without a spawn hook). cn71_layer.gd (Vanta 2 trail + bank cue, shield
    bubble) added to G71Attach.LAYERS (CNOPS71-11 CR seq 4443; 9 layers; windowed smoke owed by the agent).
- **03:00Z (ORCH): FIRES71-5 handed off (audit OK 240k) -> FIRES71-6. LIVE (6): BASTION71-4, SWARMNAT71-5, ARMY71-6,
  CNOPS71-5, DAMAGE71-5, FIRES71-6. Guard + watcher re-armed.**
  - **test_path7 (wave-2 gate blocker), state:** ORCH moved the LP-base additions to LpSetup.build_g71_late (called from
    LastProtocol._try_fill at facility fill; backups .plan/orch71/wire_orig/*.pre_late): G7 start ids unchanged, the 4 LP
    tests green (lpmode7 18/0, lpmap7 18/0, lpreserve7 7/0, lpperf7 9/0), hashes == ref, but test_path7 STILL red (got 2).
    Per-file bisect (`G71_LP_BASE=<name>`, logs C:/CODING/orch71_check/path7/bis_*.log): fires 1, army71 3, bastion71 2,
    damage71 (one tent) 1; `=0` is 6/0. So it is a real sim defect: a foot unit can end inside a moving facility vehicle;
    any change to the LP world exposes it. **CNOPS71-5 owns the sim fix (priority 1; never edit test_path7).**
  - Same check run also showed (agents' work in flight, theirs to settle): test_fires71 10/1 + 1 script error (new
    test_fo_call "observer cannot see that point": FIRES71-6), test_bastion71 11/2 (two new tests of BASTION71-4).
  - FIRES71-5: flow 24/0; provider-unregister bug fixed in fires71_view (a restarted match's old layer wiped snap.g71;
    DAMAGE71's layers had the same bug); radial clamped to the viewport on its own CanvasLayer; conductor + 4 wingmen
    added to lp_base_fires.json (NOT approved yet); `test_pick_next_in_sector` red on purpose until ARMY71 changes the
    target pick. **Design finding for the owner (FIRES71-6 measures, posts need owner.fpf_reach): FPF strips sit ~40
    tiles from the base centre, gun ranges are 12-22, so base artillery near the centre cannot reach a strip.**
  - DAMAGE71-5: triage layer draws now (shot forwarded: call-for-medic rings + a tag card). turret71_look.gd attached
    (g71_attach.gd has 7 layers). lp_base_cnops.json went live (CNOPS71-5; its LP tests wait for the path7 fix).
- **02:35Z (ORCH): four handoffs in 15 min, all audits OK (SWARMNAT71-4 198k, ARMY71-5 217k, CNOPS71-4 217k, DAMAGE71-4
  193k). LIVE (6): BASTION71-4, FIRES71-5, SWARMNAT71-5, ARMY71-6, CNOPS71-5, DAMAGE71-5 (.plan/orch71/live_agents.txt).**
  - FIRES71-5 (seq 2280): `--ui-playtest-fires71` 24/0, 0 script errors; shots .plan/shots/FIRES71/run3/ (radial,
    line barrage, smoke box, FPF strip, sector, conductor orbit; radial + orbit forwarded to the owner). Clicks: lane
    barrage 13 -> 2, smoke screen impossible -> 2, one-unit sector impossible -> 3. Seen limits: world markers (mission
    outline, orbit ring, sector) are dimmed by the LP night tint; impacts not visible in the barrage / smoke shots.
  - **test_path7 RED (5/1) "facility: no hull overlapping another unit (got 1)": caused by the LP-base placements**
    (ORCH bisect: new env switch `G71_LP_BASE=0` in LpSetup.build_g71 -> 6/0; with the base files -> 5/1; logs
    C:/CODING/orch71_check/path7/). ORCH's hook (lp_setup.gd _g71_points) puts a unit hull on another unit: CNOPS71-5
    probes which def / where and posts `need change_request.lp_setup71`; ORCH fixes the placement. Wave-2 gate blocker.
  - SWARMNAT71-4: the dsz verify diff is FIXED (entity_layer.gd: bay-hide range closed before the kernel run); verify r1
    0 real diffs on lp / lpw / lppan. Probes: m_scout_crawler + m_walker are infantry-class with basic anim61 sets (+ a
    bay-hide entry each); m_tracked is vehicle-class and drops out before registration (cause unknown). 8-step port plan
    with line numbers in .plan/handoff/SWARMNAT71-4.json. SWARMNAT71-5 does the port. No timing yet.
  - ARMY71-5: combat.gd lines VERIFIED (hashes == ref, hot_state 17/0, perfsim71 6/0, 9 test files green);
    lp_base_army71 counts APPROVED by ORCH (PROVISIONAL); army71 flow 12/2 (crew marks + hand signals never appear):
    ARMY71-6's first job; shots not looked at yet.
  - CNOPS71-4: cnmission71 'tid' errors were the TEST reading a record in the submit tick (fixed in its own test;
    test_cnops71 6/0, 0 SE); regressions green (cnmission8 7/0, cnfac7 36/0, apcmov7 16/0, facexit8 4/0, facreturn8 2/0,
    cnrole7 10/0, cnsim7 27/0) except test_path7; DW8 41.8 s on 6 seeds (seed does not vary the drill = 1 sample);
    hospital defs (two 6x6 blocks) + art live; lp_base_cnops.json staged only. HARNESS NOTE: tests/run_tests.gd reports
    PASS when a SCRIPT ERROR aborts a test before its checks: the suite gate must keep counting script errors (it does:
    err_files).
  - DAMAGE71-4: pt71_gore71 flow 12/0; real-game shots forwarded to the owner (bodies + blood draw under units). **The
    triage tags do NOT draw in the real game** (layer attached, Care71 has 13 tags): DAMAGE71-5's first job. care71
    hospital routing (CNOPS71 seq 2138) not installed. No cost numbers yet.
- **02:25Z (ORCH): 6th connection drop ~02:00Z killed all six; owner "Try again". Connection 4/4; hospital71.gd (CNOPS71-4
  reported a 1-minute parse break it fixed), world.gd, match_view.gd, entity_layer.gd, combat.gd parse clean. LIVE (6):
  SWARMNAT71-4, CNOPS71-4 (handoff only), ARMY71-5, BASTION71-4, DAMAGE71-4 (resumed in place), FIRES71-5 (new).
  Ids: .plan/orch71/live_agents.txt. Guard + watcher re-armed.**
  - **Owner 2026-11-22 "Yes, apply it" (DECISIONS.md):** ORCH applied the tests/test_conductor71.gd setup change (13 lines
    added, 0 removed; backup .plan/orch71/testfix_orig/test_conductor71.gd.pre_cr2130): test_conductor71 7/0, 0 script
    errors. Owner question (2) (LP-peak "2x G7" reading) still open, to raise with measured numbers.
  - FIRES71-4 handed off (audit OK 221k): radial + fires71_view + killzone_paint built and attached, pt71_fires71.gd
    written but never run; thermobaric / incendiary set Gore71.ctx_rc; airfix71 6/0, airops71 8/0, hot_state 17/0,
    ui_panels 5/0, ui6b 5/0, art 7/0, icons7 1/0, hashes == ref.
  - BASTION71-4 (seq 2214): lp_base_bastion71.json without generators: 4 LP tests green (18/0, 18/0, 7/0, 9/0). Survey,
    1000 machines / 90 s: uptime 0.893 -> 0.917 (0.924 with disabled-not-dead), defence deaths 25 -> 19 / 17; rotary
    rails fire ~2,200 slugs (21 when unpowered); lasers / flak 0 shots (no air targets in that wave); 0 revives (nobody
    acts on disabled turrets yet). **Counts APPROVED by ORCH as PROVISIONAL** (fact orch.lp_base71.approved).
    Approved so far: fires (2 FO, 2 MLRS), damage (1 surgery tent), bastion. Pending: army71 (no fact yet), cnops
    (staged), fires conductor + 4 wingmen (staged).
  - ARMY71-5: fact army71.cr_installed (seq 2157): BASTION71 tower guard + FIRES71 lines verified so far by perfsim71
    6/0, army71 9/0, ammo71 7/0, crew71 7/0; rest of its batch in flight.
- **02:10Z: SWARMNAT71-3 handed off (audit OK 212k) -> SWARMNAT71-4 launched. KEY FINDING: the native unit kernel
  (rts_core 0.6.4, LIVE, toggle default off; hashes / hot_state / perfsim71 green) draws ~60 human vehicles per frame at LP
  peak and 0 Machines (anim61 machines are classed as infantry and never registered), so as built it cannot move the LP
  peak. SWARMNAT71-4: fix the 1 real verify diff (unwritten dsz slot), port the anim61 Machine path into the kernel, look
  at MOTION_CAP 700. No g71 timing yet (PC never quiet); quiet-PC command list in .plan/handoff/SWARMNAT71-3.json.**
  - **OWNER QUESTIONS PENDING (fact orch.owner_asks):** (1) tests/test_conductor71.gd setup change (FIRES71-4 seq 2130:
    remove armed player units near the station so the new LP-base turrets / crews don't kill the 3 targets in 25 ticks;
    assertions unchanged; test is 6/1 until then). The agent's own Edit was refused by the permission check and it asked
    ORCH to do it: ORCH did NOT (no routing around a refusal) and asked the owner. (2) LP-peak gate reading: ">= 30 and
    >= 2x G7" was set when G7's LP peak was recorded as 13.3-15.4 p10 (loaded rounds; SWARM_NATIVE71.md s5), i.e. ~27-31;
    the quiet G7 run of 2026-11-21 gives 24.5, so the literal bar is 49 vs an estimated best case ~43. To raise with
    measured g71 numbers; agents work to >= 30 first.
- **01:55Z: BASTION71-3 (audit OK 235k) and DAMAGE71-3 (audit OK 230k) handed off -> BASTION71-4, DAMAGE71-4 launched.
  LIVE (6): FIRES71-4, SWARMNAT71-3, CNOPS71-4, ARMY71-5, BASTION71-4, DAMAGE71-4 (.plan/orch71/live_agents.txt).**
  - **LP start power bug (ORCH hook) FIXED:** power_up ran before build_g71, so wave-2 powered buildings were unpowered
    ("base powered 2730 / 3026": test_lpmode7 16/2 or 17/1). lp_setup.gd now runs power_up again after build_g71 when it
    placed anything (adds only the missing generators). VERIFIED 02:00Z: test_lpmode7 18/0, 0 script errors, with
    lp_base_fires + army71 + bastion71 live (C:/CODING/orch71_check/resume71/lpmode7_power.log).
    02:15Z DAMAGE71-4 (seq 2148): surgery tent file live; with all 4 base files and BASTION71's generators REMOVED:
    test_lpmode7 18/0 twice, test_lpmap7 18/0, test_lpreserve7 7/0, test_lpperf7 9/0 (the second power pass works).
    BASTION71-4 removes its 8 workaround generators; DAMAGE71-4 un-parks the surgery tent (count 1 approved).
  - LP start files live: lp_base_fires (approved), lp_base_army71 (4 MG crews, 2 AT, 2 AM, 2 grenadiers, 1 flame tank:
    NOT approved, no LP results posted), lp_base_bastion71 (2 siege engineers, 2 maint drones, 1 breacher, 4 rotary rail,
    2 HPM, 2 laser CIWS, 2 flak, 4 sonic sensors, + 8 generators to remove: NOT approved). Owner told the counts; may tune.
  - BASTION71-3: firing ports, choke doors (movement.gd is_passable_e), minimap sensor contacts (no windowed smoke yet),
    traverse for new turrets; test_walls71 7/0, test_bastion71 11/0; hashes == ref, hot_state 17/0, perfsim71 6/0. Survey
    (1000 machines, 90 s): uptime 0.893 -> 0.894 with disabled-not-dead (no engineers near; 18 of 25 deaths are towers).
  - DAMAGE71-3: regression green after Gore71 / Care71 (6 files, hashes, hot_state); limp native on == off test (no native
    change needed); surgery tent def + art; both view layers attached, not yet seen drawing in a real game.
  - ORCH: tools/ui_playtest.gd G7_FLOWS + 16 wave-2 flow names (fact orch.ui_playtest71); g71_attach.gd LAYERS now 6:
    gore71_layer, triage_tags, fires71_view, killzone_paint, fire_radial, signals71_layer (windowed smoke 0 script errors).
- ~23:35Z: FIRES71-3 handed off (audit OK, real 244k / 84 calls) -> **FIRES71-4 launched**. FIRES71-3: test_conductor71
  7/0 (wingmen no longer share the gunship's landing cell), conductor + wingman art, strikes.gd track_shell (LP only),
  hotkey `fire_radial71` = QUOTELEFT held (ORCH PROVISIONAL decision: F is the fixed Formation key), 3 ui71 files written
  but not attached. NOT run after the Conductor71 wiring / hotkeys change: test_airfix71, test_airops71, test_hot_state,
  hashes, test_ui_panels, test_ui6b (FIRES71-4's first job).
- world.gd also has: CnMission71 (slot after CnMission8; cn_search / cn_abort / cn_roe; CR 1811; test_cnops71 6/0 before
  registration, ORCH rerun in flight: C:/CODING/orch71_check/resume71/test_cnops71.log) and Crew71 (crew_rate / crew_top;
  CR 1863; test_crew71 7/0). DAMAGE71-3: regression after Gore71 / Care71 green on 6 files + hashes == ref (status seq 1869).
- test_art in the live tree is red on ARMY71's new crew ids (mg_crew, at_team, am_team, grenadier): told ARMY71-4.
- world.gd 23:25Z: + Conductor71 (preload, slot after Fires71, conductor_orbit / home / kamikaze; CR 1748): parse clean,
  test_conductor71 7/0, test_fires71 10/0; FIRES71-3 reruns airfix71 / airops71 / hashes / hot_state.
- DAMAGE71-2 handoff: Gore71 + Care71 + hooks in damage / wounds / medical are LIVE (test_gore71 7/0, test_care71 4/0) but
  the regression run after them (damage71, wound7, damage, lpmode7, hashes, hot_state) is NOT done: DAMAGE71-3's first job.
- BASTION71-2 handoff: hotkey cause = berm + sonic sensor ran out of build letters and took J (fix: build_cat in content);
  blocked guard in turrets7 / wallturret7; combat.gd tower line with ARMY71-4 (CR 1720).
- SWARMNAT71-2 handoff: statics records verified 0 diffs, ON by default; native unit kernel built as bin/rts_core.new.dll
  (0.6.4), NOT swapped in, never run. **Outlook (unmeasured): LP peak best case ~43 fps vs the gate 49 (2x G7 24.5): likely
  an owner stop-and-ask once SWARMNAT71-3 has quiet-PC numbers (it posts need owner.lp_peak.ask3).**
- Quiet-PC fps, G7 reference only (.plan/perfdraw71/q1121.out, 2026-11-21 22:55Z): 2k p10 62.7, 10k p10 228.0, LP zoomed-out
  62.8, LP pan 39.9, LP peak 24.5. So the amended LP-peak gate (>= 30 and >= 2x G7) = p10 >= 49. g71 run INVALID (view
  broken): redo `CASES="2k 10k" bash .plan/perfdraw71/base.sh <tag> g71` on a quiet PC once swarmnat71.view_ok is posted.
Previous park note, kept: (1) confirm the connection holds (a few minutes of curl to api.anthropic.com); (2) ORCH runs
test_lpmode7 + test_lpreserve7 (lp_home), test_ui_panels + test_ui6b, the 3 bench hashes and test_hot_state on the live tree
to know where it stands; (3) resume the six agents (SendMessage to each, or successors from the statuses above), guard +
watcher under Monitor, keep-awake on.
Wave-2 gen-2 briefing: `.plan/agents/prompts/G71-W2_GEN2.md` (what is wired, what wave 2 owes: 11 placeholder icons, the
build_rail X hotkey clash, rules). NEXT: launch DAMAGE71-2, FIRES71-2, ARMY71-3, BASTION71-2, CNOPS71-2, SWARMNAT71-2 from
`.plan/handoff/<ID>.json` (caps 750k/140, board v1, guard under Monitor, keep-awake on); then per agent: handle CRs
(change_request.world71, testfix.*), audit on completion, successors from handoffs; wave-2 gate = full suite on a refreshed
frozen copy before the wave-2 commit (owner's yes needed for the commit).
Status 2026-11-02 (ORCH): G7 leftovers committed (3a66ffc); branch `g71` cut. **D: health check FAILED** (Disk 1 Seagate:
bad blocks + hardware I/O errors logged as recently as 2026-11-02 12:00), so G7 was NOT copied to D:; all work stays on C:
and the D: tree is still at G6.1 (55b4e04). A5 done (+20% speed at load, `rules.g71_speed_mult`); goldens re-baselined
(`.plan/regold71/`). Wave 1 launched: AIRFIX71, FLOW71, CONTROL71, PERFSIM71, PERFDRAW71.
Status 2026-11-04 (ORCH, resume): CONTROL71 + FLOW71 done. AIRFIX71-2 / PERFDRAW71-2 ended with the host session
(no handoff; ORCH rebuilt `.plan/handoff/*-2.json`); successors AIRFIX71-3 / PERFDRAW71-3 running. PERFSIM71 hit the
Stop-if (2k sim 1.72x G6, loaded PC). **Owner decision 2026-11-04: native combat port (PERFSIM71-2), gate unchanged;
if it still falls short, stop and ask again.** ORCH applied CRs 149 (air_patrol on SHIFT+Y, not SHIFT+P: cn_pincer),
161 (PatrolDraw71 attach), 164 (minimap SIZE 206 in hud.gd).
**PAUSED 2026-11-04 by the owner.** All wave-1 agents stopped cleanly with handoffs: `.plan/handoff/AIRFIX71-3.json`,
`PERFDRAW71-3.json`, `PERFSIM71-2.json` (budget audits OK). Nothing committed. Resume notes: (1) PERFSIM71-2 estimates
(unmeasured) that piecewise native ports won't reach the G6 gate; measure before re-asking the owner; the G6 worktree
C:/CODING/ps71_g6 is gone, recreate at 979a6d8 first. (2) AIRFIX71 left worktree C:/CODING/af71_head (fda25f9) for the
test_cnfac7 ramp check; remove after. (3) PERFDRAW71-3 added render_snap air_hot (untested); baseline sweep not started. (4) test_ui_fit still FAILS 2/4 (log `.plan/orch71/test_ui_fit.log`):
the same BottomPanel vs GroupBar "[.] Idle" 1 px overlap (61x1). ORCH's `_minimap.SIZE = 206` in hud.gd did NOT clear it;
find what really sets BottomPanel height (FLOW71-2 saw issues=0 only with minimap DEFAULT_SIZE 192) before trying again.
Status 2026-11-04 late (ORCH, resumed by the owner: "continue where left off"): G6 worktree C:/CODING/ps71_g6 recreated at
979a6d8 and imported (smoke: SIMAB fight 23.00 ms, 0 errors). Successors AIRFIX71-4, PERFDRAW71-4, PERFSIM71-3 launched from
their handoffs (caps 750k/140, board seq 229-232, guard armed).
Status 2026-11-05/08 (ORCH): AIRFIX71-4 DONE (patrol 3/3 on route, air.nodead swap, air tests 9/8/7/6 all 0 fail, gold61 16/16
lines = regold71, air <0.05 ms/tick on 2k). test_cnfac7 ramp failure (APC hidden 0.52 tiles off) confirmed PRE-EXISTING at fda25f9
(C:/CODING/g71_clean, 35/1, log C:/CODING/orch71_check/cnfac7_head.log); G7 final was 155/0 so A5 speed is the likely cause; OPEN:
fix the lineup code, not the tolerance. PERFSIM71-3 hit the stop rule: 2k fight G6 34.0 vs G7.1 49.9 ms/tick (1.71x, loaded PC);
prefilter ports saved ~0.03 ms. **Owner decision 2026-11-05: full native combat port (option A), gate unchanged.** PERFDRAW71-5
died on an API error (handoff rebuilt by ORCH). 2026-11-08: PERFSIM71-4 (native port, gen 1 of several) + PERFDRAW71-6 launched.
Nothing committed yet.
Status 2026-11-08 (ORCH): native combat port phase 1 (mirror, rts_core 0.6.0) exact, saved ~0; phase 2 (native _find,
rts_core 0.6.1) exact (0 diffs over ~135k calls, test_hot_state 17/0) and saved ~1.5 profiled ms of a 2.0 estimate. Clean pairs
(.plan/perfsim71/n5p_pairs.txt): G6 14.82 ms, G7.1 27.45 ms = 1.85x. Projection (docs/NATIVE_COMBAT71.md s8): 1.25-1.55x G6 after
combat phases 3-5, gate also needs phase 6 cuts outside combat; 6-9 more generations. Owner asked whether to start phase 3.
PERFDRAW71-6: 10k regression = minimap._draw_incoming (242 vs 132 draw calls); CR 467 given to PERFDRAW71-7.
Owner 2026-11-08: "Yes, start phase 3" (PERFSIM71-6 running). PERFDRAW71-7: CR 467 done (same look, max diff 1/255; 10k g71 p10
~217 vs old 162-179, g7 ~226; draw calls 133 vs g7 132); FARP hot-pit draw order fixed (looked). Gates: 2k g71 65.6 vs G6.1-today
53.6 (the 85.2 reference does not reproduce on this PC; gate-grade rerun owed), 10k ~217 vs G7 ~226 (3-5% short), LP peak 22.4 vs 60.
**Owner 2026-11-08 on LP peak: "Cache now, native later"**: PERFDRAW71-8 builds the GDScript per-snapshot frame cache; the native
machine entity-list builder is queued after the native combat port. Gate unchanged.
Status 2026-11-09 (ORCH, resumed after a session break): PERFSIM71-6 phase 3a (native act driver, rts_core 0.6.2) exact
(hash 8fd794b3 / a1e5af17 / 41b5f765 on==off, 1.79M whole-shooter compares 0 diffs, test_hot_state 17/0) but ~50% of estimate:
G7.1 26.67 vs G6 15.95 ms (1.67x, .plan/perfsim71/n6p_pairs.txt). PERFDRAW71-8 frame cache: no fps gain, 2 diffs at 2k -> ORCH set
it OFF by default (entity_layer.gd rc_on). **Owner 2026-11-09: "Probe other systems first"** -> PERFSIM71-7 measures the non-combat
per-system gap and tries exact cuts; combat port paused. Decisions log: DECISIONS.md. Audit of PERFSIM71-6 usage: UNVERIFIED (session
ended before its completion usage arrived). Nothing committed.
Status 2026-11-09 (ORCH): PERFSIM71-7 probe (docs/NATIVE_COMBAT71.md s9): G6 18.11 vs G7.1 26.86 profiled; ~6.1 of the 6.7 ms
non-combat gap is new G6.1/G7 feature work; exact cuts ~1-2 ms. **Owner 2026-11-09: "New bar, move on"**: E2 sim gate is now
final build <= 1.7x G6 on 2k, later waves add ~0 (G71_SCOPE.md; DECISIONS.md). Port stopped at phase 3a. Next: wave 1 close-out
(cnfac7 ramp fix, full suite + determinism + perf gates, commit) and wave 2 briefs; LP-peak native builder now unblocked.
Status 2026-11-09 05:40Z (ORCH): RAMP71 DONE: transport.gd _tick_bay_boarder settles a vehicle on the line-up for one
tick before it drives in (A5 x1.2 moved the APC 0.52 tiles short); live test_cnfac7 36/0 (.plan/ramp71/test_cnfac7_live.log),
copy airfix71 6/0, airops71 8/0, hot_state 17/0. Open, untested: soldiers still hide ~0.73 tiles short of the ramp foot (same
pop). Wave 2 launched (roster .plan/orch71/wave2_roster.md, answers 5A): DAMAGE71, FIRES71, ARMY71, BASTION71, CNOPS71 + SWARMNAT71
(LP-peak native builder). Wave-2 agents add only new files until wave 1 is committed (owner asked; pending). ORCH stopped an
orphaned cut7.sh of the ended PERFSIM71-7 that held the timing lock 05:10-05:30Z. Nothing committed.
Status 2026-11-09 06:15Z (ORCH): owner amended the LP-peak gate ("Bar >=30 fps, build native": p10 >= 30 and >= 2x G7).
Owner approved committing wave 1 after the full suite + determinism pass on a frozen copy: copy = C:/CODING/g71_clean
(HEAD fda25f9 + the 94 wave-1 paths in C:/CODING/orch71_check/wave1_files.txt, no wave-2 files); suite running
(C:/CODING/orch71_check/w1_status.txt, w1_full_suite.log). Wave-2 gen-1 agents DAMAGE71, FIRES71, BASTION71, CNOPS71 handed off
(new files only; their CRs for world.gd SYSTEM_ORDER / COMMANDS wait for the commit); ARMY71-2 running. Hospital site A approved
(new building north of the facility). RISK for Done-when 8: CN team airlock cycle measured 102.1 s vs 70 s, soldiers not healed
in the cycle today (.plan/cnops71/repro_*.log); CNOPS71-2 must redesign the turnaround (heal in wash/garage, overlap rearm).
Status 2026-11-10 06:57Z (ORCH, resumed "continue"): step A DONE with one change: **4 fixers, not 3** (the 13 A5 files split
by area so they run in parallel): ARTFIX71-1 (test_art, test_icons7, test_art_g5_bld), UIFIX71-1 (test_ui_fit, test_ui6a),
SPEEDFIX71-1 (core sim: test_content_g6, test_perf, test_path7, test_naval_g6, test_gen61, test_real61, test_drone_team),
SPEEDCN71-1 (CN / soldiers: test_cnsuits7, test_cnsim7, test_cnrole7, test_sent7, test_wound7, test_cards8c). Briefs
`.plan/agents/prompts/G71-{ARTFIX71,UIFIX71,SPEEDFIX71,SPEEDCN71}.md` + shared `G71-FIX71_COMMON.md` (tests frozen: any
expectation change goes to ORCH as `change_request testfix.<test>`, ORCH asks the owner). Caps 750k/140 registered (seq
1047-1050); guard v1 armed under Monitor. Max 6 live: 2 slots left, wave-2 successors still wait for the commit. Next: steps B, C.
Pre-check (ORCH, 2026-11-10): the 2 live-tree fixes (rts_core 0.6.3 DLL + Cargo.toml/lock + mirror.rs, test_perfdraw71.gd,
test_perfsim71.gd) copied into the frozen copy; there: test_airfield 13/0, test_perfdraw71 7/0, test_perfsim71 6/0,
test_hot_state 17/0, 0 script errors (logs C:/CODING/orch71_check/pre71/). Frozen copy now differs from the live tree only by
docs/board + whatever the 4 fixers change.
Testfix requests (2026-11-10 ~07:25Z, board type `need`, topic `change_request.testfix.<test>`; each proposed copy passes on
G7 3a66ffc and live; evidence `.plan/speedfix71/`, scratchpad probes for SPEEDCN71). OWNER DECISION PENDING, none applied:
- Like-for-like (same check, the speed-coupled number scales with A5): test_cnsuits7 1067 (compare with the loaded G6 exo speed,
  not 2.2), test_wound7 1069 (crawl bound 4.0 x mult; crawl = 0.15 x unit speed by design, G7 had 0.007 margin), test_content_g6
  1076 (cap 10 x mult), test_real61 1094 (march leg 340 -> 283 ticks), test_gen61 1120 (lead-in 40 -> 33 ticks), test_perf 1077
  (far units 86 -> 92: A5 grew the tiers bucket 41 -> 44, so on 96-tile maps nothing under 88 is REDUCED; correct, conservative).
- Scenario changes: test_drone_team 1134 (SPAAG 3 tiles closer AND gun pre-laid at the launch: easier than G7's setup);
  test_naval_g6 1141 (sweeper stops on the field's far edge; ORCH prefers the sim alternative: sweep rate x speed mult, so one
  pass still clears the lane); test_cnrole7 1122 (tolerate the parked soldier dying to own-side splash: weakens the hold check;
  ORCH prefers a setup that keeps him alive, e.g. walker further away).
- SPEEDFIX71-1 DONE (audit OK, real 256k / 78 calls); successor SPEEDFIX71-2 on test_path7 = real sim bug (riflemen shove an
  APC backwards at the gate exit, VehDrive7 handoff t~521).
- ARTFIX71 found (seq 1131): live-tree test_icons7 also lists 11 wave-2 ids with placeholder icons (defs_g71_defences.json,
  defs_g71_fires.json: BASTION71 / FIRES71). Not in the frozen copy, so not a wave-1 blocker; wave-2 successors owe those icons.
- ARTFIX71-1 DONE (audit OK, real 270k / 99 calls): FARP art (new generator tools/art/g71_farp.gd, group assets/art/g71_farp,
  268 px, 3 build stages, icon) + air_patrol 32x32 icon (g5_bld regenerated, 936/936 old files byte-identical). Wave-1-only
  tree: test_art 7/0, test_icons7 1/0; live: test_art_g5_bld 2/0, test_airfix71 6/0, test_airops71 8/0, pt airfix71 15/0.
  Every fixer path for step B is listed in C:/CODING/orch71_check/fixer_files.txt (append as fixers finish). New PNGs need
  `--import` in the frozen copy before the suite.
- UIFIX71-1 handed off (audit OK, real 236k / 97 calls). Causes: (1) CONTROL71 minimap DEFAULT_SIZE 208 applied in _init, so
  ORCH's CR-164 `SIZE = 206` never reached the layout (panel min 230 > BOTTOM_H 220); fix: SIZE setter + hud.gd sets 198, the
  largest square the 220 px panel holds (G7 192; 206 needs a taller panel = moves the cargo strip). (2) FLOW71 flow bar rows
  HBox -> HFlowContainer (150% CLIP at 1280x720). test_ui6a 8/0, test_flow71 12/0, test_control71 6/0. ORCH (no successor)
  runs test_ui_fit, test_ui6b, test_perfdraw71 live + test_ui_panels live vs wave-1-only tree (ui_panels went 5/0 -> 4/1 in
  the live tree: build_rail hotkey X taken by G6_sweep; suspect wave-2 content). Logs C:/CODING/orch71_check/ui71/.
- SPEEDCN71-1 handed off (audit OK, real 259k / 84 calls). Sim fixes: apc7.gd agility_hit (ref x g71_speed_mult: colossus
  stride factor back to 1.0) and wounds.gd _care_pass (a carer with a `board` order ends its care job: CN operators remount);
  hashes == w2.bench_ref, hot_state 17/0. 8th testfix request: test_cards8c 1191 (scenario change: clear the enemy units so the
  base is quiet; A5 brings a Machine scout into the guard net 50 ticks earlier and the board never rotates under alarm).
  Successor SPEEDCN71-2: re-run cnsim7 + wound7, then test_sent7, then cnfac7 / cnops7 / airops71 / hashes.
- SPEEDCN71-2 DONE (board seq 1251; no sim change this gen): live test_cnsim7 27/0, test_wound7 16/1 (crawl only, CR 1069),
  test_sent7 12/1 (W face only, CR 1223); cnfac7 36/0, cnops7 11/0, airops71 8/0, hot_state 17/0, hashes == w2.bench_ref.
- 2026-11-10 ~08:00-16:20Z: PC asleep / offline; SPEEDFIX71-2 and UIFIX71-2 both died on API ENOTFOUND (no final usage:
  budget audit UNVERIFIED for both; last statuses 235k / 58 calls and 125k / 31 calls). No successors needed:
  SPEEDFIX71-2 had finished: sim/systems/veh_drive7.gd _unpush (infantry walking into a driven APC no longer shoves it
  backwards beyond its own step; other axial push taken back with the sideways part); live test_path7 6/0 (was 5/1),
  hashes == w2.bench_ref, hot_state 17/0, mil 13/0, squad61 14/0, perfsim71 6/0, cnfac7 36/0, cnsim7 27/0, facexit8 4/0,
  facreturn8 2/0, apcmov7 16/0, det7 6/0 (logs .plan/speedfix71/live_test_*.log). UIFIX71-2: hud.gd _fit_card reserves the
  CardScroll v-scrollbar width when the card scrolls (hud.gd == .plan/uifix71b/hud.gd.fixed); windowed fit at 1280x720 s=1.5
  3 issues -> 0 (.plan/uifix71b/shots_*.log); its full test_ui_fit run resumed after wake, ORCH reads the result.
- UIFIX71-2's orphaned test_ui_fit finished after wake: 6/0, TESTS OK, 0 script errors (.plan/uifix71b/test_ui_fit_after.log).
  ALL FIXER WORK DONE; only the 9 testfix requests remain (owner decision pending since 2026-11-10).
- 2026-11-13 16:35Z (ORCH, owner "status? continue"; nothing changed in the tree since 2026-11-10): step B started without
  waiting for the testfix answer: 24 fixer paths (C:/CODING/orch71_check/fixer_files.txt) copied into g71_clean, `--import`,
  `suite71.sh 6` running (pre-approval run: expect the 9 testfix files red, everything else green). First run's logs moved
  to C:/CODING/orch71_check/suite71_run1/ (fixer briefs and CRs cite them as .../suite71/).
- 2026-11-13 (ORCH): **owner "Yes, as recommended"** (DECISIONS.md). ORCH applied the 9 test edits in the live tree
  (test_content_g6, test_perf, test_gen61, test_cards8c, test_sent7 = proposed copies, diff = approved lines only;
  test_real61, test_drone_team without the debug prints; test_cnsuits7, test_wound7 by exact replacement; originals in
  .plan/orch71/testfix_orig/). Live re-run of the 9: logs C:/CODING/orch71_check/tf71/. TESTFIX71-1 (cap 750k/140, guard
  armed) does the naval sweep-rate sim fix (test_naval_g6 unchanged) and a test_cnrole7 setup where the parked soldier
  survives (only that test function may change; must pass in live / HEAD / G7 and across tick shifts).
  Live re-run of the 9 edited tests: ALL GREEN, 0 script errors: real61 8/0, gen61 15/0, drone_team 8/0, cards8c 7/0,
  cnsuits7 9/0, perf 11/0, content_g6 7/0, wound7 17/0, sent7 13/0.
  PC idle-slept again 16:58-22:10Z (suite paused at 116/177, resumed; import was clean: 0 errors). ORCH set keep-awake for the
  session. Any timing-only red in this run (test_perf_g6 etc.) gets a rerun alone before it counts.
- TESTFIX71-1 handed off (handoff .plan/handoff/TESTFIX71-1.json). NAVAL DONE: naval.gd _sweep_one rate x g71_speed_mult;
  test_naval_g6 live 10/0, G7+patch 10/0, HEAD+patch 10/0 (HEAD unpatched 9/1), test_mines 7/0, hot_state 17/0, hashes ==
  w2.bench_ref. CNROLE7 NOT DONE (need seq 1330): two causes: own-side strays at the walker 2 tiles away AND Wounds auto
  buddy-aid sends the parked soldier to treat a wounded mate (fails ever_moving / moved < 1.0; CnRole7 parked doesn't filter
  care). Original setup already failed 5/6 tick shifts on G7. No placement passes all 18 tree x shift runs; best: walker at
  a_pos + (-4,-1) (line 319) = live 6/6, HEAD 6/6, G7 5/6 (care). Options for the owner: A placement only; B parked CN units
  take no automatic buddy-aid job (sim); C both (ORCH recommends C). tests/test_cnrole7.gd untouched.
  TESTFIX71-1 audit OK (real 282k / 56 calls).
- Pre-approval full suite on the refreshed frozen copy (2026-11-13 16:33-22:32Z, with a sleep in between): files=177, 165 green,
  fail_files=11, err_files=1. The 12 red = the 9 approved test edits (not yet copied) + test_naval_g6 (sim fix not yet copied)
  + test_cnrole7 (owner choice pending) + test_perf_g6 5.05 vs 5 ms timing probe under 6 lanes. No other regression: every
  fixer-fixed file (art, icons, ui_fit, ui6a, airfield, path7, cnsim7, ...) green. Logs C:/CODING/orch71_check/suite71/.
  Then: the 9 test edits + naval.gd copied into g71_clean; those files + test_mines + test_hot_state rerun there, then
  test_perf_g6 alone (logs C:/CODING/orch71_check/frozen_tf/).
  RESULT on g71_clean: ALL GREEN, 0 script errors: real61 8/0, gen61 15/0, drone_team 8/0, cards8c 7/0, cnsuits7 9/0, perf
  11/0, content_g6 7/0, wound7 17/0, mines 7/0, naval_g6 10/0, sent7 13/0, hot_state 17/0; test_perf_g6 alone 7/0.
  => frozen copy at 176/177; only test_cnrole7 left (owner A / B / C). After it: copy, rerun cnrole7 + hot_state (+ hashes
  if B), then step C commit by path (wave1_files.txt + wave1_uids.txt + fixer_files.txt + new .uid files).
- 2026-11-13 (ORCH): owner chose **"Both A and B"** for test_cnrole7 (DECISIONS.md). Applied in the live tree: (A) test line 319
  walker a_pos + (-4,-1); (B) wounds.gd: const CnRole7 preload + `and not CnRole7.parked(w, t)` on the _auto_pass buddy branch
  (backups .plan/orch71/testfix_orig/wounds.gd.preB, test_cnrole7.gd). Verifying (C:/CODING/orch71_check/cnrole71/): parse,
  3 bench hashes, cnrole7, wound7, cnsim7, hot_state, cnfac7, cnops7, real61, tick-shift probe (tf_cn2.gd, -4,-1, 6 shifts).
  RESULT (live): parse clean; hashes 8fd794b3 / a1e5af17 / 41b5f765 == w2.bench_ref; cnrole7 10/0 + 0 script errors, wound7
  17/0, cnsim7 27/0, hot_state 17/0, cnfac7 36/0, cnops7 11/0, real61 8/0; shift probe 6/6 strict (survives undamaged, fires
  5-6 shots, never moves). Copied to g71_clean: every listed code/content/test file now byte-identical live vs frozen, no
  tracked change outside the lists. FINAL full suite on g71_clean started (run 2 logs kept in suite71_run2/).
- **WAVE-1 GATE MET (2026-11-14 02:37-03:10Z, g71_clean, suite71.sh 6 lanes): files=177 fail_files=0 err_files=0, 1,451 checks
  pass** (C:/CODING/orch71_check/suite71/STATUS + SUMMARY.txt). **Committed 82a887a** (155 files staged by path from
  C:/CODING/orch71_check/commit_paths.txt; all 114 code/content/test/asset blobs == the tested g71_clean files, CR-stripped;
  fact orch.wave1_committed posted; NOT pushed; D: still not synced). Wave 1 committed locally by path (no push): wave1_files.txt +
  wave1_uids.txt + fixer_files.txt + tools/art/g71_farp.gd.uid + fixer briefs/handoffs. NEXT (old steps 3-4 below): ORCH
  world.gd wiring CRs (FIRES71 978, DAMAGE71 damage71_register/g6hooks, BASTION71 cr_orch, CNOPS71 1001, lp_setup q15 hook),
  then post `fact orch.wave1_committed` and spawn the wave-2 successors (DAMAGE71-2, FIRES71-2, ARMY71-3, BASTION71-2,
  CNOPS71-2, SWARMNAT71-2) from their handoffs. Wave 2 also owes: icons for its 11 ids (test_art/test_icons7 live) and the
  build_rail X hotkey clash its content causes (test_ui_panels/test_ui6b live). Owner triage list: care pass overrides newer
  non-care orders (player move); cn_ops7 overwatch drone speed not A5-scaled; cn_popup strays hit own men near a target;
  Sentinel patrol arrival point speed-dependent (1 s think, 1.4 radius).
- 9th testfix request: test_sent7 1223 (count rule: a wall-patrol man on his own run counts for his run's face instead of the
  nearest face with ties to N; A5 men overshoot the 1 s arrival check and pause exactly on the NW corner = N/W tie, so W dips to
  5; with the rule all three trees give min [9,8,8,7], bar >= 6 unchanged, no alarm involved).
- ORCH UI checks (C:/CODING/orch71_check/ui71/): live test_perfdraw71 7/0; test_ui_panels wave-1-only tree 5/0 vs live 4/1
  and live test_ui6b 4/1 (same build_rail hotkey X taken by G6_sweep) = wave-2 content, not a wave-1 blocker (owed by wave 2).
  Live test_ui_fit 5/1 (was 2/4): left = test_ui_scale_75_to_150_still_fits, BottomPanel 1281 wide at 1280x720 s=1.5 (2563 at
  2560) for ui5b_air_mixed / g6_infantry / g6_vehicles; HEAD clean. Wave-1-only tree has the same 6 issues
  (w1_uifit_scale.log) = wave-1 regression, blocker: successor UIFIX71-2 launched (cap 750k/140) to fix it.
  Adjacent (for owner triage, not fixed): care pass overwrites ANY newer order incl. a player move; cn_ops7 overwatch drone
  speed (rules 6.0) not A5-scaled; cn_popup splash kills own soldiers 1 tile from its target.
**RESUME HERE (ORCH, 2026-11-09 16:10Z)** - owner chose **"Fix all 18 first"** (DECISIONS.md): commit wave 1 only when
all 177 test files are green on the frozen copy. Exact order:
A. Spawn 3 fixers on board_g71 (v1, caps 750k/140, guard v1 under Monitor, AGENT_BOARD env, status every 5 calls,
   parse-check + LF, timing lock, no background script left running, no GENESIS offer). Briefs from the findings below:
   - ARTFIX71: a_g71_farp icon + building art (>= footprint wide) + 3 construction looks + human_a faction coverage
     (test_art, test_icons7), and a 32x32 icon for command air_patrol (test_art_g5_bld), through the existing art
     manifests; no placeholder, look-checkpoint polish not needed.
   - UIFIX71: the 1 px BottomPanel / GroupBar "[.] Idle" overlap (test_ui_fit, test_ui6a; HEAD passes both; NOT the
     minimap size: same failure at 205 and 192). Find the wave-1 change (candidates: ui7/cardbar8.gd, ui5/panels/
     g5_unit_cmds.gd, ui5/panels/hotkeys.gd, ui71/roster.gd, ui71/flow_bar.gd, hud/minimap.gd frame) and fix it without
     moving the cargo strip; test_ui_fit takes ~18 min, test_ui6a ~100 s.
   - SPEEDFIX71: the 13 A5 files (list below). For each, find why +20% speed breaks it (compare with G7 worktree
     C:/CODING/pd71_g7 = 3a66ffc, HEAD worktree C:/CODING/g71_head = fda25f9). Fix the sim when behaviour is wrong. If a
     test hard-codes a speed-coupled number, post a change_request with old/new value and reason: ORCH asks the owner
     before ANY expectation change (Done-when frozen, never weaken a test).
   Wave-2 successors (DAMAGE71-2, FIRES71-2, ARMY71-3, BASTION71-2, CNOPS71-2, SWARMNAT71-2) and the world.gd wiring wait
   for the commit (sim/world.gd is a wave-1 file). Max 6 live: 3 fixers leave room for 3 wave-2 agents on NEW files only.
B. Refresh the frozen copy C:/CODING/g71_clean (ORCH's own worktree): copy every wave-1 path + the fixers' files + the
   0.6.3 DLL from the live tree, `--import`, then `bash C:/CODING/orch71_check/suite71.sh 6`. Green = files=177
   fail_files=0 err_files=0; a timing-only miss (test_perf_g6) is rerun alone on a quiet PC.
C. Commit by path (wave1_files.txt + wave1_uids.txt + the fixers' new paths), `git diff --cached --stat` has no wave-2
   file, local only, no push, Co-Authored-By line; post fact orch.wave1_committed.
Then the old steps 3 (world.gd wiring) and 4 (wave-2 successors) below.

Previous gate notes (14:55Z), kept for the evidence:
1. Wave-1 gate: wait for `SUITE71_DONE` in C:/CODING/orch71_check/suite71/STATUS (G7's method: one Godot process per test
   file, 6 lanes, `bash C:/CODING/orch71_check/suite71.sh 6`, on the frozen copy C:/CODING/g71_clean, started 14:47Z; per-file
   logs + SUMMARY.txt in that folder; progress in done.txt). The earlier single-process `tests/run.sh` run was stopped at
   14:45Z: 8.4 h in, still running at ~18% of one core, no output. Green = files=177 fail_files=0 err_files=0, incl.
   test_hot_state. Any failure: check whether it is pre-existing (HEAD fda25f9) before blaming wave 1; fix or list it.
   Checked 14:50Z: all 91 wave-1 code/content files in the live tree are byte-identical to the frozen copy (only
   board_g71.jsonl, PROGRESS.md, handoff/SWARMNAT71-1.json differ: docs updated after the copy).
   **Findings so far (15:30Z, per-file logs in C:/CODING/orch71_check/suite71, HEAD runs in .../head71 on worktree
   C:/CODING/g71_head = fda25f9):**
   - FIXED wave-1 regression, test_airfield native on != off (HEAD 13/0, wave 1 12/1): rts_core 0.6.2 prep_mirror ADDED
     `cd_ticks` as a String key where GDScript / prep_units_ids add a StringName (unit with cooldown but no cd_ticks, e.g.
     aircraft after a sortie). Same value, different var_to_bytes, so state_hash split. Fix: native/rts_core/src/mirror.rs
     k_cd_ticks = StringName variant; rts_core 0.6.3 (Cargo.toml), built + installed in the LIVE tree bin/ (0.6.2 backup
     C:/CODING/orch71_check/rts_core_062_backup.dll). New test tests/test_perfsim71.gd test_native_added_key_matches_gdscript_bytes:
     red on 0.6.2, green on 0.6.3. Live tree on 0.6.3: test_airfield 13/0, test_hot_state 17/0, bench hashes unchanged
     (2k fight 8fd794b3, 2k mixed a1e5af17, 10k valley_conquest_l 200t 41b5f765). act.rs builds `engaged` the same way but
     attack_move orders always carry engaged from the command, so it never adds it (probed 6 distances): left as is.
     NOT YET copied into the frozen copy (its DLL was locked by the running suite).
   - WAVE-1 regressions still open (art): test_art 4/3 + test_icons7 0/1 (a_g71_farp has placeholder icon/art, no 3
     construction looks; its def says "Art: placeholder until the look checkpoint"), test_art_g5_bld 1/1 (no 32x32 icon for
     command air_patrol). HEAD passes all three.
   - PRE-EXISTING at HEAD fda25f9 (identical failure messages in both trees, 10 files): test_cnsuits7, test_cnsim7,
     test_cards8c, test_path7, test_content_g6, test_cnrole7 (script error line 324), test_naval_g6, test_drone_team,
     test_gen61, test_real61. CONFIRMED 15:30Z: all 10 pass on the G7 worktree C:/CODING/pd71_g7 (3a66ffc, results
     .../g7ref71), whose only sim difference from fda25f9 is sim/content.gd = the A5 +20% speed rule. So A5 (committed at
     the G7.1 start without a full suite) broke them; they are G7.1 Done-when 1 work, not wave 1's.
   - **FULL RESULT 15:53Z: files=177, 157 green, 1,417 checks pass, fail_files=20, err_files=2.** Every failing file
     triaged by 16:05Z:
     - Wave 1, FIXED in the live tree (not yet in the frozen copy): test_airfield (rts_core 0.6.3 above);
       test_perfdraw71 (compile error: local consts RS / Mo used inside a lambda, moved to class level; 7/0 after).
     - Wave 1, OPEN: test_art 4/3 + test_icons7 0/1 + test_art_g5_bld 1/1 (FARP art / icons, air_patrol icon, see above);
       test_ui_fit 2/4 + test_ui6a 7/1 (BottomPanel overlaps the GroupBar "[.] Idle" button by 1 px at every resolution;
       HEAD passes both). NOT the minimap: same failure with _minimap.SIZE 205 and 192 (hud.gd restored to 206,
       byte-identical to the frozen copy). Cause not found yet.
     - PRE-EXISTING, A5 +20% speed rule (fail identically at HEAD fda25f9, pass on G7 3a66ffc), 13 files:
       test_cnsuits7, test_cnsim7, test_cards8c, test_path7, test_content_g6, test_cnrole7, test_naval_g6,
       test_drone_team, test_gen61, test_real61, test_perf, test_sent7, test_wound7.
     - Timing only: test_perf_g6 7/0 run alone at 16:05Z (6/1 under 6 lanes + load).
   - test_perf_g6 6/1 (elevation overhead 12.05 ms vs 5 ms budget) is a timing probe run under 6 lanes + another project's
     load; HEAD passes it. Rerun alone on an idle PC.
2. Commit wave 1 (owner said "Yes, commit after tests", local only, no push): `git add` exactly the paths in
   C:/CODING/orch71_check/wave1_files.txt PLUS the 26 `.gd.uid` files in C:/CODING/orch71_check/wave1_uids.txt (both relative
   to game/; the repo tracks .uid files; generated by the frozen copy's import, copied into the live tree 14:52Z). sim/world.gd
   is a wave-1 file, so the step-3 wiring waits for this commit. Never `git add .`; check `git diff --cached --stat` has no wave-2
   file; message "G7.1 wave 1 ..." + Co-Authored-By line. Then post `fact orch.wave1_committed {commit}` on board_g71.
3. ORCH wiring CRs (world.gd SYSTEM_ORDER + COMMANDS, ORCH-owned): FIRES71 seq 978, DAMAGE71 change_request.damage71_register
   + damage71_g6hooks, BASTION71 need bastion71.cr_orch, CNOPS71 change_request.world_cnops71 (seq 1001). Add the LP-base hook
   in lp_setup.gd reading content/g71_lp/lp_base_<agent>.json (orch.q15_fix). Parse-check, run test_hot_state + the 3 bench hashes.
4. Spawn successors (caps 750k/140 on board_g71, guard v1 under Monitor): DAMAGE71-2, FIRES71-2, ARMY71-3, BASTION71-2,
   CNOPS71-2, SWARMNAT71-2 (owner LP-peak plan: static records alone + GPU-floor probe, then native unit drawer), each from
   .plan/handoff/<ID>-<gen>.json. Max 6 live. Every prompt: AGENT_BOARD env, status every 5 calls, parse-check + LF, timing lock,
   no background script left running.
```
GOAL — G7.1 "Tide Line": the Last Protocol siege upgrade
For whom / what changes:  the owner, playing Last Protocol: an hour in, a thinking hive hits the walls from every
                          angle with 1,000+ machines; aircraft land on their own pads; fewer clicks to battle; real
                          firepower, discipline, robot companions, dark gore and horror, core raids, the Blackglass
                          reverse-engineering complex, the AI war-mind; and it runs smoother than any past build.
Outcome:                  the G7.1 scope (A–J) in one packaged build, playable from a clean folder
Done-when (frozen 2026-10-31): the 12 checks in docs/G71_SCOPE.md "Done-when", summarised:
  1. full suite 0 FAIL / 0 SCRIPT ERROR + determinism; 2. AIRFIX matrix; 3. perf beats every past build (LP peak
  1,000+ machines p10 >= 60 fps); 4. 60-min LP soak with every new machine; 5. packaged build + README/PLAY_ME + owner
  look checkpoint; 6. robot fleet survives jamming, 0 hacked; 7. LP save/resume to the same hash; 8. core raid + 70 s
  CN turnaround; 9. gore hash-identical, fps holds as bodies pile up; 10. infection purge/turn + gas, masks, filters;
  11. war-mind fallibility + RE breakout/convoy raid; 12. Blackglass full capture-to-prototype chain + overrun cases.
Out of scope:             G8+ items in docs/ROADMAP.md; the parked lists; skirmish changes beyond what A1-A5 touch.
Stop-if / park-if:        determinism breaks and can't be fixed fast -> park that feature with a note; a perf gate
                          can't be met -> stop and ask before cutting anything; look checkpoint rejected -> rework
                          samples before any full art roll-out; a feature can't reach its tests -> park it in
                          PROGRESS with the next step, ship the rest.
```

## Previous goal (G7 "Last Protocol", owner-approved 2026-10-26; execution ordered 2026-10-26 "start G7"; branch `g7`)
Scope authority: the **G7 MASTER SCOPE** in `docs/G7_REFERENCE.md` (sections 0–13). Plan and agent roster: `docs/PLAN_G7.md`.
Briefs: `.plan/agents/prompts/G7-*.md` + `G7_COMMON.md`. Board: `.plan/board_g7.jsonl`. Everything else moved to G8 (same file).
```
GOAL — G7 "Last Protocol": Signalborne ports + counter-nanite line + Last Protocol mode
For whom / what changes:  the owner, playing: squads move and fight like a real military (formations, bounding,
                          wounds, casualty care, senses); you fly drones yourself; a late-game Counter-Nanite
                          facility fields the 20-soldier strike team, tactical operators, unhackable APCs and a
                          stealth dropship to purge Machine creep; 8 new Human A turrets; a new 1v1 mode, Last
                          Protocol, on a 512x512+ map with a 3-ring base, 3 living doomsday cores and the Tide.
Outcome:                  the G7 master scope in one packaged build, playable from a clean folder
Done-when (frozen 2026-10-26; light finish line by owner choice, owner verifies feel/look/balance by playing):
  1. Full test suite: 0 FAIL and 0 SCRIPT ERROR, including every G7 suite (tests/test_*7.gd).
  2. Determinism: every new sim system is same-inputs-same-result (two identical runs print the same hash),
     including a recorded player drone flight replayed from commands.
  3. Perf on an idle PC: 2k on screen p10 >= 60 fps, 10k zoomed out p10 >= 30 fps, 2k-unit sim ms/tick
     <= 1.2x the G6.1 figure measured in the same session.
  4. Last Protocol soak: a headless run on the 512x512+ map with the full pre-built base and AI-run strike teams
     reaches the Tide finale and ends with a result line, 0 crashes, 0 invariant failures, 0 SCRIPT ERROR.
  5. Packaged build launches from a clean folder with 0 SCRIPT ERROR; build copied to Downloads; README and
     PLAY_ME describe G7 accurately (limits included).
  6. Owner look checkpoint approved from the sample frame strips BEFORE the full art roll-out (strike team, both
     APCs, facility, both dropships, drone cam, grey fog, wound/crawl, armbands, staggered column, herringbone,
     2 turrets, packhunter, Weaver, living core).
Out of scope:             everything in the G8 SCOPE list of docs/G7_REFERENCE.md; the G6-parked items (10k speed,
                          soak winners) beyond not regressing them; balance beyond the features.
Stop-if / park-if:        determinism breaks and can't be fixed fast -> park that feature with a note; the 512x512
                          map can't meet the fps/sim gates -> stop and ask the owner before shrinking anything;
                          the look checkpoint is rejected -> rework the samples before any full art roll-out;
                          an agent's feature can't reach its tests -> park it in PROGRESS with the next step, ship the rest.
```
Status 2026-10-26 (ORCH): branch `g7` cut from `g6` at 55b4e04; G7 playtest flow names registered (tools/ui_playtest.gd,
`tools/pt7_<flow>.gd`); hb.sh defaults to board_g7. D: drive (USB) threw hardware I/O errors during setup: wave 1 was stopped before
it changed anything, the project was copied to C: (28,241/28,246 files; git fsck 0 errors; the 1 tracked file lost was restored
from git, the 4 lost untracked art-kit review renders are regenerable). **G7 runs on the C: copy; push back to D: only when
G7 is complete (owner).** Wave 1 relaunching on C:.

## G7 late additions (13.9c-39..54) — evidence (2026-10-30, C: tree)
Scope authority: `docs/G7_REFERENCE.md` entries 13.9c-39 … 13.9c-54. "Result" = the final-code full suite (every listed test file green) unless stated;
"last seen" numbers in the Built column are handoff-time and superseded by the final suite.

| Entry | What was built | Tests / flows | Result |
|---|---|---|---|
| 13.9c-39 roof mounts out of reach | melee, demolition and shaped charges cannot hit roof-mounted guns (CIWS); guns, rockets, artillery, aircraft still can | ciws7 flow (found it), test_ciws7 | green in the final suite |
| 13.9c-40 no pop cap in skirmish | owner choice recorded; PARKED, not built (skirmish keeps its 120 cap); facint7 flow parked with it | none | parked (stated, not a result) |
| 13.9c-41 LP map 768x768 | map 768, base C(80,80), flat footprint, centred facility, closed rings, validate() fails on gap / off-centre / uneven; skirmish lobby map can't replace the LP map; Machine side re-laid out | test_lpmap7, test_lpmode7, flows lpmap7, lpmenu7, lpmode7; soak seed 77 | green in the final suite |
| 13.9c-42 VTOL landing rules | regular VTOL lands on open ground or its big pad only; redirect from small helipads; loads APC / suits / infantry | test_vtol8, test_air, test_air_transport, flow vtol8 (last seen 17/0) | green in the final suite |
| 13.9c-43 fatigue + barracks rest | fatigue only from activity; firing fatigue capped at 0.4 (rifle ~0.18 / min, MG ~0.29 / min); idle soldiers >= 90% fatigue inside walls rest inside a barracks (bed-limited; Sentinel barracks admits Sentinels only), last man never pulled, breach stands to | test_rest8 (last seen 11/1: test_lp_gate_relief), test_sent7, flow sent7 | green in the final suite |
| 13.9c-44 strike team + spec-ops controls | `sim/systems/cn_mission8.gd` (PURGE MISSION drive/fly, step orders), `sim/systems/specops8.gd` (escort, raid, recon, rescue), command-bar buttons, team card, F4 strategic map, reason tooltips | test_cnmission8 (last seen 7/0), test_specops8, flows cnmission8 (last seen 21/0), specops8, cnops7, opsui7 | green in the final suite |
| 13.9c-45 aircraft return to own pad | returning aircraft land centred on their own pad, nearest free pad of the same kind otherwise | test_air (low heli returns to OWN pad), test_vtol8, flow air | green in the final suite |
| 13.9c-46 VTOL cargo | `a_vtol_dropship` bay: 1 APC + 2 suits + 10 foot; stealth bay unchanged | test_vtol8 `one_apc_two_suits_and_infantry`, test_air_transport (3 vehicles) | green in the final suite |
| 13.9c-47 lethality, blast throw, concussion | `sim/systems/ballistics8.gd` + `content/g7/rules_g8_rounds.json` (27 round classes, armour classes incl. `cn_apc`); `sim/systems/blast8.gd` + `content/g7/rules_g7_blast8.json` (flights, concussion, wake, BlastCorpse arc) | test_lethal8 (last seen 14/0), test_blast8 (last seen 11/11 in scratch copy), flow blast8, test_wound7, test_cnsim7 (known ON-only timing misses, see below), test_hot_state | green in the final suite |
| 13.9c-48 facility building cards | cards for command centre, defences, supply (magazine / fuel), armory, garage, barracks, air pads, aid, lab; supply8 airdrop retrieval op (`sim/systems/supply8.gd`: pod, 2x7 Sentinel GO teams, carrier + 4 engineers, +600 ammo / +400 fuel) | test_cards8b / test_cards8c / test_supply8, flows cards8a, cards8b, cards8c, supply8 | green in the final suite |
| 13.9c-49 realistic hit chance | `sim/systems/accuracy8.gd` multiplier in `Combat._fire` (range, flight time, shooter / target motion, sight picture, visibility, under fire, posture, training); rules in `content/g7/rules_g8_accuracy.json` | test_accuracy8, test_hot_state, perf pairs | green in the final suite |
| 13.9c-50 3-APC airlock | wash 6 long single lane, SALLY_CAP 3, door time 1.75 s, staging re-laid; four exit deadlocks fixed in `fac_drive7.gd`; return path (`_rev_claim_stop`, stale route cache) fixed | test_facexit8 (last seen 4/0: hardened 83.5 s, quiet 54.0 s; target ~70 s NOT met), test_facreturn8 (last seen 2/0), test_cnfac7 (last seen 36/0), test_path7, test_apcmov7, test_gate7, flows facexit8, apcmov7, gate7 | green in the final suite |
| 13.9c-51 cards in the bottom bar | `presentation/ui7/cardbar8.gd`: 9 cards + reserve + drone bay as tabs in the command grid, live strip above the bar, Tab / Shift+Tab | flows cards8a/b/c, dronebay7, lpres7 (patched to click tabs), test_ui_panels, test_ui_fit | green in the final suite |
| 13.9c-52 knock-down / throw / unconscious animation | presentation-only baked rig animation, 8 facings (launch, tumble, impact, settle, knock-down, unconscious, come-round) | test_anim8, flow blast8 / anim flow PLAYTEST 18/0, fps gates | green in the final suite |
| 13.9c-53 stray rounds, placement, daze | `sim/systems/stray8.gd` (miss line, friendly fire, StrayHit / FriendlyFire events), vital / limb zone weights in Accuracy8, daze `e.b8d` written by Blast8 | test_accuracy8 / stray tests test_accuracy8 20/0, test_hot_state, sim speed gate | green in the final suite |

Cross-cutting: full suite 170/170 files green, 1,405 checks, 0 failures, 0 script errors (.plan/suite7/SUMMARY.txt, 2026-10-30); test_hot_state 17/0 after regold; test_det7 6/0;
sim speed vs G6.1 idle **1.42x (18.86 vs 26.80 ms, gate 1.2x NOT met; owner accepted for G7, 13.9c-54)**; fps p10 2k 64.4
(gate 60) PASS, 10k 218.7 (gate 30) PASS; LP soak seed 77: 1,251 s, countdown defeat, 3/3 cores, no ring fallen, 0 script
errors; packaged smoke: pck md5 c1db446b5534fd06faf22fff6cdcc85e; clean-folder smoke lpmode7 18/0, lpmenu7 14/0, lpmap7 45/0, cnfac7 174/0, drone7 14/0, h 33/0, 0 script / load errors; Downloads/RTS_Age_of_Modern_War_G7_2026-10-30(.zip).

### Oracle / authority changes (late additions)
Every change below was recorded by ORCH or the owner; none weakens a gate except where stated. Sources: `docs/G7_REFERENCE.md`
13.9c-43, -47, -50 build notes and the board.
1. **Fortress balance not retuned (owner, 2026-10-29, 13.9c-47):** the 13.9c-33 / -38 hold-at-2.5x / break-at-4x oracle
   (test_sent7 `test_balance_fight`) is re-stated as a report, not a gate, if lethality changes its outcome. Result:
   held vs infantry x2 / x3, Machine x2.5, combined arms x2.5; fell to combined arms x4 (report only).
2. **Firing fatigue (ORCH accepted, board rest8.fire_fatigue_balance, 13.9c-43):** capped at effect_from 0.4 and not blocking
   recovery above it. Authority record for the G7 hash re-baseline that firing fatigue causes. test_sent7 13/0 with the cap.
3. **test_cnfac7 `test_facb7_enclosed_wash` link-piece count (ORCH, board test_cnfac7.linkcount "accepted", 13.9c-50):** now
   counts a wash side cell inside a solid building (the Suit Foundry) as wall: 12 link pieces instead of 14, corrected for the
   owner-approved new geometry. The strict "no foot / vehicle cell open beside the wash" check is unchanged.
4. **test_ciws7 re-silence (ORCH, board test_ciws7.setup, 13.9c-50):** `_silence(w, fac)` re-run before the inside-crawler
   spawn because lockdown pop-up guns spawn after the first call (LETHAL8D probe). Setup only; no assertion or threshold changed.
5. **test_ciws7 pin (ORCH, board ciws7.pin_target "APPROVED (setup only)", 13.9c-50):** `bursts_and_pauses` and
   `dry_drum_engineer_swaps_and_it_fires_again` pin the tough crawler (and t2) at its spawn with `_step_pinned`, as the ring
   sub-tests already do, since 2 extra link-wall entities shifted id cadences. Every assertion and threshold unchanged.
6. **Regold to come:** test_hot_state goldens (GOLD / GOLD_FLAT) move for owner-approved reasons (lethality, hit chance, stray
   rounds, firing fatigue, facility garage / engineer / supply8 state, airlock layout). To be re-baselined from two identical
   capture runs: DONE 2026-10-30, two identical gold61 runs (.plan/regold8/run1.log, run2.log), 16/16, test_hot_state 17/0.
7. **Open oracle candidates, NOT edited (owner / ORCH to decide):** test_cnsim7 pincer timing windows (LETHAL8D: group pincer
   on m_walker 1824 ticks vs window 900-1800 with lethality ON; colossus 3-5 min case); both pass in the final suite after the cn_apc / blocked_chem fixes, nothing edited.
   Further ORCH / owner setup rulings: lethality test-setup authority (turret7, dronebay7, specops8, eng7, life7, ai, gen61,
   factions, units_g5), test_formations7 shots floor 0.75x -> 0.5x G6.1 (OWNER, 13.9c-53), test_apcmov7 long-airlock
   gate-wait oracle (ORCH, 13.9c-50), sim gate 1.42x accepted for G7 (OWNER, 13.9c-54).
8. **Also open (not oracle changes):** 8-APC hardened exit ~83 s vs ~70 s target (the 90 s check passes, not tightened);
   sim cost 1.42x (native combat port next slice); rifles do not damage hardened buildings; no pod parachute-fall frame.

## G7 owner play-test follow-up (2026-10-29) — 768 map rebuild + packaging fixes — DELIVERED
Owner after playing d57bd8d: base not flat (hills, rivers), facility off-centre, rings not closed, map tiny. Their 19:52 game
log showed a 128x128 map (only skirmish maps are that size; the LP map was 512); not reproduced from the LAST PROTOCOL
button in source or the packaged build. Fixes:
- 13.9c-41 (owner choice "768 x 768, base near top corner"): sim/maps/last_protocol.gd N 768, base C (80, 80), facility
  centred (FAC_O = C - 14), footprint flat (level 1, no water/rock/forest/ramps), map validate() fails on any ring gap,
  off-centre facility or uneven footprint; Machine spawn (715, 715), cores far side; creep sources scaled for ~85 min.
- Skirmish lobby map can no longer replace the LP map (skirmish_setup.finalize skips mode last_protocol); new windowed
  flow lpmenu7 starts LP from the real LAST PROTOCOL button and checks the 768 map.
- Packaged builds failed to load ~15 PNGs (fac_life7 sprites, 4 CN unit sheets, base props/lights, aircraft shadows:
  raw Image.load_from_file has no file in a .pck) -> export-safe loads; smoke now counts load errors (0).
- Sentinels7.seed_facility spread the starting Sentinels over free cells (was one stacked muster point; separation pushed
  one 0.07 tiles into the barracks: test_path7).
Evidence (final code): suite 155 files, 1,283 checks, 0 SCRIPT ERROR, 1 red = test_thread snapshot timing probe under
6-lane load (4/0 x2 alone); test_hot_state 17/17. LP flows lpmenu7 14/0, lpmode7 18/0, lpres7 24/0, lpmap7 45/0. Soak
seed 77 tide 600 on 768: ending=defeat_countdown at 1,252 s, cores 3/3, 0 errors, 0 invariant failures, 42.59 ms/tick.
Idle perf: sim 1.132x G6.1 (16.53 vs 18.71 ms), fps 2k p10 72.5, 10k p10 261.0. Package md5 c5db62fe..., clean-folder
smoke 6 flows all /0, 0 script errors, 0 load errors; Downloads RTS_Age_of_Modern_War_G7 + _2026-10-29.zip.

## G7 Done-when evidence — FINAL (2026-10-28/29, C: tree, final code) — DELIVERED
Owner, 2026-10-28: "STOP focusing on the skirmish - I mainly want the end protocol game mode ** give me that packaged asap
in full totality with everything we've added in DEPTH--- leave the rest for next slice".
1. Full suite — MET. `bash .plan/suite_g7.sh 6` on the final code: `files=155 fail_files=0 err_files=0`, 1,281 checks pass,
   0 SCRIPT ERROR / Parse Error (.plan/suite7/SUMMARY.txt). Includes every tests/test_*7.gd.
2. Determinism — MET. test_hot_state 17/17 against the G7 goldens (re-baselined 2026-10-28 from two identical capture runs,
   .plan/regold7/run1.log == run2.log, 16 hashes); test_det7 6/6 (wall turret, drone-bay fight, APC traffic, LP compound
   attack, LP AI-on: same future after a deep save); test_determinism 5/5; test_drone7 recorded-flight replay in the suite.
   Gate scene hash 14f1c23c6ffd1d42 at tick 600 unchanged by all perf work.
3. Perf (idle PC, 0 other Godot processes) — MET.
   - Sim 2k vs G6.1 (55b4e04 worktree), 6 alternating pairs (.plan/perf7g_runs/final8_pairs.txt): median G6.1 18.55,
     G7 21.14 ms/tick -> 1.14x (gate 1.2x); pairs 1.106-1.185. Earlier same-day confirm run 1.117x.
   - fps (`tools/bench.gd -- --fps --fps-secs=30`): 2k on screen p10 74.3 (gate 60); 10k zoomed out p10 223.9 (gate 30).
   - Work that got there: PERFSIM7 exact fast paths (combat range factor / target checks, fog enemy-only visibility,
     morale cover) 1.219x -> 1.125x; PERFFPS7 (drone bay / reserve cards no longer force a sim join; motion/entity
     layer per-unit cost) 2k p10 50.8 -> 69-74.
4. Last Protocol soak — MET. `tools/lp_soak7.gd --seed=77 --tide-at=600` (.plan/lp_soak8.log): `LP SOAK RESULT seed=77
   map=last_protocol time_s=1269 ticks=25378 phase=4 tide=true tide_at_s=601 ending=defeat_countdown cores_alive=3/3
   rings_fallen=1 ... ms_per_tick=41.95`, 0 SCRIPT ERROR, 0 invariant failures.
5. Package — MET. .plan/package_g7.sh: import 0 errors, export 0, .pck 79 MB md5 4d99f6c99c72986f6555f4e5ad1a7689.
   Clean-folder smoke (build/_clean_G7_test, rts_core 0.5.5 loaded): lpmode7 18/0, cnfac7 174/0, drone7 14/0, h 33/0,
   0 SCRIPT ERROR. Copied to C:/Users/logan/Downloads/Age of Modern War/RTS_Age_of_Modern_War_G7 (+ _2026-10-28.zip).
   README G7 section and build/PLAY_ME_G7.txt rewritten for the final build (limits included).
6. Owner look checkpoint — MET (rev3/rev4, docs/G7_REFERENCE.md).
Extra checks: Last Protocol windowed flows on the final code (.plan/pt_lp8): lpmode7 18/0, lpmap7 44/0, lpres7 24/0,
ciws7 33/0, dronebay7 33/0, sent7 25/0, gate7 20/0 (x3; one earlier 15/1 under load -> the hardened-for-sally wait now
counts sim ticks, same 20 sim-s window), wallturret7 28/0, seq7 22/0, muzzle7 21/0. All 40 G7 flows were run earlier the
same day; the 8 red ones were fixed (art7f 17/0, ciws7 33/0, wallwalk7 19/0, wallturret7 28/0, eng7 19/0, apcmov7
23/0, gate7 20/0) except facint7 (parked, below).
Game bugs fixed in this last stretch: test_path7 (repath when a footprint rises across a planned path; boarders and
units entering a footprint keep their route), cargo-bay draw cache reset per world, gate deadlock during a sally
(airborne / wall-walk units no longer hold a gate; sally follow-stop), strike APC pair head-on deadlock
(counter_nanite._pair_follow), dropship boarding of a parked APC (fac_drive7 load release), decon walkway cleaning
(cn_facility._sweep_zone), 13.9c-39 roof mounts out of reach of ground melee / demolition (new; owner choice).
Parked for the next slice (owner): 13.9c-40 no population cap in skirmish; the skirmish-hosted all-in-one facility flow
facint7 (last run 97/10: night-assault phase fires nothing for 60 s before a save/load, facility security cameras not
placed (spec 13.9b asks for them), tactical APC garage-return lane-join fix unverified); same-owner separation lets a
soldier shove a driven APC sideways (SUITSIM7 note).
D: copy and push: pending (D: health check first; ask before any push).

## G7 Done-when evidence (2026-10-27, INTEG7 fast path, ~13:46-14:08 UTC) — DELIVERED, PARTIAL
Owner, 2026-10-27: "complete in next 15-20 min TOPS no excuses or running over that time". All runs were in parallel on a
busy PC (up to 18 Godot processes), so no timing number below is an idle-PC number. Raw logs: C:/CODING/integ7_fast/.
1. Full suite — NOT MET (1 fail, 1 file not run). 126 test files run one per process, 6 lanes (suite/*.log): 999 pass,
   1 fail, 0 SCRIPT ERROR / Parse Error. Fail: test_perf_g6 elevation probe "hook + elevation overhead 9.72 ms/tick at 2k
   <= 5" (timing under load; re-run on an idle PC). test_ui_fit: 308 screens at 7 resolutions, issues=0. test_maps 13/0,
   test_gen61 15/0 (REGRESS7-7 raid fix, 220fa03), test_ai 18/0. test_hot_state NOT RUN: the G7 re-baseline (two capture
   runs of .plan/gold61.gd) reached only 11 of 16 hashes each by the deadline (gold_run1.log / gold_run2.log; the 11 match).
   tests/test_hot_state.gd still holds the G6.1 goldens; INTEG7 regold script ready at C:/CODING/integ7_fast/regold.py.
2. Determinism — UNVERIFIED as a set: per-system twice-same-hash tests pass inside the suite (test_drone7 etc.), but the
   recorded drone flight replay and the raw collection were not run.
3. Perf — NOT MET / UNVERIFIED. 2k fight 600t native, river_crossing_s, alternating trees (.plan/sim_ab7.gd, G6.1 =
   C:/CODING/g7_regress2_wt at 55b4e04), busy PC (CPU 47-77%, 18 Godot): G6.1 39.35 / 42.30 / 42.40 ms, G7 63.99 / 75.08 /
   69.63 ms -> 1.65x (gate 1.2x). fps 2k/10k not re-measured (last shared-PC: 2k p10 63.5-71, 10k ~145-172).
4. Last Protocol soak — PARTIAL. Forced-Tide run (seed 77, --tide-at=600, wall cap 1080 s): THE TIDE started at 601 s,
   reached phase 4, 2 rings fallen, cores 3/3, 0 SCRIPT ERROR, exit 0, but ending=none at the wall cap:
   "LP SOAK RESULT seed=77 map=last_protocol time_s=1059 ticks=21171 phase=4 tide=true tide_at_s=601 ending=none ...
   ms_per_tick=51.01". Natural (unforced) run not done.
5. Package — MET with 2 playtest misses. Exported from 220fa03 (.plan/package_g7.sh): import 0 errors, export exit 0,
   .pck 48M md5 9b5cb4cd799d5b66dbd3ad70b5e73d33. Clean-folder smoke (build/_clean_G7_test): lpmode7 18/0, cnfac7 172/1
   ("cnfac7_ramp_all_loaded_f6_7 1 of 2 craft hold APC + crew + 8 operators"), drone7 13/1 (known: strike_drop blast
   ~6 tiles off the squad), h 33/0; 0 SCRIPT ERROR in all. Copied to C:/Users/logan/Downloads/Age of Modern War/
   RTS_Age_of_Modern_War_G7 (+ _2026-10-27.zip). README G7 section + PLAY_ME say PARTIAL.
6. Owner look checkpoint — MET (rev3/rev4 approved, see docs/G7_REFERENCE.md).
What's left: regold test_hot_state (finish 2 capture runs) and run it; idle-PC perf (sim is 1.65x G6.1: profile wounds /
senses7 / squads7); natural LP soak to an ending; drone replay determinism; fix cnfac7 f6_7 loading and drone7 strike
drop; remaining pt7 flows windowed; copy to D: after a D: health check.

## Previous goal (G6.1 "Field Command", owner-scoped 2026-10-26 via 5 questions; one big drop; branch `g6`)
GOAL — G6.1: massive new depth in AI and command, plus owner-reported fixes
For whom / what changes:  the owner, playing: every level of command thinks (general > commander > captain > lieutenant > squad > soldier);
                          AI commanders run whole wars on their own; squads fight as one unit; plans drawn on the map; realism (suppression,
                          fatigue, comms, veterancy, traits, intel/belief); company training works; unlimited market; longer fuel; ammo bearer
Outcome:                  the owner's G6.1 scope in one packaged build, tested and documented
Owner answers (2026-10-26): Q1 full chain of command; Q2 full general (budget, reinforcements, fire support, logistics); Q3 suppression +
                          fatigue, radio/comms, veterancy + traits, "EVEN MORE DEPTH" (intel/belief included); Q4 both control layers (classic micro +
                          command layer with plans on the map); Q5 one big drop. Earlier notes: company purchase spawns nothing (bug); no market cap;
                          fuel runs out too fast; ammo bearer restocks 3 units; smarter units, formations, team management.
Done-when (frozen 2026-10-26):
  1. Workstream tests pass (test_chain61, test_gen61, test_officers61, test_squad61, test_real61, test_plans61, test_bearer61, plus ORCH's
     company-training / market / fuel tests) and the full suite has 0 FAIL outside the G6-parked items, 0 SCRIPT ERROR.
  2. The 7 new flows (chain61 gen61 officer61 squad61 real61 plan61 bearer61), 3 ORCH flows (company61 market61 fuel61) and the 26 G6 flows
     pass from the packaged build in a clean folder, 0 SCRIPT ERROR.
  3. A 10-minute headless run with an auto general and no player input logs >=5 distinct operation types plus chain-of-command orders and reports.
  4. 2k-unit sim ms/tick <= 1.2x the G6 figure measured in the same session and load.
  5. New build in Downloads; README and PLAY_ME describe G6.1 accurately (limits included).
  Added by the owner 2026-10-26 (scope addition, recorded here as the authority; items 1-5 unchanged):
  6. Look and feel: every unit def has the new animation sets (test_anim61 / test_animb61 manifest checks), effects and sounds map
     to every listed event (test_vfx61 / test_audio61), radio chatter voices chain-of-command reports; the fps gates still PASS
     (2k on screen p10 >= 60 fps, 10k zoomed out p10 >= 30 fps); flows anim61 animb61 vfx61 audio61 pass (counted in item 2).
  7. Owner checkpoint: the owner approves the new look from the animation/effects frame strips (shots sent with SendUserFile).
     EVIDENCE 2026-10-26: owner "Approved: the G6.1 look and sound (animation, effects, sound, radio) is right." after the review set
     .plan/shots/ORCH61/review/ (g61_look_review.jpg, g61_tanks_moving.gif, g61_infantry_moving.gif, g61_sound_and_radio_sample.wav). MET.
Out of scope:             the G6-parked items (10k speed, soak winners) beyond not regressing them; the 200 supply ceiling; balance beyond the features.
Stop-if / park-if:        determinism breaks and can't be fixed fast -> park that feature with a note; a helper's feature can't reach its tests
                          -> park it in PROGRESS with what's done and the next step, ship the rest.
Agents: CHAIN61, GEN61, OFF61, SQUAD61, REAL61, PLAN61 (6 live), then BEARER61, ANIMA61, AUDIO61, VFX61, ANIMB61 as slots free; briefs `.plan/agents/prompts/G61-*.md`, board `.plan/board_g61.jsonl`.

**G6.1 Done-when evidence (2026-10-26 12:40 PDT) — DELIVERED, PARTIAL.** Build: `build/RTS_Age_of_Modern_War_G61/`, zip
`build/RTS_Age_of_Modern_War_G61_2026-10-26.zip` (also in Downloads, pck md5 64ec7c5ec3049d3d9598ecea4d2a7ed1), exported at d6261b3
(import exit=0 errors=0, export exit=0). Two later changes are not in that pack: the SquadAI idle early-out (hash-identical:
2k_fight/2k_mixed on+off == GOLD, .plan/hash61.gd) and the fps-mode mouse guard in match_view (measurement only).
1. Tests: workstream tests pass (gen61 15/15, real61 8/8, squad61 14/14, ai 18/18, mil 13/13, ...). Full suite 105 files: first pass
   98 green; every failure fixed (test_ai AI-02 fairness, test_mil rifle vs MBT, test_hot_state perf paths on != off = native
   gather ignored G6.1 movement multipliers) or load noise (test_editor_core 10/10, test_perf_g6 7/7, test_ai_g5 5/5 rerun alone at
   0-4% CPU); test_art_g4_fort launch failure rc=127 rerun 5/5; test_hot_state 17/17 after the GOLD re-baseline. MET.
2. Packaged playtests (42 flows, clean folder, 2 at a time): 34 pass fully, 0 SCRIPT ERROR in all; rerun alone: bearer61 passes
   (flake); 7 fail deterministically: g4b (mortar train click, also fails on the 09:51 build -> pre-existing), air (airfield
   engineers train click, VTOL cargo select 4 of 8), support (walk-out right-click), mines (2 laid), airdef (builders not selected),
   officer61 (air-assault company clears the outpost before the flank drill), vfx61 (0 craters). NOT MET.
3. Enemy/auto general: test_gen61 15/15 and gen61 playtest pass. AI-vs-AI soak, seed 7, 18000 ticks, river_crossing_s and
   coastal_front_m, general on vs off: rc=0, 0 SCRIPT ERROR, 0 INVARIANT FAIL, AI think avg 0.09-0.10 ms both ways, but
   companies=0 so the general has nothing to command (no AiGeneral events). The 10-minute auto-general operation-count check was
   not re-run here. Default stays OFF. UNVERIFIED as written.
4. Sim 2k (river_crossing_s fight 600t, native, alternating trees, CPU 2-14%): G6 16.40 / 14.32 ms, G6.1 19.21 / 19.11 ms ->
   1.25x (limit 1.2x). NOT MET (the squad early-out came after; not re-measured).
5. Build in Downloads + D:, README updated with limits. MET.
6. Look and feel tests/flows pass (anim61 animb61 vfx61-except-craters audio61); fps: 2k p10 57.6 (gate 60, export running at the
   time), 10k invalid (mouse wheel zoomed the window to 1.53; harness now ignores mouse input). NOT MET / UNMEASURED.
7. Owner approved the look. MET.
Next step: fix the 7 flows (start with the barracks train-button click and officer61's company template), re-measure fps and the
sim ratio on an idle PC (morale realism pass is the suspected cost: its leader map scans every unit every tick).
Follow-up 2026-10-26 13:30 PDT (owner: "fix the 7 failing playtest flows, then re-measure fps and the sim ratio on an idle PC"):
- Flows, from source, one at a time: g4b 68/0, air 98/0, mines 29/0, airdef 37/0, support 37/0, vfx61 14/0 (logs in scratchpad
  pt61/r2..r7). All causes were in the flows: card paging ("More"; G6.1 added card buttons), click during card re-layout (retry),
  G6.1 double-click = one squad (VTOL cargo now box-selected; walk-out selects its exact units), minefield density 0.45 ("all
  planned mines laid" / "own count unchanged" replace ">= 3"), a scout spawned beside the duel (recon drone over the town), the
  SAM-silent oracle counted the recon vehicle's carbine (now: 0 ShotFired from the SAM). officer61 still 14/3: drill sequence
  travelling > bounding > travelling > stack > assault > consolidate > defend; react-to-contact never starts because the outpost
  dies before the company's contact test (company centroid within contact_range 11); a lead-element trigger was tried and
  reverted (the flow still failed). Item 2 now: 41 of 42 flows green, officer61 open.
- FPS (idle, CPU 11-18%, 2 Godot procs): 2k p10 85.2 (gate 60) PASS; 10k zoomed out p10 262.5, zoom 0.15 lod 2 (gate 30) PASS. Item 6 MET.
- Sim 2k fight 600t native, alternating trees (CPU 10-18%): G6 14.81 / 14.97 ms, G6.1 18.42 / 19.18 ms -> 1.26x. Item 4 NOT MET.
  Suspected cost: Morale._realism_pass builds the leader map over every unit every tick for a 1/20 bucket.
- The Downloads build (pck 64ec7c5e, exported at d6261b3) is current for gameplay: later commits change test flows, a
  hash-identical SquadAI early-out and the fps-mode mouse guard only.
Follow-up 2 2026-10-26 14:50 PDT (owner: "get the sim cost under 1.2x G6 ... and fix the officer61 flank drill"):
- Item 4 MET: idle PC (CPU 2-9%), 6 alternating pairs, 2k fight 600t native: G6 15.39/13.92/14.11/14.33/14.70/14.71, G6.1
  16.96/15.84/17.27/17.98/17.41/16.52 ms; median 14.52 vs 17.12 = 1.179x (pairs 1.10-1.26). Changes (d601e1d), all hash-identical
  (2k fight/mixed on+off == GOLD; test_hot_state 17/17): Morale leader-candidate cache (verify_leaders full-scan check 0 mismatches
  over hash61, real61, officers61, companies, doctrine, gen61); rts_core 0.5.2 gather applies pin_move + mvm (no GDScript pass).
- officer61: root cause a formation bug (Movement._g61_shape grew with group size; a 50-man wedge/echelon put slots ~30 tiles back,
  clamped at the map corner, so the company marched back to base). Groups > 12 now chunk into <= 12 abreast (<= 12 bit-identical).
  officer61 from source 17/0; squad61 14/0, ops 10/0, officers61 11/0, doctrine 9/0.
- New build: pck ec9b69d49227681b99586a491ff4ea5e, rts_core.dll 4dc23240 (0.5.2), import exit=0 errors=0, export exit=0; packaged smoke
  (clean folder): officer61 16/1 (stack_up missed: contact > assault without stacking, timing-dependent), flick61 8/0, squad61 26/0,
  company61 41/0, air 98/0, h 33/0, 0 SCRIPT ERROR. Copied to Downloads + build zip. The full 42-flow packaged run was not repeated.

## G7 owner scope, first pass (2026-10-26, six-question pass during G6.1) — SUPERSEDED by docs/G7_REFERENCE.md (G7 master scope; the rest moved to G8)
- Q1 strategy: dynamic single-player campaign on a dynamic map; deeper single matches; richer gameplay; richer evolutions and upgrades;
  "wayyyyy better animations for the entire game and all movement (complete upgrade/overhaul)".
- Q2 economy: research tree overhaul; civilians and territory, inside the main single-player campaign.
- Q3 combat sim: destructible terrain; armour + ballistics (facing armour, penetration vs angle, weak spots, ammo types); EW, drones, cyber.
- Q4 units: named soldiers + careers; specialists + kits (per-soldier roles and gear inside squads).
- Q5 enemy AI: adapts to the player's style; named rival generals; diplomacy + multiple factions; difficulty by intelligence (not cheats).
- Q6 presentation: radio chatter + sound; visual effects overhaul -- MOVED INTO G6.1 by the owner 2026-10-26, together with the
  animation overhaul from Q1.
Not chosen this pass (kept as options): story campaign, multiplayer/co-op, physical supply lines, industry chains, weather/day-night,
wounds/field medicine, vehicle crews, cinematic camera/replays, after-action reports.

## Previous goal (G6 "Command & Terrain", owner-approved 2026-10-25: all defaults D21-D44; plan `docs/PLAN_G6.md`, contract `docs/CONTRACTS_G6.md`; branch `g6`) — DELIVERED, PARTIAL (see G6 evidence)
One continuous wave, up to 8 agents live (D21, owner override), 23 agents each with an operating guide (`.plan/agents/prompts/G6-*.md`; MECH6c and ART-G6b split out of MECH6a / ART-G6 for budget). Message board + semantic layer run all wave. Scope: the G6 owner notes and answers below (items 1-17).

```
GOAL - G6 "Command & Terrain"
For whom / what changes:  Owner fights on real high ground with companies and armies under a chain of command,
                          AI that fights like a military (and AI Commanders that assist), 89 new assets with
                          their systems (mines, garrisons, rail, subs, carriers, SAM/radar, counter-drone, ...),
                          exo-suits and loadouts, Stage 10, a marketplace, a new airfield, survival mode and
                          editor Live mode; G5 gaps fixed.
Outcome:                  One continuous orchestrated wave delivers a packaged G6 build that passes every check below.
Done-when:                PLAN_G6 section 12 (frozen):
                          1. tests/run.sh TESTS OK on the final commit incl. every G6 suite; 0 files in tests/pending_g6/
                          2. Quiet PC: 10k all-fighting avg <= 62.5 ms/tick on an elevated map; 2k on screen 60+ fps;
                             10k zoomed out 30+ fps (numbers reported either way)
                          3. AI soaks 4 maps x 2 seeds + 1 editor + 1 survival map: winners (Valley incl.), 0 invariant
                             failures, logs show companies/army, doctrine tags, mines, garrison, sub, carrier, market,
                             Stage 10, an AI-commanded player formation
                          4. Playtests: existing 12 + 14 G6 flows pass twice, incl. 2 at a time
                          5. UI fit 0 issues at 7 resolutions; 6. owner doctrine+elevation checkpoint passed;
                          7. packaged build passes all from a clean folder, copied to Downloads; README/perf/PROGRESS true
Out of scope:             weather + day/night and veterancy (G7), 4th faction (G7/G8), Stages 1-6 and 11-13, audio,
                          multiplayer
Stop-if / park-if:        determinism can't be restored; existing tests can't be kept green; elevation breaks the
                          path/render core beyond repair (park with a written note). Tests are never cut.
```

**G6 status (2026-10-25 ~10:00 local, ORCH heartbeat 3). Not done; no Done-when item is met yet.**
- Checkpoint commit `84ec0be` on g6 (tree compiles; heartbeat-2 suite 517 pass / 28 fail, every failure in an
  in-progress or queued owner's file).
- Finished (own tests green, --only runs; budget audits OK): ELEV, CONTENT6, ARMY6, MECH6a(-2), MECH6b, MECH6c,
  AIRDEF6, NAVAL6, EXO6, ECON-AIRF6(-2) (market, airfield v2, air map-edge clamp), ART-G6 (89 assets).
- Live: PERF6-3 (elevated GOLD drift bisect; 10k elevated 146-177 ms/tick under load vs 62.5), AI7-USE-4 (soaks:
  draws on Valley/Heartland/custom; no company formed and no Stage 10 reached in soaks yet), AI7-DOC (doctrine),
  AI7-CMD (AI Commanders), MODES6 (survival), ART-G6b (16 new pieces + airfield art), ELEV-VIEW, VIEW6.
- Queued: UI6a, UI6b, ED6, PT6.
- **Owner decision 2026-10-25: Done-when item 2 (10k elevated <= 62.5 ms/tick) is PARKED.** Last measurement 155.7
  ms/tick under shared load (PERF6-4); the remaining big win needs a HotState writer migration (~90 sites, 18 files).
  ORCH takes one clean quiet-PC measurement at the end; G6 is delivered as partial on this item.
- **Owner decision 2026-10-25: Done-when item 3 (soak winners) is PARKED.** Lane d6 (0 SCRIPT ERROR, 0 invariant
  failures): 5/11 winners (custom_s1, survival_s1, assist_s1, river_s2, coastal_s1); draws valley s1/s2, heart s1/s2,
  river_s1, coastal_s2 (salvage starvation; Valley drew 27/28 soaks since G5). Subs and Stage 10 never appear in soak
  logs (covered by test_ai_g6). Lane d7 retest stopped. G6 is delivered partial on this item.
- **Owner approved the in-game elevation look 2026-10-25** (.plan/shots/ELEV-VIEW-3/valley_conquest_plateau.png).
- ORCH decisions today (board facts orch.decisions / owner.decision): indirect fire counts at most 18 tiles toward
  the tier contact radius (+ G5 bucket floor 36; keeps G5 hashes); supply cap 200 with a built Company HQ, else 120
  (owner-confirmed); height left the SPEED/SIGHT hook rules (packed split, hash-exact); agents run only targeted
  tests (concurrent full runs clashed on user://) and must keep every intermediate write compiling (5 tree breaks).

## G6 Done-when evidence (2026-10-26) — DELIVERED, PARTIAL (items 2 and 3 parked by the owner)
1. Tests: full suite run 2026-10-25 reached 332 PASS / 0 FAIL before the machine slept (run stopped); the remaining 43 files ran as
   two shards: 41 files 313 PASS / 0 FAIL, 0 SCRIPT ERROR; the 2 that hit the shard timeout reran alone:
   `test_hot_state rc=0 SE=0 RESULT pass=17 fail=0`, `test_ui_fit rc=0 SE=0 ... FIT RESULT screens=210 controls=25879 issues=0` and
   `screens=180 controls=21968 issues=0 (scales 0.75,1.5) RESULT pass=3 fail=0`. Total 665 PASS / 0 FAIL. Logs .plan/shots/ORCH6/fin_*.log,
   fin2_*.log. Note: test_perf_g6's elevation probe passed in the shard (pass=7) but failed once under heavy load
   (`hook + elevation overhead 7.78 ms/tick at 2k <= 5`, CPU 90%) — load-sensitive timing check.
2. 10k perf — PARKED (owner 2026-10-25): `10000 placed native avg 296.5 ms p95 566.3` (CPU 100% busy browser), 143-156 ms under shared
   load earlier; target 62.5 ms. NOT MET. 2k river: avg 54.9 ms (CPU 97%).
3. Soak winners — PARKED (owner 2026-10-25): 5/11 configs produce a winner; Valley Conquest and Industrial Heartland draw. NOT MET.
4. Playtests: all 26 flows (12 G5 + 14 G6) passed twice in the tree, plus the owner checkpoint and fog-off retake; from the packaged
   build in a clean folder (.plan/package_g6.sh) 26/26 `PLAYTEST RESULT` ok, 0 SCRIPT ERROR.
5. UI fit 0 issues at 7 resolutions and scales 0.75/1.5 (item 1). FPS (windowed harness, CPU 97-99%): 2k on screen p10 83.7 fps PASS
   (gate 60); 10k zoomed out p10 111.1 fps PASS (gate 30).
6. Owner checkpoints: elevation look approved and locked (2026-10-25); doctrine checkpoint shots after/cp_14 and after_fogoff/cp_16 sent.
7. Package: C:/Users/logan/Downloads/RTS_Age_of_Modern_War_G6 (exe, console exe, .pck md5 e97c5f773876147ff06f002589bd8f68 = build/,
   rts_core.dll, PLAY_ME.txt); README "G6" section and PLAY_ME list the parked items with these numbers.

## Previous goal (G5 "Full Spectrum", owner-approved 2026-10-24: rev 4, all defaults D9-D20; plan `docs/PLAN_G5.md`, contract `docs/CONTRACTS_G5.md`) — DELIVERED, PARTIAL (see G5 evidence)
One continuous wave, up to 8 agents live (owner override), 18 agents each with an operating guide. Message board + semantic layer run all wave.

```
GOAL - G5 "Full Spectrum"
For whom / what changes:  Owner plays the air war, the naval war, 17 new human ground units (incl. Drone Team),
                          auto resupply + medical evac with hospitals, a refreshed UI with its own typeface,
                          fixed G4 gaps and a tutorial.
Outcome:                  One continuous orchestrated wave delivers a packaged G5 build that passes every check below.
Done-when:                1. tests/run.sh TESTS OK incl. every new G5 suite (PLAN_G5 section 12.1) and 0 files left in
                             tests/pending_g5/
                          2. Quiet PC: 10k all-fighting avg <= 62.5 ms/tick; 2k on screen 60+ fps; 10k zoomed out
                             30+ fps (numbers reported either way)
                          3. AI soaks on 4 maps x 2 seeds + 1 editor map end with winners, 0 invariant failures; logs
                             show sorties, >= 1 amphibious landing, auto resupply, med evacuations
                          4. Playtests pass: existing 6 + air + naval + drone team + auto resupply + med evac + tutorial
                          5. UI fit test: 0 clipped/overlapping controls at all 7 resolutions; new typeface everywhere
                          6. Packaged build passes all of the above from a clean folder, is copied to Downloads;
                             README / perf report / PROGRESS match reality
Out of scope:             submarines, carriers, true elevation, Stages 1-6 and 10-13, audio, multiplayer
Stop-if / park-if:        determinism breaks and can't be restored; existing tests can't be kept green; typeface
                          specimen not approved (continue on a placeholder font). Anything that runs long is parked
                          with a written note; tests are never cut.
```

### G5 evidence (2026-10-25, owner asked to finish now) — DELIVERED, PARTIAL
1. **Tests:** last full `tests/run.sh`: `RESULT pass=425 fail=8 files=57`. All 8 failures were then fixed and their files re-run alone:
   - test_air_transport 7/7, test_art 7/7, test_art_g3b 5/5, test_art_machine 4/4;
   - test_ai_g5 5/5 (`.plan/shots/ORCH/t_ai_g5_r3.log`, bench f0 1.386 ms at 5006 units), test_ai 18/18, test_ai_air_naval 8/8.
   - `tests/pending_g5/` holds only README.md.
   - A full-suite rerun after commit 3716861 was **not done**: owner asked to finish.
2. **Perf:** 10k all-fighting is about 94-101 ms/tick on a quiet PC (CORE10K-2/3 handoffs). The target is 62.5, so **NOT MET**.
   - gather_trust is now on (hash-proven); the projection with it is about 86-88 ms.
   - Breakdown and next steps are in `.plan/handoff/CORE10K-3.json`.
   - Windowed fps (2k at 60+, 10k at 30+): **UNVERIFIED**, not measured.
3. **AI soaks:** the f1 lane (AI6-2 code) had 0 invariant failures but only 1 of 9 winners (coastal s1). **NOT MET.**
   - Earlier a2/a3 lanes had winners on 7 of 9.
   - The cause identified was the air/naval savings hold, which starved unit production. It was fixed in 3716861 (now buildings only).
   - The soaks were **not re-run** on the fixed code. Next step: `TAG=o1 bash .plan/shots/AI6-2/run_lane.sh river_s1 river_s2 heart_s1 heart_s2 coastal_s1 coastal_s2 valley_s1 valley_s2 custom_s1`.
   - Valley Conquest has drawn on every code version so far.
4. **Playtests:** all 12 flows pass from a clean folder on the 3716861 build. MET, with two flakes noted:
   - h 33/0, hb 37/0, m 37/0, g4b 68/0, air 98/0, naval 32/0, drone 30/0, support 37/0, med 30/0, editor 25/0.
   - stages: 43/3 when run two at a time ("select builders" found 0 units, plus 2 cascades), then **53/0 run alone**.
   - tutorial: 54/8 when run two at a time (the Strike Jet click was refused right after the hangar buy), then **72/0 run alone**.
   - Logs: `build/_clean_G5_test/pt_*.log`, `pt_s2.log`, `pt_tut2.log`. The parallel-run flakes are a G6 item.
5. **UI fit:**
   - UI5b final: `FIT RESULT screens=273 controls=29508 issues=0`.
   - Main menu after the Tutorial button: `FIT RESULT screens=63 controls=7164 issues=0` (commit 7de3984).
   - The RTS Mil typeface is the theme default. MET.
6. **Package:** `build/RTS_Age_of_Modern_War_G5/` was re-exported after 3716861, and the clean-folder playtests were re-run (`.plan/shots/ORCH/package_r2.log`). It is copied to `C:\Users\logan\Downloads\RTS_Age_of_Modern_War_G5\` plus a zip.
- Commits cd011a7 → 3716861. Nothing pushed.

## Previous goal (G4a + G4e + G4b in parallel, started 2026-10-24; plan `docs/PLAN_G4.md`, contract `docs/CONTRACTS_G4.md`) — DELIVERED, PARTIAL (see G4 evidence)
Owner decisions (2026-10-24): D1 editor + naval/air pulled into G4 (DEC-G4-01); D2 8 new human land units (4 per Human faction); D3 Machine gets a small air/naval roster (G4c/G4d); D4 helicopters hover, jets sortie; D5 gunships carry troops or a slung vehicle (G4c); D6 no true heightmap (cliff + hill tiles); D7 REDUCED movement stride stays OFF; D8 no submarines.

```
GOAL - G4a Engine foundations + G4e Map & scenario editor + G4b Walls/transports/new units
For whom / what changes:  Owner gets smooth big battles, builds and plays fully custom maps/scenarios,
                          and fights with walls, gates, towers, troop transports and 8 new human units.
Outcome:                  Sim off the main thread with 10k-scale budget, new terrain/movement layers and
                          map files; an AoE/Stronghold-style editor; fortifications + transports + 8 units,
                          all used by the AI.
Done-when:                1. tests/run.sh TESTS OK incl new suites: terrain/move-class nav, gate team-pass,
                             threaded==unthreaded hash, map file round trip, triggers, 10k save/load,
                             walls/gates/breach, transports (load/unload/capacity/carrier death/save),
                             each new unit mechanic, editor brushes/symmetry/undo/validate
                          2. Quiet PC: 60+ fps with 2,000 fighting on screen; 30+ fps zoomed out with 10,000
                             on Valley Conquest while the sim runs; 10k sim p95 < 50 ms OR >= 0.8x speed
                             with smooth frames (number reported either way)
                          3. Editor: a playtest builds a map by clicks (terrain, river, lake, trees, 2 players
                             with HQ + units, symmetry, validate, save) and starts it from skirmish; an
                             editor-made map AI soak ends with a winner
                          4. AI soaks on the 3 built-in maps with walls, transports and new units in use end
                             with winners, 0 invariant failures; playtest: drag a wall + gate, load/unload an APC
                          5. Packaged build passes all playtests (3 factions, stages, walls/transport, editor)
                             from a clean folder; README / perf report / PROGRESS match reality
Out of scope:             aircraft + naval units (G4c/G4d; the water terrain and move classes ARE in scope),
                          tutorial + settings (G4f), true elevation, submarines
Stop-if:                  threaded sim can't be made crash-free (fall back to split-step, report);
                          determinism breaks; existing tests can't be kept green
```

### Next slice: owner notes (2026-10-24). Both are REQUIRED scope.
1. **10 more units/squads for the human faction(s)**, on top of G4's 8. The per-faction split is to be proposed in the plan.
2. **Fix every current known gap:**
   - 10k all-fighting speed. The lever is hot entity state in packed arrays in `world.gd` (SIM10K-2's CR).
   - The two Valley Conquest 3-side AI soaks that end in a draw. Start from AI5-4's work-in-progress (bank launch-army fix plus late bank drop; drop the retarget penalty); its patch is in `build/_ai5-4_wip/`.
   - Measure G4 windowed fps on a quiet PC.
   - Keep burnt ground after save/load (needs a sim-side burnt set).
   - Wire `Fortify.on_attack_move_blocked` in `movement.gd`, so player units breach walls too.
3. **Airfield + hangars** (owner note, 2026-10-24):
   - The Airfield is a massive landing strip. Aircraft physically take off from it and land on it.
   - Every air vehicle needs its own hangar. You buy and upgrade hangars per aircraft at your airfield; with no free hangar you can't buy a new aircraft.
   - Design gaps and defaults are to be settled in the next-slice plan: helicopters, runway traffic, hangar sizes and upgrades, losses, small maps, Machine equivalent, AI, UI.
4. **New unit: Airfield Engineer Team** (owner note, 2026-10-24). One purchase gives a squad of 4 units. Role and defaults go in the next-slice plan.
   - **Assigning:** select the engineers, then click the airfield or one hangar. Once assigned, they handle all upkeep on their own (repair, fixes, runway, hangar, airstrips).
5. **Airfield upgrade: +2-3 extra airstrips** for landing and launching (owner note, 2026-10-24).
6. **VTOL Dropship** for the human faction(s) (owner note, 2026-10-24):
   - an EXPENSIVE unit with massive air superiority;
   - carries 2 vehicles plus a squad of 8.
7. **Human Drone Team** (owner note, 2026-10-24; inspired by soldier-portable quick-launch drone systems):
   - 3 soldiers that move and select as ONE squad;
   - 4 launchable attack drones per squad, in different drone styles the squad picks per scenario;
   - once all 4 drones are spent, the squad switches to a tactical team: infiltration, takedown, breaching, stack-up and armored attack.
8. **Logistics truck "Auto" restock mode** (owner note, 2026-10-24): every nearby unit that needs restocking gets it automatically, one of two ways:
   - the units drive to the truck, restock and return to the fight;
   - or, with the truck placed in an area, the truck drives to them one by one.
9. **UI facelift** (owner note, 2026-10-24): interface, controls, screen layout and functionality all get an upgrade.
   - Everything on screen must FIT at all times, never cut off at the top, bottom or sides.
   - A custom, unique military-style modern typeface designed for this game.
10. **Medical auto mode + 2 new human buildings** (owner note, 2026-10-24):
   - A med team or med vehicle placed in an active area with wounded troops picks the wounded up with its team.
   - It evacuates them back to base, to a "Hospital" or a "Field Hospital", both new buildings for the human faction(s).
11. **Helicopters land anywhere open** (outside a base or wherever needed), not only on helipads. Helipads are restock/repair points, auto-serviced by Airfield Engineers (owner note, 2026-10-24).
14. **Typeface approved** (owner, 2026-10-24): "RTS Mil" approved in totality; apply it everywhere.
13. **Landing anywhere big enough** (owner note, 2026-10-24): VTOLs, gunships and helicopters land on any open area big enough for them, or at their pads/hangars (CONTRACTS_G5 §7).
12. **Up to 8 subagents at once** for this build (owner override of the default 6). Every agent gets its own role/task/operating guide (owner note, 2026-10-24).

### G6 (slice after G5): owner notes. REQUIRED scope, recorded 2026-10-24
**Plan:** `docs/PLAN_G6.md` was **approved by the owner 2026-10-25 with all default decisions D21-D44**. It is now the active goal (top of this file).
1. **Marketplace:** the player buys salvage, ore, etc. with credits (in-game money). Exchange rates are to be designed (scarcity pricing, fair for AI). Note: G5 soaks showed small maps running out of salvage, so the marketplace also fixes that late-game economy dead end.
2. **Airfield / runway / hangar overhaul:** a completely new design and layout.
   - Newly bought hangars are placed in a sensible spot next to the tarmac.
   - Owner idea: hangars connect directly to a main airfield base, which connects to the tarmac and runway. Layout options to be worked out in the G6 plan.
   - **Shorter runways** (owner, explicitly G6, NOT G5): the current strip_len is 26 tiles (airfield/aerodrome), 14 (airstrip), 10 (forward strip) and 12 (Machine launch rail), which is far too long. Shorten them as part of the overhaul.
3. **Every asset on the "G6 Arsenal Concepts" page goes into the game in G6** (owner note, 2026-10-24): units, turrets, fortifications, drones, vehicles, aircraft, ships and buildings. That is **89 assets**: the page's 93 minus the 4 Irregulars assets (see owner note 5).
   - Page: https://claude.ai/artifact/CqtGqskcCzkoCjPrhMWkgw
   - Source: `docs/g6_art_kit/` holds the proposal list in `items.json`, plus drawers that already render every asset with `tools/art` as game-schema sheets. It is not wired into content, sim or AI yet; see its README.
   - By category: turrets 15, fortifications 9, drones 9, vehicles 15, infantry 13, aircraft 4, naval 10, buildings 11, horizon 3 (the Stage 6 Rhomboid Landcrawler and the Stage 10 Laser Tank and Exo-Suit Trooper). By faction: Human A, Human B, Machine and shared.
   - Each asset has to become playable: content defs, art moved into an `assets/art/g6_*` module, sim mechanics, AI use and tests.
   - Scope the G6 plan has to settle (big items inside this note):
     - new systems: minefields + EOD/mine clearing, garrisons, trench/sandbag cover, rail tiles + armored train, submarines + sonar, carriers (the hangar system at sea), radar-gated SAMs, counter-drone (laser, nets, jamming), tethered recon;
     - **Stage 6 and Stage 10** units: rhomboid landcrawler, laser tank, exo-suit trooper.
     - Submarines and carriers were out of scope in G5 (D20) and are in scope now.
4. **Map editor "Live" mode** (owner note, 2026-10-24): a toggle in the editor that is easy to switch on and off.
   - With Live on, units placed for different factions behave as in a live match or skirmish. When they are close enough, they start fighting on their own.
   - Reference: the Stronghold and Age of Empires III editors.
   - Toggling off returns to normal editing.
   - Details for the G6 plan:
     - whether Live pauses or rewinds when switched off;
     - whether the AI economy and production also run, or only combat;
     - the speed controls;
     - how undo behaves for units lost during Live.
5. **The 4th faction is out of G6** (owner note, 2026-10-24). The Irregulars faction and its 4 assets (Technical, Tunnel Network, Ambush Cell, Captured Tank) are removed from the G6 plan, to be raised again possibly in G7 or G8.
   - Their drawers stay in `docs/g6_art_kit/` (`x_*` ids in `g6_horizon.gd`, `g6_infantry.gd`), but G6 does not integrate them.

#### G6 scoping answers (owner, 2026-10-24, five-question pass). REQUIRED scope
6. **Delivery:** one continuous orchestrated wave (like G5), ending in one packaged build. Not split into G6a and G6b.
7. **Stage 10 becomes playable** ("Automated Technocracies"): an advancement gate from Stage 9 and its own unlocks. Its units are the Laser Tank, Exo-Suit Trooper, Mass Driver, Colossus Walker, Hover Tank, Assimilator, Swarm Queen, Mimic Drone, Stalker Synth, Stealth Strike Drone and Overmind Uplink. The Rhomboid Landcrawler moves to Human B at **Stage 7** as an early heavy. Stage 6 stays unplayable.
8. **True elevation** (owner, 2026-10-24; this reverses G5 D20, where it was out of scope): real terrain height in place of the G4 cliff and hill tiles.
   - Height affects sight, weapon range, cover and movement.
   - The map editor gets height brushes.
   - Rendering, pathing and fog must handle it.
9. **Wave / survival mode:** new victory types, "Repel all waves" and "Survive mm:ss" (vision images 03-04), a natural showcase for the new defenses.
10. **AI upgrades.** The baseline is that every AI uses every new unit and system. On top of that:
    - **AI Commanders** (owner design, still to be worked out properly):
      - assist commanders on the player's side, each with its own playstyle;
      - they make in-game decisions on their own, without asking for approval;
      - they are meant to ASSIST the player, NOT play the game for them.
      - The G6 plan must define:
        - what a commander controls (a group, a sector, a role such as air or logistics);
        - how the player assigns, reins in or dismisses one;
        - the playstyles;
        - how to keep it from fighting the player's own orders.
    - **Ally AI commands:** in team games the player can order an allied AI to "attack here", "defend me" or "send air support".
    - **Wave AI:** a dedicated attacker for survival mode that builds escalating waves.
11. ~~Veterancy / unit XP~~ **MOVED TO G7** (owner, 2026-10-25). Not in G6.
12. **Research upgrades** for the new units and defenses, extending `research.json` (e.g. better mines, CIWS range, armor kits).
13. ~~Weather and day/night~~ **MOVED TO G7** (owner, 2026-10-25). Not in G6.
14. **Infantry loadout upgrades and enhancements, plus exoskeleton armour suits** (owner: "think Iron Man armour"). Infantry can be upgraded with new loadouts and gear, up to powered exo-suits. The G6 plan must define how this relates to the Stage 10 Exo-Suit Trooper unit.
15. **Companies and armies (army builder)** (owner notes + design chat, 2026-10-25). Builds on the G2 officer groups (`ops.gd`) and the G5 squads.
    - **Company:** a pre-organized formation of **15-45 elements MAX** (element = one squad or one vehicle) of specialized units, trained as one order and commanded as one bigger squad.
    - **Templates: presets + custom.**
      - Each faction ships preset company types, for example:
        - A: Rifle, Mechanized, Armored, Artillery Battery, Air Assault, Engineer, Special Ops;
        - B: Conscript Battalion, Shock Assault, Heavy Armor, Siege Battery, Works;
        - Machine: Swarm Cluster, Walker Phalanx, Siege Array, Hunter Pack.
      - An **Army Builder** screen lets the player design, save and train their own templates within slot rules and the 45 cap.
    - **Training: a new Company HQ building** (one per faction, styled per faction) trains whole companies itself and spawns them all at once.
    - **Chain of command:**
      - each company has a **captain** and **lieutenants**, one lieutenant leading each platoon;
      - leaders are real units in the company.
    - **Armies:** join 2-4 companies into an **army**. This needs a **Commander unit in play**; the Commander becomes the army's top leader (army -> companies -> platoons).
    - **Limits for now:** up to 4 companies per army and 2 armies per player.
    - **Leader loss: the next in line steps up.**
      - Captain dies -> the senior lieutenant is field-promoted (short confusion + morale hit).
      - Commander dies -> the army splits back into its companies until a new Commander joins them.
      - Nothing dissolves outright.
    - **Still to settle in the G6 plan:**
      - cohesion bonuses while together;
      - auto-replenishment of losses;
      - cost and population rules;
      - company / army cards in the HUD (vision image 05);
      - the AI training and using companies;
      - letting an AI Commander (item 10) run a company or an army.
16. **Exo-suit garage + exo-suit soldiers** (owner note, 2026-10-25). A new, smaller building (an exo-suit garage / suit bay) that trains exo-suit soldiers.
    - Reference: the AMP suits from *Avatar*. A pilot in a walking armoured exo-suit, about 2-3x a soldier's height.
    - Heavy weapons: oversized assault rifles, shoulder or arm missile tubes, and similar.
    - Fits with item 14 (infantry exo armour upgrades) and the Stage 10 Exo-Suit Trooper.
    - The G6 plan must settle:
      - the suit roster and variants (e.g. rifle suit, missile suit, AA or breacher suit);
      - which factions get them (Human A sleek, Human B crude welded; the Machine has no pilots, so maybe none);
      - stage gating;
      - how they count against squad / company slots (item 15);
      - repair and resupply at the garage;
      - the pilot surviving (ejecting) when the suit is destroyed.
17. **AI command structure with true military strategy and focus** (owner note, 2026-10-25). Every AI command level (Commander -> army -> company captain -> platoon lieutenant, plus AI Commanders and enemy AI) has to fight like a real military:
    - positioning troops correctly: terrain, cover, high ground (item 8), overwatch, flanks, depth;
    - formations and structure;
    - attacking: combined arms, fire and manoeuvre, suppression then assault, breaching;
    - special ops missions: raids, sabotage, recon, sniping officers;
    - exfil missions: extracting squads, wounded and VIPs under fire;
    - and the rest of real doctrine: defence in depth, retreat and regroup, reserves, logistics, timing.

#### G6 design answers (owner, 2026-10-25, second question pass). These settle the open details above
- **Marketplace (1):** buy AND sell. Prices move with what every player trades (scarcity), and the AI uses the same market.
- **Airfield (2):** the airfield base has fixed hangar slots along the tarmac. Buying a hangar auto-fills the next free slot.
- **Editor Live mode (4):**
  - switching Live off **rewinds** the map to exactly how it was placed, so it is a repeatable test;
  - Live runs **combat + AI tactics** (units fight, and AI positions and moves them). There is **no economy or production**.
- **True elevation (8):** 4 height levels (valley, plain, hill, ridge) with slopes and ramps between them.
  - High ground gives sight, range and defence bonuses.
  - The editor gets raise, lower and smooth brushes.
- **Weather and day/night (13), for G7:** a skirmish setup option: Off, Fixed (pick the weather and time) or Dynamic (weather fronts plus a day-night cycle during the match).
- **Wave / survival (9):** works on any skirmish or editor map, with attackers spawning from the map edges, plus **2 new purpose-built stronghold maps** like vision images 03-04.
- **Veterancy (11), for G7:** 3 ranks (Veteran / Hardened / Elite) shown as chevrons. Each rank adds accuracy, HP and morale. Companies and armies track their own pooled XP.
- **AI Commanders (10):**
  - you hand one **a formation** (company or army) **or a role** (base defence, air ops, logistics, naval);
  - you steer it with an **objective** (take / hold / raid / escort) plus a **stance** (cautious / balanced / aggressive);
  - your direct orders on a unit always override it for a while, and you can recall it at any time.
  - **All four playstyles:** Defensive / fortifier, Aggressive / breakthrough, Special ops / raider, Combined arms / balanced.
- **Enemy AI (17):** uses the **same military doctrine**: companies, armies, chain of command and tactics. Fair, same rules.
- **Exo-suits (16):** **Human A only** (sleek AMP suits, e.g. rifle, missile and AA variants). The Machine has its walkers instead, and Human B gets none.
  - A destroyed suit **ejects its pilot** as one wounded soldier, who can be evacuated (G5 medical) and re-suited at the garage for less.
- **Infantry loadouts (14):** chosen **per squad at a barracks** (or the Company HQ) for a cost, e.g. assault, AT, marksman, breacher, armour plates. Exo armour is the top tier.
- **Company refill (15):** losses **auto-request replacements at the Company HQ** (toggle per company). Replacements travel to the company (lower veterancy only once G7 adds veterancy).
- **Still out of scope for G6:** Stages 1-6 and 11-13, audio, multiplayer, and the 4th faction (G7 or G8).
- **Moved to G7** (owner, 2026-10-25): weather + day/night (13) and veterancy / unit XP (11). Their answers above are kept as G7 design input.

### G4 evidence (2026-10-24, owner asked for the packaged build within 30 min) — PARTIAL
1. **Tests:** `bash tests/run.sh` → `RESULT pass=297 fail=0 files=35 time_ms=1970802` / `TESTS OK` (log `build/final_suite_G4.log`). MET.
   - The run covered all of 59afdcf plus AI5-4's uncommitted AI edits, which were in the tree at the time.
   - The shipped AI, 32eddf7, passed test_ai 18/0 in AI5-3's run.
2. **Perf:** `perf/PERF_REPORT_G4_2026-10-24.md`. Sim avg/p95 ms:
   - 2k fight 21.3/36.1: MET.
   - 10k march 63.2/85.9: at the avg bound, p95 over.
   - 10k fight 104.3/131.1: **NOT MET** (about half speed).
   - Every A/B state hash was equal to HEAD.
   - G4 windowed fps (2k fighting 60+, 10k zoomed 30+): **UNVERIFIED** (not re-measured on a quiet PC).
3. **Editor:**
   - editor playtest 25/0 (ED3, commit 121cd89);
   - an editor-made map soak, custom_front s1: `winner=0 end_tick=96442 reason=hq_elimination`, INVARIANTS fails=0 (`.plan/shots/AI5/soak_custom_front_s1.txt`, AI5-2 code);
   - clean-folder editor playtest: see 5.
4. **AI soaks:** 0 invariant failures in every run.
   - Winners: heartland s1 and s2, river s1, custom_front s1 (on cfe7bc5-era code), and river s2 (d2, commit 32eddf7: `winner=0 end_tick=86554`, breaches 3/7/2).
   - **valley_conquest_l s1 and s2 still DRAW** at max_ticks (d2: hashes 88bb7510…, ff48173b…). **NOT MET.**
   - The 4 winners above were not re-run on the 32eddf7 code.
   - Walls, gates, transports and the new units are used in every soak (SOAK G4B lines). The AI now breaches walls.
   - In-progress AI5-4 work (stage-bank launch-army fix plus a late bank drop plus retargeting) is **uncommitted in the tree** and was not shipped. Its handoff is `.plan/handoff/AI5-4.json`. Next step: keep the bank fix and lever (a), drop or decay lever (b), then rerun the valley soaks and all 7 configs.
5. **Package:** `build/RTS_Age_of_Modern_War_G4/` + `build/RTS_Age_of_Modern_War_G4_2026-10-24.zip` (91.6 MB), also copied to `C:\Users\logan\Downloads\`.
   - Exported from commit 59afdcf. AI5-4's work-in-progress was set aside for the export; its patch is in `build/_ai5-4_wip/`.
   - Run from a clean folder (`build/_clean_G4_test`), each printing `NATIVE rts_core loaded (rts_core 0.3.1)`:
     - human 33/0
     - human_b 37/0
     - machine 37/0
     - stages 53/0
     - walls/transports (g4b) 68/0
     - editor 25/0
   - MET. Owner decision (2026-10-24): 10k smoothness does not block delivery; it is tracked going forward.
- Commits: 84d28b3 → 59afdcf. Nothing pushed.

## Previous goal (G3b + Scale "Big Armies", started 2026-10-23, owner-approved: stage gates + Rust core) — PARTIAL, see evidence

```
GOAL: G3b + Scale "Big Armies"
For whom / what changes:  Owner picks from 3 maps, starts each side at Stage 7, 8 or 9, researches and advances
                          mid-match, and fights battles with thousands of units without lag.
Outcome:                  The rest of the approved G3 slice (3 maps, Stage 7->8->9) on a sim and renderer that hold
                          2,000 fully simulated units and 10,000+ on the large map.
Done-when:                1. tests/run.sh TESTS OK, all existing tests plus MATCH-01 (3 sides at stages 7/8/9),
                             QA-002, QA-014, gate refuse/pass, research, native-core determinism + save round trip
                          2. On each of the 3 maps, a 3-faction AI soak with mixed start stages ends with a winner;
                             the logs show an AI advancing 7->8 and 8->9
                          3. This PC: 2,000 fully simulated fighting units within the 50 ms budget (p95);
                             10,000 units on Valley Conquest within budget; windowed 60+ fps with 2,000 fighting
                             on screen, 30+ fps zoomed out with 10,000
                          4. The packaged build passes the 3 faction playtests, extended to pick a map + stages
                             and to research by clicking; the perf report + README match reality
Out of scope:             naval, aircraft beyond drones, walls/gates, Stages 1-6/10-13, audio, 5+ sides
Stop-if:                  native DLL won't load in the packaged exe; determinism breaks; existing tests can't stay green
```
Contracts: `docs/CONTRACTS_G3b.md`.

## G3b + Scale Done-when evidence (2026-10-24, overnight)
Orchestration: 6-agent waves; about 30 builder agents including successors. Every budget audit was OK.

1. **Tests: MET.** `bash tests/run.sh` on the final sim code gives `RESULT pass=200 fail=0 files=22` / `TESTS OK` (`.plan/shots/ORCH-final/full_suite.txt`). New suites:
   - test_stages 13: MATCH-01, QA-002, QA-014, each gate refused/passed, cost charged once, no spawn on advance, research pause/resume, save mid-research/transition, EW;
   - test_maps 11; test_native 12; test_perf 7; test_perf_systems 3; test_art_g3b 5;
   - test_ai 17, including stage-7 gating, research/advance, big map, per-resource bank, ammo-tight production.
2. **AI soaks on the 3 maps: MET for winners, with a caveat on advancement.** Final code, `.plan/shots/ORCH-final/soak_*.txt`; hashes reproduce AI4-5's batch exactly; 0 invariant failures.
   - river_crossing_s: s1 winner=0 @30428; s2 7->8 @41641, winner=0 @105813.
   - industrial_heartland_m: s1 8->9 @49541, winner=0 @81944; s2 draw @120000.
   - valley_conquest_l: s1 7->8 @28881, winner=1 @65897; s2 7->8 @37281, 8->9 @118541, draw.
   - **Caveat:** both 7->8 and 8->9 appear in the logs, but on the final code no single soak shows 7->8, 8->9 AND a winner. Earlier code did: river s2 in AI4-4 v1/v2; valley s1 in AI4-4 v3. Two of the six final soaks draw.
3. **Scale on this PC: PARTIAL** (`perf/PERF_REPORT_G3b_2026-10-24.md`, quiet machine).
   - **MET:** 2,000 FULL fighting units, native: avg 29.5 / p95 38.3 ms per tick, under the 50 ms budget. G3a was about 140 ms.
   - **NOT MET:** 10,000 units on valley_conquest_l: avg 86.7 / p95 124.1 ms, so the game runs at about half speed.
   - **NOT MET:** windowed 60+ fps with 2,000 fighting. Measured 22 avg, because `world.step()` runs on the main thread. Rendering alone is 71 fps at 2,000 paused.
   - **NOT MET:** windowed 30+ fps zoomed out with 10,000 on valley while the sim runs. Measured 7.5, sim-bound. Rendering alone is 171 fps.
4. **Packaged build + playtests: MET.** `build/RTS_Age_of_Modern_War_G3b/` (zip `build/RTS_Age_of_Modern_War_G3b_2026-10-24.zip`): export-pack + renamed 4.7.2 exes + `rts_core.dll` beside the exe. The pack excludes docs/ and native/ sources.
   - Run from a clean folder outside the repo: `NATIVE rts_core loaded (rts_core 0.2.2)`.
   - `PLAYTEST RESULT` human_a 37/0, human_b 37/0, machine 37/0, and stages 53/0 on Industrial Heartland: stages 7/8/9 picked by clicks, research building built, project started by click, gate panel shown.
   - After a one-line menu text fix the build was repackaged; the stages playtest was re-run, 53/0.
   - README and perf report updated to match.

**Parked, with the exact next step (sim off the main thread):** R5-thread found two blockers:
- gdext aborts when native objects are touched from a worker thread. It needs `godot` features `["api-4-7","experimental-threads"]` in `native/rts_core/Cargo.toml` plus a DLL rebuild.
- A deep copy of `w.entities` costs about 22 ms at 2k, so the render side needs a compact per-tick render snapshot (`w.cache.unit_snap` is a start), not a world copy.

Then step the world on a WorkerThreadPool task between frames, with HUD reads only while no step is in flight. A worker-thread step with native off was hash-equal to a main-thread step, so determinism is not at risk.

**Owner decisions pending:**
- **REDUCED movement stride:** it saves about 34 ms per tick at 10k, but it is not outcome-exact (16 seeds: one winner flip). It is OFF because of CONTRACTS_G3b §0.
- **Stage cost pacing:** credits come only from the 6/s HQ stipend, so the 8->9 bank (9,600 credits + 1,400 ore including research) takes about 27 game minutes.

## Previous goal (G3a, DONE 2026-10-23)

```
GOAL: G3a "Factions + Skirmish"
For whom / what changes:  Owner picks from 3 distinct factions (Human A modern, Human B industrial, Machine network),
                          sets up 2-4 side FFA or team skirmishes with per-side faction/team/credits/difficulty,
                          chooses victory (HQ kill, territory %, hold bridge, AND/OR, Endless); AI plays every faction.
Done-when:                1. tests/run.sh TESTS OK incl. faction/teams/territory/AND-OR tests (MATCH-01, VICT-01,
                             QA-005, QA-011/012) + all G1/G2 tests
                          2. 3-side FFA soak (one per faction) and a 2v2 soak each end with a winner
                          3. Rebuilt .exe passes a UI playtest that sets up a 3-faction match via the menu and
                             plays Human B and Machine openings (screenshots)
                          4. Perf report re-run
Out of scope:             new maps + Stage 7->9 (G3b); naval/air beyond Machine drones; audio
Stop-if:                  G1/G2 tests can't be kept green
```
Contracts: `docs/CONTRACTS_G3a.md`. Scaffold `48332f1`.

## G3a Done-when evidence (2026-10-23)
1. **Tests:** `bash tests/run.sh` gives `RESULT pass=144 fail=0 files=16` / `TESTS OK` on AI commit `e8a8464` (final code).
   - G3a suites: test_factions 12, test_victory 13 (VICT-01 territory 60%, sticky/recapture, QA-011 endless, AND/OR), test_art + test_art_machine, test_ai incl. 3-4 side cases, plus all G1/G2 tests.
2. **AI-vs-AI soaks** (normal, `tools/soak.gd`, all on final code incl. the supply-truck escort fix): **10/10 end with a winner, 0 INVARIANT FAIL.**
   - 3-side FFA (Human A, Human B, Machine): seed1 winner f0 @26443, seed2 winner f0 @46734, seed3 winner f1 @29311.
   - 2v2 (A+Machine vs B+A): seed1 team 1 @22373 (5 tolerated pop-cap notes), seed2 team 1 @26185.
   - Mirrors seeds 1-3: f1 @11573, f0 @18831, f0 @11980. Territory 60%: f0 @14960. Hold bridge 300 s: f0 @19780.
   - Before the escort fix, FFA seeds 2 and 3 hit max_ticks (supply trucks left attacking waves to repair, so waves ran dry); fixed in `sim/ai/ai_logistics.gd`.
   - FFA seed 2 is slow (46734 ticks, about 39 min of game time).
3. **Packaged UI playtest:** `build/RTS_Age_of_Modern_War_G3a/` (zip `build/RTS_Age_of_Modern_War_G3a_2026-10-23.zip`), copied to a clean folder outside the repo, run with `--ui-playtest-faction`.
   - The playtest sets up a 3-faction, 3-team match by clicking the skirmish menu, then plays the faction opening (build, gather, barracks, train, attack-move, officer + mission).
   - Human B `PLAYTEST RESULT pass=37 fail=0`; Machine `pass=37 fail=0`; Human A `pass=37 fail=0` on rerun.
   - **Flake:** Human A's first run (first launch of the new build) failed `match_started` within the 10 s wait, with no errors logged. The immediate rerun passed. Likely a cold-start load delay; not root-caused.
   - Shots: `.plan/shots/orch/ui_g3a/` (3-faction menu, Human B officer mission, Machine attack-move, both factions' barracks equivalents).
4. **Perf:** `perf/PERF_REPORT_G3a_2026-10-23.md` (quiet machine).
   - Sim: no regression vs G2. At 512 units, 27.6 avg / 43.2 p95 ms (G2: 29.1 / 42.4). Cap stays 512.
   - Window fps with 3 sides: 60 / 42-52 / 10-21 at ~80 / ~160 / 250-400 units.
   - **Known gap:** large fights lag. A follow-up profile showed the cause is not the side count (3 sides cost +10% sim time). The limits are the GDScript sim (~65 µs per unit-tick, so 1,000 units = ~70 ms per tick) and per-unit sprite rendering (~12 ms per frame at 1,000), both on the main thread.

Known gaps carried forward:
- Large-fight lag (above). The owner has made scale the priority for the next slice.
- First-launch playtest flake (above).
- The Machine top bar still shows Fuel, though Machine units don't use fuel (cosmetic).
- The packaged build excludes `docs/` (vision mockups are reference only, not shipped). `docs/vision/.gdignore` keeps Godot from importing them.

Next: G3b (Industrial Heartland + Valley Conquest maps, Stage 7->8->9). Needs an owner decision on stage-gate thresholds.

## Previous goal (G2, DONE 2026-10-23)

```
GOAL: G2 "Smart Warfare" slice + vehicle/building art detail pass
For whom / what changes:  Owner plays the same River Crossing match with real tactics: cover, suppression,
                          flanking armor, crippled vehicles, ammo/fuel logistics, officers running missions,
                          a destructible/repairable bridge; the AI uses all of it.
Outcome:                  Roadmap G2 deliverables working in the packaged .exe + more detailed vehicles/buildings.
Done-when:                1. tests/run.sh TESTS OK incl. G2 acceptance (MIL-02, QA-007/008, supply conservation,
                             officer multi-step mission + reports) and all G1 tests
                          2. AI-vs-AI soak seeds 1-3 end with a winner; logs show AI resupply + broken-unit retreat
                          3. Rebuilt packaged .exe passes an extended UI playtest (officer -> mission -> status shown)
                          4. Perf report re-run with the 256-unit number published honestly
Out of scope:             3 factions, 3 maps, Stage 7->9 (G3); naval/air; audio
Stop-if / park-if:        G1 tests can't be kept green, or sim drops below ~128 units at 20 Hz
```
Contracts: `docs/CONTRACTS_G2.md`. Scaffold commit `d878ba1`.

## G2 Done-when evidence (2026-10-23)
1. **Tests:** `bash tests/run.sh` gives `RESULT pass=100 fail=0 files=12` / `TESTS OK`, run by ORCH after the last sim change.
   - New: test_damage (10), test_supply (10), test_ops (10), test_g2_scenarios (7: MIL-02/QA-008, QA-007 + supply,
     officer resupply, morale + officer death, 3000-tick conservation brawl, save@1500, determinism), plus test_ai G2 (+2).
2. **AI-vs-AI soak** (normal, `tools/soak.gd`, final code): seeds 1-3 end in HQ elimination.
   - seed1 winner=1 @28749, seed2 winner=1 @23426, seed3 winner=0 @15646.
   - 8-seed sweep: 7 decisive, 4/3 side split. **Seed 4 reaches max_ticks (stalemate), a known gap.**
   - 0 INVARIANT FAIL (incl. G2 invariants).
   - Probe logs show the AI training officers and trucks, resupplying (pull/refill counts), repairing and flanking.
3. **UI playtest:** `tools/ui_playtest.gd` now drives input through `Input.parse_input_event`.
   - Covers the G1 flow plus G2: train officer, box-select squad + officer, Assign button, Secure point button + map click, mission in progress, 3 reports.
   - Result: `PLAYTEST RESULT pass=26 fail=0` from source, and twice from the packaged build
     (`build/RTS_Age_of_Modern_War_G2/`, zip `build/RTS_Age_of_Modern_War_G2_2026-10-23.zip`).
   - Shot: `.plan/shots/orch/ui/ui_07_officer_mission.png`.
4. **Perf:** `perf/PERF_REPORT_G2_2026-10-23.md` (quiet machine).
   - G2 battle sim: 1.5 / 4.6 / 12.0 / 29.1 ms avg at 64 / 128 / 256 / 512; p95 at 512 is 42 ms < 50.
   - **Sim cap ≥512, up from ~256.**
   - Window fps: 53-60 / 45-53 / 21-24 at ~105 / ~210 / ~440 units.

Integration fixes found by verification:
- groups outlived dead officers for one tick;
- the AI looped on a stale withdraw (89x);
- long games starved of salvage, so wrecks now drop scrap and map salvage was raised;
- cancelled foundations dropped scrap;
- synthetic-input harness (box-drag) rebuilt on Input.parse_input_event.

Known gaps:
- the hard-AI defensive bridge demolition is not built;
- seed 4 stalemate;
- 1000+ units are unmeasured;
- fps at ~440 units is choppy (the sim is on the main thread);
- the owner has not hand-played G2 yet.

## Previous goal (G1, DONE 2026-10-23)

```
GOAL: First playable slice (G0+G1 core loop)
For whom / what changes:  Owner gets a Godot 4 Windows build where they play a full skirmish vs an
                          autonomous AI and can win or lose.
Outcome:                  One river-valley map (River Crossing), Human A at Stage 8 vs one AI. Gather,
                          power/HQ/depot/barracks/motor pool, ~5 unit types, fog, combat, HQ-kill victory,
                          save/load, measured 64-unit baseline.
Done-when:                1. `bash tests/run.sh` prints TESTS OK (ledger conservation, command validation,
                             determinism, save round-trip, fog-fair AI)
                          2. AI-vs-AI soak with no player input ends with one HQ destroyed (SOAK RESULT line)
                          3. Game launches windowed from a clean checkout; a scripted/manual playthrough builds
                             barracks, trains a squad, kills the enemy HQ (screenshots)
                          4. Perf report with measured tick ms + fps at 64/128/256 actors on this PC; README
                             claims match reality
Out of scope:             3 factions, 3 maps, Stage 7->9 progression, officers, cover/suppression, bridges
                          (G2-G4); handoff originals untouched
Stop-if / park-if:        Godot can't install/run headless; agent-board guard tooling broken
```
Scope chosen by owner 2026-10-22: engine Godot 4, scope G0+G1, art "readable pixel-art pass".

## Log
- 2026-10-22: Godot 4.7.2 installed (winget). Foundation committed `39ed6d7`: SimWorld core (fixed 20 Hz
  tick, command bus, atomic ledger, entities, save dict, state hash), deterministic point-symmetric River
  Crossing map gen, provisional content, strict test runner (8/8 core tests). Found and fixed: SimRng's bare
  `randf()` resolved to Godot's global RNG (non-deterministic maps).
- 2026-10-22: Wave 1 dispatched (6 parallel builders, budget-guarded): A-econ, B-mil, C-art, D-view, E-hud,
  F-infra. See `.plan/agents/`. Wave 2 (AI opponent + integration) follows.
- 2026-10-23: Wave 1 complete (`c1f1011`). C-art was stopped by the budget guard after 20 silent minutes (no
  files written) and replaced by C-art-2. D-view, B-mil and G-ai handed off on budget nudges; D-view's and
  B-mil's leftovers were finished by the orchestrator, and G-ai's by G-ai-2. All 9 completions passed
  `guard.mjs --audit` (no OVER-CAP or MODEL-BREACH).
- 2026-10-23: Wave 2 (`2ac8c1d`): fair AI. Content rebalanced (provisional): credits were the only binding
  constraint. Verification pass found and fixed:
  - the AI razed a new player's HQ at 02:57, so offensives now wait for a difficulty grace period;
  - end-of-match alerts were repeated;
  - a fresh checkout could not launch without an import, so `run.bat`/`run.sh` now import first.

## Done-when evidence (2026-10-23)
1. **Tests:** `bash tests/run.sh` gives `RESULT pass=60 fail=0 files=8` / `TESTS OK`, run by the orchestrator
   after the last code change.
2. **AI-vs-AI soak** (`tools/soak.gd`, normal, after the grace-period change):
   - seed1 `winner=0 end_tick=18378 reason=hq_elimination`
   - seed2 `winner=0 end_tick=13015`
   - seed3 `winner=1 end_tick=16484`
   - 0 INVARIANT FAIL.
   - Before the change, the orchestrator re-ran seed 2 independently: hash `e09a4ce2...` matched G-ai-2's run.
3. **Real window:**
   - `tools/ui_playtest.gd` drove menu -> select engineers -> build generator + barracks by hotkey ->
     right-click gather -> click Rifle Squad -> 4 riflemen -> attack-move, all through synthetic input:
     `PLAYTEST RESULT pass=18 fail=0`. Shots: `.plan/shots/orch/ui/`.
   - Rendered AI-vs-AI seed 1 (`--player-ai`) reached the VICTORY screen at 04:17, the same end tick as the
     headless soak (`.plan/shots/orch/04_aivai_end.png`).
   - A clean `git clone` launched via `run.sh` and `run.bat` with zero script errors.
   - **Not done:** a human (the owner) playing a full match by hand. The UI playtest stops after the first
     attack-move; it does not kill the enemy HQ by hand.
4. **Perf:** `perf/PERF_REPORT_2026-10-23.md` (Ryzen 5 8640HS / Radeon 760M).
   - Sim avg 3.2 / 5.2 / 11.9 / 75.3 ms per tick at 64 / 128 / 256 / 512 units.
   - Supported cap about 256; 512 is over the 50 ms budget.
   - Window fps: 60 / 53-60 / 45-52 at ~64 / ~128 / ~250 units.

## Known gaps / next
- The AI reads the remaining amount of unexplored own-half resource piles (neutral info, disclosed by G-ai-2).
- The "under attack" alert fired at 00:30 in the playtest; the cause is unverified.
- The debug `--spawn-test` ticks the squad objective.
- Infantry sprites are small at 1x. Roads and bridges have no direction variants.
- Salvage is finite (~4.9k per side), so long Endless games dry up.
- Next gate: G2 (groups/officers, suppression/cover, component damage, supply, smarter AI).
