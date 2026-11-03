# G7-EXO7: counter-nanite armoured suits from the armory + suit bay (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board, heartbeat via `bash .plan/hb.sh EXO7 <calls> <tokens> "<label>" -- <cmd>`, status every 5
tool calls with calls_used / tokens_used_est / next_action, also during long runs; post `fact shots.best` as soon as
something is visible; no git, no D:). Spec: docs/G7_REFERENCE.md **13.9c-20** (the owner's note and answer: read every
word), 13.9c-13 (realism, no gimmicks), 6.3-6.8 (counter-nanite teams and weapons: disruptor, harpoon, limpet, EMP),
13.9c-6 (the armory + suit bay building), and the G6 exo system (sim/systems/exo.gd, content/g6/defs_units_g6.json
a_exo_*: pilot inside, can_produce, pilot ejection), and the approved art bar (Look checkpoints; the CN operators and
dropships the owner called "fucking fire").

## Build
1. Content content/g7/defs_g7_cnsuits.json: 3-5 counter-nanite armoured-suit variants for Human A and B, each one-man
   (one gunner) on the G6 exo mechanics, each with a clear military role (e.g. heavy-gun suit, anti-armour / anti-walker
   missile suit, anti-air / anti-drone suit, anti-nanite disruptor suit); weapons reuse / extend the CN weapon set; all
   numbers PROVISIONAL and balanced against the existing exo suits and CN units.
2. Production: the armory + suit bay (the facility's `armory` zone / part: find how the facility's buildings expose
   production; the Sentinel barracks trains units, follow that pattern) produces them; only the facility owner; one
   gunner per suit (a pilot def); Exo.can_produce rules hold.
3. Art: a new generator tools/art/g7_cnsuits.gd (yours) on the same rig / scale / detail as the approved operators and
   dropships: believable powered armour (load-bearing frame, plates, joints, sensors, weapon mounts, ammo feed, rear hatch
   / pilot access), 8 facings, walk / run / aim / fire / reload / hit / destroyed (pilot ejects) frames, team masks;
   each variant readable by silhouette; NO transparency (13.9c-18).
4. Tests tests/test_cnsuits7.gd (each variant built only at the armory, one gunner, pilot ejects, weapons and roles,
   hash twice-same, no facility = no cost) and playtest tools/pt7_cnsuits7.gd (ORCH registered "cnsuits7"): each variant
   built at the armory, walking, firing, reloading, destroyed with the pilot ejecting; shots at zoom 1 / 1.75 / 2.5; Read
   every PNG; post fact shots.best; list the best.
Files you own: content/g7/defs_g7_cnsuits.json, tools/art/g7_cnsuits.gd + assets/art/g7_cnsuits/, tests/test_cnsuits7.gd,
tools/pt7_cnsuits7.gd, presentation/art/art_catalog.gd (register only). Facility production hooks (defs_g7_facility.json /
cn_facility.gd: no live facility owner, you may add the armory's production entry there, nothing else). Anything else:
change_request (exact lines).
