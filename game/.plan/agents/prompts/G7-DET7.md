# G7-DET7: save / load determinism of the G7 facility systems (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board; status DIRECTLY every 5 tool calls with calls_used / tokens_used_est / next_action,
including before / after long runs; no git, no D:). Frozen Done-when #2 (PROGRESS.md Active goal G7): determinism, incl.
the drone replay. A REAL save / load (SimWorld.from_dict(bytes_to_var(var_to_bytes(w.to_dict())))) of a CN facility world
must produce the same future as the original.
Evidence: ORCH fixed tests/test_wallturret7.gd test_save_load_round_trip to deep-copy (the old bare to_dict shared the
entities dict; drone-bay spawns then collided ids). With a real deep save it now FAILS: "loaded world keeps firing
identically (got 71c93f54..., expected 526bf9b3...)" after 100 ticks. ORCH already fixed two stale-SimIndex divergences
(sentinels7 threat(), base_state7 _eval: skip ids not in w.entities). Today's systems with state: CnFacility, WallWalk7,
Sentinels7, Engineer7, FacDrive7 (+ fac_suits7), VehDrive7, DroneBay7 (hive, VER 2), Traverse7 (e.tf/tft/tfh/tfa),
WallTurret7, Turrets7, BaseState7, CnRole7, Vanta7, Apc7, Counterdrone (CIWS pending lay), Threats7.
## Build
1. A harness (.plan/det7_probe.gd): facility worlds (the wallturret7 test setup, an LP start world with an attack, a
   drone-bay fight) -> run N -> deep save / load -> run both M ticks -> on the first tick their state_hash differs, diff
   the two worlds (entities field by field, sys_state key by key, w.cache-derived decisions) and name the system.
2. Fix each root cause in the owning system: state that lives only in w.cache / statics / iteration order of a
   Dictionary built differently after load / stale SimIndex entries / float keys / unsaved per-unit fields. Never hide it
   in the test. Post each finding + fix on the board.
3. Prove: test_wallturret7 test_save_load_round_trip green; add a general tests/test_det7.gd (3 facility scenes, deep
   save / load, 300 ticks, same future); rerun test_cnrole7, test_dronebay7, test_sent7, test_apcmov7, test_cnfac7 save /
   load tests.
Files: any G7 system without a live owner (post a fact naming each file before editing). Live owners: PATH7-2
(veh_drive7, fac_drive7, movement separation), PERF7F (whatever it claims on the board), LIGHT7-5 (display):
change_request to them. combat.gd / world.gd / render_snap.gd: change_request to ORCH.
