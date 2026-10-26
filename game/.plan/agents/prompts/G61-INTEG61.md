# G61-INTEG61: integration of finished G6.1 workstreams (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G61_COMMON.md first. SQUAD61, OFF61, CHAIN61, PLAN61, REAL61, BEARER61 and AUDIO61 have finished; their leftover
cross-file wiring is yours. You may edit the files of those FINISHED agents (squad_ai.gd, orders.gd, g2_commands.gd,
hotkeys.gd, teams_panel.gd, ai_army.gd, ai_tactics.gd, doctrine/*, ops*.gd, command_net.gd, intel.gd, plans.gd,
presentation/ui6/command_layer/*, morale/fatigue/veterancy, ammo_bearer.gd, presentation/audio/*) plus ORCH-delegated
files named below. NOT yours (live agents): GEN61-2 (commanders.gd, ai_command.gd, general*.gd, ally_cmds, wave_ai,
doc_strategic, doc_specops, commanders_panel; it may add a small hook in ai_army.gd/doctrine.gd — coordinate on the
board), ANIMA61-2 (entity_layer, batch_art, batch_atlas, motion.gd, infantry drawers), ANIMB61 (vehicle drawers),
VFX61 (fx_layer, fx drawers). Board details for each item are in .plan/board_g61.jsonl (the seq numbers).

1. **Ammo bearer UI** (BEARER61 CR seq 332, was to SQUAD61): Join squad / Leave squad buttons on the bearer's command
   card; right-click a friendly squad member with bearer(s) selected issues join_squad; rebindable hotkeys bearer_join (J)
   and bearer_leave (Shift+J) if free (check collisions; test_ui_panels must stay green); SquadAI.leader_of must skip
   bearers (`ammo_bearer: true`). Add the new card buttons to panel_probe like the squad61 ones (ORCH added that block).
2. **Enemy AI bearers** (CR seq 333, was to OFF61): in ai_army.gd manage_army, on a staggered cadence call AB.ai_attach,
   and queue AB.bearer_def_for when AB.ai_wanted > 0 (Lib.queue_item). Tell GEN61-2 on the board before touching ai_army.
3. **Company presets:** add one bearer slot to each infantry company preset in content/g6/rules_companies.json (ids in
   board fact bearer.defs); test_companies must stay green (plan counts may change: update only counts that are the
   intended change and say so).
4. **test_ai_g6::test_ai_trains_companies_and_forms_army fails: "the AI trained at least two companies (0)".** Cause: G6.1
   train_company now refuses a company that could not deploy (Companies.deploy_reason, owner bug fix). ORCH changed
   sim/ai/ai_g6_co.gd to build a depot when nothing fits supply now (block `if not fits_now`), but the test still sees 0.
   Find out why (log g.co_why over the test run) and fix the AI side (ai_g6_co.gd / ai_econ) — never weaken the test or
   revert the purchase check.
5. **plan61 playtest fails at plan_select_company** (click on company A's captain symbol in command mode gives draft
   formation {}): .plan/shots/ORCH61/pt_plan61.log. Debug cl_overlay formation_at / to_local_pt vs the click point and fix the
   flow or the overlay (if the overlay misses real clicks, that's a game bug: fix it). Then the full flow must pass.
6. **UI fit:** cmd61_mode OVERLAP of RightScroll with CommandCard (move the card); the Teams panel/card pages (sq61_*) and
   the Settings Audio tab are now in the fit screens. Run `--only=test_ui_fit` once at the end (heavy, ~10 min) — 0 issues.
7. Run and make green: test_ui_panels (ORCH changed command_layer Tab -> F3 and added the squad61 probe block),
   test_ui6a, test_ai_g6, test_companies, test_supply, test_units*, test_art_machine, test_art_g3b, test_art_g6, test_content*,
   test_bearer61, test_squad61, test_officers61, test_chain61, test_plans61, test_real61, test_audio61. Run `--import` once
   first (new bearer PNGs + audio wavs need .import files).
8. Playtests, windowed, one at a time (timeout 900): chain61 (ORCH changed the flow to move the whole platoon), plan61,
   bearer61 (now with the real Join button), audio61 (the director is now hooked in match_view and the Audio tab in
   Settings: the flow must find them hooked, not attach them itself). Shots to .plan/shots/INTEG61/.
9. Nice to have: voice the player's own direct orders on the radio (AUDIO61 gap: CommandApplied's "type" is overwritten
   by the event envelope; read the command type from another field or emit a separate event).
Report every test line raw. Flows: write fixes only in the flow files you touch for the reasons above.
