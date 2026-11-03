# G7-ENG7: the Facility Engineer (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board, heartbeat via `bash .plan/hb.sh ENG7 <calls> <tokens> "<label>" -- <cmd>`, status every 5
tool calls with calls_used / tokens_used_est / next_action, also while writing long files; no git, no D:). Spec:
docs/G7_REFERENCE.md **13.9c-11** (Facility Engineer) and **13.9c-12** (fully autonomous staff: read every word),
13.9c-6 (magazine, fuel point), 13.9c-9 (wall turrets), 13.9c-10 (Sentinels). Read SENT7's facts on the board (locker
stock get/add API, repair hook, the shared facility job board if SENT7 built one: use it, don't make a second one) and
LIFE7's `fact life7.engineer_hook` (display forklifts / fuel truck attach to your unit while it does those jobs).

## Build
1. The Facility Engineer unit (content/g7/defs_g7_engineer.json; Human A and Human B), trained at the facility
   (workshop or barracks: agree with FACB7-2/SENT7 on the board), pistol only.
2. Fully automatic jobs (13.9c-12), chosen by urgency and distance through the shared facility job board: repair damaged
   walls, towers, wall turrets and facility buildings (existing repair mechanics: sim/systems/repair.gd / engineering);
   refill ready-ammo lockers from the special ammo magazine (carry run; the forklift drawn by LIFE7 while carrying);
   refuel APCs at the fuel point and the stealth / VTOL dropships on the pads (existing fuel / rearm state if any; else
   a small fuel value the facility uses; agree with SENT7/FACB7). No player orders needed; player orders still work and
   the unit returns to duty after.
3. Starting staff: the facility starts with a few engineers (PROVISIONAL count) who get to work at once.
4. Tests tests/test_eng7.gd: each job happens on its own (a damaged wall gets repaired, an empty locker gets refilled
   from the magazine, an APC / dropship gets refuelled), no two engineers take the same job, the most urgent job wins,
   player order override then return to duty, hash twice-same, no facility = no cost. Playtest tools/pt7_eng7.gd (ORCH
   registered "eng7"): shots of each job at zoom 1 / 1.75 / 2.5; Read every PNG; list the best (the owner wants them).
Files you own: content/g7/defs_g7_engineer.json, new sim/systems/engineer7.gd (SYSTEM_ORDER slot via change_request to
ORCH), tests/test_eng7.gd, tools/pt7_eng7.gd. Anything else: change_request (exact lines).
