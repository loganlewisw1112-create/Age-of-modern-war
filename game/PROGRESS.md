# PROGRESS: RTS: Age of Modern War

## Active goal (G6.1 "Field Command", owner-scoped 2026-10-26 via 5 questions; one big drop; branch `g6`)
GOAL — G6.1: massive new depth in AI and command, plus owner-reported fixes
For whom / what changes:  the owner, playing: every level of command thinks (general > commander > captain > lieutenant > squad > soldier);
                          AI commanders run whole wars on their own; squads fight as one unit; plans drawn on the map; realism (suppression,
                          fatigue, comms, veterancy, traits, intel/belief); company training works; unlimited market; longer fuel; ammo bearer
Outcome:                  the owner's G6.1 scope in one packaged build, tested and documented
Owner answers (2026-10-26): Q1 full chain of command; Q2 full general (budget, reinforcements, fire support, logistics); Q3 suppression +
                          fatigue, radio/comms, veterancy + traits, "EVEN MORE DEPTH" (intel/belief included); Q4 both control layers (classic micro +
                          command layer with plans on the map); Q5 one big drop. Earlier notes: company purchase spawns nothing (bug); no market cap;
                          fuel runs out too fast; ammo bearer restocks 3 units; smarter units, formations, team management.
Done-when (frozen 2026-10-26):
  1. Workstream tests pass (test_chain61, test_gen61, test_officers61, test_squad61, test_real61, test_plans61, test_bearer61, plus ORCH's
     company-training / market / fuel tests) and the full suite has 0 FAIL outside the G6-parked items, 0 SCRIPT ERROR.
  2. The 7 new flows (chain61 gen61 officer61 squad61 real61 plan61 bearer61), 3 ORCH flows (company61 market61 fuel61) and the 26 G6 flows
     pass from the packaged build in a clean folder, 0 SCRIPT ERROR.
  3. A 10-minute headless run with an auto general and no player input logs >=5 distinct operation types plus chain-of-command orders and reports.
  4. 2k-unit sim ms/tick <= 1.2x the G6 figure measured in the same session and load.
  5. New build in Downloads; README and PLAY_ME describe G6.1 accurately (limits included).
Out of scope:             the G6-parked items (10k speed, soak winners) beyond not regressing them; the 200 supply ceiling; balance beyond the features.
Stop-if / park-if:        determinism breaks and can't be fixed fast -> park that feature with a note; a helper's feature can't reach its tests
                          -> park it in PROGRESS with what's done and the next step, ship the rest.
Agents: CHAIN61, GEN61, OFF61, SQUAD61, REAL61, PLAN61 (6 live), BEARER61 queued; briefs `.plan/agents/prompts/G61-*.md`, board `.plan/board_g61.jsonl`.

## Previous goal (G6 "Command & Terrain", owner-approved 2026-10-25: all defaults D21-D44; plan `docs/PLAN_G6.md`, contract `docs/CONTRACTS_G6.md`; branch `g6`) — DELIVERED, PARTIAL (see G6 evidence)
One continuous wave, up to 8 agents live (D21, owner override), 23 agents each with an operating guide (`.plan/agents/prompts/G6-*.md`; MECH6c and ART-G6b split out of MECH6a / ART-G6 for budget). Message board + semantic layer run all wave. Scope: the G6 owner notes and answers below (items 1-17).

```
GOAL - G6 "Command & Terrain"
For whom / what changes:  Owner fights on real high ground with companies and armies under a chain of command,
                          AI that fights like a military (and AI Commanders that assist), 89 new assets with
                          their systems (mines, garrisons, rail, subs, carriers, SAM/radar, counter-drone, ...),
                          exo-suits and loadouts, Stage 10, a marketplace, a new airfield, survival mode and
                          editor Live mode; G5 gaps fixed.
Outcome:                  One continuous orchestrated wave delivers a packaged G6 build that passes every check below.
Done-when:                PLAN_G6 section 12 (frozen):
                          1. tests/run.sh TESTS OK on the final commit incl. every G6 suite; 0 files in tests/pending_g6/
                          2. Quiet PC: 10k all-fighting avg <= 62.5 ms/tick on an elevated map; 2k on screen 60+ fps;
                             10k zoomed out 30+ fps (numbers reported either way)
                          3. AI soaks 4 maps x 2 seeds + 1 editor + 1 survival map: winners (Valley incl.), 0 invariant
                             failures, logs show companies/army, doctrine tags, mines, garrison, sub, carrier, market,
                             Stage 10, an AI-commanded player formation
                          4. Playtests: existing 12 + 14 G6 flows pass twice, incl. 2 at a time
                          5. UI fit 0 issues at 7 resolutions; 6. owner doctrine+elevation checkpoint passed;
                          7. packaged build passes all from a clean folder, copied to Downloads; README/perf/PROGRESS true
Out of scope:             weather + day/night and veterancy (G7), 4th faction (G7/G8), Stages 1-6 and 11-13, audio,
                          multiplayer
Stop-if / park-if:        determinism can't be restored; existing tests can't be kept green; elevation breaks the
                          path/render core beyond repair (park with a written note). Tests are never cut.
```

