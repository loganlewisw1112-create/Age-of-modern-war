# G7-FACINT7: the whole counter-nanite facility, everything at once, newest build (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board; status DIRECTLY every 5 tool calls, never 10 min silent: heartbeat .plan/hb.sh around
long runs; no git, no D:). Owner asked (2026-10-28): "have we tested out how the most updated newest version of our
counter nanite facility with ALL the perks, vehicles, updated buildings, units, specialties, air vehciles , etc y todo ??"
Honest state: every feature has its own test + windowed flow (pt7_cnfac7, pt7_sent7, pt7_dronebay7, pt7_ciws7, pt7_gate7,
pt7_apcmov7, pt7_cnsuits7, pt7_wallturret7, pt7_wallwalk7, pt7_turret7, pt7_muzzle7, pt7_atmo7, pt7_life7, pt7_seq7,
pt7_eng7, pt7_cnops7, pt7_vanta7, pt7_drone7, ...), but nothing runs the NEWEST facility with everything working together
in one match, and the last full pt7_cnfac7 run predates today's changes (lighting, blast doors, drone hive, CIWS,
suit redesign, traverse, CN roles, fortress balance).
## Jobs
1. Inventory: from docs/G7_REFERENCE.md (counter-nanite sections + every 13.9c owner note) and content/g7 defs, list
   EVERY facility item: buildings / parts, unit types (strike team, tactical squads, operators + specialties, suit
   bearers / armoured suits, Sentinels by type, engineers, medics), vehicles (APCs both kinds, fuel tanker, ...), air
   (dropships incl. stealth, drone hive types, player drones), defences (towers, wall turrets, wall-walk, CIWS, blast
   doors, gates, wash / decon), perks / upgrades / research / specialties, services (rearm, refuel, repair, decon,
   casualty care), missions / ops. Write it to .plan/facint7_inventory.md as a coverage matrix: item | spec ref |
   unit test | windowed flow | exercised in the all-in-one run | shot.
2. One all-in-one windowed flow `facint7` (tools/pt7_facint7.gd + register in tools/ui_playtest.gd G7_FLOWS): one match,
   newest code, the full facility raised, then in order: train / field every unit type; every vehicle drives in and out
   through the gates and the wash; air: dropship sortie + return, drone hive launch / recall, player drone; a mission out
   and back; every service used once; every perk / upgrade bought or applied; then a night combined-arms Machine assault
   against the full defence (Sentinels, towers, wall turrets, drone hive, CIWS, blast doors) with an engineer CIWS drum
   swap; a deep save / load mid-fight that keeps going. Each step is a pt._log check with a real oracle (state seen in
   the sim / view, not "the call returned"). Frame-exact shots of each item at a readable zoom.
3. Run it windowed (timeout 1800 if it needs it) until 0 fail; also run the full existing facility flows listed above
   once each (sequentially, not in parallel, windowed) and record each PLAYTEST RESULT. Every failure: find the cause;
   fix it only if it sits in your flow, otherwise post a `need` to orch naming the file, the evidence and the exact
   failing check (do NOT edit other agents' live files: LPRES7, CIWS7-5, PERF7H are live).
4. Report: the coverage matrix (items NOT exercised named plainly), every PLAYTEST RESULT line, every failure and its
   cause, and post fact shots.best with the best 6-10 shots (read them first; plain caption naming what each shows).
Files you own: tools/pt7_facint7.gd, the G7_FLOWS line in tools/ui_playtest.gd (post a fact), .plan/facint7_*.
Note: CIWS7-5 is changing the CIWS art and LPRES7 adds an LP-only barracks reserve; your flow is a skirmish facility.
The flow will be re-run on the final tree, so keep it robust (no fixed sleeps where a wait-until fits).
