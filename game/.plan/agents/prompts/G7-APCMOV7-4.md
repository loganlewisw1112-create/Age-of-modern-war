# G7-APCMOV7-4: foot-only mantrap + suits through a hardened gate (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board; status DIRECTLY every 5 tool calls with calls_used / tokens_used_est / next_action; no git,
no D:). Read the board posts: FACB7-7 seq 5748 (the foot-only gate change request + its BLOCKER note), APCMOV7-3's final
report posts, and .plan/handoff/APCMOV7-2.json. Spec: docs/G7_REFERENCE.md 13.9c-20c (CN suits never use the infantry
mantrap / decon hall), 13.9c-22 (outer gate hardens when enemies are near), 13.9c-25 (APC entry = vehicles + suits, suits
decon 4 at a time).
## Build
1. Apply FACB7-7's patch: `python3 .plan/handoff/FACB7-7_patch_movement.py sim/systems/movement.gd` (exact-match; it refuses
   on mismatch: then apply the diff .plan/handoff/FACB7-7_movement_fonly.diff by hand). You own movement.gd gate parts.
2. Fix the dependency it exposes: with the mantrap foot-only, test_apcmov7::test_suits_wait_for_hardened_gate fails
   (suits ordered into the compound while the outer APC gate is hardened get an unreachable goal, Movement.order_move turns
   the order idle, FacDrive7._suit_scan never queues them). Make own-team suits / APCs keep their order and queue at the
   outer gate for a cycle (e.g. own-team locked vehicle-only gates count as passable for path PLANNING while FacDrive7
   holds the actual traffic at the gate; or FacDrive7 catches the order before Movement drops it). Deterministic; no
   facility = no cost; never weaken a test.
3. Green: test_apcmov7 (all, incl. the hardened-gate suit test), test_cnfac7 (incl. FACB7-7's test_facb77), test_lpmode7,
   test_wallwalk7, test_sent7. Then the windowed playtest --ui-playtest-apcmov7 (timeout 900): suits through a hardened
   gate cycle, infantry via the foot entry, a suit ordered to the mantrap goes round to the APC entry; Read every PNG; post
   fact shots.best.
Files you own: sim/systems/fac_drive7.gd, sim/systems/movement.gd (gate parts only), tests/test_apcmov7.gd,
tools/pt7_apcmov7.gd. cn_facility.gd / test_cnfac7.gd are FACB7-7's (live): change_request to it.

## Also (from GATE7's handoff .plan/handoff/GATE7.json)
4. tools/pt7_gate7.gd: add the final step (remove the spawned enemy, keep clearing the AI, wait up to 40 s for the
   opening mid-travel, shoot it, check the open frame) and rerun --ui-playtest-gate7 to all ok; also trigger an inner-gate
   cycle (an APC out while the outer gate is hardened) and shoot it; Read the PNGs, post fact shots.best.
