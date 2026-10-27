# RTS: Age of Modern War: playable slice (G0 through G7)

A classic real-time strategy skirmish built in **Godot 4.7.2**. It is offline and single-player.

You pick one of **three factions** (Human A, Human B, Machine), start each side at **Stage 7, 8 or 9**, and fight up to three autonomous AIs, free-for-all or in teams, on one of **three maps**: River Crossing (96×96), Industrial Heartland (160×160) or Valley Conquest (256×256). Battles can involve thousands of units.

## What you can do in this build
- Start a skirmish from the menu (see G3a below for factions, teams and victory modes): seed, per-side credits and AI difficulty, economy profile.
  - All 13 stages are listed. Stages 7, 8 and 9 are playable; research and advance mid-match (see G3b below).
- **Economy:**
  - Engineers gather salvage and ore and deliver them to the HQ or a depot.
  - Credits come from the treasury plus an HQ stipend.
  - Power is a flow: generators produce it, and production stalls with LOW POWER when it runs short.
  - The supply cap comes from the HQ and depots.
- **Build:** generator, depot, barracks, motor pool and guard tower. A placement ghost shows a legal or illegal reason and the cost.
- **Train:** work crews, rifle squads (4), AT teams (2), recon scouts, IFVs and main battle tanks.
- **Fight:**
  - Select by click, drag, shift or double-click.
  - Right-click is a smart command (move, attack, gather or assist construction).
  - Hotkeys: A attack-move, S stop, H hold. Ctrl+1–9 saves a control group and 1–9 recalls it.
  - Armor classes matter: small arms barely scratch tanks.
  - Fog of war, with remembered enemy buildings.
  - Vehicles and buildings leave persistent wrecks.
- **Win** by destroying the enemy HQ, or play Endless. The AI follows the same rules you do:
  - it issues the same commands;
  - it pays the same costs;
  - it only knows what its units can see.
  - It won't launch an offensive before a grace period: about 7 minutes on Normal, 10 on Easy, 5 on Hard.
- Save and load: F5 / F9, or the pause menu.

## Run it
- **Windows:** double-click `game/run.bat`.
- **Git Bash:** `bash game/run.sh`.

The first launch imports the project once (a few seconds). Needs Godot 4.7.2: `winget install GodotEngine.GodotEngine --version 4.7.2`, or set `GODOT` to your Godot exe.

Useful flags (append to the launcher):

| Flag | What it does |
|---|---|
| `--autostart` | Skip the menu |
| `--autostart-seed=N` | Set the match seed |
| `--autostart-factions=human_a,human_b,machine` | Skip the menu with these sides (you are the first) |
| `--autostart-map=<id>` / `--autostart-stages=7,8,9` | Map (`river_crossing_s`, `industrial_heartland_m`, `valley_conquest_l`) and start stage per side |
| `--spawn-test=N --fps-log` | Spawn N extra fighting units and log fps (perf runs) |
| `--player-ai --speed=8` | Watch AI vs AI |
| `--ui-playtest=<dir>` | Scripted UI playtest |
| `--autoshot=<png> --autoshot-delay=N` | Save a screenshot after N seconds |

## Verify it
```bash
bash game/tests/run.sh
```
This runs 200 headless tests (22 files): ledger conservation, command validation, placement rules, power/supply stalls, pathing, combat, fog fairness, victory, save round-trip, same-seed determinism, AI autonomy and fairness, stages and research, maps, native-core parity and fidelity-tier parity. Other checks:
- `game/tools/soak.gd`: AI vs AI to a winner.
- `game/tools/bench.gd` and `game/tools/scale_bench.gd`: sim performance (`scale_bench` covers 1k–10k units on any map, native on/off).
- `bash game/tools/build_native.sh`: rebuilds the Rust native core (`game/native/rts_core` → `game/bin/rts_core.dll`; needs Rust). The built DLL is committed, so you only need this if you change the Rust code.
- `game/tools/ui_playtest.gd`: a menu → build → train → attack-move flow driven by synthetic input.

## G2 "Smart Warfare" (2026-10-23)
- **Supply:** ammo and fuel with resupply near the HQ, depots and supply trucks; the refinery converts ore into fuel and ammo.
- **Combat:**
  - directional armor (flank the tanks);
  - infantry cover, suppression/pinning, and morale break/retreat/rally;
  - vehicle component damage (mobility/weapon/sensors);
  - ridges block line of fire, and infantry hide in forest.
