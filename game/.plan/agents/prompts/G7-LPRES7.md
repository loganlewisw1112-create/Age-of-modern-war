# G7-LPRES7: Last Protocol 100-Sentinel barracks reserve, tiered release (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board; status DIRECTLY every 5 tool calls with calls_used / tokens_used_est / next_action, also
before/after every long run, never 10 min silent: use a heartbeat (.plan/hb.sh) around long runs; no git, no D:).
Spec: docs/G7_REFERENCE.md **13.9c-34** with the owner's answers (every word), plus 13.9c-10/-11 (Sentinels), 13.9c-29
(strike teams / spec ops NEVER on base defence), 13.9c-27 (drone bay auto + manual pattern), 13.9c-33 (fortress).
Owner verbatim: "last protocol game mode your facility should start with at min the sentinels and units already within
the facility + an extra 80+sentinels in the barracks garrison *** (make a tactically strategic way that they filter out
as necessary and conflict gets more heavy in defending the facility from being breached/takenover".
Answers: 100 reserve; tiered by pressure (1 replace post casualties 1:1, 2 quick-reaction squads of 4-8 to a wall sector /
gate under heavy attack, bounding from cover, 3 counter-attack surge on a real breach, ~20% last stand always held at the
command centre + core rooms); auto by default + manual (barracks card: release a squad, recall, auto off); finite pool
with a slow paid trickle of replacements.
Existing code: sim/systems/sentinels7.gd (start garrison rules.start.force, posts, QRF / off-duty roster in the barracks,
alarm scan, threat(), withdraw / rest), content/g7/defs_g7_sentinels.json (cn_sentinel_barracks garrison_slots 120),
sim/systems/lp_setup.gd fill_facility (LP pre-built facility), lp_garrison7.gd / lp_defence.gd (LP army jobs; the
facility's Sentinels are NOT the LP army), drone_bay7.gd + presentation/ui7/dronebay_card.gd (the auto/manual card
pattern to copy), cn_role7.gd.
## Build
1. LP only: when Last Protocol fills its facility, the barracks also holds a 100-Sentinel reserve (a sensible type mix
   from rules.start.force proportions, PROVISIONAL), inside the barracks (garrisoned, not on the map), on top of the
   normal start garrison. Make the 120-slot barracks fit reserve + off-duty roster + ~20 free for returning wounded
   (raise the LP barracks cap or count rules, your call, report it). Skirmish facilities unchanged (prove: a skirmish
   facility's state hash is unchanged by your code).
2. The tiered release (deterministic, cheap: evaluate on a cadence, staggered, no per-tick full scans; SimIndex
   liveness rule: skip ids not in w.entities): pressure per wall sector / gate from Sentinels7's alarm / threat data;
   step 1 post refills, step 2 QRF squads (4-8) to the sector, moving by bounding / cover (reuse the Sentinel movement
   gaits), step 3 breach surge (enemies inside the walls), last-stand group (~20%) held for the command centre + core
   rooms and only committed there. Released Sentinels return to the barracks to rest / refill when their sector is
   quiet. Never touch strike teams / spec ops (13.9c-29).
3. Manual control: barracks card (copy dronebay_card's pattern): reserve count, in-field count, last-stand count, auto
   ON/OFF, Release squad, Recall; sim commands validated like dronebay_launch / recall / auto (register in world.gd
   COMMANDS; post a fact naming the lines you add there).
4. Trickle: slow paid replacements up to the reserve size (PROVISIONAL rate / cost), stops when the barracks is gone.
5. Save / load: state in w.sys_state (saved, hashed); deep save/load mid-release gives the same future (add a scene to
   test_det7 or your own test using the deep var_to_bytes round trip).
6. Tests: new tests/test_lpreserve7.gd (reserve present only in LP, size 100, tiers fire in order under rising pressure,
   last stand held until the core rooms are threatened, manual release / recall / auto off, trickle, never strike teams,
   save/load). Keep test_lpmode7, test_sent7, test_cnfac7, test_det7, test_lpperf7 green; run an LP soak segment
   (tools/lp_soak7.gd --tide-at=600 --wall-max=900) and report ms/tick vs .plan/soak7/early_seed77.log (75 ms/tick on a
   busy PC) - 100 extra Sentinels must not blow the LP perf budget (test_lpperf7).
7. Windowed playtest: add a G7 flow lpres7 (tools/ui_playtest.gd G7_FLOWS + tools/pt7_lpres7.gd) showing the barracks
   card, a QRF squad bounding to a pressed wall, and a breach surge; 0 fail; post fact shots.best (read them first,
   plain caption).
Files: new sim/systems/lp_reserve7.gd (or a clearly separated block in sentinels7.gd), defs json, lp_setup.gd
(fill_facility only), world.gd (COMMANDS / SYSTEM_ORDER lines only, post a fact), new ui7 card + hud attach line,
tests, tools/pt7_lpres7.gd. Post a claim first; PERF7G (wounds/shrapnel/damage/combat/formations7) and CIWS7-5 are live.
