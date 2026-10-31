# RTS: AGE OF MODERN WAR — PROJECT UNDERSTRIKE
## Feature handoff v1.0 | 2026-10-30 | 32/32 design decisions locked

**This package is a design + engineering planning handoff, not a report of implemented features.**

UNDERSTRIKE is a Modern-Human-exclusive network of up-to-15-floor underground military and civilian complexes, supported by specialized boring vehicles, persistent geology, underground territorial warfare, deep automated economies, concealed service elevators, and first-class underground RTS perspectives. The experience must be **easy to command, deep to simulate**: the player chooses objectives and policies; managers, engineers, and officers carry out details.

## Read this first
1. `Specs/00_AUTHORITY_AND_DESIGN_RULES.md` — governing constraints, scope and contradiction resolution.
2. `Specs/01_PLAYER_EXPERIENCE_AND_UI.md` — final Decision 32 and user-facing behavior.
3. `Specs/02_WORLD_BUNKER_CONSTRUCTION.md` — spatial model, levels, geology, excavation, construction, damage.
4. `Specs/03_MODULAR_FACILITIES_CITIES_AUTOMATION.md` — modular facility design, inhabitants, economy and energy.
5. `Specs/04_MILITARY_FLEET_AND_WARFARE.md` — 12 borers, specialized corps, tactics and surface emergence.
6. `Specs/05_LOGISTICS_INTELLIGENCE_FACTIONS.md` — elevators/rail, sensing, and strictly asymmetric faction rules.
7. `Specs/06_TECH_DISCOVERIES_AND_PROGRESS.md` — 13-stage integration and rare material origins.
8. `Specs/07_TECHNICAL_ARCHITECTURE.md` — code boundaries, authoritative simulation, persistence, rendering and performance.
9. `Specs/08_PHASES_TESTS_AND_DEFINITION_OF_DONE.md` — four releases and acceptance tests.
10. `Specs/09_DECISIONS_01_TO_32.md` — complete traceability register.

## Reference files
- `References/Base_Project_v1.3/` contains the prior project's four documents. The original Master GDD v1.3 (2026-10-22) continues to govern base RTS mechanics and is amended by these feature-specific decisions.
- `References/Approved_Concept/05_Underground_Civilization.png` is a previously approved *visual concept*, not gameplay implementation.
- `References/Gameplay_Screenshots/` contains supplied captures for UI/readability reference, not proof of engine completeness.

## Authority & conflict handling
1. Explicit newer user decisions in `09_DECISIONS_01_TO_32.md` override earlier suggested alternatives and earlier generic GDD descriptions **only within UNDERSTRIKE**.
2. `Decision 11 = modular room/facility construction (B) with automation`, not unrestricted mechanical placement for every object. Structural excavation is freeform (Decision 02), which is a different layer.
3. `Decision 28 = only Modern Human builds bunkers`. Other factions may discover, breach, occupy, raid, and sabotage them but may **not unlock bunker construction by capture**.
4. `Decision 21 = living population simulation (C), automated`. Avoid mandatory citizen-level management.
5. `Decision 22 = simple smart blueprints (C+)`; advanced planning is automated with human approval of major changes.
6. Every number not explicitly agreed (cost, times, radius, soldier counts, spawn rates, vehicle dimensions) is marked **provisional** until validated in balancing and runtime benchmarks.
7. Do not implement the entire full-world target before delivering an actually playable phase-1 bunker. Do not claim features exist until runtime verified.

## Minimal player promise
> Select the bunker, choose a construction or military objective, approve major decisions, and watch a persistent underground civilization operate through beautiful readable simulation. Take control whenever desired; never babysit routine workers, conveyors, elevators, energy grids, or residents.

## Implementation starting points (not a code repository)
- Inventory existing engine components first; map reusable world positions, units, formations, construction, resource stores, cameras, pathfinding, orders, AI and save/load boundaries.
- Prototype a single facility, two connected floors, one concealed vehicle elevator, and a 3-mode camera using **the same authoritative simulation** as the surface.
- Then generalize to 15 floors, automation policies, modular blueprints, and expansion. Gate progression via acceptance criteria in `08_...`.
- Treat all further technical tuning as engineering decisions unless it changes a locked player-facing behavior.
