# UI4: setup + stage/research HUD + big-map camera + playtest (CONTRACTS_G3b §7)
Read G3B_COMMON.md first. Files: `presentation/**` except R4's (match_view.gd and view/entity/terrain/fog/fx/overlay layers) and `presentation/art/**`; plus `tools/ui_playtest.gd`.

Dependencies:
- STG4 posts `fact stg4.data_ready` (stage fields, research.json, gate_report) and MAP4 posts maps.json. Build the UI against the contract now, and wire it to real data as it lands (read the board).
- Until `Progression.gate_report` is real it returns []; show "no gates" gracefully.

Order:
1. Skirmish setup:
   - map picker (River Crossing / Industrial Heartland / Valley Conquest, with size and max sides; disable maps that are missing from maps.json);
   - a Stage dropdown per side (7/8/9, from stages.json `playable_now`);
   - an Advancement rules option (Free / Standard / Simulation);
   - the summary line shows map + stages.
   - The config goes to `cfg.map`, `sides[i].stage`, `cfg.advancement`.
   - Add `--autostart-map=<id>` and `--autostart-stages=7,8,9` in `presentation/main.gd`.
2. HUD stage panel:
   - current stage name;
   - gate checklist (have/need, ticks);
   - an Advance button (enabled only when every gate is ok; it submits `advance_stage`);
   - the transition countdown;
   - a toast on `StageAdvanced`.
   Fit the existing HUD style.
3. Research panel when a research building is selected: projects with cost/time, start (submits `research`), progress bar, active project, done ticks.
4. Build/train buttons for unavailable defs show disabled with the reason (from validate_command reasons).
5. Camera bounds, edge-pan speed and minimap scale for 160/256 maps (read map.w/h; no hard-coded 96).
6. ui_playtest: a `--ui-playtest-stages` flow. Setup picks Industrial Heartland (fall back to River Crossing if it is missing) with stages 7/8/9 by clicks, then plays the normal opening plus: build the research building, start a research project by clicking, and check the stage panel shows gates. Keep the existing 3 faction flows passing (37/37).
MAX_TOKENS 500000, MAX_TOOL_CALLS 130, board id `UI4`.