- **Engineer repair.** Wrecks leave scrap you can harvest.
- **Officers** command groups on delegated missions (secure / hold / attack / patrol) and report their phase and reasons. Also patrol, guard and formations.
- **The river bridge** can be demolished (Shift+right-click) and rebuilt; traffic reroutes over the fords.
- **The AI** uses all of the above.
- More detailed vehicle and building art.
- Evidence: `PROGRESS.md`, `perf/PERF_REPORT_G2_2026-10-23.md`. Packaged build: `build/RTS_Age_of_Modern_War_G2/`.

## G3a "Factions + Skirmish" (2026-10-23)
- **Three factions**, each with its own buildings, units, art and economy twist:
  - **Human A, Modern Military Power:** the G1/G2 combined-arms army.
  - **Human B, Industrial Power:** salvage economy (the Salvage Yard pulls in scrap), tough infantry, rebuilt tanks, artillery trucks.
  - **Machine, Autonomous Network:** energy-bound units that recharge near hubs, no morale; combat drones (air), walkers, artillery nodes.
- **Skirmish setup:**
  - 2–4 sides, each set to You, AI or Closed, with faction, team, colour, credits and AI level;
  - free-for-all or teams, with allied shared vision;
  - arcade / standard / simulation economy.
- **Victory modes:** HQ elimination, territory control (hold N% of map sectors), hold the bridge for N seconds, Endless, or two combined with AND/OR.
- **New weapons:** artillery (indirect fire, splash, minimum range) and anti-air rules (only small arms, machine guns and autocannons hit drones).
- **The AI** plays every faction, picks targets among several enemies and cooperates with allies.
- Evidence: `PROGRESS.md`, `perf/PERF_REPORT_G3a_2026-10-23.md`. Packaged build: `build/RTS_Age_of_Modern_War_G3a/` (see its `PLAY_ME.txt`).

## G3b + Scale "Big Armies" (2026-10-24)
- **Two new maps:**
  - Industrial Heartland (160×160): factories, rail siding, refinery site, ruined plant, two bridges plus fords, 6 spawn sites.
  - Valley Conquest (256×256): river branches, central dam, airfields, foothills, 8 spawn sites.
  - Both are generated from a seed, deterministic, and validated for fair, reachable spawns.
- **Stage 7 → 8 → 9:**
  - Each side picks its start stage.
  - Stage 7 has an older roster: Cold-War Tank, Towed Field Gun, Siege Crawler.
  - Stage 9 adds drones, electronic warfare and precision fire for each faction (12 new units and 5 new buildings, all with art).
  - **Research** at a research building.
  - **Advance** by clicking once the stage panel's gates are met (owner-approved gates; see `docs/CONTRACTS_G3b.md` §3.2).
  - Advancing never spawns free gear.
- **EW jamming and guided weapons.**
- **Refinery:** now refines only while fuel or ammo is below its cap, so ore can be saved.
- **Scale:**
  - a **native core in Rust** (`game/native/rts_core`, loaded as a GDExtension) for movement, pathfinding, flow fields, spatial queries, fog and line of sight;
  - **fidelity tiers** (units far from any enemy update less often, with identical fight outcomes);
  - shared entity indexes;
  - a batched renderer with culling and zoomed-out unit icons.
- **The AI** researches, advances, uses Stage 9 units, routes over several crossings, commits decisive waves on big maps, and stays under 1 ms per tick per side at 5,000 units.
- Evidence: `PROGRESS.md`, `perf/PERF_REPORT_G3b_2026-10-24.md`. Packaged build: `build/RTS_Age_of_Modern_War_G3b/`. Keep `rts_core.dll` next to the exe.

