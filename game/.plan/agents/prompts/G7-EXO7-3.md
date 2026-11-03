# G7-EXO7-3: CN armoured suits in game + per-role polish (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board; status DIRECTLY every 5 tool calls with calls_used / tokens_used_est / next_action,
including before / after every long generator or playtest run; post `fact shots.best` as soon as something is visible;
no git, no D:). Read the handoff .plan/handoff/EXO7-2.json and EXO7-2's board posts. Spec: docs/G7_REFERENCE.md 13.9c-20,
-20a, -20b, -20c, -20d (owner: "for the aormoured suits need to push for more defined roles/specializations ... make them
DOPE"; "almost avatar movie size suits"; "tactical aggressive stances ... animations and movemnt smoother"), 13.9c-18.
## Build
1. In-game shots of the per-role suits: run --ui-playtest-cnsuits7 (timeout 900; EXO7-2 fixed fog / camera), each role
   walking, aiming, firing (braced), reloading, destroyed with the gunner ejecting, at zoom 1.75 and 2.5; Read every PNG;
   post fact shots.best.
2. Per-role polish EXO7-2 listed: Aegis array reads like a cap over the head in the front facing (make the raised sensor
   mast / array clearly a back-mounted array); Bastion head mostly hidden in the front facing; destroyed frame in facing 1
   is a blob. Push each role's silhouette further where it still reads samey at game size (owner bar: "make them DOPE").
   Enlarged board (.plan/suits_sheet.py style, 5x) before / after.
3. Smoother motion (13.9c-20b): if more walk / run in-betweens are needed, send ORCH a change_request for the cn_suit
   units only (batch_art.gd / motion.gd frame counts) with exact lines; stride matched to speed.
4. test_cnsuits7 green (never weaken); muzzle data: re-run tools/art/muzzle7_gen.gd after any regeneration (MUZZLE7-2
   owns that tool: ask it on the board, or run it read-only and post the result).
Files you own: tools/art/g7_cnsuits.gd + assets/art/g7_cnsuits/, content/g7/defs_g7_cnsuits.json, tests/test_cnsuits7.gd,
tools/pt7_cnsuits7.gd. Anything else: change_request.