**G6 status (2026-10-25 ~10:00 local, ORCH heartbeat 3). Not done; no Done-when item is met yet.**
- Checkpoint commit `84ec0be` on g6 (tree compiles; heartbeat-2 suite 517 pass / 28 fail, every failure in an
  in-progress or queued owner's file).
- Finished (own tests green, --only runs; budget audits OK): ELEV, CONTENT6, ARMY6, MECH6a(-2), MECH6b, MECH6c,
  AIRDEF6, NAVAL6, EXO6, ECON-AIRF6(-2) (market, airfield v2, air map-edge clamp), ART-G6 (89 assets).
- Live: PERF6-3 (elevated GOLD drift bisect; 10k elevated 146-177 ms/tick under load vs 62.5), AI7-USE-4 (soaks:
  draws on Valley/Heartland/custom; no company formed and no Stage 10 reached in soaks yet), AI7-DOC (doctrine),
  AI7-CMD (AI Commanders), MODES6 (survival), ART-G6b (16 new pieces + airfield art), ELEV-VIEW, VIEW6.
- Queued: UI6a, UI6b, ED6, PT6.
- **Owner decision 2026-10-25: Done-when item 2 (10k elevated <= 62.5 ms/tick) is PARKED.** Last measurement 155.7
  ms/tick under shared load (PERF6-4); the remaining big win needs a HotState writer migration (~90 sites, 18 files).
  ORCH takes one clean quiet-PC measurement at the end; G6 is delivered as partial on this item.
- **Owner decision 2026-10-25: Done-when item 3 (soak winners) is PARKED.** Lane d6 (0 SCRIPT ERROR, 0 invariant
  failures): 5/11 winners (custom_s1, survival_s1, assist_s1, river_s2, coastal_s1); draws valley s1/s2, heart s1/s2,
  river_s1, coastal_s2 (salvage starvation; Valley drew 27/28 soaks since G5). Subs and Stage 10 never appear in soak
  logs (covered by test_ai_g6). Lane d7 retest stopped. G6 is delivered partial on this item.
- **Owner approved the in-game elevation look 2026-10-25** (.plan/shots/ELEV-VIEW-3/valley_conquest_plateau.png).
- ORCH decisions today (board facts orch.decisions / owner.decision): indirect fire counts at most 18 tiles toward
  the tier contact radius (+ G5 bucket floor 36; keeps G5 hashes); supply cap 200 with a built Company HQ, else 120
  (owner-confirmed); height left the SPEED/SIGHT hook rules (packed split, hash-exact); agents run only targeted
  tests (concurrent full runs clashed on user://) and must keep every intermediate write compiling (5 tree breaks).

## G6 Done-when evidence (2026-10-26) — DELIVERED, PARTIAL (items 2 and 3 parked by the owner)
1. Tests: full suite run 2026-10-25 reached 332 PASS / 0 FAIL before the machine slept (run stopped); the remaining 43 files ran as
   two shards: 41 files 313 PASS / 0 FAIL, 0 SCRIPT ERROR; the 2 that hit the shard timeout reran alone:
   `test_hot_state rc=0 SE=0 RESULT pass=17 fail=0`, `test_ui_fit rc=0 SE=0 ... FIT RESULT screens=210 controls=25879 issues=0` and
   `screens=180 controls=21968 issues=0 (scales 0.75,1.5) RESULT pass=3 fail=0`. Total 665 PASS / 0 FAIL. Logs .plan/shots/ORCH6/fin_*.log,
   fin2_*.log. Note: test_perf_g6's elevation probe passed in the shard (pass=7) but failed once under heavy load
   (`hook + elevation overhead 7.78 ms/tick at 2k <= 5`, CPU 90%) — load-sensitive timing check.
2. 10k perf — PARKED (owner 2026-10-25): `10000 placed native avg 296.5 ms p95 566.3` (CPU 100% busy browser), 143-156 ms under shared
   load earlier; target 62.5 ms. NOT MET. 2k river: avg 54.9 ms (CPU 97%).
3. Soak winners — PARKED (owner 2026-10-25): 5/11 configs produce a winner; Valley Conquest and Industrial Heartland draw. NOT MET.
4. Playtests: all 26 flows (12 G5 + 14 G6) passed twice in the tree, plus the owner checkpoint and fog-off retake; from the packaged
   build in a clean folder (.plan/package_g6.sh) 26/26 `PLAYTEST RESULT` ok, 0 SCRIPT ERROR.
5. UI fit 0 issues at 7 resolutions and scales 0.75/1.5 (item 1). FPS (windowed harness, CPU 97-99%): 2k on screen p10 83.7 fps PASS
   (gate 60); 10k zoomed out p10 111.1 fps PASS (gate 30).
6. Owner checkpoints: elevation look approved and locked (2026-10-25); doctrine checkpoint shots after/cp_14 and after_fogoff/cp_16 sent.
7. Package: C:/Users/logan/Downloads/RTS_Age_of_Modern_War_G6 (exe, console exe, .pck md5 e97c5f773876147ff06f002589bd8f68 = build/,
   rts_core.dll, PLAY_ME.txt); README "G6" section and PLAY_ME list the parked items with these numbers.

## Previous goal (G5 "Full Spectrum", owner-approved 2026-10-24: rev 4, all defaults D9-D20; plan `docs/PLAN_G5.md`, contract `docs/CONTRACTS_G5.md`) — DELIVERED, PARTIAL (see G5 evidence)
One continuous wave, up to 8 agents live (owner override), 18 agents each with an operating guide. Message board + semantic layer run all wave.

```
GOAL - G5 "Full Spectrum"
For whom / what changes:  Owner plays the air war, the naval war, 17 new human ground units (incl. Drone Team),
                          auto resupply + medical evac with hospitals, a refreshed UI with its own typeface,
                          fixed G4 gaps and a tutorial.
Outcome:                  One continuous orchestrated wave delivers a packaged G5 build that passes every check below.
Done-when:                1. tests/run.sh TESTS OK incl. every new G5 suite (PLAN_G5 section 12.1) and 0 files left in
                             tests/pending_g5/
                          2. Quiet PC: 10k all-fighting avg <= 62.5 ms/tick; 2k on screen 60+ fps; 10k zoomed out
                             30+ fps (numbers reported either way)
                          3. AI soaks on 4 maps x 2 seeds + 1 editor map end with winners, 0 invariant failures; logs
                             show sorties, >= 1 amphibious landing, auto resupply, med evacuations
                          4. Playtests pass: existing 6 + air + naval + drone team + auto resupply + med evac + tutorial
                          5. UI fit test: 0 clipped/overlapping controls at all 7 resolutions; new typeface everywhere
                          6. Packaged build passes all of the above from a clean folder, is copied to Downloads;
                             README / perf report / PROGRESS match reality
Out of scope:             submarines, carriers, true elevation, Stages 1-6 and 10-13, audio, multiplayer
Stop-if / park-if:        determinism breaks and can't be restored; existing tests can't be kept green; typeface
                          specimen not approved (continue on a placeholder font). Anything that runs long is parked
                          with a written note; tests are never cut.
```

### G5 evidence (2026-10-25, owner asked to finish now) — DELIVERED, PARTIAL
1. **Tests:** last full `tests/run.sh`: `RESULT pass=425 fail=8 files=57`. All 8 failures were then fixed and their files re-run alone:
   - test_air_transport 7/7, test_art 7/7, test_art_g3b 5/5, test_art_machine 4/4;
   - test_ai_g5 5/5 (`.plan/shots/ORCH/t_ai_g5_r3.log`, bench f0 1.386 ms at 5006 units), test_ai 18/18, test_ai_air_naval 8/8.
   - `tests/pending_g5/` holds only README.md.
   - A full-suite rerun after commit 3716861 was **not done**: owner asked to finish.
2. **Perf:** 10k all-fighting is about 94-101 ms/tick on a quiet PC (CORE10K-2/3 handoffs). The target is 62.5, so **NOT MET**.
   - gather_trust is now on (hash-proven); the projection with it is about 86-88 ms.
   - Breakdown and next steps are in `.plan/handoff/CORE10K-3.json`.
   - Windowed fps (2k at 60+, 10k at 30+): **UNVERIFIED**, not measured.
3. **AI soaks:** the f1 lane (AI6-2 code) had 0 invariant failures but only 1 of 9 winners (coastal s1). **NOT MET.**
   - Earlier a2/a3 lanes had winners on 7 of 9.
   - The cause identified was the air/naval savings hold, which starved unit production. It was fixed in 3716861 (now buildings only).
   - The soaks were **not re-run** on the fixed code. Next step: `TAG=o1 bash .plan/shots/AI6-2/run_lane.sh river_s1 river_s2 heart_s1 heart_s2 coastal_s1 coastal_s2 valley_s1 valley_s2 custom_s1`.
   - Valley Conquest has drawn on every code version so far.
4. **Playtests:** all 12 flows pass from a clean folder on the 3716861 build. MET, with two flakes noted:
   - h 33/0, hb 37/0, m 37/0, g4b 68/0, air 98/0, naval 32/0, drone 30/0, support 37/0, med 30/0, editor 25/0.
   - stages: 43/3 when run two at a time ("select builders" found 0 units, plus 2 cascades), then **53/0 run alone**.
   - tutorial: 54/8 when run two at a time (the Strike Jet click was refused right after the hangar buy), then **72/0 run alone**.
   - Logs: `build/_clean_G5_test/pt_*.log`, `pt_s2.log`, `pt_tut2.log`. The parallel-run flakes are a G6 item.
5. **UI fit:**
   - UI5b final: `FIT RESULT screens=273 controls=29508 issues=0`.
   - Main menu after the Tutorial button: `FIT RESULT screens=63 controls=7164 issues=0` (commit 7de3984).
   - The RTS Mil typeface is the theme default. MET.
6. **Package:** `build/RTS_Age_of_Modern_War_G5/` was re-exported after 3716861, and the clean-folder playtests were re-run (`.plan/shots/ORCH/package_r2.log`). It is copied to `C:\Users\logan\Downloads\RTS_Age_of_Modern_War_G5\` plus a zip.
- Commits cd011a7 → 3716861. Nothing pushed.

## Previous goal (G4a + G4e + G4b in parallel, started 2026-10-24; plan `docs/PLAN_G4.md`, contract `docs/CONTRACTS_G4.md`) — DELIVERED, PARTIAL (see G4 evidence)
Owner decisions (2026-10-24): D1 editor + naval/air pulled into G4 (DEC-G4-01); D2 8 new human land units (4 per Human faction); D3 Machine gets a small air/naval roster (G4c/G4d); D4 helicopters hover, jets sortie; D5 gunships carry troops or a slung vehicle (G4c); D6 no true heightmap (cliff + hill tiles); D7 REDUCED movement stride stays OFF; D8 no submarines.

```
GOAL - G4a Engine foundations + G4e Map & scenario editor + G4b Walls/transports/new units
For whom / what changes:  Owner gets smooth big battles, builds and plays fully custom maps/scenarios,
                          and fights with walls, gates, towers, troop transports and 8 new human units.
Outcome:                  Sim off the main thread with 10k-scale budget, new terrain/movement layers and
                          map files; an AoE/Stronghold-style editor; fortifications + transports + 8 units,
                          all used by the AI.
Done-when:                1. tests/run.sh TESTS OK incl new suites: terrain/move-class nav, gate team-pass,
                             threaded==unthreaded hash, map file round trip, triggers, 10k save/load,
                             walls/gates/breach, transports (load/unload/capacity/carrier death/save),
                             each new unit mechanic, editor brushes/symmetry/undo/validate
                          2. Quiet PC: 60+ fps with 2,000 fighting on screen; 30+ fps zoomed out with 10,000
                             on Valley Conquest while the sim runs; 10k sim p95 < 50 ms OR >= 0.8x speed
                             with smooth frames (number reported either way)
                          3. Editor: a playtest builds a map by clicks (terrain, river, lake, trees, 2 players
                             with HQ + units, symmetry, validate, save) and starts it from skirmish; an
                             editor-made map AI soak ends with a winner
                          4. AI soaks on the 3 built-in maps with walls, transports and new units in use end
                             with winners, 0 invariant failures; playtest: drag a wall + gate, load/unload an APC
                          5. Packaged build passes all playtests (3 factions, stages, walls/transport, editor)
                             from a clean folder; README / perf report / PROGRESS match reality
Out of scope:             aircraft + naval units (G4c/G4d; the water terrain and move classes ARE in scope),
                          tutorial + settings (G4f), true elevation, submarines
Stop-if:                  threaded sim can't be made crash-free (fall back to split-step, report);
                          determinism breaks; existing tests can't be kept green
```

### Next slice: owner notes (2026-10-24). Both are REQUIRED scope.
1. **10 more units/squads for the human faction(s)**, on top of G4's 8. The per-faction split is to be proposed in the plan.
2. **Fix every current known gap:**
   - 10k all-fighting speed. The lever is hot entity state in packed arrays in `world.gd` (SIM10K-2's CR).
   - The two Valley Conquest 3-side AI soaks that end in a draw. Start from AI5-4's work-in-progress (bank launch-army fix plus late bank drop; drop the retarget penalty); its patch is in `build/_ai5-4_wip/`.
   - Measure G4 windowed fps on a quiet PC.
   - Keep burnt ground after save/load (needs a sim-side burnt set).
   - Wire `Fortify.on_attack_move_blocked` in `movement.gd`, so player units breach walls too.
3. **Airfield + hangars** (owner note, 2026-10-24):
   - The Airfield is a massive landing strip. Aircraft physically take off from it and land on it.
   - Every air vehicle needs its own hangar. You buy and upgrade hangars per aircraft at your airfield; with no free hangar you can't buy a new aircraft.
   - Design gaps and defaults are to be settled in the next-slice plan: helicopters, runway traffic, hangar sizes and upgrades, losses, small maps, Machine equivalent, AI, UI.
4. **New unit: Airfield Engineer Team** (owner note, 2026-10-24). One purchase gives a squad of 4 units. Role and defaults go in the next-slice plan.
   - **Assigning:** select the engineers, then click the airfield or one hangar. Once assigned, they handle all upkeep on their own (repair, fixes, runway, hangar, airstrips).
5. **Airfield upgrade: +2-3 extra airstrips** for landing and launching (owner note, 2026-10-24).
6. **VTOL Dropship** for the human faction(s) (owner note, 2026-10-24):
   - an EXPENSIVE unit with massive air superiority;
   - carries 2 vehicles plus a squad of 8.
7. **Human Drone Team** (owner note, 2026-10-24; inspired by soldier-portable quick-launch drone systems):
   - 3 soldiers that move and select as ONE squad;
   - 4 launchable attack drones per squad, in different drone styles the squad picks per scenario;
   - once all 4 drones are spent, the squad switches to a tactical team: infiltration, takedown, breaching, stack-up and armored attack.
8. **Logistics truck "Auto" restock mode** (owner note, 2026-10-24): every nearby unit that needs restocking gets it automatically, one of two ways:
   - the units drive to the truck, restock and return to the fight;
   - or, with the truck placed in an area, the truck drives to them one by one.
9. **UI facelift** (owner note, 2026-10-24): interface, controls, screen layout and functionality all get an upgrade.
   - Everything on screen must FIT at all times, never cut off at the top, bottom or sides.
   - A custom, unique military-style modern typeface designed for this game.
10. **Medical auto mode + 2 new human buildings** (owner note, 2026-10-24):
   - A med team or med vehicle placed in an active area with wounded troops picks the wounded up with its team.
   - It evacuates them back to base, to a "Hospital" or a "Field Hospital", both new buildings for the human faction(s).
11. **Helicopters land anywhere open** (outside a base or wherever needed), not only on helipads. Helipads are restock/repair points, auto-serviced by Airfield Engineers (owner note, 2026-10-24).
14. **Typeface approved** (owner, 2026-10-24): "RTS Mil" approved in totality; apply it everywhere.
13. **Landing anywhere big enough** (owner note, 2026-10-24): VTOLs, gunships and helicopters land on any open area big enough for them, or at their pads/hangars (CONTRACTS_G5 §7).
12. **Up to 8 subagents at once** for this build (owner override of the default 6). Every agent gets its own role/task/operating guide (owner note, 2026-10-24).

### G6 (slice after G5): owner notes. REQUIRED scope, recorded 2026-10-24
**Plan:** `docs/PLAN_G6.md` was **approved by the owner 2026-10-25 with all default decisions D21-D44**. It is now the active goal (top of this file).
1. **Marketplace:** the player buys salvage, ore, etc. with credits (in-game money). Exchange rates are to be designed (scarcity pricing, fair for AI). Note: G5 soaks showed small maps running out of salvage, so the marketplace also fixes that late-game economy dead end.
2. **Airfield / runway / hangar overhaul:** a completely new design and layout.
   - Newly bought hangars are placed in a sensible spot next to the tarmac.
   - Owner idea: hangars connect directly to a main airfield base, which connects to the tarmac and runway. Layout options to be worked out in the G6 plan.
   - **Shorter runways** (owner, explicitly G6, NOT G5): the current strip_len is 26 tiles (airfield/aerodrome), 14 (airstrip), 10 (forward strip) and 12 (Machine launch rail), which is far too long. Shorten them as part of the overhaul.
3. **Every asset on the "G6 Arsenal Concepts" page goes into the game in G6** (owner note, 2026-10-24): units, turrets, fortifications, drones, vehicles, aircraft, ships and buildings. That is **89 assets**: the page's 93 minus the 4 Irregulars assets (see owner note 5).
   - Page: https://claude.ai/artifact/CqtGqskcCzkoCjPrhMWkgw
   - Source: `docs/g6_art_kit/` holds the proposal list in `items.json`, plus drawers that already render every asset with `tools/art` as game-schema sheets. It is not wired into content, sim or AI yet; see its README.
   - By category: turrets 15, fortifications 9, drones 9, vehicles 15, infantry 13, aircraft 4, naval 10, buildings 11, horizon 3 (the Stage 6 Rhomboid Landcrawler and the Stage 10 Laser Tank and Exo-Suit Trooper). By faction: Human A, Human B, Machine and shared.
   - Each asset has to become playable: content defs, art moved into an `assets/art/g6_*` module, sim mechanics, AI use and tests.
   - Scope the G6 plan has to settle (big items inside this note):
     - new systems: minefields + EOD/mine clearing, garrisons, trench/sandbag cover, rail tiles + armored train, submarines + sonar, carriers (the hangar system at sea), radar-gated SAMs, counter-drone (laser, nets, jamming), tethered recon;
     - **Stage 6 and Stage 10** units: rhomboid landcrawler, laser tank, exo-suit trooper.
     - Submarines and carriers were out of scope in G5 (D20) and are in scope now.
4. **Map editor "Live" mode** (owner note, 2026-10-24): a toggle in the editor that is easy to switch on and off.
   - With Live on, units placed for different factions behave as in a live match or skirmish. When they are close enough, they start fighting on their own.
   - Reference: the Stronghold and Age of Empires III editors.
   - Toggling off returns to normal editing.
   - Details for the G6 plan:
     - whether Live pauses or rewinds when switched off;
     - whether the AI economy and production also run, or only combat;
     - the speed controls;
     - how undo behaves for units lost during Live.
5. **The 4th faction is out of G6** (owner note, 2026-10-24). The Irregulars faction and its 4 assets (Technical, Tunnel Network, Ambush Cell, Captured Tank) are removed from the G6 plan, to be raised again possibly in G7 or G8.
   - Their drawers stay in `docs/g6_art_kit/` (`x_*` ids in `g6_horizon.gd`, `g6_infantry.gd`), but G6 does not integrate them.

#### G6 scoping answers (owner, 2026-10-24, five-question pass). REQUIRED scope
6. **Delivery:** one continuous orchestrated wave (like G5), ending in one packaged build. Not split into G6a and G6b.
7. **Stage 10 becomes playable** ("Automated Technocracies"): an advancement gate from Stage 9 and its own unlocks. Its units are the Laser Tank, Exo-Suit Trooper, Mass Driver, Colossus Walker, Hover Tank, Assimilator, Swarm Queen, Mimic Drone, Stalker Synth, Stealth Strike Drone and Overmind Uplink. The Rhomboid Landcrawler moves to Human B at **Stage 7** as an early heavy. Stage 6 stays unplayable.
8. **True elevation** (owner, 2026-10-24; this reverses G5 D20, where it was out of scope): real terrain height in place of the G4 cliff and hill tiles.
   - Height affects sight, weapon range, cover and movement.
   - The map editor gets height brushes.
   - Rendering, pathing and fog must handle it.
9. **Wave / survival mode:** new victory types, "Repel all waves" and "Survive mm:ss" (vision images 03-04), a natural showcase for the new defenses.
10. **AI upgrades.** The baseline is that every AI uses every new unit and system. On top of that:
    - **AI Commanders** (owner design, still to be worked out properly):
      - assist commanders on the player's side, each with its own playstyle;
      - they make in-game decisions on their own, without asking for approval;
      - they are meant to ASSIST the player, NOT play the game for them.
      - The G6 plan must define:
        - what a commander controls (a group, a sector, a role such as air or logistics);
        - how the player assigns, reins in or dismisses one;
        - the playstyles;
        - how to keep it from fighting the player's own orders.
    - **Ally AI commands:** in team games the player can order an allied AI to "attack here", "defend me" or "send air support".
    - **Wave AI:** a dedicated attacker for survival mode that builds escalating waves.
11. ~~Veterancy / unit XP~~ **MOVED TO G7** (owner, 2026-10-25). Not in G6.
12. **Research upgrades** for the new units and defenses, extending `research.json` (e.g. better mines, CIWS range, armor kits).
13. ~~Weather and day/night~~ **MOVED TO G7** (owner, 2026-10-25). Not in G6.
14. **Infantry loadout upgrades and enhancements, plus exoskeleton armour suits** (owner: "think Iron Man armour"). Infantry can be upgraded with new loadouts and gear, up to powered exo-suits. The G6 plan must define how this relates to the Stage 10 Exo-Suit Trooper unit.
15. **Companies and armies (army builder)** (owner notes + design chat, 2026-10-25). Builds on the G2 officer groups (`ops.gd`) and the G5 squads.
    - **Company:** a pre-organized formation of **15-45 elements MAX** (element = one squad or one vehicle) of specialized units, trained as one order and commanded as one bigger squad.
    - **Templates: presets + custom.**
      - Each faction ships preset company types, for example:
        - A: Rifle, Mechanized, Armored, Artillery Battery, Air Assault, Engineer, Special Ops;
        - B: Conscript Battalion, Shock Assault, Heavy Armor, Siege Battery, Works;
        - Machine: Swarm Cluster, Walker Phalanx, Siege Array, Hunter Pack.
      - An **Army Builder** screen lets the player design, save and train their own templates within slot rules and the 45 cap.
    - **Training: a new Company HQ building** (one per faction, styled per faction) trains whole companies itself and spawns them all at once.
    - **Chain of command:**
      - each company has a **captain** and **lieutenants**, one lieutenant leading each platoon;
      - leaders are real units in the company.
    - **Armies:** join 2-4 companies into an **army**. This needs a **Commander unit in play**; the Commander becomes the army's top leader (army -> companies -> platoons).
    - **Limits for now:** up to 4 companies per army and 2 armies per player.
    - **Leader loss: the next in line steps up.**
      - Captain dies -> the senior lieutenant is field-promoted (short confusion + morale hit).
      - Commander dies -> the army splits back into its companies until a new Commander joins them.
      - Nothing dissolves outright.
    - **Still to settle in the G6 plan:**
      - cohesion bonuses while together;
      - auto-replenishment of losses;
      - cost and population rules;
      - company / army cards in the HUD (vision image 05);
      - the AI training and using companies;
      - letting an AI Commander (item 10) run a company or an army.
16. **Exo-suit garage + exo-suit soldiers** (owner note, 2026-10-25). A new, smaller building (an exo-suit garage / suit bay) that trains exo-suit soldiers.
    - Reference: the AMP suits from *Avatar*. A pilot in a walking armoured exo-suit, about 2-3x a soldier's height.
    - Heavy weapons: oversized assault rifles, shoulder or arm missile tubes, and similar.
    - Fits with item 14 (infantry exo armour upgrades) and the Stage 10 Exo-Suit Trooper.
    - The G6 plan must settle:
      - the suit roster and variants (e.g. rifle suit, missile suit, AA or breacher suit);
      - which factions get them (Human A sleek, Human B crude welded; the Machine has no pilots, so maybe none);
      - stage gating;
      - how they count against squad / company slots (item 15);
      - repair and resupply at the garage;
      - the pilot surviving (ejecting) when the suit is destroyed.
17. **AI command structure with true military strategy and focus** (owner note, 2026-10-25). Every AI command level (Commander -> army -> company captain -> platoon lieutenant, plus AI Commanders and enemy AI) has to fight like a real military:
    - positioning troops correctly: terrain, cover, high ground (item 8), overwatch, flanks, depth;
    - formations and structure;
    - attacking: combined arms, fire and manoeuvre, suppression then assault, breaching;
    - special ops missions: raids, sabotage, recon, sniping officers;
    - exfil missions: extracting squads, wounded and VIPs under fire;
    - and the rest of real doctrine: defence in depth, retreat and regroup, reserves, logistics, timing.

#### G6 design answers (owner, 2026-10-25, second question pass). These settle the open details above
- **Marketplace (1):** buy AND sell. Prices move with what every player trades (scarcity), and the AI uses the same market.
- **Airfield (2):** the airfield base has fixed hangar slots along the tarmac. Buying a hangar auto-fills the next free slot.
- **Editor Live mode (4):**
  - switching Live off **rewinds** the map to exactly how it was placed, so it is a repeatable test;
  - Live runs **combat + AI tactics** (units fight, and AI positions and moves them). There is **no economy or production**.
- **True elevation (8):** 4 height levels (valley, plain, hill, ridge) with slopes and ramps between them.
  - High ground gives sight, range and defence bonuses.
  - The editor gets raise, lower and smooth brushes.
- **Weather and day/night (13), for G7:** a skirmish setup option: Off, Fixed (pick the weather and time) or Dynamic (weather fronts plus a day-night cycle during the match).
- **Wave / survival (9):** works on any skirmish or editor map, with attackers spawning from the map edges, plus **2 new purpose-built stronghold maps** like vision images 03-04.
- **Veterancy (11), for G7:** 3 ranks (Veteran / Hardened / Elite) shown as chevrons. Each rank adds accuracy, HP and morale. Companies and armies track their own pooled XP.
- **AI Commanders (10):**
  - you hand one **a formation** (company or army) **or a role** (base defence, air ops, logistics, naval);
  - you steer it with an **objective** (take / hold / raid / escort) plus a **stance** (cautious / balanced / aggressive);
  - your direct orders on a unit always override it for a while, and you can recall it at any time.
  - **All four playstyles:** Defensive / fortifier, Aggressive / breakthrough, Special ops / raider, Combined arms / balanced.
- **Enemy AI (17):** uses the **same military doctrine**: companies, armies, chain of command and tactics. Fair, same rules.
- **Exo-suits (16):** **Human A only** (sleek AMP suits, e.g. rifle, missile and AA variants). The Machine has its walkers instead, and Human B gets none.
  - A destroyed suit **ejects its pilot** as one wounded soldier, who can be evacuated (G5 medical) and re-suited at the garage for less.
- **Infantry loadouts (14):** chosen **per squad at a barracks** (or the Company HQ) for a cost, e.g. assault, AT, marksman, breacher, armour plates. Exo armour is the top tier.
- **Company refill (15):** losses **auto-request replacements at the Company HQ** (toggle per company). Replacements travel to the company (lower veterancy only once G7 adds veterancy).
- **Still out of scope for G6:** Stages 1-6 and 11-13, audio, multiplayer, and the 4th faction (G7 or G8).
- **Moved to G7** (owner, 2026-10-25): weather + day/night (13) and veterancy / unit XP (11). Their answers above are kept as G7 design input.

### G4 evidence (2026-10-24, owner asked for the packaged build within 30 min) — PARTIAL
1. **Tests:** `bash tests/run.sh` → `RESULT pass=297 fail=0 files=35 time_ms=1970802` / `TESTS OK` (log `build/final_suite_G4.log`). MET.
   - The run covered all of 59afdcf plus AI5-4's uncommitted AI edits, which were in the tree at the time.
   - The shipped AI, 32eddf7, passed test_ai 18/0 in AI5-3's run.
2. **Perf:** `perf/PERF_REPORT_G4_2026-10-24.md`. Sim avg/p95 ms:
   - 2k fight 21.3/36.1: MET.
   - 10k march 63.2/85.9: at the avg bound, p95 over.
   - 10k fight 104.3/131.1: **NOT MET** (about half speed).
   - Every A/B state hash was equal to HEAD.
   - G4 windowed fps (2k fighting 60+, 10k zoomed 30+): **UNVERIFIED** (not re-measured on a quiet PC).
3. **Editor:**
   - editor playtest 25/0 (ED3, commit 121cd89);
   - an editor-made map soak, custom_front s1: `winner=0 end_tick=96442 reason=hq_elimination`, INVARIANTS fails=0 (`.plan/shots/AI5/soak_custom_front_s1.txt`, AI5-2 code);
   - clean-folder editor playtest: see 5.
4. **AI soaks:** 0 invariant failures in every run.
   - Winners: heartland s1 and s2, river s1, custom_front s1 (on cfe7bc5-era code), and river s2 (d2, commit 32eddf7: `winner=0 end_tick=86554`, breaches 3/7/2).
   - **valley_conquest_l s1 and s2 still DRAW** at max_ticks (d2: hashes 88bb7510…, ff48173b…). **NOT MET.**
   - The 4 winners above were not re-run on the 32eddf7 code.
   - Walls, gates, transports and the new units are used in every soak (SOAK G4B lines). The AI now breaches walls.
   - In-progress AI5-4 work (stage-bank launch-army fix plus a late bank drop plus retargeting) is **uncommitted in the tree** and was not shipped. Its handoff is `.plan/handoff/AI5-4.json`. Next step: keep the bank fix and lever (a), drop or decay lever (b), then rerun the valley soaks and all 7 configs.
5. **Package:** `build/RTS_Age_of_Modern_War_G4/` + `build/RTS_Age_of_Modern_War_G4_2026-10-24.zip` (91.6 MB), also copied to `C:\Users\logan\Downloads\`.
   - Exported from commit 59afdcf. AI5-4's work-in-progress was set aside for the export; its patch is in `build/_ai5-4_wip/`.
   - Run from a clean folder (`build/_clean_G4_test`), each printing `NATIVE rts_core loaded (rts_core 0.3.1)`:
     - human 33/0
     - human_b 37/0
     - machine 37/0
     - stages 53/0
     - walls/transports (g4b) 68/0
     - editor 25/0
   - MET. Owner decision (2026-10-24): 10k smoothness does not block delivery; it is tracked going forward.
- Commits: 84d28b3 → 59afdcf. Nothing pushed.

## Previous goal (G3b + Scale "Big Armies", started 2026-10-23, owner-approved: stage gates + Rust core) — PARTIAL, see evidence

```
GOAL: G3b + Scale "Big Armies"
For whom / what changes:  Owner picks from 3 maps, starts each side at Stage 7, 8 or 9, researches and advances
                          mid-match, and fights battles with thousands of units without lag.
Outcome:                  The rest of the approved G3 slice (3 maps, Stage 7->8->9) on a sim and renderer that hold
                          2,000 fully simulated units and 10,000+ on the large map.
Done-when:                1. tests/run.sh TESTS OK, all existing tests plus MATCH-01 (3 sides at stages 7/8/9),
                             QA-002, QA-014, gate refuse/pass, research, native-core determinism + save round trip
                          2. On each of the 3 maps, a 3-faction AI soak with mixed start stages ends with a winner;
                             the logs show an AI advancing 7->8 and 8->9
                          3. This PC: 2,000 fully simulated fighting units within the 50 ms budget (p95);
                             10,000 units on Valley Conquest within budget; windowed 60+ fps with 2,000 fighting
                             on screen, 30+ fps zoomed out with 10,000
                          4. The packaged build passes the 3 faction playtests, extended to pick a map + stages
                             and to research by clicking; the perf report + README match reality
Out of scope:             naval, aircraft beyond drones, walls/gates, Stages 1-6/10-13, audio, 5+ sides
Stop-if:                  native DLL won't load in the packaged exe; determinism breaks; existing tests can't stay green
```
Contracts: `docs/CONTRACTS_G3b.md`.

## G3b + Scale Done-when evidence (2026-10-24, overnight)
Orchestration: 6-agent waves; about 30 builder agents including successors. Every budget audit was OK.

1. **Tests: MET.** `bash tests/run.sh` on the final sim code gives `RESULT pass=200 fail=0 files=22` / `TESTS OK` (`.plan/shots/ORCH-final/full_suite.txt`). New suites:
   - test_stages 13: MATCH-01, QA-002, QA-014, each gate refused/passed, cost charged once, no spawn on advance, research pause/resume, save mid-research/transition, EW;
   - test_maps 11; test_native 12; test_perf 7; test_perf_systems 3; test_art_g3b 5;
   - test_ai 17, including stage-7 gating, research/advance, big map, per-resource bank, ammo-tight production.
2. **AI soaks on the 3 maps: MET for winners, with a caveat on advancement.** Final code, `.plan/shots/ORCH-final/soak_*.txt`; hashes reproduce AI4-5's batch exactly; 0 invariant failures.
   - river_crossing_s: s1 winner=0 @30428; s2 7->8 @41641, winner=0 @105813.
   - industrial_heartland_m: s1 8->9 @49541, winner=0 @81944; s2 draw @120000.
   - valley_conquest_l: s1 7->8 @28881, winner=1 @65897; s2 7->8 @37281, 8->9 @118541, draw.
   - **Caveat:** both 7->8 and 8->9 appear in the logs, but on the final code no single soak shows 7->8, 8->9 AND a winner. Earlier code did: river s2 in AI4-4 v1/v2; valley s1 in AI4-4 v3. Two of the six final soaks draw.
3. **Scale on this PC: PARTIAL** (`perf/PERF_REPORT_G3b_2026-10-24.md`, quiet machine).
   - **MET:** 2,000 FULL fighting units, native: avg 29.5 / p95 38.3 ms per tick, under the 50 ms budget. G3a was about 140 ms.
   - **NOT MET:** 10,000 units on valley_conquest_l: avg 86.7 / p95 124.1 ms, so the game runs at about half speed.
   - **NOT MET:** windowed 60+ fps with 2,000 fighting. Measured 22 avg, because `world.step()` runs on the main thread. Rendering alone is 71 fps at 2,000 paused.
   - **NOT MET:** windowed 30+ fps zoomed out with 10,000 on valley while the sim runs. Measured 7.5, sim-bound. Rendering alone is 171 fps.
4. **Packaged build + playtests: MET.** `build/RTS_Age_of_Modern_War_G3b/` (zip `build/RTS_Age_of_Modern_War_G3b_2026-10-24.zip`): export-pack + renamed 4.7.2 exes + `rts_core.dll` beside the exe. The pack excludes docs/ and native/ sources.
   - Run from a clean folder outside the repo: `NATIVE rts_core loaded (rts_core 0.2.2)`.
   - `PLAYTEST RESULT` human_a 37/0, human_b 37/0, machine 37/0, and stages 53/0 on Industrial Heartland: stages 7/8/9 picked by clicks, research building built, project started by click, gate panel shown.
   - After a one-line menu text fix the build was repackaged; the stages playtest was re-run, 53/0.
   - README and perf report updated to match.

**Parked, with the exact next step (sim off the main thread):** R5-thread found two blockers:
- gdext aborts when native objects are touched from a worker thread. It needs `godot` features `["api-4-7","experimental-threads"]` in `native/rts_core/Cargo.toml` plus a DLL rebuild.
- A deep copy of `w.entities` costs about 22 ms at 2k, so the render side needs a compact per-tick render snapshot (`w.cache.unit_snap` is a start), not a world copy.

Then step the world on a WorkerThreadPool task between frames, with HUD reads only while no step is in flight. A worker-thread step with native off was hash-equal to a main-thread step, so determinism is not at risk.

**Owner decisions pending:**
- **REDUCED movement stride:** it saves about 34 ms per tick at 10k, but it is not outcome-exact (16 seeds: one winner flip). It is OFF because of CONTRACTS_G3b §0.
- **Stage cost pacing:** credits come only from the 6/s HQ stipend, so the 8->9 bank (9,600 credits + 1,400 ore including research) takes about 27 game minutes.

## Previous goal (G3a, DONE 2026-10-23)

```
GOAL: G3a "Factions + Skirmish"
For whom / what changes:  Owner picks from 3 distinct factions (Human A modern, Human B industrial, Machine network),
                          sets up 2-4 side FFA or team skirmishes with per-side faction/team/credits/difficulty,
                          chooses victory (HQ kill, territory %, hold bridge, AND/OR, Endless); AI plays every faction.
Done-when:                1. tests/run.sh TESTS OK incl. faction/teams/territory/AND-OR tests (MATCH-01, VICT-01,
                             QA-005, QA-011/012) + all G1/G2 tests
                          2. 3-side FFA soak (one per faction) and a 2v2 soak each end with a winner
                          3. Rebuilt .exe passes a UI playtest that sets up a 3-faction match via the menu and
                             plays Human B and Machine openings (screenshots)
                          4. Perf report re-run
Out of scope:             new maps + Stage 7->9 (G3b); naval/air beyond Machine drones; audio
Stop-if:                  G1/G2 tests can't be kept green
```
Contracts: `docs/CONTRACTS_G3a.md`. Scaffold `48332f1`.

## G3a Done-when evidence (2026-10-23)
1. **Tests:** `bash tests/run.sh` gives `RESULT pass=144 fail=0 files=16` / `TESTS OK` on AI commit `e8a8464` (final code).
   - G3a suites: test_factions 12, test_victory 13 (VICT-01 territory 60%, sticky/recapture, QA-011 endless, AND/OR), test_art + test_art_machine, test_ai incl. 3-4 side cases, plus all G1/G2 tests.
2. **AI-vs-AI soaks** (normal, `tools/soak.gd`, all on final code incl. the supply-truck escort fix): **10/10 end with a winner, 0 INVARIANT FAIL.**
   - 3-side FFA (Human A, Human B, Machine): seed1 winner f0 @26443, seed2 winner f0 @46734, seed3 winner f1 @29311.
   - 2v2 (A+Machine vs B+A): seed1 team 1 @22373 (5 tolerated pop-cap notes), seed2 team 1 @26185.
   - Mirrors seeds 1-3: f1 @11573, f0 @18831, f0 @11980. Territory 60%: f0 @14960. Hold bridge 300 s: f0 @19780.
   - Before the escort fix, FFA seeds 2 and 3 hit max_ticks (supply trucks left attacking waves to repair, so waves ran dry); fixed in `sim/ai/ai_logistics.gd`.
   - FFA seed 2 is slow (46734 ticks, about 39 min of game time).
3. **Packaged UI playtest:** `build/RTS_Age_of_Modern_War_G3a/` (zip `build/RTS_Age_of_Modern_War_G3a_2026-10-23.zip`), copied to a clean folder outside the repo, run with `--ui-playtest-faction`.
   - The playtest sets up a 3-faction, 3-team match by clicking the skirmish menu, then plays the faction opening (build, gather, barracks, train, attack-move, officer + mission).
   - Human B `PLAYTEST RESULT pass=37 fail=0`; Machine `pass=37 fail=0`; Human A `pass=37 fail=0` on rerun.
   - **Flake:** Human A's first run (first launch of the new build) failed `match_started` within the 10 s wait, with no errors logged. The immediate rerun passed. Likely a cold-start load delay; not root-caused.
   - Shots: `.plan/shots/orch/ui_g3a/` (3-faction menu, Human B officer mission, Machine attack-move, both factions' barracks equivalents).
4. **Perf:** `perf/PERF_REPORT_G3a_2026-10-23.md` (quiet machine).
   - Sim: no regression vs G2. At 512 units, 27.6 avg / 43.2 p95 ms (G2: 29.1 / 42.4). Cap stays 512.
   - Window fps with 3 sides: 60 / 42-52 / 10-21 at ~80 / ~160 / 250-400 units.
   - **Known gap:** large fights lag. A follow-up profile showed the cause is not the side count (3 sides cost +10% sim time). The limits are the GDScript sim (~65 µs per unit-tick, so 1,000 units = ~70 ms per tick) and per-unit sprite rendering (~12 ms per frame at 1,000), both on the main thread.

Known gaps carried forward:
- Large-fight lag (above). The owner has made scale the priority for the next slice.
- First-launch playtest flake (above).
- The Machine top bar still shows Fuel, though Machine units don't use fuel (cosmetic).
- The packaged build excludes `docs/` (vision mockups are reference only, not shipped). `docs/vision/.gdignore` keeps Godot from importing them.

Next: G3b (Industrial Heartland + Valley Conquest maps, Stage 7->8->9). Needs an owner decision on stage-gate thresholds.

## Previous goal (G2, DONE 2026-10-23)

```
GOAL: G2 "Smart Warfare" slice + vehicle/building art detail pass
For whom / what changes:  Owner plays the same River Crossing match with real tactics: cover, suppression,
                          flanking armor, crippled vehicles, ammo/fuel logistics, officers running missions,
                          a destructible/repairable bridge; the AI uses all of it.
Outcome:                  Roadmap G2 deliverables working in the packaged .exe + more detailed vehicles/buildings.
Done-when:                1. tests/run.sh TESTS OK incl. G2 acceptance (MIL-02, QA-007/008, supply conservation,
                             officer multi-step mission + reports) and all G1 tests
                          2. AI-vs-AI soak seeds 1-3 end with a winner; logs show AI resupply + broken-unit retreat
                          3. Rebuilt packaged .exe passes an extended UI playtest (officer -> mission -> status shown)
                          4. Perf report re-run with the 256-unit number published honestly
Out of scope:             3 factions, 3 maps, Stage 7->9 (G3); naval/air; audio
Stop-if / park-if:        G1 tests can't be kept green, or sim drops below ~128 units at 20 Hz
```
Contracts: `docs/CONTRACTS_G2.md`. Scaffold commit `d878ba1`.

## G2 Done-when evidence (2026-10-23)
1. **Tests:** `bash tests/run.sh` gives `RESULT pass=100 fail=0 files=12` / `TESTS OK`, run by ORCH after the last sim change.
   - New: test_damage (10), test_supply (10), test_ops (10), test_g2_scenarios (7: MIL-02/QA-008, QA-007 + supply,
     officer resupply, morale + officer death, 3000-tick conservation brawl, save@1500, determinism), plus test_ai G2 (+2).
2. **AI-vs-AI soak** (normal, `tools/soak.gd`, final code): seeds 1-3 end in HQ elimination.
   - seed1 winner=1 @28749, seed2 winner=1 @23426, seed3 winner=0 @15646.
   - 8-seed sweep: 7 decisive, 4/3 side split. **Seed 4 reaches max_ticks (stalemate), a known gap.**
   - 0 INVARIANT FAIL (incl. G2 invariants).
   - Probe logs show the AI training officers and trucks, resupplying (pull/refill counts), repairing and flanking.
3. **UI playtest:** `tools/ui_playtest.gd` now drives input through `Input.parse_input_event`.
   - Covers the G1 flow plus G2: train officer, box-select squad + officer, Assign button, Secure point button + map click, mission in progress, 3 reports.
   - Result: `PLAYTEST RESULT pass=26 fail=0` from source, and twice from the packaged build
     (`build/RTS_Age_of_Modern_War_G2/`, zip `build/RTS_Age_of_Modern_War_G2_2026-10-23.zip`).
   - Shot: `.plan/shots/orch/ui/ui_07_officer_mission.png`.
4. **Perf:** `perf/PERF_REPORT_G2_2026-10-23.md` (quiet machine).
   - G2 battle sim: 1.5 / 4.6 / 12.0 / 29.1 ms avg at 64 / 128 / 256 / 512; p95 at 512 is 42 ms < 50.
   - **Sim cap ≥512, up from ~256.**
   - Window fps: 53-60 / 45-53 / 21-24 at ~105 / ~210 / ~440 units.

Integration fixes found by verification:
- groups outlived dead officers for one tick;
- the AI looped on a stale withdraw (89x);
- long games starved of salvage, so wrecks now drop scrap and map salvage was raised;
- cancelled foundations dropped scrap;
- synthetic-input harness (box-drag) rebuilt on Input.parse_input_event.

Known gaps:
- the hard-AI defensive bridge demolition is not built;
- seed 4 stalemate;
- 1000+ units are unmeasured;
- fps at ~440 units is choppy (the sim is on the main thread);
- the owner has not hand-played G2 yet.

## Previous goal (G1, DONE 2026-10-23)

```
GOAL: First playable slice (G0+G1 core loop)
For whom / what changes:  Owner gets a Godot 4 Windows build where they play a full skirmish vs an
                          autonomous AI and can win or lose.
Outcome:                  One river-valley map (River Crossing), Human A at Stage 8 vs one AI. Gather,
                          power/HQ/depot/barracks/motor pool, ~5 unit types, fog, combat, HQ-kill victory,
                          save/load, measured 64-unit baseline.
Done-when:                1. `bash tests/run.sh` prints TESTS OK (ledger conservation, command validation,
                             determinism, save round-trip, fog-fair AI)
                          2. AI-vs-AI soak with no player input ends with one HQ destroyed (SOAK RESULT line)
                          3. Game launches windowed from a clean checkout; a scripted/manual playthrough builds
                             barracks, trains a squad, kills the enemy HQ (screenshots)
                          4. Perf report with measured tick ms + fps at 64/128/256 actors on this PC; README
                             claims match reality
Out of scope:             3 factions, 3 maps, Stage 7->9 progression, officers, cover/suppression, bridges
                          (G2-G4); handoff originals untouched
Stop-if / park-if:        Godot can't install/run headless; agent-board guard tooling broken
```
Scope chosen by owner 2026-10-22: engine Godot 4, scope G0+G1, art "readable pixel-art pass".

## Log
- 2026-10-22: Godot 4.7.2 installed (winget). Foundation committed `39ed6d7`: SimWorld core (fixed 20 Hz
  tick, command bus, atomic ledger, entities, save dict, state hash), deterministic point-symmetric River
  Crossing map gen, provisional content, strict test runner (8/8 core tests). Found and fixed: SimRng's bare
  `randf()` resolved to Godot's global RNG (non-deterministic maps).
- 2026-10-22: Wave 1 dispatched (6 parallel builders, budget-guarded): A-econ, B-mil, C-art, D-view, E-hud,
  F-infra. See `.plan/agents/`. Wave 2 (AI opponent + integration) follows.
- 2026-10-23: Wave 1 complete (`c1f1011`). C-art was stopped by the budget guard after 20 silent minutes (no
  files written) and replaced by C-art-2. D-view, B-mil and G-ai handed off on budget nudges; D-view's and
  B-mil's leftovers were finished by the orchestrator, and G-ai's by G-ai-2. All 9 completions passed
  `guard.mjs --audit` (no OVER-CAP or MODEL-BREACH).
- 2026-10-23: Wave 2 (`2ac8c1d`): fair AI. Content rebalanced (provisional): credits were the only binding
  constraint. Verification pass found and fixed:
  - the AI razed a new player's HQ at 02:57, so offensives now wait for a difficulty grace period;
  - end-of-match alerts were repeated;
  - a fresh checkout could not launch without an import, so `run.bat`/`run.sh` now import first.

## Done-when evidence (2026-10-23)
1. **Tests:** `bash tests/run.sh` gives `RESULT pass=60 fail=0 files=8` / `TESTS OK`, run by the orchestrator
   after the last code change.
2. **AI-vs-AI soak** (`tools/soak.gd`, normal, after the grace-period change):
   - seed1 `winner=0 end_tick=18378 reason=hq_elimination`
   - seed2 `winner=0 end_tick=13015`
   - seed3 `winner=1 end_tick=16484`
   - 0 INVARIANT FAIL.
   - Before the change, the orchestrator re-ran seed 2 independently: hash `e09a4ce2...` matched G-ai-2's run.
3. **Real window:**
   - `tools/ui_playtest.gd` drove menu -> select engineers -> build generator + barracks by hotkey ->
     right-click gather -> click Rifle Squad -> 4 riflemen -> attack-move, all through synthetic input:
     `PLAYTEST RESULT pass=18 fail=0`. Shots: `.plan/shots/orch/ui/`.
   - Rendered AI-vs-AI seed 1 (`--player-ai`) reached the VICTORY screen at 04:17, the same end tick as the
     headless soak (`.plan/shots/orch/04_aivai_end.png`).
   - A clean `git clone` launched via `run.sh` and `run.bat` with zero script errors.
   - **Not done:** a human (the owner) playing a full match by hand. The UI playtest stops after the first
     attack-move; it does not kill the enemy HQ by hand.
4. **Perf:** `perf/PERF_REPORT_2026-10-23.md` (Ryzen 5 8640HS / Radeon 760M).
   - Sim avg 3.2 / 5.2 / 11.9 / 75.3 ms per tick at 64 / 128 / 256 / 512 units.
   - Supported cap about 256; 512 is over the 50 ms budget.
   - Window fps: 60 / 53-60 / 45-52 at ~64 / ~128 / ~250 units.

## Known gaps / next
- The AI reads the remaining amount of unexplored own-half resource piles (neutral info, disclosed by G-ai-2).
- The "under attack" alert fired at 00:30 in the playtest; the cause is unverified.
- The debug `--spawn-test` ticks the squad objective.
- Infantry sprites are small at 1x. Roads and bridges have no direction variants.
- Salvage is finite (~4.9k per side), so long Endless games dry up.
- Next gate: G2 (groups/officers, suppression/cover, component damage, supply, smarter AI).
