# RTS: Age of Modern War

A single-player real-time strategy war in Godot 4.7.2. Skirmish still stands — three factions, stages, salvage and steel — but the heart of the current build is **Last Protocol**: one night against the Machine tide, walls and robots and a war that does not pause for breath.

Branch **`g71`** is G7.1 *Tide Line*. It is playable. It is not finished.

---

## Last Protocol

You hold a fortified ring while the hive learns you. Creep eats the land. Nests pulse. Wildfire walks with the wind. Captured machines go to the study cells; some come back as hard-won knowledge, some break out. Your robot fleet fights under jamming without flipping sides. The war-mind can be fooled. Conduct has a cost. When the night deepens, searchlights and muzzle flash are all the map you get.

This is the siege the rest of the game was built to earn.

---

## Play the packaged build

Latest Windows package (auto-refreshed every ship):

`Downloads\Age of Modern War\RTS_Age_of_Modern_War_G71_*`

Keep these three together:

- `RTS_Age_of_Modern_War.exe`
- `RTS_Age_of_Modern_War.pck`
- `rts_core.dll`

Double-click the exe. Main menu → **Last Protocol**.

Also in that folder: `PLAY_ME.txt`, look-checkpoint strips under `G71_LOOK_CHECKPOINT/`, and a matching `.zip` beside the folder.

From source (dev): Godot **4.7.2**, open `game/`, or `game/run.bat`.

---

## How to fight

- Select: click, drag, shift, double-click. Right-click is the smart order.
- Common hotkeys: **A** attack-move, **S** stop, **H** hold. Ctrl+1–9 control groups.
- **Ctrl+M** — minimal Last Protocol HUD (cinematic).
- Save / load: F5 / F9 (or pause menu).
- Skirmish still works from the main menu if you want a classic match.

---

## In this build (G7.1, live)

Hive network, wildfire and fire-lines, machine death chains, harvester swarms, capture and evolve, night illumination, weather wind and fog, request queue, robot fleet under jam, research / RE / warmind / conduct / infection / Lazarus, core-raid phases, efficiency HUD grades, tide-song audio, and forced-join cuts so the view stays off the sim thread.

Look samples for owner review ship with every package (`G71_LOOK_CHECKPOINT`).

---

## Still open (Done-when holds)

- **Owner look checkpoint (E3)** — approve or reject each sample; full art roll-out waits on that.
- **E4 animation** — after look approval.
- **LP peak fps** — amended gate p10 ≥ 30 with 1,000+ machines (still under on quiet remeasures; work continues).
- **60-minute peak siege soak** and live RE / warmind siege length.
- Strict 2k / zoomed-out panning vs every past build where the frozen bar still applies.

Frozen Done-when is never weakened to make a check pass.

---

## Branch & ship

- Active branch: `g71`
- Every tested slice: commit → push `github` → `game/.plan/package_g71.ps1` → playable folder + zip in Downloads (keeps the newest 2).
- Smoke: `powershell -File game/tools/g71_donewhen_smoke.ps1`
- Short soak: `godot --headless --path game -s res://tools/g71_soak_short.gd -- --secs=90`

Build tag in Downloads embeds the short git hash so you always know which commit you are playing.
