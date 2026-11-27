# RTS: Age of Modern War

[![Godot](https://img.shields.io/badge/Godot-4.7.2-478cbf?logo=godotengine&logoColor=white)](https://godotengine.org/)
[![Platform](https://img.shields.io/badge/platform-Windows-0078d4?logo=windows&logoColor=white)](https://godotengine.org/)
[![Branch](https://img.shields.io/badge/branch-g71-111111)](https://github.com/loganlewisw1112-create/Age-of-modern-war)
[![Build](https://img.shields.io/badge/build-G10.1-2ea44f)](#play-the-packaged-build)
[![Status](https://img.shields.io/badge/status-active%20development-orange)](#development-pipeline)

**Build a military civilization. Command its armies. Survive an enemy that adapts.**

Age of Modern War is an offline, single-player real-time strategy game built in **Godot 4.7.2** with a native **Rust simulation core**. It combines civilization-style technological advancement, combined-arms warfare, asymmetric factions, autonomous military command and persistent battlefield systems.

Four playable factions fight across a thirteen-stage technology framework, from early recovery to advanced synthetic warfare. Classic Skirmish and the dedicated **Last Protocol** siege mode are playable now; campaign, underground civilization and continental-scale progression remain roadmap tracks.

**Current build:** G10.1 stabilization · November 27, 2026 · `09313a2d` · branch `g71`. G10 is closed; wider regression acceptance remains open.

[Play the build](#play-the-packaged-build) · [Factions](#factions-playable-now) · [Skirmish](#skirmish) · [Last Protocol](#last-protocol) · [Performance](#performance-and-verification) · [Roadmap](#development-pipeline) · [Developer setup](#from-source-dev)

<p align="center">
  <img src="docs/media/hero.jpg" alt="Last Protocol — the two-ring fortress you inherit and hold" width="1200">
</p>
<p align="center"><em>Last Protocol — the fortress. Two rings. One facility. Hold it.</em></p>
<p align="center">
  <img src="docs/media/hero_last_protocol_dusk.jpg" alt="Last Protocol fortress under dusk light" width="560">
  &nbsp;&nbsp;
  <img src="docs/media/hero_last_protocol_core.jpg" alt="Last Protocol core compound and inner ring" width="560">
</p>
<p align="center"><em>Dusk on the wire · core compound inside the inner wall</em></p>

---

## Game overview

- **Skirmish** — pick faction, stage band, map, teams, and victory rules; fight up to three AI sides.
- **Last Protocol** — hold a fortified facility against an escalating Machine siege on its own map and ruleset (not a skirmish preset).
- **Long-term** — a chaptered campaign, underground expansion content, Living World, and later orbit/arrival content are planned; see below.

The game stays offline. Balance numbers in content JSON are provisional fixtures, not final.

### Core gameplay systems

| System | Gameplay |
|---|---|
| Civilization and economy | Resource gathering, power flow, supply, production, research and trade |
| Combined arms | Infantry, armor, aircraft, naval forces, drones and electronic warfare |
| Field command | Companies, armies, chain of command, suppression, fatigue and veterancy |
| Persistent battlefield | Wrecks, terrain damage, elevation, fortifications and vehicle wear |
| Autonomous opposition | Fog-limited AI, adaptive Machine warfare, diplomacy and strategic decision-making |
| Intelligence and covert warfare | Reconnaissance, concealment, counter-detection and Coalition operations |
| Custom battles | Map editor, teams, economy profiles, configurable victory conditions and save/load |

These are documented current systems, not a claim of final balance or complete regression acceptance.

### Gallery

| | |
|:--:|:--:|
| <img src="docs/media/menu.png" alt="Main menu and Skirmish setup" width="560"><br><em>Main menu — Skirmish setup</em> | <img src="docs/media/skirmish.jpg" alt="Skirmish match underway" width="560"><br><em>Skirmish — early match</em> |
| <img src="docs/media/last_protocol.jpg" alt="Last Protocol defensive line" width="560"><br><em>Last Protocol — belts under fire</em> | <img src="docs/media/siege_line.jpg" alt="Outer ring defenses" width="560"><br><em>Siege line — outer ring</em> |

Captures are ~1600×900, compressed for GitHub. Prefer `docs/media/` when linking screenshots from this README.

---

## Skirmish

Open **Main menu → Skirmish**.

<p align="center">
  <img src="docs/media/menu.png" alt="Skirmish setup: maps, sides, victory rules" width="1000">
</p>
<p align="center"><em>Skirmish setup — map, sides, economy, and victory in one pass.</em></p>

### Factions (playable now)

| Faction | Role |
|---|---|
| **Human A — Modern Human** | Modern military combined arms, hierarchical command, robotics and counter-nanite / Counter-Ghost capabilities |
| **Human B — Scavenger Human** | Industrial and salvage-oriented power |
| **Machine** | Autonomous energy-bound hive network, creep, adaptation and siege warfare |
| **Shadow Coalition** | Covert infrastructure, Ghost Exo operators, technology acquisition, patron contracts and asymmetric operations |

Unreleased and discovery-gated campaign identities remain undisclosed.

### Shadow Coalition

The fourth faction has a documented **61 gameplay definitions**, six distinct aircraft and full Stage 1–13 progression. All 31 previously deferred vehicle and facility designs were approved on November 26, 2026. [Approved art and repository-generated review sheets](game/docs/G10_1_DEFERRED_ART.md).

Coalition infantry and all six aircraft use authored four-direction sprites. Infantry lower NVGs at dusk and night; firing uses the green laser pose. Ghost Infiltrators shimmer while concealed, Counter-Ghost trackers and sensors can reveal them nearby, and Silent Rotor deploys its weapons when it first fires. The eight-seat Stealth Transport supports landing, boarding, deployment and extraction. Concealed facilities retain per-viewer cover appearances until revealed.

Open **Coalition** in the match HUD for doctrine intent and Ghost Command. Scout an enemy structure, build a Ghost Complex and field four healthy Ghost operators to launch a ground mission. The Conductor issues orders and reports the outcome after extraction. The Advanced panel offers four dark operations, technology acquisition and patron contracts. Blackout temporarily interrupts power and production in the target area.

### Stages / tech eras

The technology framework contains **thirteen stages**. Human A, Human B and Machine currently focus on the mid–late band (roughly Stages **7–10**), with research and stage-gated advancement during matches. Shadow Coalition ships its full **Stage 1–13** band. Remaining early (1–6) and late (11–13) faction parity is planned for G14.

### Setup (high level)

- **2–4 sides** — You / AI / Closed; faction, team, colour, starting credits, AI difficulty
- **Teams or free-for-all** — allies share vision
- **Economy profile** — arcade / standard / simulation
- **Maps** include River Crossing (96²), Industrial Heartland (160²), Valley Conquest (256²); custom maps from the editor can be selected when saved
- **Victory modes** — HQ elimination, territory control, hold-the-bridge, Endless, or combined AND/OR rules
- Optional **adaptive Machine director** toggle on setup; capped siege units accept attack-move

### What a match includes

Economy (salvage/ore, power flow, supply), build/train, fog of war, armour classes, wrecks, walls/gates, air and naval layers, companies/armies and chain of command, EW, field forts, vehicle crews/wear, and AI that pays the same costs and only knows what it sees. Full system history lives under `game/docs/` and older slice notes in `game/README.md`.

<p align="center">
  <img src="docs/media/skirmish.jpg" alt="In-match skirmish HUD and starting base" width="1000">
</p>
<p align="center"><em>In match — resources, stage goals, and the first footprint on the map.</em></p>

---

## Last Protocol

Somewhere under the map, a clock is still counting. Nobody who wrote the Protocol is left to explain what happens at zero. You get one night. Maybe two if you steal the dark and make it yours.

<p align="center">
  <img src="docs/media/siege_line.jpg" alt="Last Protocol outer ring under dusk pressure" width="1000">
</p>
<p align="center"><em>Outer ring — walls, pads, and the wire you inherit.</em></p>

### The ground you inherit

You don't drop into an empty sandbox. You inherit a living fortress already under pressure:

- **Two rings of wall** — outer kill-zone and a hard **core** around the heart of the base.
- Between them: the economy that keeps guns fed, pads hot, and wounded moving.
- At the centre: the **facility** — command, labs, workshops, pads on the roof, doors that open into a war that never clocks out.
- Gates with approach belts. Cameras on the corners. Helipads already loaded. An army on the wire — and a reserve held back behind the last wall, because someone before you knew the first wave is never the real one.
- On the far horizon: **Machine cores**. Kill them and the tide can break. Fail, and the count finishes what the hive started.

The clock starts at **dusk**. Night lasts longer than day here. When the lights die down to searchlights and muzzle flash, the map stops being a map and starts being a confession.

### On the ground

<table>
  <tr>
    <td align="center" width="33%"><img src="docs/media/creep.jpg" alt="Something spreads across the dark" width="420"><br><em>Something spreads.</em></td>
    <td align="center" width="33%"><img src="docs/media/hive_nodes.jpg" alt="Machine hive nodes waking in the night" width="420"><br><em>Nodes wake.</em></td>
    <td align="center" width="33%"><img src="docs/media/base.jpg" alt="The fortress ring you have to hold" width="420"><br><em>Hold the ring.</em></td>
  </tr>
</table>

### Why you fight

The hive is not a faction. It is a *process*. Creep eats the land. Nests pulse. Something in the dark adapts to how you hold a wall, how you rotate a sector, how you panic. It will feint. It will learn your weak face. It will climb its own dead if that is what the wall demands.

You are not here to farm a leaderboard. You are here because if this ring falls, there is no next ring.

### What you actually do

Hold. Rotate. Fall back only when the Protocol would rather you live than die proud on a cracked rampart. Strike the cores when the night opens a seam. Spend what the siege pays you — scrap, captured steel, intel, research scratched out under fire — without a tutorial telling you which door is mercy and which is a trap.

There are tools. Loyal robots that refuse the hive's handshake. Eyes that see what camo thinks is invisible. Fire that redraws the approaches. A war-mind you can lie to. Conduct that costs more than ammo. None of them come with a ribbon that says *press this to win*. The game wants you hungry. It wants you wrong once, then dangerous forever.

<p align="center">
  <img src="docs/media/last_protocol.jpg" alt="Last Protocol — defensive belts under fire at night" width="1000">
</p>
<p align="center"><em>Night line — formations on the belts while the Protocol still counts.</em></p>

### The part we won't spoil

There are things in the tide with names you will earn the hard way. There are endings that change what dawn means. There is a reason the Protocol is called *Last* — and the only way to learn it is to still be standing when the count runs out… or to watch the facility go quiet and know exactly what you traded.

**Main menu → Last Protocol.** Bring a pulse.

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

G0 engine → G1 core RTS → G2 smart warfare → G3a/G3b factions, stages 7–9, maps → G4 editor / walls / scale → G5 air/naval/hospitals/tutorial → G6 elevation, companies, marketplace → G6.1 field command → **G7 Last Protocol** → **G7.1** Tide Line siege depth → **G8** Four Sides view rotation + end-of-run presentation → **G9** Machine overhaul + combat depth → **Pre-G10** AI/economy depth bridge → **G10** Shadow Coalition (closed).

### G10 and G10.1 (current)

- **Shadow Coalition** fourth faction: Stages 1–13, buy/steal/unseal tech, Ghost Exo + Exo Armory, Counter-Ghost Corps, dark picks, Coalition LP defender profile
- Pre-G10 stack retained: Four Sides, HIVE9/COUNT9/COMBAT9/AI9/ECON9, Warmind, PACE71
- Original G10 lock: **122 passed / 0 failed**; stage hashes matched. [Historical lock evidence](.superpowers/sdd/g10.lock).
- G10.1: all 31 deferred art assets subsequently approved; four-facing runtime sprites, transport extraction, covert HUD and per-viewer facility states delivered.
- Machine and combat verification passed 74 checks across hive, countermeasures, combat, crew, behavior, siege and accuracy suites. AI adaptation uses observed combat history; automatic truces account for combat strength.
- Latest reported G10 smoke: **129 passed / 0 failed**, 14 suites, zero script errors. **Wider regression gate remains open.** [Stabilization report](.superpowers/sdd/g10.1-stabilization-report.md).

### Next gates (planned order)

| Gate | Headline (public) |
|---|---|
| **G11–G13** | UNDERSTRIKE foundation → military → networked underground |
| **G12** (with soldiers/theatres) | Human depth, biomes/modes; optional uncapped skirmish population |
| **G14** | Remaining factions’ Stages 1–6 and 11–13 |
| **G15** | Campaign *Inheritance* |
| **G16–G17** | High-fidelity underground; Living World |
| **G18** | Orbit / arrival expansion |
| **G19** | Last Protocol co-op |

Detail and acceptance live in `game/docs/ROADMAP.md`. Design contracts and older slice evidence: `game/docs/CONTRACTS*.md`, `game/README.md`.

---

## Performance and verification

Reported results from the [November 27 stabilization report](.superpowers/sdd/g10.1-stabilization-report.md). These are specific test-machine measurements, not universal hardware guarantees.

| Test | Reported result |
|---|---|
| G10 smoke | 129 passes, zero failures and zero script errors across 14 suites |
| 1,000-unit Last Protocol, windowed Radeon, 0.50 zoom | 95.2 FPS average; 44.4 FPS tenth percentile |
| 120 four-operator squads, 900 ticks | 5.78 ms mean simulation step |
| Four-AI skirmish, 7,200 ticks | Ledger checks passed; 145 damage events, 65 production completions, 360 Coalition operation decisions |
| Determinism | Stage 3, 8 and 12 hashes matched on separate 600-tick runs; Ghost mission save/load matched through 240 additional ticks |
| 2,012-unit snapshot | 5.06 ms median; relative gate passed, historical 2 ms target not met |

### Known issues / acceptance

G10 remains locked, but G10.1 wider regression acceptance is not closed. The historical broad run recorded 1,738 passes and 85 assertion failures with script errors; subsequent targeted fixes and reruns passed several affected suites. A clean full regression rerun is still required. Outstanding issues include drive rescue return, revived tower fire, APC travel time, convoy spacing, walker damage, gate-fight balance and clean legacy animation/generator comparison reruns. See the stabilization report for details.

---

## Play the packaged build

For G10.1, extract the fresh `RTS_Age_of_Modern_War_G71_<date>_<commit>.zip` and open `RTS_Age_of_Modern_War.exe`. The accompanying `PLAY_ME.txt` identifies the commit and describes the new controls.

Latest Windows stabilization package

`Downloads\Age of Modern War\RTS_Age_of_Modern_War_G71_*`

**Latest documented verified package:** `RTS_Age_of_Modern_War_G71_2026-11-27_09313a2d.zip`. The extracted executable launched a Stage 8 Coalition skirmish headlessly with `rts_core 0.6.5` active and zero script errors. The extracted data pack hash matched the export. See the [G10.1 stabilization report](.superpowers/sdd/g10.1-stabilization-report.md) for package verification and hashes.

The Downloads path above is a local packaging destination, not a public download URL. If you do not have the packaged build, use the source instructions below.

Keep the extracted folder together, including the executable, data pack and native engine files.

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

- Active branch: `g71` (`g10.lock` CLOSED)
- Ship path: commit → push `github` → `game/.plan/package_g71.ps1` → playable folder + zip in Downloads (keeps the newest 2). Build tag embeds the short git hash.
- Smoke: `powershell -File game/tools/g71_donewhen_smoke.ps1`
- Short soak: `godot --headless --path game -s res://tools/g71_soak_short.gd -- --secs=90`
- Tests from source: `bash game/tests/run.sh`

---

## Technical architecture

| Layer | Responsibility |
|---|---|
| Godot 4.7.2 | Game presentation, input, battle view, HUD and launcher |
| Native Rust core | Simulation acceleration; the stabilization report records `rts_core 0.6.5` in the packaged executable |
| Content JSON | Data-driven content and provisional balance fixtures |
| Verification | Headless smoke, deterministic save/load, native/fallback comparisons and stress harnesses |

For exact build requirements and system details, consult the developer documentation and scripts below. Minimum and recommended hardware specifications have not yet been established here.

## Docs map

| Doc | Use |
|---|---|
| This file | Public overview for GitHub |
| `game/README.md` | Historical playable-slice notes (G0–G7.1 era) |
| `game/docs/ROADMAP.md` | Full gate order to finished game |
| `game/docs/CAMPAIGN_VISION.md` | Campaign / Living World / space vision (spoiler-heavy — for contributors who need it) |
| [UNDERSTRIKE design handoff](game/docs/understrike/) | Underground expansion design |
| [G10.1 stabilization report](.superpowers/sdd/g10.1-stabilization-report.md) | Latest build, benchmark and regression evidence |
| [G10 lock](.superpowers/sdd/g10.lock) | Historical gate closure and acceptance evidence |
| [Coalition art and review sheets](game/docs/G10_1_DEFERRED_ART.md) | Approved vehicles and facilities |
