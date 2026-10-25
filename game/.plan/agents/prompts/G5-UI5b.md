# G5-UI5b: operating guide
Read `.plan/agents/prompts/G5_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G5 §0.6, §1, §4, §5. **Plan:** Plan sections 3, 5, 6, 7.
**Board / bus id:** `UI5b`. **Budget: MAX_TOKENS 700000, MAX_TOOL_CALLS 170** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g5/test_ui_panels.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### UI5b: new command panels and settings
- **Role:** every new control the player uses.
- **Owns:**
  - `presentation/ui5/panels/**`: airfield/hangar panel (strips, hangars, occupants, upgrades, engineers, Buy hangar, "No free hangar"), aircraft commands (sortie, rebase, land here, take off), VTOL cargo, drone picker with the ● counter, tactical-mode buttons, truck Auto (station/roam drag), medic Auto, naval commands, engineer assign cursor;
  - `presentation/hud/g2_commands.gd`, `g4b_commands.gd`, `g3_faction.gd`, `g2_inspector.gd`, `presentation/view/g4b_input.gd`, `g4b_overlay.gd`;
  - `presentation/menu/settings.gd` (graphics, speed, edge-pan, health bars, **key rebinding**);
  - the F1 hotkey sheet.
- **Inputs:** `ui5.kit_ready`; every `*.api_ready` command list.
- **Tasks:**
  1. Build each panel on the kit. Every button calls only the posted commands.
  2. Hotkey map with no collisions (checked by a test).
  3. Settings menu with persistence.
  4. Each panel passes UI5a's fit test.
- **Done-when:** every new command reachable by button + hotkey; the fit test green including the new panels; full suite green.
- **Budget:** 700k / 170.
