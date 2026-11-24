# RTS: Age of Modern War

A single-player real-time strategy war in Godot 4.7.2. Skirmish is the sparring floor. **Last Protocol** is the night they built the game to survive.

Branch **`g71`**. **G7.1**, **G8**, **G9**, and the **Pre-G10 Depth Bridge** are CLOSED (`pre_g10.lock`).

---

## Last Protocol

Somewhere under the map, a clock is still counting. Nobody who wrote the Protocol is left to explain what happens at zero. You get one night. Maybe two if you steal the dark and make it yours.

### The ground you inherit

You don't drop into an empty sandbox. You inherit a living fortress already under pressure:

- **Two rings of wall** — outer kill-zone and a hard **core** around the heart of the base.
- Between them: the economy that keeps guns fed, pads hot, and wounded moving.
- At the centre: the **facility** — command, labs, workshops, pads on the roof, doors that open into a war that never clocks out.
- Gates with approach belts. Cameras on the corners. Helipads already loaded. An army on the wire — and a reserve held back behind the last wall, because someone before you knew the first wave is never the real one.
- On the far horizon: **Machine cores**. Kill them and the tide can break. Fail, and the count finishes what the hive started.

The clock starts at **dusk**. Night lasts longer than day here. When the lights die down to searchlights and muzzle flash, the map stops being a map and starts being a confession.

### Why you fight

The hive is not a faction. It is a *process*. Creep eats the land. Nests pulse. Something in the dark adapts to how you hold a wall, how you rotate a sector, how you panic. It will feint. It will learn your weak face. It will climb its own dead if that is what the wall demands.

You are not here to farm a leaderboard. You are here because if this ring falls, there is no next ring.

### What you actually do

Hold. Rotate. Fall back only when the Protocol would rather you live than die proud on a cracked rampart. Strike the cores when the night opens a seam. Spend what the siege pays you — scrap, captured steel, intel, research scratched out under fire — without a tutorial telling you which door is mercy and which is a trap.

There are tools. Loyal robots that refuse the hive's handshake. Eyes that see what camo thinks is invisible. Fire that redraws the approaches. A war-mind you can lie to. Conduct that costs more than ammo. None of them come with a ribbon that says *press this to win*. The game wants you hungry. It wants you wrong once, then dangerous forever.

### The part we won't spoil

There are things in the tide with names you will earn the hard way. There are endings that change what dawn means. There is a reason the Protocol is called *Last* — and the only way to learn it is to still be standing when the count runs out… or to watch the facility go quiet and know exactly what you traded.

**Main menu → Last Protocol.** Bring a pulse.

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

## In this build (Pre-G10 release candidate)

**Four Sides:** Q/E + MMB rotate the view; rot buildings and loco/fire/death/k8 sheets follow the camera (no mirror cheats). **Last Protocol clock** starts at dusk; night lasts **2×** day. End-of-run: director PiP, highlight reel, creep timelapse, kill-heat strip.

**G9 depth complete:** HIVE9 has 60 blended Machine definitions, eat/replicate/modular depth, quality-aware mesh/spine links and severable shared senses. COUNT9 exposes all thirteen counters through play paths and temporary coalitions.

**Combat and skirmish:** persistent field forts, vehicle crews/bail/recrew, wear/breakdown/recovery, deeper EW and multi-class weak spots. Skirmish setup now has the adaptive Machine-director toggle, and capped siege units accept attack-move. PACE71 raises open-ground vehicle tempo to ~1.7× while preserving terrain and deployment friction.

**AI9 + ECON9:** evidence-driven composition adaptation, five named rival generals, temporary anti-Machine diplomacy, intelligence-only difficulty, and recon→fix→assault→exploit operations. Matches add gathered rare metals, location-mix trade posts, territory/civilian support, tiered research and a black-market tier.

Plus G7.1: hive network, wildfire, death chains, harvest / capture / evolve, night illumination, weather, fleet under jam, RE / warmind / conduct, Wave 6 art + E4 motion, Stage A polish, forced-join cuts.

Look samples ship with every package (`G71_LOOK_CHECKPOINT`).

**Perf:** pan **p10 68.3**; 2k **p10 69.9**; Pre-G10 peak remasure **p10 116.8** (amended peak gate ≥30 and chase target ≥60 held).

**Soaks / smoke:** expanded Done-when smoke includes G7.1 + G8 + G9 + PACE71 + AI9 + ECON9. The three-faction coalition soak forms and breaks its truce deterministically.

---

## Still open (UP71)

- **G10 Shadow Coalition** — full faction Stages **1–13** (1–6 raiders, 7–10 core, 11–13 late syndicate); scope
  `game/docs/G10_SCOPE.md` · ROADMAP; AI/economy depth already under `pre_g10.lock`.
- Peak chase continues (amended G7.1 gate held; target 60 p10).
- Frozen Done-when is never weakened to make a check pass.

---

## Branch & ship

- Active branch: `g71` (`pre_g10.lock` CLOSED)
- Board: `game/.plan/upgrade_board/` (permanent semantic CLAIM board)
- Every tested slice: commit → push `github` → `game/.plan/package_g71.ps1` → playable folder + zip in Downloads (keeps the newest 2). Root README updated every ship.
- Smoke: `powershell -File game/tools/g71_donewhen_smoke.ps1` (expanded Pre-G10 suites)
- Short soak: `godot --headless --path game -s res://tools/g71_soak_short.gd -- --secs=90`
- Live siege: `godot --headless --path game -s res://tools/g71_live_siege.gd -- --secs=600`
- Durable soak: `... g71_soak_short.gd -- --secs=3600 --save_at=1800`

Build tag in Downloads embeds the short git hash so you always know which commit you are playing.