## G4 "Foundations, Editor, Fortifications" (2026-10-24)
- **Map & scenario editor** (main menu > Map Editor): terrain, rivers, lakes, ocean, beaches, cliffs, hills, trees/rocks/decor, units and buildings for any player, symmetry, undo/redo, triggers and victory presets, validate, save `.rtsmap`, test-play, and play it from Skirmish Setup.
- **Walls, gates, towers:** drag-built wall lines (8 directions), per-team gates with Lock/Unlock, wall towers, breach by attack or engineer charges.
- **Troop transports:** load by right-click, cargo strip, unload at point / all, officer "Transport to point".
- **8 new human units:** APC, Sniper (concealment), Mortar (deploy), Combat Engineer (mines, charges); Flamer (forest fire), Halftrack, Scrap Mech, Rocket Truck. All have art, frames and effects.
- **Engine:** the sim runs on its own thread, with a render snapshot; new terrain (shallow/deep water, beach, cliff, hill) and movement classes (amphibious, naval, air); map files with triggers; save/load at 10k units.
- **AI:** builds walls/gates, lays mines, uses transports, fields the new units, and breaches walls that force a detour.
- **Scale:** native core 0.3.1. 2k fight 21 ms/tick; 10k march 63 ms; 10k all-fighting 104 ms (still about half speed). See `perf/PERF_REPORT_G4_2026-10-24.md`.
- Evidence: `PROGRESS.md`. Packaged build: `build/RTS_Age_of_Modern_War_G4/` (keep `rts_core.dll` next to the exe).

## G5 "Full Spectrum" (2026-10-25)
- **Air war:**
  - airfields with hangars you buy and upgrade, and extra airstrips;
  - Airfield Engineer Teams (click to assign, then automatic upkeep);
  - helipads as restock points;
  - helicopters, gunships and VTOLs land on any open area big enough;
  - VTOL dropship (2 vehicles + a squad of 8).
- **Naval war:** shipyards, ships, shore bombardment, amphibious landings.
- **17 new human ground units**, including the Drone Team: 3 soldiers, 4 drone styles, then tactical breach, takedown and stack-up.
- **Support:** logistics truck "auto" restock; medics and ambulances auto-evacuate wounded to a Hospital or Field Hospital.
- **UI:** refreshed layout that fits at 7 resolutions x 3 UI scales (0 clipped controls), the original RTS Mil typeface, and a 16-step tutorial.
- **AI:** uses air, naval, drones, medevac and the new units.
- **Scale:** native core 0.4.2. 10k all-fighting is about 94-101 ms/tick, still under target.
- Valley AI soaks still draw; see PROGRESS G5 evidence. Packaged build: `build/RTS_Age_of_Modern_War_G5/`.

## G6 "Command & Terrain" (2026-10-25) — delivered PARTIAL (see PROGRESS G6 evidence)
- **True elevation:** 4 height levels with ramps and cliffs; high ground sees and shoots farther and takes less damage
  from below. Bold in-game look approved by the owner (taller cliff faces, level tint, baked shadows).
- **Companies, armies, Commanders:** Company HQ, Army Builder (presets + custom, 15-45 elements), captains and
  lieutenants, armies under a Commander; a built Company HQ raises the supply cap to 200.
- **AI:** military doctrine (overwatch, suppress, flank, assault, hold high ground, raids, exfil) for enemy and allies;
  AI Commanders that assist the player (4 playstyles, never override an order from the last 20 s); ally commands;
  wave AI for survival.
- **89 new units and buildings** with their systems: mines, fieldworks, garrisons, rail, engineering, subs + sonar,
  carriers, radar/SAM, CIWS, jammers, call-ins, auras, Machine specials, strike batteries; exo-suits and loadouts;
  marketplace; compact airfields; Stage 10; survival mode (any map + Ridge Bastion, River Dam); editor Live mode.
- **Not met (owner parked both):** 10k all-fighting speed on an elevated map (target 62.5 ms/tick; measured 296.5 under
  heavy background load, 143-156 under shared agent load) and AI soak winners on every map (5/11; Valley and
  Heartland draw). Frame rate gates pass: 2k on screen p10 83.7 fps, 10k zoomed out p10 111.1 fps.
- Packaged build: `build/RTS_Age_of_Modern_War_G6/` (also copied to Downloads).

## G6.1 "Field Command" (2026-10-26) — delivered PARTIAL (see PROGRESS G6.1 evidence)
Scoped by the owner in two question passes. Every level of the army now thinks for itself, and the game looks and sounds new.
- **Chain of command:** General > Commander > Captain > Lieutenant > squad leader > soldier. Orders go down by radio with
  a delay (jammers slow or cut links), reports come up ("Contact, enemy armour, north-east!"), cut-off units act on their
  last orders. Each side fights from what it *believes* about the enemy (fading last-known positions, decoys), not the truth.
