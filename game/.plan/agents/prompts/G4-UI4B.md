# UI4B: player UI for walls, gates, transports, new unit commands
Read G4_COMMON.md first. Contract: CONTRACTS_G4 §1, §6, §7, §8.
**Owns:** `presentation/hud/g4b_*.gd`, `presentation/view/g4b_*.gd`, `tools/ui_playtest.gd`. Wiring into `hud.gd`/`match_view.gd` (THREAD owns those) goes through CHANGE_REQUESTs to THREAD with exact small hooks. Read the UI only through THREAD's render snapshot API (`w.render_snap`, CONTRACTS_G4 §4; `fact thread.snapshot_api`), never the live world.
**Depends on:** FORT (`fort.api_ready`), TRANS (`trans.api_ready`), UNITS (commands).

Tasks:
1. **Wall drag tool:**
   - pick a wall from the build card → drag a line → preview segments (valid green / invalid red), cost total, 8-direction snap;
   - release issues `build_line` (Shift appends);
   - gate/tower placement as single buildings;
   - a gate panel with a Lock/Unlock button.
2. **Transport UI:**
   - right-click a carrier with infantry selected → `load`;
   - carrier selected → a cargo panel (slot icons, per-unit unload), Unload-at-point (click a target), Unload all;
   - a cargo count badge over the carrier;
   - an officer mission button "Transport to point".
3. **New unit commands:** mortar Deploy/Pack, engineer Lay mine / Plant charge (targeted), plus mine markers for own mines and detected enemy mines (view).
4. Hotkeys that don't collide with existing ones (check `g3_faction.gd` / `g2_commands.gd`).
5. `tools/ui_playtest.gd` gets a `--ui-playtest-g4b` flow:
   - build an APC; drag a 6-segment wall with a gate; lock and unlock the gate;
   - load a squad into the APC; unload at a point; deploy a mortar.
   - The 4 existing flows must still pass (human 33, human_b 37, machine 37, stages 53).
6. Screenshots in `.plan/shots/UI4B/`, self-checked with Read.

Done when: tasks 1-6 are done and the playtests pass. MAX_TOKENS 600000, MAX_TOOL_CALLS 150, board id `UI4B`.
