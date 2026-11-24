# RTS: Age of Modern War

Offline single-player real-time strategy in **Godot 4.7.2**, with a Rust native sim core. Classic skirmish plus a dedicated siege mode (**Last Protocol**). Tech climbs through **thirteen stages** (Age-of style eras): early recovery through modern combined arms into late synthetic forms.

Branch **`g71`**. Gates through **G7.1**, **G8**, **G9**, and the **Pre-G10 Depth Bridge** are closed (`pre_g10.lock`).

---

## What this is

- **Skirmish** — pick faction, stage band, map, teams, and victory rules; fight up to three AI sides.
- **Last Protocol** — hold a fortified facility against an escalating Machine siege on its own map and ruleset (not a skirmish preset).
- **Long-term** — a chaptered campaign, underground expansion content, Living World, and later orbit/arrival content are planned; see below.

The game stays offline. Balance numbers in content JSON are provisional fixtures, not final.

---

## Skirmish

Open **Main menu → Skirmish**.

### Factions (playable now)

| Faction | Role |
|---|---|
| **Human A** | Modern military combined arms |
| **Human B** | Industrial / salvage power |
| **Machine** | Autonomous energy-bound network |

Additional factions unlock through later development and play; this README does not list unreleased or discovery-gated identities.

### Stages / tech eras

There are **thirteen stages**. In the current build, sides typically start in the **mid–late band** (roughly Stages **7–10**): research mid-match and advance when stage gates are met. Earlier and later stage bands for existing factions are planned for a later slice; a forthcoming faction ships its own full 1–13 band when that gate lands.

### Setup (high level)

- **2–4 sides** — You / AI / Closed; faction, team, colour, starting credits, AI difficulty
- **Teams or free-for-all** — allies share vision
- **Economy profile** — arcade / standard / simulation
- **Maps** include River Crossing (96²), Industrial Heartland (160²), Valley Conquest (256²); custom maps from the editor can be selected when saved
- **Victory modes** — HQ elimination, territory control, hold-the-bridge, Endless, or combined AND/OR rules
- Optional **adaptive Machine director** toggle on setup; capped siege units accept attack-move

### What a match includes

Economy (salvage/ore, power flow, supply), build/train, fog of war, armour classes, wrecks, walls/gates, air and naval layers, companies/armies and chain of command, EW, field forts, vehicle crews/wear, and AI that pays the same costs and only knows what it sees. Full system history lives under `game/docs/` and older slice notes in `game/README.md`.

---

## Last Protocol

Separate mode: **Main menu → Last Protocol**.

You inherit a living two-ring fortress around a central facility and hold it through night-heavy siege pressure. Kill remote Machine cores to break the tide; fail and the countdown finishes the job. Night lasts longer than day; the clock starts at dusk.

End of a run: director picture-in-picture beats, highlight reel, creep timelapse, and kill-heat strip. **Ctrl+M** toggles a minimal cinematic HUD. Specific hive forms, endings, and late tools are left for play — this README will not list them.

Canonical entry remains Human A vs Machine. Later slices may add alternate defender profiles without changing the solo reference ruleset.

---

## Campaign (planned)

Working title: **Inheritance**. Vision is recorded in `game/docs/CAMPAIGN_VISION.md` (not contracted build scope yet; roadmap places it as a later gate).

Public shape only:

- **Thirteen chapters**, one per stage — from scattered survivors through modern war into late synthetic eras
- **Founder lifetime** early, then **heir generations**
- **Regional map hub** (real-time, pausable) with authored operations; every battle is played in the same RTS sim
- **Carry-over** — scars, people, grudges, builds
- **Story** (retry) and **Dynasty / Ironman** modes
- Roughly **60–80 hours** targeted across the arc
- After the finale: an endless **Living World** on the same save

Story twists, secret identities, and chapter beats stay out of this README. **Last Protocol stays a separate mode** from the campaign Machine war.

---

## Addons / expansions (roadmap)

Not shipped. High-level only, from the owner-approved roadmap (`game/docs/ROADMAP.md`):

| Track | What it is |
|---|---|
| **UNDERSTRIKE** | Human A–only underground bunkers, floors, borers, and later networked underground civilization (multi-phase) |
| **All Thirteen** | Early (1–6) and late (11–13) stage parity for factions that still lack those bands |
| **Inheritance** | The 13-chapter campaign above |
| **Living World** | Post-campaign endless dynasty / continental layer |
| **Orbit / arrivals** | Space tier and further factions after Living World |
| **Last Protocol co-op** | Offline-first 2–4 player siege on the same LP ruleset; solo LP stays the 1v1 reference |

