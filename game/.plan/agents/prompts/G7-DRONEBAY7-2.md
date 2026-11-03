# G7-DRONEBAY7-2: the defence drone garrison as a hive mind (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board; status DIRECTLY every 5 tool calls with calls_used / tokens_used_est / next_action,
including before / after long runs; post `fact shots.best` as soon as something is visible; no git, no D:). Read the
handoff .plan/handoff/DRONEBAY7.json and DRONEBAY7's board posts. Spec: docs/G7_REFERENCE.md **13.9c-27a** (owner: "make
defense drones have better tactical capabilites/functionalities/formations/etc -- they should operate likea hive mind to
defend the facility at all cost"), 13.9c-27, 13.9c-13 (realism, no gimmicks).
State: sim/systems/drone_bay7.gd (yours), defs_g7_dronebay.json, presentation/ui7/dronebay_card.gd, tests/test_dronebay7.gd
(10/0 after ORCH's sampling fix), tools/pt7_dronebay7.gd (ORCH run: 21/2: the two AUTO button clicks did not register:
`dronebay7_auto_off` / `dronebay7_auto_on` ok=false: fix the flow or the card hit area, never weaken the check).
## Build
1. Hive mind per 13.9c-27a: shared threat board (drones + facility sensors + Sentinels' contacts), priority tasking with
   re-balancing, layered interceptor screen, gun-drone fire teams with orbit / strafe / converge, kamikazes timed with
   suppression, rotation to rearm (never all down), full commit on breach, last-resort ram at the core. Deterministic,
   saved, hashed; cost small (measure .plan/sim_ab7.gd 2k with and without a facility, report honestly).
2. Display: formations / orbits readable (sim positions drive it); card shows tasking counts (SCREEN n / STRIKE n /
   REARM n). UI file is yours.
3. Tests: extend test_dronebay7 (priority order, screen holds while strikers engage, rotation keeps >= 1/3 aloft,
   breach = full commit, ram only at the core, hash twice-same, save / load same future). Playtest: drones defending
   against a mixed attack (infantry, armour, enemy drones, missiles); shots at zoom 1 / 1.75 of the formations; Read every
   PNG; post fact shots.best.
Files you own: sim/systems/drone_bay7.gd, content/g7/defs_g7_dronebay.json, presentation/ui7/dronebay_card.gd,
tests/test_dronebay7.gd, tools/pt7_dronebay7.gd. world.gd / combat.gd / render_snap.gd / entity_layer.gd: change_request
to ORCH. Sentinel contacts: read sentinels7.gd state read-only.
