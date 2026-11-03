# G7-GATE7: APC gate blast doors redesigned (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board, heartbeat via `bash .plan/hb.sh GATE7 <calls> <tokens> "<label>" -- <cmd>`, status every 5
tool calls with calls_used / tokens_used_est / next_action, also during long runs; post `fact shots.best` as soon as
something is visible; no git, no D:). Spec: docs/G7_REFERENCE.md **13.9c-26** (the owner's note: read every word), 13.9c-22 (gate
hardening states), 13.9c-25, 13.9c-13, 13.9c-18. APCMOV7-3 owns the sim gate state machine (fac_drive7.gd; CnFacility
render_entries "gates" = [outer open|closing|hardened|opening, inner open|closing|closed|opening, hardened]);
entity_layer.gd draws gate_outer / gate_inner with their _lockdown art when not open (ORCH CR 5068).
## Build
1. Art: the gate_outer / gate_inner pieces in tools/art/g7_fac7f.gd (gate functions only: WALL7-2 owns wall / tower parts,
   FACB7-6 owns armory(); re-read before every edit, announce generator runs on the board): heavy armoured blast doors
   per 13.9c-26, open / closing frames (6-10 frames of door travel + bolt / beacon states), closed = sealed.
2. Display: play the open / close animation from the sim state with a smooth heavy travel (entity_layer.gd gate block or
   a small display helper: change_request to ORCH for entity_layer lines), warning beacons on while moving.
3. Tests: frames exist for every state / facing; animation follows the state sequence; display-only: hash on == off.
4. Windowed: gate cycle shots (open, closing, sealed, opening) at zoom 1.75 / 2.5; Read every PNG; post fact shots.best.
Files you own: g7_fac7f.gd gate functions, a new presentation/view/fac_gate7.gd if useful, tests/test_gate7.gd,
tools/pt7_gate7.gd (ORCH registers "gate7"). Anything else: change_request.
## Found by APCMOV7-3 (board seq 5350, shot .plan/shots/APCMOV7-3/cmp_open_vs_hardened.png)
Today the outer gate looks the same open and hardened: a tall grey, slightly SEE-THROUGH slab in both states that also
hides the suits in the wash; only the amber beacons differ. Fix both: an open gate shows its leaves retracted into the
portal (the opening clear, the wash visible through the open doorway, not through a translucent slab); hardened shows the
sealed leaves; nothing semi-transparent (13.9c-18). Check the gate pieces' alpha in the generator and in entity_layer.
