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
- **Up to 8 agents live at a time** (owner override for G5, 2026-10-24; the standing default is 6). When an agent finishes, the next queued agent starts immediately, so from your side it is one wave.
- **Every agent gets its own operating guide** (section 11): role, files it owns, inputs, ordered tasks, what it publishes, done-when, budget, and what it must never touch. No two agents own the same file.
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
| D11 | Helicopters | **Land on any open ground, anywhere** (in or outside a base, forward, in the field). **Helipads are restock/repair points**: a landed helicopter there is rearmed, refuelled and repaired, automatically when Airfield Engineers are assigned. Each helicopter still has a home pad (buying one needs a free pad, like hangars) | No pad gating (helicopters need no pad at all) |
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

### B2. Helicopter landing + helipads (D11, owner note)
- **Helicopters land on any open, flat ground** (not water, trees or buildings), in a base, outside it, at the front, wherever ordered. Order: Land here / Take off. A landed helicopter can load and unload troops and sling vehicles, and is more vulnerable while on the ground.
- **Helipads are service points:** a helicopter landed on a pad is rearmed, refuelled and repaired. With **Airfield Engineers assigned** to the pad (or to its airfield), this runs automatically and faster. Pads draw ammo and fuel from your supply stock.
- Each helicopter has a **home pad**; buying one needs a free pad. When low on ammo or fuel, a helicopter returns to the nearest friendly pad with a free slot, not only its home pad.
- **Forward pads:** Airfield Engineers can build a Forward Helipad in the field, giving a restock point near the front. A logistics truck on Auto (E1) also restocks helicopters landed nearby.

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
- **air_low** (helicopters, VTOL): hit by AA and by small arms/HMG flagged `anti_air_low`. **Can land on any open, flat ground** (landing-zone check: open, flat, not water, no trees or buildings) to wait, hide fuel use, or load and unload. Restock happens only at helipads, an airfield, a logistics truck on Auto, or with Airfield Engineers nearby.
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
- **Field rearm:** rearms, refuels and repairs a helicopter or light aircraft landed anywhere nearby, using supply stock.
- **Helipad service:** engineers assigned to a helipad (or its airfield) keep it stocked and auto-service every helicopter that lands there.
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

## 11. How it's built: agents, roles and operating guides (one wave, up to 8 live)

### 11.0 Rules every agent follows (the common operating guide)
Each agent gets this block plus its own guide (11.2) as its brief. They become `.plan/agents/prompts/G5_COMMON.md` and `G5-<ID>.md`.
1. **Read first, in order:**
   1. `.plan/AGENT_RULES.md`;
   2. `docs/CONTRACTS_G5.md` (§0 hard rules, §1 ownership, plus the sections its guide names);
   3. this plan;
   4. its own guide;
   5. the code it owns or calls (headers and public functions first).
2. **Touch only the files you own.** For anything else, post a `change_request` to the file's owner on the board and list it in your report. No two agents own the same file.
3. **Determinism:** same seed + same commands = same state hash, threaded or not, native or fallback. New state must survive a save/load round trip and be included in the hash.
4. **Keep the tree compiling after every write:**
   - add stub functions first;
   - write chunks of ≤250 lines;
   - after each, run `godot --headless --path . --quit-after 60 | grep "SCRIPT ERROR"`, which must print nothing.
5. **Tests:** iterate with `tests/run.sh --only=<file>`, then run the full suite once at the end inside `.plan/hb.sh`.
6. **Budget:**
   - post a status as your **first** tool call, then every 5 calls (with `calls_used`, `tokens_used_est` and `next_action`);
   - wrap any command over 60 s in `.plan/hb.sh`;
   - at 70% of the projection, write `.plan/handoff/<ID>-<n>.json` (done / exact remaining steps / files / test state / gotchas) and stop. A successor resumes from it.
   - Silent for 12 minutes = stopped.
7. **Machine sharing:**
   - never kill a godot process you didn't start;
   - rebuild the native DLL only by `build_native.sh --stage` then `--swap`;
   - record the CPU load with any timing.
   - Final benchmarks are taken by ORCH with every agent stopped.
8. **Finish:** kill your own processes, post `done`, and send the final report:
   - STATUS;
   - FILES;
   - TESTS (raw lines);
   - EVIDENCE;
   - CONTRACT_DEVIATIONS;
   - CHANGE_REQUESTS;
   - KNOWN_GAPS.

   Do not commit. Do not add a GENESIS offer.

### 11.1 Schedule (one continuous wave)