- **AI generals:** hand a company or army to an AI Commander on "Auto (general)" with a budget. It picks its own operations
  (strike, infil/exfil, deliberate attack with fix-and-flank, defend in depth, counter-attack, recon in force, screen, supply
  raid, refit), buys replacements within the budget, calls artillery, air sorties and JTAC marks (never danger-close),
  sets up medevac, attaches ammo bearers and reports in plain lines. Enemy AI sides can run the same engine (off by default).
- **Officers:** battle drills (stack up and breach, bounding overwatch, react to contact, fix-and-flank and pincers, defence
  in depth, routes around minefields and open ground under fire); officers stay behind the line.
- **Squads:** shared targets and return fire, cohesion, cover, spreading under artillery, role-aware targeting, wounded fall
  back to medics; stances (aggressive, defensive, hold fire, hold position); 8 formations; Teams panel (F2); double-click
  selects a squad, Ctrl+double-click a platoon.
- **Command mode (F3):** draw objectives, an axis of advance and phase lines for a company; the chain of command executes it.
- **Realism:** weapon-scaled suppression and pinning, fatigue, veterancy (green to hero, with chevrons), leader traits.
- **Ammo bearer** (all factions): restocks 3 units fully, joins a squad ([ / ]), reloads at supply points; the AI uses them.
- **Owner-reported fixes:** Company HQ refuses a company you can't house (with the reason) and shows training progress;
  no market cap ("Buy max"); vehicles go about 3x further on fuel; match setup "Starting resources" up to 50k of each.
- **Look and sound:** new infantry animation (walk/run cycles, crouch, prone/crawl, firing, reload, throw, death), smooth
  motion, rotating tank/IFV turrets, recoil, tracks, banking aircraft and ships; new effects (muzzle flashes, tracers,
  layered explosions, craters, burning wrecks, smoke screens, dust); generated battle sound and radio chatter (Windows
  speech voices through a radio filter) with Settings > Audio sliders.
- **Verified (2026-10-26, final build):** full test suite run (105 files): every failure found was fixed or shown to be
  load noise (AI fair play, rifle-vs-tank, fast-path movement parity; the 3 timing tests pass on an idle PC); fixed-result
  hash tests 17/17 after the G6.1 re-baseline (two identical capture runs); 42 playtests from the packaged build in a clean
  folder: 34 fully pass, 0 script errors in all 42; the flicker probe passes 8/8; enemy general on vs off: no errors, no
  invariant failures, same AI think time.
- **Fixed today:** units flickering or not drawn; the AI general knew about enemy deaths it never saw; pinned, suppressed and
  tired units did not slow down in the shipped build (fast movement path); tanks backed away from riflemen showing their rear.
- **Follow-up (2026-10-26 afternoon):** 6 of the 7 failing playtest flows fixed and green from source (g4b 68/0, air 98/0,
  mines 29/0, airdef 37/0, support 37/0, vfx61 14/0). The causes were in the test flows, not the game: G6.1's extra card
  buttons pushed some units onto page 2 of the card, double-click now selects one squad, a minefield's size is random, a
  scout placed beside the tank duel, a SAM check that counted another unit's shots. Frame rate on an idle PC: 2,000 units
  on screen p10 85.2 fps (gate 60) PASS; 10,000 zoomed out p10 262.5 fps (gate 30) PASS.
- **Follow-up 2 (2026-10-26 afternoon):** simulation cost now 1.18x G6 at 2,000 fighting units (median of 6 alternating
  runs on an idle PC: 17.12 vs 14.52 ms per tick; limit 1.2x) with identical results (cached morale leader list;
  native core 0.5.2 applies the realism movement factors itself). Fixed a formation bug: any group over 12 in formation
  had slots ~30 tiles behind its target, so a big group ordered forward walked back toward its base; groups over 12 now
  form blocks of up to 12 side by side. The officer61 flow passes from source (17/0: advance, contact drill, stack-up,
  assault). The new build (pck ec9b69d4, native core 0.5.2) passed officer61 16/1, flick61 8/0, squad61 26/0,
  company61 41/0, air 98/0 and the core flow 33/0 from a clean folder, 0 script errors.
