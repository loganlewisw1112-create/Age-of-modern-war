# G7-FACB7-7: Suit Foundry pushed to signature level + mantrap no-suits (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board, heartbeat via `bash .plan/hb.sh FACB7-7 <calls> <tokens> "<label>" -- <cmd>`, status every 5
tool calls with calls_used / tokens_used_est / next_action, also during long runs; post `fact shots.best` as soon as
something is visible; no git, no D:). Read the predecessor handoff .plan/handoff/FACB7-6.json first. Spec:
docs/G7_REFERENCE.md **13.9c-20e** (the owner's note: "for suit foundry push everything even more"), 13.9c-20c, 13.9c-18,
13.9c-24, 13.9c-13; the latest shots .plan/shots/FACB7-6/ (in game art7f_armory_z2.png, sprite x3 / x4).
## Build
1. Art: tools/art/g7_fac7f.gd armory() section only (GATE7 edits gate functions and WALL7-3 wall / tower parts in the same
   file: re-read before every edit, post on the board before every generator run, copy in only your g7_fac_armory_* PNGs
   and manifest entries as FACB7-6 did). Push the Suit Foundry to a signature building per 13.9c-20e; same footprint.
   Enlarged sprite board first (x3), iterate until it clearly reads as a hardened high-tech suit foundry, then in game.
2. Mantrap no-suits (ORCH seq 5361, FACB7-6 next step 1): CN suits (exo_suit / cn_suit defs) never path through the
   infantry mantrap / decon hall cells; foot infantry still do; test it in tests/test_cnfac7.gd (yours) and keep
   test_apcmov7 green. Movement.gd lines (APCMOV7-3 added vonly gates) go to ORCH as a change_request.
3. Tests: test_cnfac7, test_art7f, test_apcmov7, test_lpmode7, test_cnsuits7 green (never weaken). Windowed pt7_art7f
   armory shots at zoom 1 / 2 / 3 (day and night); Read every PNG; post fact shots.best.
Files you own: g7_fac7f.gd armory() only, content/g7/defs_g7_facility.json, sim/systems/cn_facility.gd (layout parts),
tests/test_cnfac7.gd. Anything else: change_request.
