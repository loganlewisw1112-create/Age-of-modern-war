# G4 plan: "Harden, Scale, Expand" (draft for owner approval, 2026-10-24)

Owner request (2026-10-24):
- Roadmap G4 (harden + scale), **plus**:
  - walls and gates;
  - troop transports;
  - gunships that carry troops and vehicles;
  - naval units;
  - aircraft;
  - 6–8 more human unit types;
  - a full **map and scenario editor** in the spirit of Age of Empires / Stronghold.

Design status: the Master GDD lists the "Map and Scenario Editor" as a *full-game expansion*, and naval/air fleets as later scope. Pulling them into G4 is an owner decision, recorded as **DEC-G4-01** once approved.

G4 is too big for one run, so it ships as **six sub-slices**, each a playable build with its own GOAL block. Every sub-slice keeps the standing rules:
- the sim is deterministic;
- the AI uses the same rules as the player;
- the full test suite stays green;
- numbers are measured on a quiet machine;
- each sub-slice ends with a packaged build tested from a clean folder.

---

## 0. Order and why

| # | Sub-slice | What you get to play | Depends on |
|---|---|---|---|
| **G4a** | Engine foundations | Smooth big battles (sim on its own thread), 10k units in budget, new terrain (shallow/deep water, beach, cliff), save/load at scale | none |
| **G4e** | Map and scenario editor | Build your own maps and matches: terrain, water, trees, rocks, units, buildings, players, objectives; play them in skirmish | G4a (terrain + map file) |
| **G4b** | Fortifications + ground transports + new infantry/vehicles | Drag-built walls, gates, towers; APCs carry squads; 8 new human unit types | G4a |
| **G4c** | Air | Helipads/airfields, attack helicopters, transport gunships (troops + sling-loaded vehicles), jets that sortie and rearm | G4a, G4b (transport system) |
| **G4d** | Naval | Coastal map, shipyards, boats, destroyers, landing craft, amphibious assaults, shore bombardment | G4a, G4b (transports) |
| **G4f** | Onboarding + polish + final gate | Tutorial match, hotkey sheet, settings, the polish list, the final perf/quality gate | all |

- **G4e (editor) runs in parallel with G4b.** It mostly lives in its own files (`presentation/editor/**`, `sim/map_io.gd`). Its unit/building palettes fill automatically from content, so walls, air and naval appear in the editor as those slices land.
- Rough size: each sub-slice is about one overnight orchestrated run. G4a and G4e are the largest.

---

## 1. Decisions needed (my recommended default first)

