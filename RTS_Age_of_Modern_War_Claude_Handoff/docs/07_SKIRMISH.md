# Custom skirmish and victory configuration

Status: consolidated handoff; no gameplay implementation or verification claimed.

Sources: [Master_GDD_v1.3](../source_text/Master_GDD_v1.3.md), [First_Playable_Spec_v1.3](../source_text/First_Playable_Spec_v1.3.md)

4. Custom Skirmish Setup
4.1 Geographic selection
Choose fictional continent → select map from that continent's collection → choose compatible size/seed variation → choose playable sides and match rules. Each continent must contain multiple genuinely distinct maps, not cosmetic variations of one terrain file. The first approved region is a diverse continent's Industrial River Valley. Initial handcrafted map working titles: River Crossing (small), Industrial Heartland (medium), and Valley Conquest (large). Their macro geography is authored: bridges, riverbanks, ridgelines, roads, industrial centers, vegetation and vital resources. Seeded variants alter foliage, resource quantities/position within safe masks, ruins, minor barriers and legal spawn alternatives without ruining navigation or spawn fairness.
4.2 Per-civilization controls
Every human and AI player can have separately configured faction, team/alliance, start location, Stage 1–13, starting treasury credits, stockpiled physical resources, population and workforce, existing structures/utilities, trained troops, vehicles/aircraft, starting territory, unlocked tech, actual research, industrial tooling, logistics, commander competence and doctrinal profile. AI skill and starting handicap must remain separate. The UI shows what is actually granted, estimated match load, any scenario incoherencies and the practical consequences of unequal stages.
Content availability: show all 13 stage names in the selector, but only Stages 7, 8 and 9 are match-start enabled in the first slice. Unavailable stages are clearly marked, never silently converted. Starting at Stage 9 does not conjure an unconfigured inventory of Stage 9 weapons or production assets.
4.3 Economy profile
Arcade: fast credits, simplified material pools, abstracted logistics and forgiving refill rules.
Standard: currency plus explicit physical resources, production, power/storage, basic supply transport and consumables.
Simulation: detailed materials, inventories, transport, manufacturing recipes, labor, markets, servicing and shortages.
Custom: independently tune individual supply/economy rules; all profiles use the same legal resources and command interface.
Realism and economic complexity are separate from AI difficulty. The player may select full simulation and easy AI, or Arcade economy with very intelligent AI.
4.4 Victory expression
Military elimination/HQ capture; territorial percentage or hold objectives; economy/score thresholds; stage/research race; diplomacy/unification; defense survival; timed scenarios; linked AND/OR requirements; allied/individual victory; Endless Mode. Each condition is evaluated against authoritative state. Display clear progress and failure feedback. Prevent conflicting configurations (e.g., endless and mandatory timer termination) or explain priority. A scenario author may apply custom starting asymmetric objectives in the full editor.
4.5 Presets
Quick setup provides Balanced Build-Up, Immediate Battle, Survival Frontier and Last Stand (working preset names). Advanced setup preserves every supported knob. Local versioned config import/export and reproducible seeds are design targets; the first slice must save and reuse preset configurations.

2. Player Journey Acceptance Scenarios
Scenario S1 - First 15 Minutes (illustrative flow; times not guaranteed)
Select Industrial Heartland; player Human A at Stage 8, AI Human B Stage 7, AI Machine Stage 9; 50,000 opening credits; Standard economy; military elimination or 60% territorial control.
Setup preview identifies each side's independent treasury, start positions, stage-specific viable industry and asymmetry. Start succeeds with seeded layout.
Camera pans/zooms without rotation; marquee-select workers; order salvage collectors to storage.
Place a power station and barracks (ghost indicates costs/area). Workers deliver resources; build progress appears.
Queue a squad; configure rally point; trained squad appears with correct faction equipment and spends credits/materials exactly once.
Build motor pool, produce a vehicle, assign squad + vehicle to a group, issue attack-move toward a known chokepoint.
Scouts reveal enemy units; fog is observer-dependent. Officer can be assigned secure_bridge objective and gives progress updates.
Damage disables a vehicle component or destroys a bridge; pathfinding/transport reroutes or signals blocked. Game can save/reload and reproduce seeded opening.
Scenario S2 - Age Progression
Start Stage 7 with sufficient valid material chain; research/construct prerequisite packages; Stage 8 eligible indicator appears; manually trigger transition; new modern units/buildings become manufacturable once physical tooling/prerequisites exist. Continue research toward Stage 9; network systems appear without instantly spawning gear. A Stage 9 starter can be chosen independently for enemy sides.
Scenario S3 - Variable Wins
Play a territorial objective game; change to two-condition (hold bridge 5m AND 60% controlled territory), observe both checklist states; then start Endless with no termination. Invalid contradictory condition sets are rejected with explanatory errors.
3. Initial Skirmish Maps - Handcrafted + Validated Seed Variants
river_crossing_s - River Crossing | Scale and geography: Small valley: one major river, primary bridge, two secondary crossings, forests and ridges | Intended tactical lesson: Fast expansion, contesting a crossing | Distinct POIs / constraints: Fuel depot, crossing chokepoint; 2-4 initial spawn sites proposed
industrial_heartland_m - Industrial Heartland | Scale and geography: Medium river basin: factories, train yards, scattered towns, road loops | Intended tactical lesson: Build economy, defend industry, alternate attack routes | Distinct POIs / constraints: Refinery, rail siding, ruined plant, 3-6 spawn sites proposed
valley_conquest_l - Valley Conquest | Scale and geography: Large valley: multiple industrial pockets, foothills, river branches, complex roads | Intended tactical lesson: Larger formations, divided fronts and logistical vulnerability | Distinct POIs / constraints: Dam, tunnel portal as scenery, airfield, 4-8 spawn sites proposed
Number of map slots, map dimensions and kilometer scales must be performance-tested; above spawn counts are design fixtures, not fixed constraints. Procedural generation only changes legal seeded zones, never foundational crossings or core macro-geography without a verified alternate connectivity graph.

