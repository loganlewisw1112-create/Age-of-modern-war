# RTS: Age of Modern War

A single-player real-time strategy war in Godot 4.7.2. Skirmish still stands — three factions, stages, salvage and steel — but the heart of the current build is **Last Protocol**: the siege the rest of the game was built to earn.

Branch **`g71`**. **G7.1 Tide Line Done-when is CLOSED.** **G8 Four Sides Done-when is CLOSED (`g8.lock`).** UP71 continues into **G9 Hive Reborn**.

---

## Last Protocol

Something under the world is finishing a count. When it hits zero, there is no second chance — only the Protocol.

You are the last ring still standing: walls, guns, people who know the gates by heart, and machines that still answer to your side. Outside, the hive does not advance like an army. It *learns*. Land turns wrong. The dark lasts longer than the day. Somewhere in the tide, things that should not speak do.

**Your brief is simple.** Hold until the cores fall or the count ends you. Keep the rings. Spend what you earn — intel, scrap, captured steel, hard choices — without knowing which door leads out. Tools exist for those who dig: eyes that cut the dark, steel that will not turn, fire that refuses the ground, a war-mind that can be lied to. Use them. Or don't. The Protocol does not explain itself.

Win, and dawn still feels like a question. Lose, and you will understand why it was called *Last*.

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
