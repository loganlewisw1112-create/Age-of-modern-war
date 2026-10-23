# PROGRESS: RTS: Age of Modern War

## Active goal (G2, started 2026-10-23)

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
