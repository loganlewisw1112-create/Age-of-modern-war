# G7-APCMOV7-3: gate hardening, vehicle-only APC entry, suits through the wash (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board, heartbeat via `bash .plan/hb.sh APCMOV7-3 <calls> <tokens> "<label>" -- <cmd>`, status
every 5 tool calls with calls_used / tokens_used_est / next_action, also during long runs; post `fact shots.best` as soon
as something is visible; no git, no D:). Read the predecessor handoff .plan/handoff/APCMOV7-2.json first (and its final
board posts). Spec: docs/G7_REFERENCE.md **13.9c-22** (outer gate hardening when enemies are near, not gimmicky), **13.9c-25**
(the owner's new note: APC entry / wash = vehicles and CN suits only; suits decon up to 4 at a time), 13.9c-16, 13.9c-13.
State: ORCH has wired FacDrive7 into world.gd (SYSTEM_ORDER after Movement, COMMANDS fd7_go) and applied CR 5068
(entity_layer shows a shut gate with its _lockdown art). GATES_ON is false in fac_drive7.gd; 2 gate tests fail.
## Build
1. 13.9c-22: fix the outer gate state machine (stuck in "closing"; suspects in the handoff), turn GATES_ON on, make
   test_apcmov7's two gate tests pass without weakening them.
2. 13.9c-25: the APC gates (gate_outer, gate_inner) and the wash pass only vehicles and the CN suits (defs with
   exo_suit / cn_suit, defs_g7_cnsuits.json, EXO7-2 owns it); infantry and every other ground unit, any team, are never
   pathed through them (team-aware gate passability in sim/systems/movement.gd: find w.nav.gates / _gate_open). Suits
   entering: up to 4 at a time in the wash (decon cycle like the APCs), more queue outside the outer gate in order;
   leaving: through the gates like the APCs. Infantry ordered to a point whose shortest path is the APC gate go round via
   the foot entry.
3. Tests (test_apcmov7.gd): infantry never on a gate / wash cell over a full in/out run; 5 suits entering -> at most 4 in
   the wash, the 5th waits; gates harden and stand down; hash twice-same; no facility = no cost. test_cnfac7 /
   test_lpmode7 / test_sent7 / test_wallwalk7 stay green.
4. Playtest tools/pt7_apcmov7.gd (registered "apcmov7"), windowed: two APCs at the bays, both sent out in convoy, a third
   waiting, one sent back to its garage; enemy near -> outer gate hardens; a squad of infantry walking around to the foot
   entry; suits entering through the wash; shots at zoom 1 / 1.75 / 2.5; Read every PNG; post fact shots.best.
Files you own: sim/systems/fac_drive7.gd, sim/systems/movement.gd (gate passability only), tests/test_apcmov7.gd,
tools/pt7_apcmov7.gd. FACB7-6 owns the layout json / cn_facility.gd, EXO7-2 the suits, WALL7-2 / POLISH7-5 art: never
edit their files; change_request (exact lines).