| Slot use | Agents |
|---|---|
| **Start (8 live)** | CORE10K, AIRSYS, NAVAL, UNITS5, SUPPORT, UI5, FONT, ART-U5 |
| **Queue, starting the moment a slot frees** | ART-BLD → ART-AIR → VIEW5 → ART-NAV → AI6 → PT5 → ED5 |
| **Successors** | take queue priority (a stopped agent's work resumes before new work starts) |
| **Final gate** | ORCH, with every agent stopped |

Before anyone starts, ORCH writes `CONTRACTS_G5.md`, which fixes:
- the IDs (units, buildings, upgrades, commands);
- file ownership;
- the APIs between agents (signatures);
- the `api_ready` facts.

ORCH also adds the scaffold: empty system files registered in SYSTEM_ORDER, empty content fragments, and stub panels. Every agent therefore starts on a compiling tree.

### 11.2 Operating guide for each agent

---
#### CORE10K: engine hot state, 10k speed, wall-breach hook
- **Role:** make 10,000 fighting units run at ≥0.8x speed with identical results, and fix the engine-side G4 gaps.
- **Owns:**
  - `sim/hot_state.gd` (new); the hot-state block of `sim/world.gd` (the region marked by ORCH);
  - `sim/systems/{movement,combat,damage,supply,morale,fog,tiers,territory,sim_index,unit_subsets}.gd`;
  - `sim/native_core.gd`, `native/**`, `bin/**`, `tools/build_native.sh`, `tools/scale_bench.gd`;
  - `tests/test_perf*.gd`, `tests/test_hot_state.gd`.
- **Inputs:** SIM10K-2's report and CR (packed per-id arrays), `perf/PERF_REPORT_G4_2026-10-24.md`, `.plan/handoff/SIM10K-2-*`.
- **Tasks (in order):**
  1. Post the hot-state API (`HotState.set_pos/set_target/set_moving/set_cd/set_order/set_hp`, plus array getters) as `fact core.hot_api_ready` within the first hour, stubbed and compiling.
  2. Move movement gather, combat prep, supply, morale and fog onto the arrays, with the dictionaries flushed for hash, save and snapshot.
  3. Native core reads the arrays directly (rts_core 0.4.x).
  4. Wire `Fortify.on_attack_move_blocked` where an attack-move path fails, so player units breach.
  5. Add the `Damage.on_zero_hp(w, e)` hook for SUPPORT's Wounded state: return true = "don't destroy".
  6. Add the air/naval damage-class flags AIRSYS/NAVAL request through CRs.
- **Publishes:** `core.hot_api_ready`, `core.zero_hp_hook_ready`, `core.breach_wired`.
- **Done-when:**
  - A/B state hash equal to HEAD on 2k fight, 2k mixed, 10k fight and 10k march, with native on and off and with the sim thread on and off;
  - 10k fight avg ≤ 62.5 ms/tick in its own run (CPU load noted);
  - test_hot_state + test_perf green;
  - full suite green.
- **Budget:** 700k / 170.
- **Never:** change a gameplay result without a flag that defaults off.

---
#### AIRSYS: airfields, hangars, flight model, air transport
- **Role:** the whole air sim.
- **Owns:**
  - `sim/systems/air.gd` (flight: hover, sorties, holding, fuel/ammo return, air-vs-air targeting);
  - `sim/systems/airfield.gd` (strips, hangars, upgrades, runway queue, craters, diverts, engineer assignment hooks);
  - `sim/systems/transport.gd` (adds sling, `cargo_size` and mixed cargo for the VTOL);
  - `content/g5/air.json`;
  - `tests/test_air.gd`, `tests/test_airfield.gd`, `tests/test_air_transport.gd`.
- **Inputs:** plan §3, contract §AIR, `core.hot_api_ready`.
- **Tasks:**
  1. Content for every air unit and air building with fixed IDs (Human A/B/Machine), including the Airstrip variant and the Drone Launch Rail/Bays.
  2. Hangar gating: production of an aircraft fails with `no_free_hangar` unless a free hangar of the right class exists. Post `fact air.gating_ready`.
  3. Runway ops:
     - deterministic taxi → roll → airborne;
     - approach → touchdown → taxi → hangar;
     - one aircraft per strip;
     - a holding-pattern queue with low-fuel priority.
  4. Sorties, rearm/refuel timed by hangar level. Helicopters `land_at` any open ground (landing-zone check). Helipad service (rearm/refuel/repair) is automatic with assigned engineers; low helicopters return to the nearest free friendly pad.
  5. Craters close a strip; `Airfield.repair_crater` is the engineer API; diverts and crashes when no field is left; a destroyed hangar kills the aircraft parked in it.
  6. Air transport: troops, sling vehicles, VTOL 2 vehicles + 8 troops, and landing-zone validation.
  7. `air_low`/`air_high` targeting rules plus the `anti_air_low` flag.
  8. Save/load mid-flight and mid-holding.
- **Publishes:** `air.api_ready` (commands: `build_hangar`, `upgrade_hangar`, `upgrade_airfield_strip`, `sortie`, `rebase`, `land_at`, `assign_engineers`), `air.gating_ready`.
- **Done-when:** the 3 test files green (sortie cycle, holding, craters + repair, gating, VTOL cargo, air-vs-air, save mid-flight) and the full suite green.
- **Budget:** 700k / 170.
- **Never:** touch `movement.gd`; ground units keep their nav. Aircraft use their own flight model in `air.gd`.

---
#### NAVAL: ships, shipyards, Coastal Front
- **Role:** the whole naval sim and the new map.
- **Owns:**
  - `sim/systems/naval.gd` (bombardment, beaching/unload rules, sinking wrecks, pier resupply);
  - `sim/maps/coastal_front.gd` (new map generator + validation);
  - `content/g5/naval.json`;
  - `tests/test_naval.gd`, `tests/test_coastal_front.gd`.
- **Inputs:** plan §4; G4 movement classes (`naval`, `naval_small`, `amphibious`); `Movement` API (call only).
- **Tasks:**
  1. Content for every ship and naval building with fixed IDs.
  2. Coastal Front (192×192):
     - mainland, 2 islands, beaches, an estuary with fords;
     - 2–4 spawns validated reachable by land or sea;
     - registered through a CR to ORCH (map list).
  3. Shipyard shore placement (part water, part beach).
  4. Landing craft unload only at beach/shallow; the amphibious crawler drives ashore.
  5. Shore bombardment (indirect fire on land in range).
  6. Wrecks sink into a shallow obstruction (nav updated).
  7. Supply Pier restock.
  8. Save/load mid-sea.
- **Publishes:** `naval.api_ready`, `map.coastal_front_ready`.
- **Done-when:** test files green (movement by class, placement, beaching, amphibious path, bombardment, sinking, save mid-sea); the map validates for seeds 1–5; full suite green.
- **Budget:** 700k / 170.
- **Never:** edit `movement.gd` (CR to CORE10K) or the AI.

---
#### UNITS5: 17 new ground units and the Drone Team
- **Role:** every new human ground unit's sim behaviour, plus the burnt-ground save fix.
- **Owns:**
  - `content/g5/units_g5.json`;
  - `sim/systems/g5_mech.gd` (new: Drone Team, HMG deploy, Special Forces concealment/charges, Grenadier/Shock bonuses, ambulance carry slots);
  - `sim/systems/g4b_mech.gd` (burnt cells become a saved, hashed sim set);
  - `tests/test_units_g5.gd`, `tests/test_drone_team.gd`.
- **Inputs:** plan §5, contract §UNITS; `core.hot_api_ready`; the transport API for ambulance slots.
- **Tasks:**
  1. Content for all 16 human units and the Machine Maintenance Swarm (stats, weapons, armor, production links, stage gates).
  2. **Drone Team:**
     - one squad entity of 3;
     - `launch_drone {type, target}` command;
     - 4 charges;
     - 4 drone types as short-lived `air_low` entities (strike dive, frag, recon reveal/mark, EMP/jam), shootable by AA and jammable by EW;
     - auto-switch to **tactical mode** at 0 charges (infiltrate, takedown, breach, stack-up, armored attack);
     - restock at a supply source returns it to drone mode.
  3. HMG deploy/pack, Special Forces concealment + charges + air-drop flag, Grenadier/Shock bonuses, Mobile AA targeting `air_high`.
  4. Burnt cells as sim state, kept through save/load.
- **Publishes:** `units5.api_ready` (commands: `launch_drone`, `tactical_*`, `deploy`/`pack`).
- **Done-when:**
  - tests green: each unit's special, drone launch per type, the 4 → tactical switch, restock back to drone mode, burnt ground saved and reloaded;
  - full suite green.
- **Budget:** 700k / 170.
- **Never:** write the wounded/medical logic (SUPPORT) or the art.

---
#### SUPPORT: Auto resupply, Wounded, evacuation, hospitals
- **Role:** the two auto-support systems and the medical buildings.
- **Owns:**
  - `sim/systems/support.gd` (Auto Resupply: station + roam, thresholds, combat rule, resume orders, truck self-refill, multi-truck split);
  - `sim/systems/medical.gd` (Wounded state via `Damage.on_zero_hp`, 60 s bleed-out, auto evac, Hospital/Field Hospital healing → free reinforcement);
  - `content/g5/support.json` (Hospital, Field Hospital for both human factions);
  - `tests/test_support.gd`, `tests/test_medical.gd`.
- **Inputs:** plan §6; `core.zero_hp_hook_ready`; the Supply API (call only); UNITS5's ambulance/medic IDs.
- **Tasks:**
  1. The `set_auto_resupply {mode: station|roam, area, thresholds}` command and per-truck state.
  2. Units requesting supply go and return to the order they had saved.
  3. A truck refills itself at the nearest depot/refinery.
  4. Wounded: infantry at 0 HP → Wounded (immobile, no fire, counted in pop); bleed-out after 60 s; saved and hashed.
  5. `set_auto_evac {area}` for medic/ambulance; pick-up capacity per unit; delivery to the nearest hospital; Field Hospital triage → Hospital; healed → a free reinforcement at the Hospital.
  6. Works for ships (pier) and helicopters (forward strip) through AIRSYS/NAVAL APIs.
- **Publishes:** `support.api_ready`, `medical.api_ready`.
- **Done-when:**
  - tests green: station and roam resupply, combat rule, resume order, self-refill, two trucks not doubling up, wounded → evac → hospital → reinforcement, bleed-out, save mid-evac;
  - full suite green.
- **Budget:** 700k / 170.
- **Never:** edit `supply.gd` or `damage.gd` (CRs to CORE10K).

---
#### UI5: interface facelift and every new panel
- **Role:** a new UI kit, layouts that fit at every size, and every new command panel and setting.
- **Owns:**
  - `presentation/hud/**`, `presentation/menu/**`, `presentation/match_view.gd`, `presentation/view/g4b_*.gd`;
  - `presentation/ui5/**` (new panel kit, airfield/hangar panel, drone picker, truck and medic Auto panels, control-group bar, idle button, F1 sheet, settings menu with key rebinding);
  - `tools/ui_fit_test.gd`.
- **Inputs:** plan §7; FONT's TTF when ready (use a placeholder until then); every `*.api_ready` command list; THREAD's rule to read only the render snapshot while `sim_busy()`.
- **Tasks:**
  1. **Fit test first:** `tools/ui_fit_test.gd` opens every screen and panel at the 7 resolutions; it fails on any rect outside the viewport or overlapping. Run it on today's UI to list every current clip.
  2. Panel kit and theme: a military style, faction accents, hover/selected/disabled states, tooltips with hotkey + cost.
  3. Re-layout the HUD, menus, setup, pause and objectives with anchors/containers, plus a UI Scale setting (75–150%).
  4. New panels:
     - airfield (strips, hangars, occupants, upgrades, engineers, Buy hangar, "No free hangar" state);
     - aircraft commands (sortie, rebase, land);
     - VTOL cargo;
     - drone picker with the ● counter;
     - tactical-mode buttons;
     - truck Auto (station/roam drag);
     - medic Auto;
     - naval commands.
  5. Control-group bar, idle-units button, double-click select-type, F1 hotkey sheet, settings menu (graphics, speed, edge-pan, health bars, key rebinding).
  6. Swap in FONT's typeface everywhere once the owner approves the specimen.
- **Publishes:** `ui5.kit_ready` (ED5 and PT5 build on it), `ui5.fit_green`.
- **Done-when:**
  - the fit test shows 0 clipped/overlapping controls at all 7 resolutions (screenshot sheets saved);
  - the 6 existing playtests still pass;
  - full suite green.
- **Budget:** 700k / 170.
- **Never:** read `w.entities` during a step; edit the editor (ED5) or `ui_playtest.gd` (PT5).

---
#### FONT: the game's own typeface
- **Role:** design and build an original military-modern typeface.
- **Owns:** `tools/font/**` (an outline-based builder that writes a TTF via fontTools), `assets/fonts/rts_mil_{bold,regular}.ttf`, `assets/fonts/specimen.png`.
- **Tasks:**
  1. Glyph design rules: angular stencil cuts, squared counters, clear 0/O and 1/l/I.
  2. Full Latin A–Z/a–z, digits, punctuation, symbols used in the UI (● × % + − / : arrows).
  3. Build the TTF in 2 weights, with kerning pairs for common pairs.
  4. A specimen sheet (UI sizes 12–48 px, light/dark backgrounds, numbers in tables). Post `fact font.specimen_ready`. **ORCH shows it to the owner for approval.**
  5. Apply the owner's fixes and post `fact font.final`.
- **Done-when:** both TTFs load in Godot; the specimen is approved; licence note: original work, no third-party outlines.
- **Budget:** 400k / 100.
- **Never:** copy or trace an existing font.

---
#### ART-U5: ground units and launched drones
- **Owns:** `tools/art/g5_units*.gd`, `assets/art/g5_units/**`, `tests/test_art_g5_units.gd`.
- **Tasks:**
  - sheets for all 17 new ground units: 8 facings; idle/move/fire; specials (deploy, launch, carry wounded, wounded pose, tactical stance); team masks; wrecks; icons;
  - the 4 drone types × 2 factions (Human A precision, Human B rigged) with dive/trail frames;
  - faction styles kept;
  - self-check every sheet by viewing zoomed crops; manifest entries with `lod_class`.
- **Done-when:** the art test green; every ID in `units_g5.json` has art; zoomed crops saved in `.plan/shots/ART-U5/`.
- **Budget:** 600k / 150.

#### ART-BLD: all new buildings and command icons
- **Owns:** `tools/art/g5_bld*.gd`, `assets/art/g5_bld/**`, `tests/test_art_g5_bld.gd`.
- **Tasks:**
  - airfield (4 rotations, 1–4 strips, crater overlays);
  - Light/Heavy hangars with 3 upgrade looks;
  - helipad, control tower, Forward Airstrip, Airstrip variant;
  - Machine Launch Rail + Drone Bays;
  - shipyard (shore art), Supply Pier, Coastal Battery × 3 factions;
  - Hospital and Field Hospital × 2 human factions;
  - damaged states;
  - icons for every new unit, building and command.
- **Done-when:** the art test green; every new building ID has art; crops saved.
- **Budget:** 600k / 150.

#### ART-AIR: aircraft
- **Owns:** `tools/art/g5_air*.gd`, `assets/art/g5_air/**`, `tests/test_art_g5_air.gd`.
- **Tasks:**
  - 12 aircraft;
  - rotor/jet animations;
  - a ground shadow plus altitude offset;
  - landing-gear frames for taxi/landing;
  - a sling-load pose;
  - VTOL hover/landing frames for both versions;
  - wrecks;
  - effects: bombs, missile trails, smoke.
- **Done-when:** the art test green; every air ID has art; crops saved.
- **Budget:** 600k / 150.

#### ART-NAV: ships and the coast
- **Owns:** `tools/art/g5_naval*.gd`, `assets/art/g5_naval/**`, `tests/test_art_g5_naval.gd`.
- **Tasks:**
  - 9 ships: wakes, bow spray, firing, sinking frames, wrecks;
  - Coastal Front decor (piers, cliffs-to-sea transitions, island details);
  - effects: shell splash, landing-ramp frames.
- **Done-when:** the art test green; every naval ID has art; crops saved.
- **Budget:** 600k / 150.

---
#### VIEW5: drawing everything new in the game world
- **Role:** render the new sim state from the snapshot.
- **Owns:** `sim/render_snap.gd`, `presentation/view/{entity_layer,batch_art,fx_layer,terrain_layer,lod_icons}.gd`, `presentation/art/art_catalog.gd`.
- **Inputs:** every `*.api_ready`; the art manifests from the ART agents.
- **Tasks:**
  - aircraft with altitude offset + shadow, takeoff/landing/taxi on the strips, holding circles, sling loads;
  - runway craters and hangar states;
  - ships with wakes and sinking;
  - drones in flight;
  - the wounded marker and the evac carry pose;
  - the truck Auto area circle and supply icons;
  - burnt ground from the sim set;
  - LOD icons for all new units;
  - snapshot flags for every new visual state.
- **Done-when:**
  - a headless probe passes for each new visual state;
  - the 6 existing playtests pass;
  - screenshots of air, naval, drones and evac saved;
  - full suite green.
- **Budget:** 600k / 150.
- **Never:** read the live world while `sim_busy()`.

---
#### AI6: the AI for all of it, plus the Valley fix
- **Owns:** `sim/ai/**`, `tools/soak.gd`, `tests/test_ai.gd`.
- **Inputs:** `air.api_ready`, `naval.api_ready`, `units5.api_ready`, `support.api_ready`, `medical.api_ready`; AI5-4's work-in-progress patch in `build/_ai5-4_wip/`; `.plan/handoff/AI5-3.json` and `AI5-4.json`.
- **Tasks:**
  1. **Valley fix first:** the bank uses the launch army plus a late-game bank drop, with no retarget penalty. Valley s1/s2 must end with winners.
  2. Air: pick an airfield site, buy then upgrade hangars, assign engineers, AA cover, air assaults with gunship/VTOL, jet strikes on clusters/artillery, bombing enemy airfields, AA on contact.
  3. Naval: a shipyard on water maps, contest the water, bombardment, amphibious landings when the land route is blocked or long.
  4. New units: Drone Team usage by type, tactical breaching, medics/ambulances on Auto with hospitals, a logistics truck on Auto behind every army.
  5. Soaks: 4 maps × 2 seeds + 1 editor map, run at most 3 at a time; log lines for sorties, landings, resupply and evac.
  6. ai_bench < 2 ms per side at 5k units.
- **Done-when:** every soak ends with a winner with 0 invariant failures and the usage logs present; test_ai green; full suite green.
- **Budget:** 700k / 170, with successors expected.
- **Never:** change soak criteria or max_ticks.

---
#### PT5: playtests for every new flow
- **Owns:** `tools/ui_playtest.gd`, `tools/editor_playtest.gd`, `.plan/shots/PT5/**`.
- **Inputs:** `ui5.kit_ready` plus every `api_ready`.
- **Tasks:** add synthetic-input flows (screenshots at each step) for:
  - **air:** place airfield → buy hangar → assign engineers → build a jet → takeoff → sortie → land; VTOL loads 2 vehicles + 8 → flies → unloads; a helicopter lands on open ground outside the base → takes off → is serviced at a helipad with engineers assigned;
  - **naval:** shipyard → landing craft → load → beach landing;
  - **Drone Team:** 4 launches of chosen types → tactical breach;
  - **Auto resupply:** station and roam;
  - **medical:** wounded → evac → Hospital → reinforcement;
  - **tutorial:** a full run-through.

  Keep the existing 6 flows passing.
- **Done-when:** every flow prints `PLAYTEST RESULT pass=N fail=0` twice in a row; screenshots self-checked.
- **Budget:** 500k / 120.

---
#### ED5: editor additions, tutorial, polish
- **Owns:**
  - `presentation/editor/**`;
  - `sim/systems/triggers.gd` (new conditions: aircraft landed, unit evacuated, beach landing);
  - `content/scenarios/tutorial.rtsmap`;
  - `presentation/main.gd`;
  - the polish items in files it owns, with CRs for the rest.
- **Inputs:** `ui5.kit_ready`; all content IDs.
- **Tasks:**
  1. Editor palettes show the new units/buildings. Place airfields with strips/hangars and aircraft already parked, plus helipads, shipyards, hospitals and ships on water. Validate the new placements.
  2. New trigger conditions.
  3. The tutorial match: move, gather, build, train, attack, advance a stage, walls, transports, Auto resupply, airfield (buy a hangar, build a jet, take off/land), med evac. Step prompts in the new UI; reachable from the main menu.
  4. The polish list (§9).
- **Done-when:** the editor playtest passes; the tutorial completes in PT5's flow; test_editor_* green; full suite green.
- **Budget:** 600k / 150.

---
#### ORCH (me): contracts, verification, commits, final gate
- Writes `CONTRACTS_G5.md` + scaffold + every brief before any agent starts.
- Registers every budget cap and runs the budget guard + board monitors all wave.
- Audits each completion; verifies tests and evidence; commits each agent's files by path.
- Handles every change request in files it owns (`world.gd` outside the hot block, `content.gd`, base `rules.json`, the map list).
- Shows you the typeface specimen and asks for your OK.
- **Final gate**, with all agents stopped:
  - full suite;
  - quiet-PC perf (sim + windowed fps);
  - all soaks;
  - all playtests;
  - the UI fit test;
  - packaged build from a clean folder;
  - copy to Downloads;
  - README/perf/PROGRESS updated.

  Then a report to you with raw evidence per Done-when item.

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
   - **air:** place airfield → buy hangar → assign engineers → build jet → takeoff/land; VTOL carries 2 vehicles + 8; a helicopter lands in the field and is auto-serviced at a helipad;
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
