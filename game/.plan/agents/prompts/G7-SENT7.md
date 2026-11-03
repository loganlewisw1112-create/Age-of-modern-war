# G7-SENT7: Sentinels, the facility's guard force (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board, heartbeat via `bash .plan/hb.sh SENT7 <calls> <tokens> "<label>" -- <cmd>`, status every 5
tool calls with calls_used / tokens_used_est / next_action, no git, no D:). Spec: docs/G7_REFERENCE.md **13.9c-10** (the
owner's note + ORCH's decisions: read every word), 13.9c..13.9c-9 (the facility: towers, walls, wall-walk, foot entry,
wall turrets), 6.3-6.8 (counter-nanite teams, weapons: disruptor, harpoon, limpet, EMP), section 2 (G7 soldier realism:
wounds, senses), 7 (turrets). Existing systems to build on: sim/systems/garrison.gd (garrison_slots, entry / exit),
wallwalk7.gd + movement.gd wall cells (WALL7), lp_garrison7.gd (BASE7-2 wall patrols: reuse its patrol pattern),
counter_nanite.gd / cn_facility.gd (facility), wounds.gd, morale.gd, squad_ai.gd, the AI commander (sim/ai/).
Live agents: FACB7 (facility layout files: it places the Sentinel Barracks in place of the ready room and sets the
tower / entry garrison slots in defs_g7_facility.json: agree on the board), LIFE7 (display: it drops its animated wall
guards in favour of your real Sentinels), WTUR7 (wall turrets), ATMO7, SEQ7 (display). Coordinate on the board.

## Build
1. Content (content/g7/defs_g7_sentinels.json): the 7 Sentinel types for Human A and Human B (Warden, Marksman, Gunner,
   Bulwark, Lancer, Arc, Mender), weapons (new where needed, reusing CN weapon mechanics: disruptor anti-nanite, harpoon,
   limpet, EMP), self-heal armour, the Sentinel Barracks (trains them; garrison 120, Sentinels only; FACB7 places it).
   No rank_role / officers: they are excluded from the chain of command (Companies / CommandNet / SquadAI leader logic
   must not try to give them leaders); each obeys direct orders; the AI commander can use them for facility defence.
2. Garrison rules: hardened facility towers hold up to 4 Sentinels; the foot entry booth / scan point up to 15; the
   barracks 120; Sentinels only (others rejected with a reason). Garrisoned Sentinels fire out (towers / booth) as the
   garrison system allows.
3. Self-heal: regen out of combat (stops while hit recently, suppressed, EMP'd); facility defence bonus inside the
   facility radius (walls, towers, garrisons); nanite-exposure resistance; NOT invincible (cost, train time, pop, EMP
   vulnerability, no bonus outside). Balance target: a Sentinel garrison of ~20 holds the facility against roughly 2-3x
   its value of human infantry or Machine units, but loses to a combined-arms assault with armour + artillery.
4. Starting garrison: when the facility is raised (every match / Last Protocol), the owner gets a Sentinel force that
   mans the walls (wall-walk), the towers (some), the entry booth and patrols the interior (staggered thinking, like
   lp_garrison7). Player can re-task them.
5. Tests tests/test_sent7.gd: 7 types exist with distinct weapons; only the barracks trains them; garrison caps 4 / 15 /
   120 and Sentinels-only; self-heal on/off conditions; defence bonus inside vs outside; no chain-of-command leader;
   the balance target above in a headless fight (report the numbers); hash twice-same; no facility = no cost.
6. Art: placeholder art is fine at first (tinted CN operator sheets); post `fact sent7.art_needs` with the 7 types'
   silhouettes / weapons so a dedicated art agent can draw them next (ORCH starts it when a slot frees). Playtest
   tools/pt7_sent7.gd (ORCH registered "sent7"): Sentinels on the walls, in a tower, at the entry booth, an assault by
   humans and by the Machine; shots at zoom 1 / 1.75 / 2.5; LOOK at each; list the best in your report.
Files you own: content/g7/defs_g7_sentinels.json, a new sim/systems/sentinels7.gd (+ SYSTEM_ORDER slot via
change_request to ORCH), sim/systems/garrison.gd (Sentinel-only caps), tests/test_sent7.gd, tools/pt7_sent7.gd. Anything
else (Companies, CommandNet, SquadAI, AI commander, wounds, morale): change_request to ORCH with exact lines.
