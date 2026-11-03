# G7-TURRET7: every turret traverses to its target before firing (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board; status DIRECTLY every 5 tool calls with calls_used / tokens_used_est / next_action,
including before / after long runs; post `fact shots.best` as soon as something is visible; no git, no D:). Spec:
docs/G7_REFERENCE.md **13.9c-30** (owner: "ensure all turret types actually turn towards enemies and fire towards them --
it currently reads as they shoot at enemies but never actually turn their barrel(s) to face them before shooting -- make
it realistic"), 13.9c-28 / -28a (muzzle from the barrel; MUZZLE7-2 built APC gun overlays with their own traverse:
presentation/view/apc_gun7.gd), 13.9c-13.
## Build
1. Audit every turret family and how its facing is simulated and drawn: building turrets (Combat building branch,
   turrets7.gd a_t7_*, wallturret7.gd, tower weapons, airdef / counterdrone CIWS, SAM), vehicle turrets (anim61 turret
   rows: mbt / ifv; VehAnim61 aim_row; motion.aim_row), ships. Post the audit (which already traverse, which snap, which
   never turn) on the board.
2. Sim: a turret facing per armed building / turret (saved, hashed), traversing toward the target at a per-def rate
   (PROVISIONAL deg/s by class), firing only when laid within tolerance; vehicles: turret facing separate from hull where
   the def has a turret. Keep balance: short lay times; measure test_hot_state / balance tests and report changes
   honestly (hash changes expected: ORCH re-baselines).
3. Display: draw the turret / barrel row from the simulated turret facing (not the target angle, not the hull), so the
   barrel visibly swings then fires; muzzle tip (muzzle_g61 / muzzle7.json) follows that row.
4. Tests tests/test_turret7.gd (traverse takes time, no shot before laid, tracks a mover, rest bearing when idle,
   deterministic hash twice-same, no-turret matches unchanged) and a windowed playtest tools/pt7_turret7.gd (ORCH
   registers "turret7"): a turret line-up turning onto targets from behind, frame shots before / during / at the shot;
   Read every PNG; post fact shots.best.
Files: turrets7.gd, wallturret7.gd and other turret systems with no live owner (post a fact naming each file before
editing); combat.gd / entity_layer.gd / motion.gd / world.gd: change_request to ORCH with exact lines; MUZZLE7-2's files
(muzzle_g61.gd, fx_layer muzzle parts, apc_gun7.gd) via change_request to it while it is live.
