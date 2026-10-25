# G5 plan: "Full Spectrum" (draft for owner approval, 2026-10-24)

**One seamless wave.** G5 absorbs the rest of the G4 roadmap (G4c Air, G4d Naval, G4f Onboarding) and every owner note recorded on 2026-10-24 (PROGRESS.md, "Next slice: owner notes" 1-10). It is built as **one continuous wave**: no stops between parts and no hand-offs back to you until the packaged build.

## What you get to play
- **Air war:**
  - airfields with real runways that aircraft take off from and land on;
  - per-aircraft hangars you buy and upgrade;
  - extra-airstrip upgrades;
  - helicopters on helipads, jets on sorties;
  - a VTOL Dropship carrying 2 vehicles + 8 troops;
  - Airfield Engineer Teams that keep everything running once assigned.
- **Naval war:** a new Coastal Front map, shipyards, boats, warships, landing craft, beach landings, shore bombardment.
- **17 new human ground units/squads**, including:
  - your Drone Team: 3 soldiers, 4 pickable launch drones, then a tactical team;
  - Airfield Engineers;
  - medics and ambulances.
- **Auto-support:**
  - logistics trucks restock nearby units on their own;
  - medics evacuate wounded to a new **Hospital** / **Field Hospital**, which send them back as free reinforcements.
- **A full UI facelift:**
  - every screen fits at every window size, with nothing cut off;
  - a custom military typeface made for this game;
  - better controls.
- **Fixes for every G4 known gap:**
  - 10k battles at ≥0.8x speed;
  - the Valley AI draws;
  - player units breach walls;
  - burnt ground survives save/load;
  - G4 fps measured.
- **Onboarding:** a tutorial match, the F1 hotkey sheet, a settings menu and the polish list.

---

## 0. How "one wave" works
- I write the contracts and IDs first (about 1 hour). Then every workstream runs at once in a single continuous pipeline.
- The rule of **at most 6 agents live at a time** still holds. When an agent finishes, the next queued agent starts immediately, so from your side it is one wave.
- Dependencies are handled with "API ready" facts on the board, not with separate waves:
  - the AI starts as soon as the air/naval/support APIs are posted;
  - art agents start at once from the fixed IDs.
- **Honest size:** about 37 new units, about 29 new building art sets, 1 new map, 4 new sim systems, an engine refactor and a full UI pass. G4's three parts took about one long day; this is **about 2–3x that**. Expect **2–3 days** of continuous orchestrated work, with status updates whenever you ask.
- If a part runs long, I park it with a written note rather than cut tests. Nothing is pushed without asking.

---

## 1. Decisions (recommended default first; change any before approval)