Treat these as a shipping pipeline, not a storefront promise. Each gate still gets its own frozen Done-when before build.

---

## Development pipeline

### Shipped (orientation)

G0 engine → G1 core RTS → G2 smart warfare → G3a/G3b factions, stages 7–9, maps → G4 editor / walls / scale → G5 air/naval/hospitals/tutorial → G6 elevation, companies, marketplace → G6.1 field command → **G7 Last Protocol** → **G7.1** Tide Line siege depth → **G8** Four Sides view rotation + end-of-run presentation → **G9** Machine overhaul + combat depth → **Pre-G10** AI/economy depth bridge (closed).

### In this Pre-G10 build (summary)

- **Four Sides:** Q/E or horizontal middle-mouse drag rotates the view 90°; art sheets follow the camera
- **Last Protocol** dusk clock; night **2×** day; end-of-run presentation suite
- **Hive / counters / combat / skirmish** depth from G9; **AI9** evidence adaptation and named generals; **ECON9** rare metals, trade, territory support, tiered research, black market
- Look samples ship with packages (`G71_LOOK_CHECKPOINT`)

### Next gates (planned order)

| Gate | Headline (public) |
|---|---|
| **G10** | Fourth faction + related counterplay (in progress on `g71`) |
| **G11–G13** | UNDERSTRIKE foundation → military → networked underground |
| **G12** (with soldiers/theatres) | Human depth, biomes/modes; optional uncapped skirmish population |
| **G14** | Remaining factions’ Stages 1–6 and 11–13 |
| **G15** | Campaign *Inheritance* |
| **G16–G17** | High-fidelity underground; Living World |
| **G18** | Orbit / arrival expansion |
| **G19** | Last Protocol co-op |

Detail and acceptance live in `game/docs/ROADMAP.md`. Design contracts and older slice evidence: `game/docs/CONTRACTS*.md`, `game/README.md`.

---

## Play the packaged build

Latest Windows package (auto-refreshed every ship):

`Downloads\Age of Modern War\RTS_Age_of_Modern_War_G71_*`

Keep these three together:

- `RTS_Age_of_Modern_War.exe`
- `RTS_Age_of_Modern_War.pck`
- `rts_core.dll`

Double-click the exe. Main menu → **Last Protocol** or **Skirmish**.

Also in that folder: `PLAY_ME.txt`, look-checkpoint strips under `G71_LOOK_CHECKPOINT/`, and a matching `.zip` beside the folder.

### From source (dev)

- Godot **4.7.2**
- Open `game/`, or run `game/run.bat` (Windows) / `bash game/run.sh`
- Install tip: `winget install GodotEngine.GodotEngine --version 4.7.2`, or set `GODOT` to your exe

Useful launcher flags (append): `--autostart`, `--autostart-seed=N`, `--autostart-factions=human_a,human_b,machine`, `--autostart-map=<id>`, `--player-ai`, `--speed=8`.

---

## How to fight

- Select: click, drag, shift, double-click. Right-click is the smart order.
- Hotkeys: **A** attack-move, **S** stop, **H** hold. Ctrl+1–9 control groups. **Q / E** (or horizontal middle-mouse drag) rotate the view 90°.
- **Ctrl+M** — minimal Last Protocol HUD.
- Save / load: F5 / F9 (or pause menu).

---

## Branch & verify

- Active branch: `g71` (`pre_g10.lock` CLOSED)
- Ship path: commit → push `github` → `game/.plan/package_g71.ps1` → playable folder + zip in Downloads (keeps the newest 2). Build tag embeds the short git hash.
- Smoke: `powershell -File game/tools/g71_donewhen_smoke.ps1`
- Short soak: `godot --headless --path game -s res://tools/g71_soak_short.gd -- --secs=90`
- Tests from source: `bash game/tests/run.sh`

---

## Docs map

| Doc | Use |
|---|---|
| This file | Public overview for GitHub |
| `game/README.md` | Historical playable-slice notes (G0–G7.1 era) |
| `game/docs/ROADMAP.md` | Full gate order to finished game |
| `game/docs/CAMPAIGN_VISION.md` | Campaign / Living World / space vision (spoiler-heavy — for contributors who need it) |
| `game/docs/understrike/` | UNDERSTRIKE design handoff |