| ID | Question | Recommended default | Alternative |
|---|---|---|---|
| D1 | Pull the editor and naval/air into G4 | **Yes** (your request), recorded as DEC-G4-01 | Keep them as later expansions |
| D2 | "6–8 more unit types for the human faction(s)" | **8 new land unit types: 4 for Human A, 4 for Human B**, on top of the air/naval/transport rosters below | 6–8 for *each* human faction (about 14 units; one more art night) |
| D3 | Do Machines get air/naval too? | **Yes, a smaller roster** (2 air, 2 naval), because the design forbids clone rosters and every faction must be able to fight on water/air maps | Humans only (Machines can't use water maps) |
| D4 | Aircraft model | **Helicopters hover and stay** (attack, transport). **Jets fly sorties:** they launch from an airfield, strike, then return to rearm. Low/high altitude is a rule, not 3D. | All aircraft hover like helicopters (simpler, less distinct) |
| D5 | Gunship transport | **The transport gunship carries 8 infantry or 1 light vehicle (sling), is armed, and must land on open ground to load/unload.** A heavy-lift variant carries 1 heavy vehicle. | Troops only |
| D6 | Terrain height | **No true height map in G4.** Cliffs/ridges block movement and sight; a new "hill" tile gives a sight + cover bonus | A real elevation system (large engine change; G5) |
| D7 | Distant-army movement shortcut | **Off** (keeps outcomes exact) | On: saves about 34 ms per tick at 10k, rare outcome changes |
| D8 | Submarines | **Not in G4** (stealth/detection is its own system) | Add with a sonar/detection rule |

---

## 2. G4a: Engine foundations

**Goal:** big battles stay smooth; the engine supports water/land/air layers and saved maps.

### 2.1 Sim off the main thread
1. Rebuild the native core with the gdext `experimental-threads` feature. Each `SimWorld` owns its native objects; the main thread never touches the stepping world's natives.
2. **Render snapshot instead of a world copy:** a deep copy costs 22 ms at 2k, which is too slow. Movement already publishes `unit_snap`; extend it to a compact per-tick **render snapshot** holding:
   - packed ids, positions, facing, def index, owner, hp fraction, state bits (moving, firing, selected-relevant flags);
   - building/fx/events deltas.
   The renderer and HUD read only the snapshot, plus an immutable content cache.
3. The sim steps on a WorkerThreadPool task. Player/AI commands queue on the main thread and enter at the tick boundary (same as now), so determinism holds.
4. **HUD reads:** panels that need full entity data (selection details, officer cards) read through a small per-tick "selection detail" export, never the live dict.
5. **Overload:** if a tick runs long, the game slows gracefully and frames stay smooth.
6. A `--sim-thread=off` fallback.
7. **Tests:** threaded vs unthreaded give the same state hash for a recorded command stream, and the 4 playtests pass threaded.

### 2.2 10,000 units within budget
1. Native-held positions and moving flags, synced only on change, so idle/marching units aren't touched in GDScript every tick. This is the biggest remaining cost: about 3.7 µs per unit.
2. Spread the tier-recompute decision loops across ticks (save-exact: occupancy snapshot in `sys_state`).
3. Victory/territory spikes at 10k: an incremental sector occupancy.
4. **Measure:** 10k all-fighting (not just marching) on Valley Conquest.

### 2.3 New terrain + movement classes
1. **New terrain codes:**
   - `BUILDING` (8): impassable footprint for map decor;
   - `SHALLOW` (9): foot/vehicle slow, small boats, landing craft beach here;
   - `DEEP` (10): naval only;
   - `SAND`/`BEACH` (11): landable, buildable for shore structures;
   - `CLIFF` (12): impassable, blocks line of sight;
   - `HILL` (13): passable, +sight, light cover;
   - plus a cosmetic biome set (snow, mud, rock, scrub) as alternate looks of grass/dirt.
   - The existing `WATER` (4) stays the river code, so River Crossing is byte-identical.
2. **New movement classes:**
   - `naval_small`: river WATER + SHALLOW + DEEP;
   - `naval`: DEEP + river WATER wide enough;
   - `amphibious`: land + SHALLOW + river WATER;
   - `air_low` (helicopters: shot by AA and some small arms);
   - `air_high` (jets: AA only).
   - The native nav gets a grid per class.
3. **Per-team passability for gates:** for each team, gate cells are solid unless the gate belongs to the team or an ally. At most 4 teams × classes, built lazily.
4. Terrain art for every new code, with automatic shoreline/cliff edge transitions (bitmask tiles).

### 2.4 Map file format (`.rtsmap`) and save/load at scale
1. `sim/map_io.gd`:
   - a JSON header (name, author, size, version, players, victory, stages, credits, triggers);
   - base64 terrain bytes;
   - a decor list;
   - a resources list;
   - pre-placed entities (owner, def, cell, facing, built flag);
   - bridges.
   - Generated maps can be exported to the same format.
2. `SimWorld.new_match` accepts `cfg.map_file` as well as generated ids. A file map is validated with the existing map validator: spawns reachable, start positions legal.
3. **Save/load:** round trip a 10,000-unit battle mid-fight (size, time, hash equal); seed-repeat test across all maps.

### 2.5 Perf regression suite
- `tools/perf_gate.sh` runs fixed scenarios: 2k fight, 5k/10k valley, render paused/running.
- It refuses to run unless the machine is quiet: CPU < 30% and no other godot processes.
- It writes a dated report and fails if any number regresses more than 15% against the stored baseline.

**G4a Done-when:**
1. All tests green, plus the new terrain/class nav tests, threaded-hash test, map-file round trip and 10k save/load.
2. **Quiet PC:** 60+ fps with 2,000 fighting on screen; 30+ fps zoomed out with 10,000 on Valley Conquest while the sim runs; 10k sim at p95 < 50 ms or, if not, the game runs ≥0.8× speed with smooth frames (the number is reported either way).
3. The packaged build passes all playtests with the thread on.
4. The perf report and README match.

---

## 3. G4e: Map and scenario editor

**Benchmarks studied.** These are the patterns that make classic RTS editors fast to use:
- **Age of Empires II (DE) Scenario Editor:** tabbed panels (Map, Terrain, Players, Units, Triggers, Victory) and immediate test-play.
- **Warcraft III World Editor:** separate palettes for terrain, doodads, units and regions; a simple, powerful trigger editor.
- **StarCraft II Editor:** mirror/symmetry painting for fair maps.
- **Stronghold's map editor:** quick "sketch the land then decorate" flow, with brushes for trees/rocks and water.
- **OpenRA editor:** small and approachable; map validation before save.

We take the concise parts (tabs, palettes, brushes, symmetry, validate, test-play) and leave out the heavy scripting UIs.

### 3.1 Editor layout (one screen, reuses the game renderer)
- **Top bar:** New / Open / Save / Save As / Test Play / Undo / Redo / Validate / Exit.
- **Left: tabbed tool palette.**
  1. **Map:** size (96 / 128 / 160 / 192 / 256), base fill (grass, desert, snow), name, author, description; "Generate base map" from a seed using our generators, then edit.
  2. **Terrain:** paint any terrain code. Brush shape (circle/square), size 1–15, strength (fill / scatter %). Line and rectangle tools. Auto shore/cliff edges.
  3. **Water:**
     - **River tool:** click points, set width (1–9), shallow edges toggle, auto fords.
     - **Lake / Ocean fill:** flood a region to SHALLOW/DEEP, with an automatic beach ring and depth falloff.
     - **Bridge tool:** place a bridge across water; checks that the span is valid.
  4. **Nature and objects:**
     - trees (per biome), bushes, plants, rocks, boulders, ruins, wrecks, rail, factory blocks, all POI decor;
     - **scatter brush** with density and random rotation/variation;
     - eraser.
  5. **Resources:** salvage and ore piles (amount slider), with scatter or single placement.
  6. **Units and buildings:** pick a player (colour chip), faction filter, and any unit/building available to that faction (content-driven, so new units appear automatically).
     - Place, rotate facing (Q/E), set "built" or "foundation".
     - Garrison troops into transports/buildings.
     - Drag a box to place a formation.
  7. **Players:** 2–4 slots (faction, team, colour, start stage 7/8/9, credits, start stock, AI difficulty, human/AI/closed) and a start position marker per player.
  8. **Victory and triggers (scenario):**
     - Victory presets (HQ elimination, territory %, hold point, survive N minutes, destroy target, reach Stage N), plus AND/OR.
     - **Simple trigger list:** WHEN (time reached / unit enters region / entity destroyed / stage reached / units of player fewer than N) THEN (message / spawn units / reveal area / grant resources / win / lose / set AI attack target).
     - **Regions:** drawn rectangles, named.
- **Right:** minimap (click to jump), a properties panel for the selected placed object, and the layer visibility toggles (decor / units / fog preview / grid / passability overlay per movement class).
- **Symmetry:** off / mirror X / mirror Y / mirror diagonal / rotate 180° / 4-way. It applies to terrain, decor, resources, buildings and start positions, so fair skirmish maps take minutes.
- **Undo/redo:** a 200-step command stack, with brush strokes as single steps.
- **Validate:**
  - every start position can reach every other one (foot + vehicle; naval-only maps say so);
  - resources reachable;
  - nothing placed illegally;
  - player count matches start positions;
  - errors listed with "jump to".
- **Test Play:** starts the match from the editor state with fog on/off toggle, and returns to the editor on exit.

### 3.2 Using custom maps
- Saved to `user://maps/*.rtsmap`, with a "Maps" folder button.
- Skirmish setup lists **Built-in** and **Custom** maps, with a thumbnail and size/player info.
- Custom scenarios start with their own players/victory/triggers, or "skirmish rules only".
- Editor access from the main menu: **Map Editor**.

### 3.3 Under the hood
- **Sim-side** (deterministic, saved): `sim/map_io.gd` (format), `sim/systems/triggers.gd` (trigger runtime).
- **Editor UI:** `presentation/editor/**`, reusing terrain_layer/entity_layer drawing.
- **Brushes** are pure functions on the terrain/decor arrays (fast for 256×256). The editor rebuilds nav and terrain chunks only for changed regions.

**G4e Done-when:**
1. Tests:
   - map_io round trip (all features), validator cases, trigger runtime (each condition/effect);
   - a playtest that builds a small map by clicks: paint terrain, river, lake, trees, place HQ + units for 2 players, symmetry on, validate, save, then start it from skirmish.
2. A custom map made in the editor plays a full AI-vs-AI soak to a winner.
3. Undo/redo and symmetry verified by test; editor at 60 fps on a 256×256 map.
4. The packaged build includes the editor; README documents it.

---

## 4. G4b: Fortifications, ground transports, new human units

### 4.1 Walls, gates, towers (per faction look)
- **Human A:** concrete barrier walls, steel gates, MG tower.
- **Human B:** brick and scrap walls, rolling iron gate, flak tower.
- **Machine:** energy barrier pylons (wall segment between pylons), field gate, sentry spire.
- **Drag placement:**
  - click-drag a line; it snaps to 8 directions; corners connect automatically;
  - preview shows cost per segment and invalid cells in red;
  - engineers build segment by segment (queued);
  - Shift-drag adds to the queue.
- **Gates:** open automatically for own/allied units and stay shut to enemies. A Lock/Unlock toggle can lock a gate even to allies.
- Walls/gates are buildings with HP. They are **impassable to enemies** (per-team nav from G4a) and **block bullets**: wall cells block direct fire line of sight for units behind them, but towers can shoot over.
- **Breaching:**
  - artillery and AT do bonus damage to walls;
  - engineers can place demolition charges;
  - the attacking AI paths to the weakest segment when no gate route exists.
- **AI:** builds walls at chokepoints/base perimeter on Normal+ (Hard more); uses gates; breaches enemy walls.

### 4.2 Ground transports (shared transport system, also used by air and naval)
- **Carrier entity:** `cargo` list (unit ids), `slots` capacity:
  - infantry squad member = 1 slot;
  - light vehicle = 4 slots, heavy = 8, by def `cargo_size`.
- **Commands:**
  - `load` (units walk to the carrier, or the carrier picks them up);
  - `unload` (at a point: units spread out), `unload_all`;
  - right-click a carrier with infantry selected loads them.
- **Cargo while inside:** hidden, untargetable, consumes no supply; can't shoot (except designated firing ports on the IFV: G4b option).
- **Carrier destroyed:**
  - **ground:** cargo ejects at 50% HP;
  - **air:** cargo dies;
  - **naval:** cargo dies unless next to shore.
  - This is a rule; it's tunable.
- **UI:** a cargo panel with slot icons; unload buttons; a cargo count badge on the carrier.
- **Officers:** a mission "Transport to point" (load the group, move, unload, then secure).
- **AI:** uses APCs to move infantry to the front; later the air/naval assault plans.

### 4.3 Eight new human unit types (D2 default: 4 per human faction)

**Human A (modern military):**
1. **APC**: transport, 10 infantry slots, light MG.
2. **Sniper team**: long range, high damage vs infantry, concealed when still.
3. **Mortar team**: light indirect fire, can set up/pack up.
4. **Combat engineer**: lays mines, places demolition charges, clears mines, repairs walls.

**Human B (industrial):**
1. **Flamethrower squad**: short range, ignores cover, sets forest fires (fire spreads to adjacent forest cells for N ticks, slow-burning).
2. **Armored half-track**: transport (8 slots) with an HMG.
3. **Scrap mech (Walker-B)**: slow heavy walker, crushes infantry, heavily armored front.
4. **Rocket truck (MLRS)**: salvo artillery, long reload.

- Each gets stats, stage eligibility (mostly Stage 8; flamethrower and half-track Stage 7), art, icons and AI role usage.
- **New mechanics this brings:**
  - mines (hidden from enemies until detected by engineers/recon);
  - demolition charges;
  - fire spreading on forest;
  - sniper concealment;
  - mortar set-up time.

**G4b Done-when:**
1. Tests:
   - wall drag placement, gate team-pass/lock, wall blocks enemy paths and line of sight, breach;
   - transport load/unload/capacity/destroyed-carrier rules;
   - save mid-transport;
   - each new unit's mechanic: mines, charges, fire spread, concealment, set-up.
2. Soaks with walls and transports in AI use, on 3 maps: winners, no invariant failures.
3. Playtest: build a wall line + gate by drag, load an APC, unload at a point.
4. Packaged build.

---

## 5. G4c: Air

**New buildings:**
- Helipad (helicopters land/rearm; 1 helicopter per pad);
- Airfield (jets: hangar slots, runway footprint, rearm + refuel);
- Air control tower (needed for jets; sight bonus).

**Rosters** (D3/D4/D5 defaults):

| Faction | Attack helicopter | Transport gunship | Jet | Extra |
|---|---|---|---|---|
| Human A | Attack helicopter (rockets + cannon) | **Transport gunship**: 8 troops or 1 light vehicle, door guns | Strike jet (sortie: bombs/missiles) | Interceptor jet (air-to-air) |
| Human B | Gunship (heavy MG, armored) | **Heavy-lift gunship**: 1 heavy vehicle or 12 troops | Bomber (area damage sortie) | none |
| Machine | Strike drone carrier (spawns micro-drones) | **Lifter drone**: 1 vehicle or 6 units | none | Interceptor swarm |

**Air rules:**
- **Helicopters (`air_low`):** hover; hit by AA and by small arms/HMG flagged `anti_air_low`; land to load/unload on open cells; rearm at a helipad automatically when out of ammo.
- **Jets (`air_high`):** only targetable by AA. **Sortie model:** order a target or area; the jet flies in, strikes and returns to its airfield to rearm (time-based). It can't hover, and it's lost if its airfield is destroyed while airborne and no other airfield exists.
- **Air vs air:** interceptors auto-engage enemy aircraft near them.
- **Fuel/time aloft** for helicopters (return when low) uses the existing supply rules.
- **Fog:** aircraft see far but are spotted from far away.
- **AA:** existing AA units gain `air_high` capability where it makes sense; new AA guns get a range that reaches jets.

**Air transport:** reuses the G4b transport system with `cargo_size` limits, "sling" for vehicles (the vehicle is visible under the helicopter), and landing-zone validation.

**AI:**
- builds helipads/airfields at Stage 8+;
- air assault: load an infantry group, fly behind lines, unload near a weak target;
- uses jets on clustered enemies/artillery;
- builds AA when it sees air.

**G4c Done-when:**
1. Tests: sortie cycle, rearm, AA layering, transport by air (troops + vehicle), landing validation, air-vs-air, save mid-flight.
2. Soaks: AI uses air on all maps, still decisive.
3. Playtest: build a helipad, train a transport gunship, load a squad + a light vehicle, fly over a river, unload.
4. Packaged build.

---

## 6. G4d: Naval

**New map:** **Coastal Front** (160×160 or 192×192): mainland coast, islands, beaches and an estuary river, 2–4 players, generated plus editor-polished.

**New buildings:**
- Shipyard (shore footprint: part water, part beach);
- Naval dock / supply pier (resupply ships);
- Coastal battery (shore defence).

**Rosters:**

| Faction | Fast boat | Landing craft (transport) | Warship | Extra |
|---|---|---|---|---|
| Human A | Patrol boat (MG, fast, `naval_small`, rivers OK) | **Landing craft**: 12 troops or 2 vehicles; beaches on SAND/SHALLOW | Destroyer (guns + shore bombardment + AA) | Frigate (AA-heavy escort) |
| Human B | Gunboat (river-capable, cannon) | **Barge carrier**: 3 vehicles | Monitor (heavy guns, slow, shore bombardment) | none |
| Machine | Hydro-drone skiff | **Amphibious crawler carrier** (`amphibious`: drives from sea onto land) | none | none |

**Naval rules:**
- ships use `naval`/`naval_small` nav;
- shore bombardment = indirect fire onto land within range;
- ships are supplied at docks or by a supply ship;
- wrecks sink, leaving a shallow-water obstruction;
- landing craft unload only at a beach;
- the amphibious class drives across.

**AI:** on maps with water, builds a shipyard, contests water, and runs amphibious landings (escort + landing craft + troops) when the land route is blocked or long.

**G4d Done-when:**
1. Tests: naval nav per class, shipyard shore placement, beaching/unload, amphibious path, bombardment, sink/wreck, save mid-sea.
2. Coastal Front soaks (3 factions) end with winners; the AI performs at least one amphibious landing (log line).
3. Playtest: build a shipyard, a landing craft, load troops, land on a beach.
4. Packaged build.

---

## 7. G4f: Onboarding, settings, polish, final gate

**Tutorial match:** a short scripted scenario built with the G4e trigger system. It covers move, gather, build, train, attack, research/advance, transport and walls, with on-screen prompts.

**Help:** an in-game hotkey sheet (F1) and a "How to Play" update covering stages, air, naval and transports.

**Settings menu:**
- UI scale;
- graphics quality (icon-zoom threshold, effects density, fog smoothness);
- default game speed;
- edge-pan speed;
- show health bars (always / selected / damaged);
- key rebinding for the main hotkeys.

**Polish list (known):**
- Machine top bar hides Fuel;
- the refinery's `STOCK_FULL` status gets a readable label;
- field-gun crew art;
- skirmish table column headers aligned;
- minimap edge-pan on 256 maps;
- first-launch playtest flake (cold start > 10 s).

**Final gate:** quiet-machine perf suite, full soaks on all 4 maps plus 1 editor map, full suite, packaged build from a clean folder, README/PERF/PROGRESS updated.

---

## 8. Art plan (procedural pipeline, faction styles kept)

| Group | Count | Notes |
|---|---|---|
| New land units (G4b) | 8 | 8 facings, anims, team masks, wrecks |
| Air units | 10 | rotor/jet anims, shadows, altitude bob |
| Naval units | 9 | wakes, bow spray, sinking frames |
| Wall/gate/tower sets | 3 factions × 4 pieces (straight, corner, gate open/closed, tower) | autoconnect variants |
| Air/naval buildings | 9 | shore-footprint art for shipyards |
| Terrain | shallow/deep water + beach + cliff + hill + biome variants, animated water edges | bitmask transitions |
| Editor | tool icons, brush cursors, region overlay | |
| Effects | fire spread, mines, demolition, bombs, naval shells, splash, smoke trails | |

Art totals about 27 new units, 9 new buildings and 12 wall/gate/tower pieces, so roughly 48 sprite sets plus terrain and effects. Expect 2 art agents per sub-slice.

---

## 9. AI work summary (fair AI, same rules)
- **Walls:** chokepoint/perimeter planning, gate use, breach targeting.
- **Transports:** infantry ferrying (ground), air assault, amphibious landing plans.
- **Air:** production triggers, sortie targeting, AA response.
- **Naval:** water-control decisions, shipyard placement, bombardment.
- **Editor scenarios:** obey trigger-set AI targets.
- **Budgets:** AI think stays < 2 ms per tick per side at 5k units; soaks on every map, decisive.

---

## 10. How it's built (orchestration)
- Each sub-slice gets a contract doc (`docs/CONTRACTS_G4x.md`) with fixed ids, file ownership and APIs, written before agents start, like G3b.
- At most 6 agents at once, caps ≥400k (guard floor), status every 5 calls / 4 min, heartbeat on long runs.
- **Benchmarks only on a quiet machine:** agents compare sub-phase ratios; final numbers are taken with all agents stopped. Stale background processes are killed between waves.
- The orchestrator commits each agent's files by path after verifying them; the full suite runs before every packaged build. Nothing is pushed without asking.

## 11. Known risks
- **Thread safety (G4a):** gdext experimental threads and HUD reads. The fallback is `--sim-thread=off` plus a split-step mode.
- **Per-team nav memory/time:** 4 teams × 6 classes on 256×256 is about 1.5 MB of bytes; fine, built lazily.
- **Naval/air AI** is the hardest AI work; soaks may need a successor or two.
- **Art volume:** about 48 sprite sets, so quality checks are needed.
- **Scope:** if a sub-slice runs long, park with a note rather than cut tests.