## Proposed validation and lifecycle contract

Store a versioned match configuration separately from a world save. Validate map/faction/stage availability; unique side IDs and legal teams; supported spawn count; nonoverlapping spawn masks; connected supply access; finite nonnegative grants; compatible technology/tooling/force packages; supported victory expression and economy overrides; declared seed and load warning. Reject an unavailable stage with a visible explanation, never substitute Stage 8 silently.

Preview computes effective assets after preset and override application and shows grants per side. A stage grant does not create equipment. Commit one validated configuration snapshot before constructing the world; record content version and seed in the save. Startup failure returns to setup with actionable reasons rather than leaving a half-created match.

Proposed objective tree nodes: ALL, ANY and typed leaves (elimination, HQ capture, territory threshold, hold target, score, research, defense duration). Specify time units, allied ownership accounting, interruption resets and simultaneous victories before implementation. Endless suppresses automatic terminal wins; progress may still be displayed. Contradictory forced end rules are rejected or explicitly resolved in preview, according to an agreed policy.

Initial QA fixtures: Human A Stage 8 / Human B Stage 7 / Machine Stage 9; repeated seed; asymmetric stockpiles; missing prerequisite; blocked spawn; AI free-for-all; no-timer Endless; bridge hold AND territory threshold. Illustrative 50,000 credits, 60% control and five-minute hold are source scenarios, not balance locks.


## Approved DLC addendum — 2026-11-27
DLC ownership immediately unlocks new DLC playable factions in Skirmish only, not Campaign or Living World. Add quick presets and optional expanded scenario settings with compatible environments and validated starts. [Approved expansion design](../../game/docs/BEYOND_CIVILIZATION_GDD.md).


## 2026-11-27 — Current expansion design authority

DLC 1 is Space Expansion (G18); DLC 2 is Beyond Civilization (future unnumbered). UNDERSTRIKE is base game. True Dynasty is the primary earned continuous campaign → Living World → DLC 1 → DLC 2 path; preset/custom independent starts are separate new saves. Existing game code, gate statuses, campaign canon and rosters are unchanged. All additions are planned, not implemented.

New DLC factions playable only in Skirmish upon ownership; preset/custom independent expansion saves are separate from Dynasty, not a change to campaign faction rules.

[SPACE EXPANSION GDD](../../game/docs/SPACE_EXPANSION_GDD.md) · [STELLAR SYSTEM BIBLE](../../game/docs/STELLAR_SYSTEM_BIBLE.md) · [EXOTIC RESOURCE BIBLE](../../game/docs/EXOTIC_RESOURCE_BIBLE.md) · [SPACE TECHNOLOGY ARCHITECTURE](../../game/docs/SPACE_TECHNOLOGY_ARCHITECTURE.md) · [DYNAMIC SPACE ENVIRONMENT](../../game/docs/DYNAMIC_SPACE_ENVIRONMENT.md) · [HIDDEN CHRONICLE](../../game/docs/HIDDEN_CHRONICLE.md) · [AUTONOMOUS SPACE COMMAND](../../game/docs/AUTONOMOUS_SPACE_COMMAND.md) · [SPACE EXPANSION DELIVERY PLAN](../../game/docs/SPACE_EXPANSION_DELIVERY_PLAN.md)
