# PROGRESS: RTS: Age of Modern War

## Active goal (G4a + G4e + G4b in parallel, started 2026-10-24; plan `docs/PLAN_G4.md`, contract `docs/CONTRACTS_G4.md`)
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