| ID | Question | Default | Alternative |
|---|---|---|---|
| D9 | New ground units per human faction | **Human A 8, Human B 7** (the 10 requested + Drone Team + Airfield Engineers per faction + a Human A ambulance) | 10 each |
| D10 | Engine change for 10k speed | **Yes:** hot per-unit state in packed arrays in `world.gd`, results identical | Keep dictionaries, accept about half speed |
| D11 | Helicopters | **Helipads** (1 pad = 1 helicopter "hangar"), placeable forward | Helicopters also need airfield hangars |
| D12 | Hangar classes | **Light** (fighters, strike, interceptor) and **Heavy** (bomber, heavy-lift, VTOL Dropship); Light → Heavy upgrade | One size fits all |
| D13 | Hangar upgrades | **3 levels:** faster rearm/refuel, repair while parked, armored roof | Fewer levels |
| D14 | Airfield size and strips | **Base 1 strip + 4 hangar slots; each "Extra Airstrip" upgrade adds 1 strip + 2 hangar slots (max 3 extra → 4 strips, 10 hangars)** | Fixed strips |
| D15 | Small maps | **Airstrip** variant (short, light aircraft only) where a full airfield doesn't fit | Air only on big maps |
| D16 | Wounded | **Human infantry at 0 HP become Wounded for 60 s** (immobile, can't fight); evacuated → Hospital heals → free reinforcement; not picked up → dies. Machines/vehicles unchanged | No wounded state (medics heal only) |
| D17 | Drone Team per faction | **Human A precision version, Human B cruder rigged-FPV version**; Machine none | Human A only |
| D18 | Machine air/naval | **Smaller distinct rosters** (3 air, 2 naval, drone launch rail + drone bays, maintenance swarm) | Humans only |
| D19 | Typeface | **Original design, built from scratch** (stencil-cut military modern, 2 weights); you approve a specimen sheet before roll-out | License an existing font |
| D20 | Out of scope | **Submarines, aircraft carriers, true elevation, Stages 1–6/10–13, audio, multiplayer** | (carriers fit the hangar design; could be G6) |

---

## 2. Workstream A: engine, performance, G4 gaps

### A1. Packed hot state (D10)
- Per-unit hot fields move from dictionaries into packed per-id arrays owned by `world.gd`:
  - `pos_x/pos_y`, `moving`, `cd_ticks`, `target`, `order_kind`, `hp`, `status flags`.
- **One write API** (`W.set_pos`, `W.set_target` …) used by every system, with the native core reading and writing the arrays directly.
- Dictionaries stay as the save/hash view: the arrays are flushed into them before `state_hash`, saves and the render snapshot. The hash is unchanged.
- Movement gather, combat prep, supply, morale and fog then read the arrays and stop touching 10k dictionaries every tick.
- **Rule:** A/B state hash equal to HEAD on 2k fight, 2k mixed, 10k fight and 10k march, native on and off, threaded and unthreaded.
- **Target:** 10k all-fighting avg ≤ 62.5 ms/tick (0.8x speed) on a quiet PC. Today it is 104 ms.

### A2. Gap fixes
1. **Valley Conquest AI draws:**
   - restart from AI5-4's work-in-progress (patch in `build/_ai5-4_wip/`): the bank uses the *launch* army, plus the late-game bank drop;
   - drop the retarget penalty, or make it decay;
   - auto-resupply (D-section E) also stops armies running dry.
   - Every soak must end with a winner.
2. **Player wall breach:** wire `Fortify.on_attack_move_blocked` in `movement.gd`. A blocked attack-move then targets the blocking wall/gate.
3. **Burnt ground survives save/load:** burnt cells become a sim-side set in the map state, saved, hashed and drawn from the snapshot.
4. **Windowed fps measured on a quiet PC** (all agents stopped): 2k fighting on screen, and 10k zoomed out with the sim running.

---

## 3. Workstream B: air

### B1. Airfield (Human A "Airfield", Human B "Aerodrome"; Machine: Drone Launch Rail)
- **Footprint:**
  - a long runway (about 4 × 26 tiles) plus an apron and tower;
  - must be flat open ground (no water, cliff, trees or buildings);
  - rotates in 4 directions when placed;
  - the placement preview shows where future strips and hangars will go.
- **Requires:** Stage 8 and an Air Control Tower nearby (tower: sight bonus, needed for jets).
- **Airstrips:**
  - base 1 strip;
  - **Extra Airstrip upgrade** ×3: each adds a parallel strip (+4 tiles wide) and 2 hangar slots;
  - each strip handles **one takeoff or landing at a time**.
- **Hangars (D12/D13):**
  - Buy hangars into the airfield's slots: Light or Heavy.
  - **Each aircraft needs a free hangar of the right class.** With none, the aircraft's build button is greyed out with "No free hangar".
  - A hangar is tied to the aircraft built into it. If that aircraft dies, the hangar is empty and can be refilled.
  - Upgrade levels:
    - L1: rearm/refuel −40% time;
    - L2: repairs a parked aircraft;
    - L3: armored roof (a parked aircraft survives bombing).
  - Light → Heavy upgrade.
- **Runway operations:**
  - **Takeoff:** taxi along a fixed lane from the hangar → roll along the strip in the runway direction → airborne → fly free. There is no ground pathfinding for planes.
  - **Landing:** approach on the runway axis → touch down → taxi to its hangar → rearm/refuel (time set by the hangar level).
  - **Holding pattern:** when all strips are busy, arrivals circle the airfield; low-fuel aircraft land first.
  - **Runway damage:** bombs and shells crater a strip, which then closes. Other strips keep working. Airfield Engineers fill craters.
  - **Airfield destroyed, or every strip closed:** airborne jets divert to another friendly airfield. With none, they crash when out of fuel. A destroyed hangar destroys any aircraft parked in it.
  - **Ground vulnerability:** parked aircraft can be destroyed unless the hangar has the L3 roof. Raiding an airfield is a real tactic.
- **Airstrip variant (D15):** short strip, 2 Light hangar slots, light aircraft only, no extra-strip upgrades. Offered automatically on maps where a full airfield doesn't fit.
- **Machine Drone Launch Rail:**
  - catapult launch, net recovery, compact **Drone Bays** in place of hangars;
  - the same rules (1 bay per aircraft, upgrades, holding) with a different look and feel;
  - no Extra Airstrip upgrade: it gets an Extra Rail upgrade instead.

### B2. Helipads (D11)
- 1 helipad holds 1 helicopter: build and rearm there. Placeable anywhere (forward bases).
- Helicopters fly home to their pad to rearm when out of ammo or low on fuel.

### B3. Air rosters

| Faction | Unit | Class | Hangar | Role and cargo |
|---|---|---|---|---|
| Human A | Attack Helicopter | air_low | pad | rockets + cannon, anti-armor |
| Human A | Transport Gunship | air_low | pad | 8 troops OR 1 light vehicle (sling, visible), door guns, lands on open ground |
| Human A | Strike Jet | air_high | Light | sortie: bombs/missiles on a target or area |
| Human A | Interceptor | air_high | Light | auto-engages aircraft near it, escorts |
| Human A | **VTOL Dropship** | air_low | **Heavy** | **2 vehicles + 8 troops**; heavy AA missiles + nose cannon (wins most air fights); lands on any flat open area or at the airfield; very expensive, Stage 9, high population cost; vulnerable while hovering low to unload |
| Human B | Armored Gunship | air_low | pad | heavy MG, armored |
| Human B | Heavy-Lift | air_low | pad | 12 troops OR 1 heavy vehicle (sling) |
| Human B | Bomber | air_high | Heavy | area-damage sortie |
| Human B | **VTOL Dropship (B)** | air_low | **Heavy** | same capacity; B look (riveted, rotor-ducted); flak cannons + rockets; cheaper, less AA power |
| Machine | Drone Carrier | air_low | bay | releases micro-drones |
| Machine | Lifter Drone | air_low | bay | 6 units OR 1 vehicle |
| Machine | Interceptor Swarm | air_high | bay | anti-air |

### B4. Air rules
- **air_low** (helicopters, VTOL): hit by AA and by small arms/HMG flagged `anti_air_low`. Lands to load and unload (landing-zone check: open, flat, not water).
- **air_high** (jets): only AA reaches them. **Sortie model:** order a target or area → fly in → strike → return to the airfield → land → rearm. They can't hover.
- **Air vs air:** interceptors and VTOL Dropships auto-engage enemy aircraft in range.
- **Fuel and ammo:** use the existing supply rules; helicopters return to their pad, jets to their airfield.
- **Fog:** aircraft see far and are seen from far.
- **AA:** existing AA units gain `air_high` where it fits. New Mobile AA (Human A) and the coastal battery's AA mode.
- **Air transport:** reuses the G4b transport system, adding `cargo_size` and **sling** for vehicles. The VTOL Dropship has mixed cargo: 2 vehicle slots + 8 infantry slots.

### B5. Airfield Engineer Team (one per human faction; Machine: Maintenance Drone Swarm)
- **One purchase = a squad of 4 that moves and selects as one unit.**
- **Assign:** select the engineers → click the airfield or one hangar → assigned (a badge on the building; the airfield panel shows engineer counts).
- **When assigned, automatic upkeep:**
  - repair building damage;
  - fill runway craters (reopens strips);
  - clear wrecks;
  - put out fires;
  - +50% hangar build/upgrade speed;
  - rearm/refuel parked aircraft faster.
  - Assigned to a hangar, they put that hangar first, then the rest of the airfield.
- **Forward strip:** the engineers can build a temporary **Forward Airstrip / Helipad** near the front, where light aircraft and helicopters rearm and refuel.
- **Field rearm:** rearms a landed helicopter or light aircraft anywhere, using supply stock.
- Sidearms only. They stay assigned until given another order.

---

## 4. Workstream C: naval

- **New map: Coastal Front** (192×192):
  - mainland coast, 2 islands, beaches, an estuary river with shallow fords;
  - 2–4 players, seeded and validated;
  - polished in the editor;
  - shown in Skirmish Setup.
- **Buildings** (each faction styled):
  - **Shipyard** (shore footprint, part water, part beach);
  - **Supply Pier** (resupplies ships);
  - **Coastal Battery** (shore defence; AA mode on Human A).

| Faction | Fast boat | Transport | Warship | Extra |
|---|---|---|---|---|
| Human A | Patrol Boat (naval_small, rivers OK) | **Landing Craft:** 12 troops OR 2 vehicles, beaches on beach/shallow | Destroyer (guns, shore bombardment, AA) | AA Frigate |
| Human B | River Gunboat | **Barge Carrier:** 3 vehicles | Monitor (heavy guns, slow, bombardment) | none |
| Machine | Hydro-drone Skiff | **Amphibious Crawler** (amphibious: drives from sea onto land) | none | none |

- **Rules:**
  - ships move by class: `naval` needs channels ≥3 wide; `naval_small` uses rivers;
  - shore bombardment = indirect fire onto land within range;
  - ships restock at a Supply Pier or from a supply ship (Auto mode works on water too);
  - wrecks sink and leave a shallow-water obstruction;
  - landing craft unload only at a beach;
  - amphibious units drive across.
- Naval units also work on River Crossing, Valley Conquest and editor maps wherever water allows.

---

## 5. Workstream D: new human ground units (D9)

**Human A (modern), 8 new:**

| Unit | Squad | Role / special |
|---|---|---|
| Medic Team | 2 | heals nearby infantry +morale; **med team** for evac (carries 2 wounded) |
| HMG Team | 3 | Deploy/Pack; long-range suppression |
| Mobile AA (SPAAG) | vehicle | hits air_low + air_high, drones |
| Armored Recon Car | vehicle | fast scout/raider, light autocannon, long sight |
| Special Forces | 4 | concealed when slow/still, plants charges, can be air-dropped from a gunship |
| **Drone Team** | 3 | see below |
| **Airfield Engineer Team** | 4 | see B5 |
| Armored Ambulance | vehicle | **med vehicle**: carries 6 wounded, light armor |

**Human B (industrial), 7 new:**

| Unit | Squad | Role / special |
|---|---|---|
| Grenadier Squad | 4 | area damage vs infantry, bonus vs walls |
| Shock Troopers | 4 | close assault, fast breach, strong vs wall towers |
| AT Rocket Team | 3 | cheap anti-armor |
| Armored Car | vehicle | fast raider, heavy MG |
| Field Ambulance | vehicle | **med vehicle**: carries 4 wounded, heals nearby slowly |
| **Drone Team (B)** | 3 | the rigged-FPV version (cheaper, less accurate) |
| **Airfield Engineer Team (B)** | 4 | see B5 |

**Machine, 1 new ground unit:** Maintenance Drone Swarm (the engineer equivalent).

### D1. Drone Team (owner design)
- **3 soldiers move and select as ONE squad.** You never control them individually. The squad dies when all 3 are down; losses weaken it.
- **Drone mode:** 4 drone charges (counter ● ● ● ●). Press **Launch Drone** → pick the type for the situation → click a target.

  | Drone | Use |
  |---|---|
  | Strike (loitering munition) | top-attack dive, big anti-armor hit |
  | Frag | small-area blast vs infantry |
  | Recon | flies a path, reveals fog and marks targets for a while |
  | EMP / Jammer | disables machines, turrets and electronics briefly; jams enemy drones |

  - Launched drones are short-lived `air_low` entities. Enemy AA and EW can shoot them down or jam them.
- **Tactical team mode (automatic when all 4 drones are spent):**

  | Ability | Effect |
  |---|---|
  | Infiltrate | concealed while slow/still |
  | Takedown | silent close kill of a lone infantry unit or officer |
  | Breach | fast charge on a wall, gate or building |
  | Stack up | hold at a door/gate/breach, then assault with a first-strike burst |
  | Armored attack | short-range AT rockets |

- **Rearm:** a supply source (logistics truck, depot, HQ area) restocks the drones and returns the squad to drone mode. Auto-resupply includes it.

---

## 6. Workstream E: auto-support

### E1. Logistics "Auto Resupply" (all factions' supply vehicles)
- **Station mode** (truck parked, Auto on): nearby units that need supply drive to the truck, restock, and resume their previous order and position.
- **Roam-area mode** (Auto on + drag a circle): the truck drives to units in the area one by one, neediest first, then returns to its post.
- **Needs supply:** ammo < 40%, fuel < 30%, or drones 0 (thresholds adjustable in the truck panel).
- **Combat rule:** a unit in combat leaves only when fully out of ammo; otherwise it waits for a lull.
- **Units remember their order** (attack-move, hold, patrol, officer mission) and resume it.
- **Truck self-refill:** when its stock is empty, it drives to the nearest depot/refinery, refills and returns.
- **Several trucks** split the work without doubling up.
- **Visuals:** a dashed area circle and a supply icon over units heading to restock.
- Works for ships at a Supply Pier and for helicopters at forward strips.

### E2. Medical: Wounded, Auto Evac, Hospitals (D16)
- **Wounded state:** human infantry at 0 HP fall Wounded for 60 s: immobile, can't fight, shown with a red cross marker. Not evacuated in time → dies. Saved and hashed.
- **Med team / med vehicle on Auto** (placed in an active area or toggled):
  1. finds Wounded in the area, most critical / nearest first;
  2. picks them up (Medic Team 2, Field Ambulance 4, Armored Ambulance 6);
  3. evacuates to the nearest **Field Hospital** or **Hospital**;
  4. returns for more. It refills nothing, but needs no supply.
- **New buildings (Human A and Human B, each styled):**

  | Building | Where | Function |
  |---|---|---|
  | **Hospital** | main base, Stage 7+ | heals evacuated wounded fully and returns them as **free reinforcements** (no cost, population re-used); upgrades speed it up |
  | **Field Hospital** | forward, cheaper | fast drop-off; treats light wounds on the spot and sends the rest on to the Hospital |

- **AI** uses both.

---

## 7. Workstream F: UI facelift and typeface

- **Fit everywhere:**
  - the layout scales by anchors and containers;
  - tested at 1280×720, 1366×768, 1600×900, 1920×1080, 2560×1440, 3440×1440 (ultrawide) and 3840×2160, windowed and fullscreen;
  - panels wrap or shrink before anything clips;
  - long lists scroll;
  - a **UI Scale** setting (75–150%).
- **Automated fit test** (`tools/ui_fit_test.gd`): opens every screen and panel at the resolutions above:
  - main menu, skirmish setup, HUD, build cards, cargo strip, airfield panel, hangar panel, truck/med panels, editor, pause, settings, tutorial overlay.
  - **Fails if any control's rect leaves the viewport or overlaps another panel.**
  - Saves a screenshot sheet for each resolution.
- **Typeface (D19):**
  - an original "military modern" face for this game: angular stencil cuts, squared counters, clean numerals;
  - **two weights** (Bold headers, Regular body/numbers);
  - full Latin, digits and symbols;
  - built from hand-defined outlines into a TTF with an in-repo tool, so it is our own;
  - **you approve a specimen sheet** before it's applied everywhere.
- **Visual refresh:**
  - a consistent military panel style (frames, plates, rivets per faction accent);
  - clear hover, selected and disabled states;
  - a tooltip on every button, with hotkey and cost;
  - better health/ammo/fuel/drone bars;
  - a cleaner top bar and minimap frame.
- **Controls and functionality:**
  - control-group bar on screen;
  - idle-units button;
  - double-click selects all of a type on screen;
  - hotkeys shown on every command button;
  - consistent right-click;
  - **F1 hotkey sheet**;
  - an airfield panel (strips, hangars, occupants, upgrades, engineers, "Buy hangar");
  - a Rebase command for aircraft;
  - the drone picker;
  - Auto toggles on the truck and medic panels.

---

## 8. Workstream G: AI (fair, same rules)
- **Air:**
  - picks an airfield site;
  - buys hangars before aircraft and upgrades them;
  - assigns engineers;
  - guards the airfield with AA;
  - runs air assaults (gunship/VTOL lands troops and vehicles behind lines);
  - sends jets at clustered armies and artillery;
  - bombs enemy airfields;
  - builds AA when it sees enemy air.
- **Naval:**
  - on maps with water, builds a shipyard, contests the water, and bombards the shore;
  - runs amphibious landings (escort + landing craft + troops) when the land route is blocked or long.
- **New units:**
  - Drone Team: strike on tanks, frag on infantry groups, recon ahead of attacks; breaches in tactical mode;
  - medics on Auto with hospitals;
  - logistics trucks on Auto behind every army.
- **Valley fix** (A2.1).
- **Budget:** AI think < 2 ms per tick per side at 5k units.

---

## 9. Workstream H: editor, tutorial, settings, polish
- **Editor:**
  - palettes fill automatically with the new units and buildings;
  - place airfields (with strips/hangars and aircraft parked in them), helipads, shipyards, hospitals;
  - ships on water;
  - the trigger system gains "aircraft landed", "unit evacuated" and "beach landing" conditions.
- **Tutorial match** (built with editor triggers): move, gather, build, train, attack, advance stage, walls, transports, Auto resupply, airfield (buy a hangar, build a jet, take off/land), med evac. On-screen prompts in the new UI.
- **Settings menu:**
  - UI scale, graphics quality (icon-zoom threshold, effects, fog smoothness);
  - default game speed, edge-pan speed;
  - health bar mode;
  - **key rebinding**.
- **Polish list:**
  - Machine top bar hides Fuel;
  - readable refinery status;
  - field-gun crew art;
  - skirmish table headers aligned;
  - minimap edge-pan on 256 maps;
  - first-launch playtest flake.

---

## 10. Art (procedural pipeline, faction styles kept)

| Group | Count | Notes |
|---|---|---|
| New ground units | 16 | 8 facings, idle/move/fire/special frames (deploy, launch, carry wounded), team masks, wrecks |
| Air units | 12 | rotor/jet animations, shadows + altitude offset, sling-load pose, landing-gear frames |
| Naval units | 9 | wakes, bow spray, sinking frames |
| Launched drones | 4 types × 2 factions | small, fast, trail |
| Air buildings | ~14 | airfield (rotations, 1–4 strips), Light/Heavy hangars + 3 upgrade looks, helipad, control tower, forward strip, Machine rail + bays |
| Naval buildings | 9 | shipyard (shore art), pier, coastal battery × 3 factions |
| Medical buildings | 4 | Hospital, Field Hospital × 2 human factions |
| Terrain | Coastal Front coast, islands, estuary | uses G4 water/beach sets |
| Effects | runway craters, bomb/shell/splash, smoke trails, drone dive/EMP, red-cross marker, wounded pose | |
| UI | new panel kit, icons for every new unit/building/command, typeface specimen | |

**About 37 units + 29 building sets + effects + the UI kit.** Every sheet is self-checked by eye (zoomed crops) before commit.

---

## 11. How it's built (agents, one wave)
Each agent gets **one fixed role, a fixed file list and contract sections**. Every agent runs under the budget rules:
- caps ≥ 400k;
- status every 5 calls;
- a heartbeat during long runs;
- a handoff at 70%;
- a successor from that handoff.

**At most 6 agents live at once, in a queue.**

| Agent | Role | Starts |
|---|---|---|
| ORCH | contracts (`docs/CONTRACTS_G5.md`), IDs, scaffold, commits, final gate | first |
| CORE10K | packed hot state + perf + breach hook + burnt save | immediately |
| AIRSYS | airfield/strips/hangars/helipads, flight model, sorties, holding, runway damage, air transport, VTOL | immediately |
| UNITS5 | 16 ground units incl. Drone Team + engineers + ambulances, wounded state | immediately |
| SUPPORT | Auto resupply, medical evac, Hospital/Field Hospital | immediately |
| UI5 | facelift, fit test, all new panels/commands, settings | immediately |
| ART-U5 | ground unit + drone art | immediately |
| NAVAL | naval systems, Coastal Front map, shipyard, landing, bombardment | next free slot |
| ART-AIR / ART-NAV / ART-BLD | air units, naval units, all buildings | as slots free |
| FONT | typeface tool + specimen + the TTF | early (you approve the specimen) |
| AI6 | AI for everything (+ successors) | when air/naval/support APIs post `api_ready` |
| ED5 | editor additions, tutorial, polish | after UI5's panel kit |

- **Benchmarks** are taken only with every agent stopped.
- **Commits** are made by me, by path, after verifying each agent's files.
- **Nothing is pushed.**

---

## 12. Done-when (frozen once work starts)
1. `tests/run.sh` TESTS OK, including new suites for:
   - packed-state equality;
   - takeoff/landing/holding;
   - hangar gating ("no free hangar");
   - runway craters + engineer repair;
   - sorties/rearm;
   - VTOL 2 vehicles + 8;
   - air-vs-air;
   - naval movement by class;
   - beaching/amphibious;
   - bombardment;
   - wreck sinking;
   - drone launches by type → tactical mode;
   - Auto resupply (station + roam);
   - wounded → evac → hospital → reinforcement;
   - save mid-flight, mid-sea and mid-evac.
2. **Perf (quiet PC):**
   - 10k all-fighting avg ≤ 62.5 ms/tick;
   - 2k fighting on screen 60+ fps;
   - 10k zoomed out 30+ fps;
   - numbers reported either way.
3. **AI soaks:** 4 built-in maps × 2 seeds + 1 editor map end with winners and 0 invariant failures. The logs show air sorties, at least 1 amphibious landing on Coastal Front, Auto resupply and med evacuations.
4. **Playtests pass:**
   - the existing 6;
   - **air:** place airfield → buy hangar → assign engineers → build jet → takeoff/land; VTOL carries 2 vehicles + 8;
   - **naval:** shipyard → landing craft → beach landing;
   - **Drone Team:** 4 launches → tactical breach;
   - **Auto resupply;**
   - **med evac** to a Hospital;
   - **tutorial.**
5. **UI fit test:** every screen at all 7 resolutions, 0 clipped or overlapping controls. The new typeface is used everywhere. Screenshot sheets are attached.
6. **Packaged build** passes all of the above from a clean folder, is copied to Downloads, and README/perf/PROGRESS match reality.

## 13. Known risks
- **Scope:** the largest slice yet. If something runs long, I park it with a note and never cut tests.
- **Packed-state refactor** touches every system; determinism is guarded by A/B hashes at every step.
- **Flight model and runway queueing** must stay deterministic and threaded-safe.
- **Air/naval AI** is the hardest AI work; expect 2–3 AI successors.
- **Art volume:** about 66 sprite sets. Quality is self-checked; you may want a look at the airfield and VTOL sheets mid-wave.
- **Typeface:** a hand-built font needs good kerning; your specimen approval is the gate.
