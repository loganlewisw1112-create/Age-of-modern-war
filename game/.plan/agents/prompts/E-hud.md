# E-hud: HUD, menus, app flow
MAX_TOKENS 500000 | MAX_TOOL_CALLS 130 | model sonnet (bounded UI spec)

You own `presentation/main.gd`, `presentation/main.tscn`, `presentation/menu/**`, `presentation/hud/**`.
Implement the HUD, main menu and pause/end screens from CONTRACTS.md section 7. Keep the `--autoshot` hook in main.gd
working, and add `--autostart` (skips the menu and starts the default match) plus `--autostart-seed=N`.

Details:
- The MatchView API (agent D, concurrent) is in CONTRACTS section 7. The current stub has `world`, `selection`, `issue`,
  `begin_build_placement` and `selection_changed`. Code defensively with `has_method`/`has_signal` for the newer members
  (`world_events`, `get_hover_info`, `center_camera_on`, `control_groups`, `speed`, `paused`).
- Read display values straight from `match_view.world` (factions, entities). Never mutate sim state except through
  `match_view.issue(cmd)`. Production and build buttons show their cost and a disabled reason:
  `world.preview_command(cmd)` returns the reason, and `Construction.placement_error` covers placement. Hotkeys follow the
  `hotkey` fields in `content/production.json` and `buildings.json`. The build menu opens with B when engineers are selected.
- Alerts feed: subscribe to `world_events`, with severity colours. Show:
  - CommandRejected reasons for the player's commands;
  - ConstructionCompleted, ProductionCompleted, ProductionBlocked (with its reason);
  - "Base under attack" (throttled), when the player's entities take damage (ShotFired with a target owned by the player);
  - SideEliminated, MatchEnded.
- Minimap 192x192: terrain colours + fog + own units/buildings + enemies (only visible or remembered) + the camera rectangle.
  Click/drag moves the camera (`center_camera_on`).
- Save/Load: agent F writes `sim/save_system.gd` (`save(w, path) -> String`, `load(path) -> SimWorld`). Until it exists,
  check `ResourceLoader.exists("res://sim/save_system.gd")` and disable the buttons with "Save system pending".
  F5 quick-saves to `user://saves/quick.sav`, and F9 quick-loads. On load, rebuild the MatchView with the loaded world.
- Theme: dark military UI (gunmetal panels, amber/olive accents, readable 14-16 px font, UI scale option 1.0/1.25/1.5).
  Build it in code; no external fonts are needed.
- Main menu: per CONTRACTS section 7. "Start" validates with `SimWorld.validate_config` and shows the reason inline if invalid.
  Also add a "How to play" panel (controls list).
- UI-01: a new player must be able to go from HQ to depot/barracks to a trained squad using the contextual UI alone. Add a short dismissible objectives checklist
  (Build a Generator, Build Barracks, Train a Rifle Squad, Find and destroy the enemy HQ) that ticks off from real events.
- Verification: take autoshots of the menu, the in-match HUD with engineers selected (build menu), a selected barracks (production),
  the pause menu and the end screen (force it with a debug arg `--debug-end=win|lose`). View them with the Read tool and save them under
  `.plan/shots/E-hud/`. Add `tests/test_hud.gd` ONLY if you can test logic headlessly (e.g. the objectives tracker).
