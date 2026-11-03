# G7-APCMOV7: smooth, realistic APC driving in the facility (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board, heartbeat via `bash .plan/hb.sh APCMOV7 <calls> <tokens> "<label>" -- <cmd>`, status every
5 tool calls with calls_used / tokens_used_est / next_action, also during long runs; no git, no D:). Spec:
docs/G7_REFERENCE.md **13.9c-16** (the owner's note: read every word), 13.9c-13 (realism, no gimmicks), 13.9c-2/-8/-9
(enclosed wash between two gates, lanes), 6.2 / 6.9 (facility flows: garages, staging, loading pad, dropship ramp).
Read the facility layout (content/g7/defs_g7_facility.json `_g7_facility`: zones, lanes, doors, garage rects) and how
CnFacility (sim/systems/cn_facility.gd) moves APCs today (phases garage / to_pad / loading / to_gate / out / returning /
to_inner / to_garage), plus Movement (sim/systems/movement.gd: paths, separation) and the display motion
(presentation/view/motion.gd: how vehicle heading / position is interpolated on screen).

## Build
1. A facility traffic controller (new sim/systems/fac_drive7.gd, yours): a lane graph from the layout's lanes / gates /
   garage doors / staging bays; reservations so no two vehicles take the same lane segment head-on or the same bay; a
   following gap; convoy order for departures (one after another). Two marked staging bays in the open staging area
   (agree the bay cells with FACB7-4 on the board; FACB7-4 owns the layout json / cn_facility.gd: hooks into
   CnFacility's phases go through a change_request to FACB7-4 or ORCH with exact lines).
2. Realistic vehicle motion inside the compound: follow lane centre-lines with a turning radius (no on-the-spot pivots,
   no heading snaps), smooth accel / brake, stop-and-wait at a reserved segment; deterministic, saved, hashed; a match
   without a facility costs nothing. If the sim's vehicle heading changes per tick in big steps, add display-side heading
   smoothing in motion.gd for vehicles (ORCH owns motion.gd: change_request with the exact cheap lines).
3. Player control: select one APC or both and order them out / to their own garage / to the staging bays / to a map
   point outside: they queue and depart one after another through the gates in convoy order. The automatic facility
   flows (launch, return, wash, garages) use the same controller.
4. Tests tests/test_apcmov7.gd: never on a building cell; no two APCs overlap (min distance) over a full launch +
   return; 2 bays max, the 3rd waits; convoy departure order kept; heading change per tick bounded (turn radius);
   player orders to garage / outside work; hash twice-same; no facility = no cost. test_cnfac7 stays green (never weaken).
5. Playtest tools/pt7_apcmov7.gd (ORCH registered "apcmov7"): two APCs at the bays, both selected and sent out, a third
   waiting, one sent back to its garage; capture the drive frame by frame (positions + headings) and shots at zoom 1 /
   1.75 / 2.5; Read every PNG; list the best (the owner wants them).
Files you own: sim/systems/fac_drive7.gd (SYSTEM_ORDER slot or CnFacility hook via change_request), tests/test_apcmov7.gd,
tools/pt7_apcmov7.gd. Anything else: change_request (exact lines).
