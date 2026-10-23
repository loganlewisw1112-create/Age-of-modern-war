# RTS: Age of Modern War: first playable slice (G0+G1)

A classic real-time strategy skirmish built in **Godot 4.7.2**. It is offline and single-player.

You play **Human A (Modern Military Power) at Stage 8** against one autonomous AI on the **River Crossing** map: a river valley with one bridge, two fords, forests and ridges.

## What you can do in this build
- Start a skirmish from the menu: seed, starting credits, AI difficulty, and victory (HQ elimination or Endless).
  - All 13 stages are listed. Only Stage 8 is playable in this slice.
- **Economy:**
  - Engineers gather salvage and ore and deliver them to the HQ or a depot.
  - Credits come from the treasury plus an HQ stipend.
  - Power is a flow: generators produce it, and production stalls with LOW POWER when it runs short.
  - The supply cap comes from the HQ and depots.
- **Build:** generator, depot, barracks, motor pool and guard tower. A placement ghost shows a legal or illegal reason and the cost.
- **Train:** work crews, rifle squads (4), AT teams (2), recon scouts, IFVs and main battle tanks.
- **Fight:**
  - Select by click, drag, shift or double-click.
  - Right-click is a smart command (move, attack, gather or assist construction).
  - Hotkeys: A attack-move, S stop, H hold. Ctrl+1–9 saves a control group and 1–9 recalls it.
  - Armor classes matter: small arms barely scratch tanks.
  - Fog of war, with remembered enemy buildings.
  - Vehicles and buildings leave persistent wrecks.
- **Win** by destroying the enemy HQ, or play Endless. The AI follows the same rules you do:
  - it issues the same commands;
  - it pays the same costs;
  - it only knows what its units can see.
  - It won't launch an offensive before a grace period: about 7 minutes on Normal, 10 on Easy, 5 on Hard.
- Save and load: F5 / F9, or the pause menu.

## Run it
```bash
"/c/Users/logan/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64.exe" --path game
```
(Install Godot with `winget install GodotEngine.GodotEngine --version 4.7.2` if needed. Run from the repository root.)

Useful flags (after `--`):

| Flag | What it does |
|---|---|
| `--autostart` | Skip the menu |
| `--autostart-seed=N` | Set the match seed |
| `--player-ai --speed=8` | Watch AI vs AI |
| `--ui-playtest=<dir>` | Scripted UI playtest |
| `--autoshot=<png> --autoshot-delay=N` | Save a screenshot after N seconds |

## Verify it
```bash
bash game/tests/run.sh
```
This runs 60 headless tests: ledger conservation, command validation, placement rules, power/supply stalls, pathing, combat, fog fairness, victory, save round-trip, same-seed determinism, AI autonomy and AI fairness. Other checks:
- `game/tools/soak.gd`: AI vs AI to a winner.
- `game/tools/bench.gd`: sim performance.
- `game/tools/ui_playtest.gd`: a menu → build → train → attack-move flow driven by synthetic input.

## Status (honest)
- **Done and verified:** G0+G1 core loop. Evidence is in `PROGRESS.md`.
- **Measured performance:** about 256 fighting units sustained at 20 Hz on this PC. 512 is over budget. See `perf/PERF_REPORT_2026-10-23.md`.
- **Not in this slice:**
  - 3 distinct factions (the AI uses the Human A roster as a test economy);
  - 3 maps;
  - Stage 7→8→9 progression;
  - officers, cover/suppression, component damage, supply lines, destructible bridges;
  - audio;
  - an exported build.
  These are gates G2–G4 in the roadmap.
- All costs and stats are **provisional balance fixtures** (`game/content/*.json`), not approved numbers.
- Design sources: `RTS_Age_of_Modern_War_Claude_Handoff/` (immutable). Engineering contract: `game/docs/CONTRACTS.md`.
