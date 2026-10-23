# D2-view: G2 presentation + HUD (everything players see/do for G2)
MAX_TOKENS 600000 | MAX_TOOL_CALLS 150 | model opus (multi-file UI integration)

You own `presentation/**` except `presentation/art/**` (agent E2). The G1 files to extend are `presentation/match_view.gd`, `presentation/view/*.gd`, `presentation/hud/*.gd`, `presentation/main.gd` and `presentation/menu/*.gd`. Read them before editing; they are large, so read selectively. Keep every G1 debug flag working (`--autostart`, `--autoshot`, `--player-ai`, `--speed`, `--ui-playtest`, `--spawn-test`, `--demo-script`).

Implement CONTRACTS_G2.md section 5 (D2), with the event fields from section 7. The sim systems are being built concurrently by A2 (damage/morale), B2 (supply/repair), C2 (ops/orders/bridges), so code against the contract fields and events. Fields may be absent on older entities, so default safely. Never mutate sim state except via `match_view.issue(cmd)`.

Must-haves:
1. **Inspector:**
   - Ammo bar and fuel bar (vehicles).
   - MOB/WPN/SEN chips (green >50, amber >0, red 0).
   - Tags: PINNED, BROKEN, IN COVER, NO AMMO, NO FUEL.
   - For an officer, or a unit in a group: a group card showing mission, phase, reason, progress bar and the last 3 reports.
2. **World overlays:**
   - A pinned/suppressed marker over infantry.
   - A cover shield pip when in_cover.
   - A smoke/fire loop over vehicles with any disabled component (use `ArtCatalog.effect_frames("smoke")` until E2 adds `disabled_smoke`).
   - Retreat chevrons on broken units.
   - A thin line from the officer to the mission target, and a radius ring when the officer is selected.
3. **Top bar:** fuel and ammo stock, and a LOW tag when below 100.
4. **Commands and hotkeys:**
   - Officer selected together with units: an "Assign to officer" button.
   - Officer selected: a Mission panel. Pick secure/hold/attack/patrol, then click a map target (patrol: shift-click several points, Enter to confirm), pick risk low/medium/high, and Cancel mission.
   - Units selected: Patrol (Q, then shift-click points and right-click to finish), Guard (click Guard, then click a friendly), Formation (F cycles line/wedge/column; show the current one).
   - Engineers: right-click an own damaged unit/building/ruined bridge issues smart `repair`, and there is a Repair button.
   - Right-click the bridge with combat units: show a context hint "Shift+right-click to demolish". Shift+right-click issues `attack` on the bridge. This prevents accidental demolition.
   - Refinery in the build menu (hotkey F conflicts with formation: in the engineer build card use **N** for refinery, i.e. map key N → refinery when engineers are selected. Formation F applies only to combat units.) The logistics truck and officer already appear through production.json.
5. **Bridge visuals:** intact/damaged (hp < 50%)/ruined. Until E2's sprites land, draw a darkening/broken-plank overlay procedurally. The terrain chunk bake must re-bake affected chunks on BridgeDestroyed/BridgeRepaired, because the terrain array changes.
6. **Alerts** for ComponentDisabled (own: "Tank immobilized!"), UnitBroken (own), OfficerReport (own, phase changes only), SupplyShortage, BridgeDestroyed/BridgeRepaired, RepairBlocked.
7. **Objectives panel:** add "Assign an officer and give a mission" as a 5th objective (the objectives tracker ticks from the OfficerReport event).

Verification: autoshots of each must-have (use `--demo-script` names you add, e.g. `g2_inspector`, `g2_officer`, `g2_bridge_ruined`, built from debug world mutations). View every one with Read. Save them to `.plan/shots/D2-view/`. Run the full test suite at the end; presentation has no unit tests, but nothing must break. Report the fps with `--spawn-test=200`. It must not drop more than 10% vs G1's 41-59 (G1 report).
