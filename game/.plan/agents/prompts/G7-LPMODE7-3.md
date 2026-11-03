# G7-LPMODE7-3: Last Protocol mode, finish (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first, then G7-LPMODE7.md (the original brief, still the spec) and the handoffs
.plan/handoff/LPMODE7-1.json and .plan/handoff/LPMODE7-2.json ("remaining" is your list). Flow name: lpmode7.

ORCH has applied LPMODE7-2's change requests: the "Last Protocol" main-menu button + records line (main_menu.gd), the
LP HUD card + end panel (hud.gd setup, `LpHud.wants/attach`), and the fit screens ui7_lp_hud / ui7_lp_end in
presentation/ui5/kit/fit_screens.gd. The map `last_protocol` is registered (skirmish false, mode last_protocol).

Files you own: sim/systems/last_protocol.gd, lp_setup.gd, lp_defence.gd, lp_world.gd, presentation/ui7/lp_menu.gd,
lp_hud.gd, tests/test_lpmode7.gd, tools/pt7_lpmode7.gd, new tools/lp_soak7.gd. You may also fix the Economy pop-cache
root cause in sim/systems/cn_facility.gd (`_finish_train` boarding operators into APCs in the same tick the carried pop
count misses them; CNFAC7 is finished) if that's where it lives: fix it at the root, then remove the
`w.cache.eco_pop` clear workaround from last_protocol.gd and prove save/load hash equality. Anything else: change_request.

## Do (in order)
1. The 2 pt7_lpmode7 fails: breach must seal the next ring's gates on the REAL map layout (`map.lp` rings[i].gates vs
   LpDefence.rings_step); the Tide must set the defence posture to maximum inside start_tide (not on the next 3 s
   think). Rerun windowed to PLAYTEST RESULT all ok, 0 SCRIPT ERROR, rc 0; look at every shot yourself.
2. **Balance (spec: a 60-90 minute run)**: on last_protocol the run starts at 40% creep against a 62% critical line
   with the countdown at x1.81. That is far too heavy. Tune your PROVISIONAL thresholds/rates (and send LPMAP7-2 a
   change_request if the pre-spread radii must shrink) so an AI-run defence lasts in the target band. Also find why an
   ending reported time_s 9 s (tick rate / time accounting on 512 maps).
3. **Soak hook for INTEG7** (`tools/lp_soak7.gd`): headless AI-vs-AI run on last_protocol that reaches the Tide and
   prints one result line (time, phase reached, ending, creep, cores, wall-clock); run it and report the line.
4. Run test_lpmode7, test_creep7, test_cnfac7, test_cnsim7, test_turret7, test_threat7, test_lpmap7 and report raw
   RESULT lines. Do NOT re-baseline test_hot_state (ORCH does that at the end); just report whether it changed.
5. Measure LP system cost per tick on last_protocol (shared PC, not a gate number); re-post `fact lp.api` complete.
