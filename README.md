# RTS: Age of Modern War

A single-player real-time strategy war in Godot 4.7.2. Skirmish still stands — three factions, stages, salvage and steel — but the heart of the current build is **Last Protocol**: one night against the Machine tide, walls and robots and a war that does not pause for breath.

Branch **`g71`** is G7.1 *Tide Line*. **UP71** is underway: finish G7.1 Done-when + polish, chase LP-peak toward 60, then G8 Four Sides and G9 Hive Reborn — one continuous phase. It is playable. G7.1 is not locked yet.

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

## In this build (G7.1 + UP71 Stage A polish, live)

Hive network, wildfire and fire-lines, machine death chains, harvester swarms, capture and evolve, night illumination, weather wind and fog, request queue, robot fleet under jam, research / RE / warmind / conduct / infection / Lazarus, core-raid phases, efficiency HUD grades, tide-song audio, Wave 6 art + E4 motion, and forced-join cuts so the view stays off the sim thread.

**UP71 polish (Stage A2):** turret-eater latch clear + sapper jam radius events; Reclaimer body-piles as tagged wreck cover; Glass stalker reveal via thermal / rain-mist / smoke; fleet board counts (docked / charging / damaged / lost / in production) on the LP HUD.

Look samples ship with every package (`G71_LOOK_CHECKPOINT`).

**Perf (Done-when 3):** zoomed-out pan **p10 68.3** (gate ≥60 CLEAR); 2k **p10 69.9** (gate ≥60 PASS). LP peak amended gate **≥30 CLEAR** (prior quiet 42.8). UP71 chase mid-flight: noisy remasure **p10 48.9** after far-LOD overlay throttle + advisor HUD budget (gap_to_60 ≈11). Quiet remasure continues.

**Soaks / smoke:** Done-when smoke **21/0**. Live siege 600 **SIEGE_DONE** (feints=6, jam no-hack, RE/breakout/raid). Soak90 PASS. Durable 3600 running. Gore71 two-run hash green + bodies logged on soak/siege marks.

---

## Still open (UP71)

- Stage A: durable 60-min soak finish + quiet PEAK60 remasure + G7.1 LOCK.
- Then G8 Four Sides → G9 Hive Reborn (scopes frozen in `game/docs/G8_SCOPE.md`, `G9_SCOPE.md`).
- Frozen Done-when is never weakened to make a check pass.

---

## Branch & ship

- Active branch: `g71` (UP71 execution)
- Board: `game/.plan/upgrade_board/` (permanent semantic CLAIM board)
- Every tested slice: commit → push `github` → `game/.plan/package_g71.ps1` → playable folder + zip in Downloads (keeps the newest 2). Root README updated every ship.
- Smoke: `powershell -File game/tools/g71_donewhen_smoke.ps1` (21 suites incl. AIRFIX; last run 0 fails)
- Short soak: `godot --headless --path game -s res://tools/g71_soak_short.gd -- --secs=90`
- Live siege: `godot --headless --path game -s res://tools/g71_live_siege.gd -- --secs=600`
- Durable soak: `... g71_soak_short.gd -- --secs=3600 --save_at=1800`

Build tag in Downloads embeds the short git hash so you always know which commit you are playing.