- **Known issues (honest):** in the packaged officer61 run the company went from the contact drill straight to the assault
  without stacking up first (timing-dependent; it stacks in the run from source). The full 42-flow packaged run was not
  repeated for this build. The enemy general stays off by default (in AI-vs-AI matches the AI fields no companies).
- Packaged build: `build/RTS_Age_of_Modern_War_G61/` + `build/RTS_Age_of_Modern_War_G61_2026-10-26.zip` (also in Downloads).

## G7 "Signalborne / Last Protocol" (2026-10-27) — delivered PARTIAL (see PROGRESS G7 evidence)
Scope: `docs/G7_REFERENCE.md` (master scope + owner amendments 13.9a fissures, 13.9b base layout).
- **Last Protocol** (main menu, its own mode; the map is locked out of skirmish): hold a 3-ring fortress around the
  Counter-Nanite facility against the Machine's nanite creep, which escalates in phases, opens fissures and canyons with
  growths rising out of them, sends Weavers and ends in THE TIDE. Strike teams hit nanite cores; ops room on F4;
  protocol advisor card; cinematic intro (skippable in Settings).
- **Counter-nanite line:** operators; APCs with dome shield, side panels, .50 pods and a pop-out 6-tube rocket pod;
  limpet / harpoon / disruptor weapons; the anti-walker pincer that topples heavy walkers and blows them up; stealth and
  regular VTOL dropships with rear-ramp loading; the facility (gate > decon > staging > garages > pad / helipad).
- **Signalborne ports:** player-flown drone with exact replay, wounds and casualty care, senses (units act on what they
  see and hear), threat units (burrowers, mimics, leeches, cocoons, webs), turret line, squads redrawn at true scale.
- **Bases:** compact, function-grouped rings, gate / ring / service roads, floodlights and street lights, cameras with
  real sight, auto turrets at gates and corners.
- **Status (2026-10-27, cut short by the owner's 20-minute limit):** suite 999 pass / 1 fail (a timing probe under load) /
  0 script errors; hash goldens not yet re-baselined; sim 2k is 1.65x G6.1 on a busy PC (gate 1.2x, NOT MET); Last
  Protocol reaches THE TIDE in a forced run without crashing but did not finish within 18 min; packaged build smoke 4 flows,
  2 checks miss (one dropship pair loading, drone strike drop). Full evidence and what's left: PROGRESS.md "G7 Done-when
  evidence".

## Status (honest)
- **Done and verified:** G0+G1 core loop, G2 Smart Warfare, G3a Factions + Skirmish, G3b maps and stages, G4 editor / walls / transports / new units (see PROGRESS.md for the G4 items that are NOT met: 10k all-fighting speed, 2 Valley AI soaks drawing, G4 windowed fps unmeasured). Evidence is in `PROGRESS.md`.
- **Measured performance (this PC, quiet):**
  - **Sim:** 2,000 fighting units average 29.5 ms per tick (p95 38.3), within the 20 Hz budget. That's about 4–5x faster than G3a.
  - **10,000 units on Valley Conquest:** 86.7 ms per tick (p95 124), over budget, so the game runs at about half speed.
  - **On screen:** rendering alone holds 71 fps at 2,000 units and 171 fps at 10,000 zoomed out. While the sim runs on the main thread, frame rate drops to about 22 fps with 2,000 fighting. See `perf/PERF_REPORT_G3b_2026-10-24.md`.
- **Not in this slice:**
  - naval units and aircraft beyond drones (G4c/G4d; the water terrain and move classes are in);
  - Stages 1–6 and 11–13 (Stage 10 arrived in G6; audio arrived in G6.1).
  These are gates G4–G6 in the roadmap.
- **Visual direction** for later gates: `docs/vision/` (owner mockups; reference only, not scope).
- All costs and stats are **provisional balance fixtures** (`game/content/*.json`), not approved numbers.
- Design sources: `RTS_Age_of_Modern_War_Claude_Handoff/` (immutable). Engineering contracts: `game/docs/CONTRACTS.md`, `CONTRACTS_G2.md`, `CONTRACTS_G3a.md`, `CONTRACTS_G3b.md`.
