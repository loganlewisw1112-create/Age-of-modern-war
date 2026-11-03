# G7-PATH7: nothing walks through anything; smooth movement everywhere (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board; status DIRECTLY every 5 tool calls with calls_used / tokens_used_est / next_action,
including before / after long runs; post `fact shots.best` as soon as something is visible; no git, no D:). Spec:
docs/G7_REFERENCE.md **13.9c-31** (owner: "ensure NO units walk throuhg buildings/walls/other units/etc in the facility and
elswhere ** smooth animations and walking and movement at all times"), 13.9c-16 (APC driving), 13.9c-13.
## Build
1. Measure first: a probe (headless) over representative scenes: the LP facility (Sentinels, engineers, ammo bearers,
   CN teams, suits, APCs through lanes / gates / mantrap / decon hall / wall-walk stairs), a normal match base, a 200-unit
   field battle, a 2k crowd. Count per tick: units whose position is inside a building / wall / tower / gate footprint
   (by def size), unit-unit overlaps below a min gap (infantry, vehicles), large per-tick position jumps (teleports), and
   heading snaps. Also a display-side check (motion / entity_layer interpolated positions). Post the numbers on the board.
2. Fix root causes in the right systems (movement.gd paths / separation / footprint pushout, formations, fac_drive7,
   wallwalk stairs, sentinels / engineer7 routes, display interpolation in motion.gd): never by hiding units. Keep the 2k
   sim cost within noise (.plan/sim_ab7.gd before / after) and determinism (hash twice-same).
3. Tests tests/test_path7.gd with the probe's counts as hard checks (0 inside footprints; overlaps / teleports below
   strict thresholds you justify from the measurements, never loosened later); keep test_hot_state / test_squad7 /
   test_apcmov7 / test_cnfac7 / test_wallwalk7 green or report hash moves honestly (ORCH re-baselines).
4. Windowed: shots of crowded facility moments (gates, mantrap, decon hall, staging) at zoom 1.75 / 2.5; Read every PNG;
   post fact shots.best.
Files: movement.gd (APCMOV7-4 owns the gate parts while live: change_request for those), formations7.gd / combat.gd /
world.gd / motion.gd / entity_layer.gd: change_request to ORCH with exact lines; other systems without a live owner: post a
fact naming each file before editing.
