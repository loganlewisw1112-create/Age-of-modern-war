# RTS: Age of Modern War

A single-player real-time strategy war in Godot 4.7.2. Skirmish still stands — three factions, stages, salvage and steel — but the heart of the current build is **Last Protocol**: one night against the Machine tide, walls and robots and a war that does not pause for breath.

Branch **`g71`**. **G7.1 Tide Line Done-when is CLOSED.** **G8 Four Sides Done-when is CLOSED (`g8.lock`).** UP71 continues into **G9 Hive Reborn**.

---

## Last Protocol

You hold a fortified ring while the hive learns you. Creep eats the land. Nests pulse. Wildfire walks with the wind. Captured machines go to the study cells; some come back as hard-won knowledge, some break out. Your robot fleet fights under jamming without flipping sides. The war-mind can be fooled. Conduct has a cost. The clock starts at dusk; night lasts twice as long as day — when it deepens, searchlights and muzzle flash are all the map you get.

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
- Common hotkeys: **A** attack-move, **S** stop, **H** hold. Ctrl+1–9 control groups. **Q / E** (or horizontal middle-mouse drag) rotate the view 90° (G8 Four Sides). Rot buildings and loco / fire / death / k8 sheets follow the camera (no mirror cheats on rot_0..3).
- **Ctrl+M** — minimal Last Protocol HUD (cinematic).
- End of a Last Protocol run: director PiP beats, highlight reel, creep timelapse, and kill-heat strip on the after-action screen.
- Save / load: F5 / F9 (or pause menu).
- Skirmish still works from the main menu if you want a classic match.

---

## In this build (G8 LOCK)

**Four Sides:** Q/E + MMB rotate the view; rot buildings and loco/fire/death/k8 sheets follow the camera (no mirror cheats). **Last Protocol clock** starts at dusk; night lasts **2×** day. End-of-run: director PiP, highlight reel, creep timelapse, kill-heat strip.

Plus G7.1: hive network, wildfire, death chains, harvest / capture / evolve, night illumination, weather, fleet under jam, RE / warmind / conduct, Wave 6 art + E4 motion, Stage A polish, forced-join cuts.

Look samples ship with every package (`G71_LOOK_CHECKPOINT`).

**Perf:** pan **p10 68.3**; 2k **p10 69.9**; quiet chase **p10 72.9** (amended peak gate ≥30 still held — remasure FACT cites prior evidence; chase continues into G9).

**Soaks / smoke:** Done-when smoke includes G8 suites. Soak90 / 3600 / live siege 600 GREEN from G7.1 lock evidence. Gore71 + LP two-run hash green.

---

## Still open (UP71)

- **G9 Hive Reborn** next — scope `game/docs/G9_SCOPE.md`.
- Peak chase continues across G9 (amended G7.1 gate held).
- Frozen Done-when is never weakened to make a check pass.

---

## Branch & ship

- Active branch: `g71` (UP71 → G9)
- Board: `game/.plan/upgrade_board/` (permanent semantic CLAIM board)
- Every tested slice: commit → push `github` → `game/.plan/package_g71.ps1` → playable folder + zip in Downloads (keeps the newest 2). Root README updated every ship.
- Smoke: `powershell -File game/tools/g71_donewhen_smoke.ps1` (G7.1 + G8 suites; last lock run 0 fails)
- Short soak: `godot --headless --path game -s res://tools/g71_soak_short.gd -- --secs=90`
- Live siege: `godot --headless --path game -s res://tools/g71_live_siege.gd -- --secs=600`
- Durable soak: `... g71_soak_short.gd -- --secs=3600 --save_at=1800`

Build tag in Downloads embeds the short git hash so you always know which commit you are playing.
