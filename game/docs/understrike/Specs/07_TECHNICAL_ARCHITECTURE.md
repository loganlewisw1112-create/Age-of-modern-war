# 07 — Technical architecture: authoritative world, commands, persistence and scale

## Integration-first constraints
**Inspect existing RTS code before implementation.** Reuse the current world simulation, fixed-step clock, unit IDs, military orders, building definitions, factions, resource wallets/inventories, technology state, pathfinding, seed/match configuration, save slots and HUD. Do not fork the entire engine for underground gameplay. Select exact language/framework/data formats based on the actual repository—this document is deliberately engine-neutral.

## Recommended bounded contexts
| Subsystem | Owns authoritative data | Emits/consumes |
| --- | --- | --- |
| WorldSpace | surface + subsurface coordinates, chunk topology and collision | geometry revisions, access changes |
| Geology | material/voids/deposits, groundwater/faults/stability | survey results, excavation jobs, hazard events |
| Structure | rooms, floor integrity, support relationships, debris | damage, collapse, repair and reconstruction |
| Construction | blueprint plans, prerequisites, assigned projects | excavation, module assembly, cost reservations |
| UtilityNetwork | power/air/water/drainage graphs and availability | outages, emergency isolation, consumption |
| Logistics | physical inventory, routing, elevators, rail, cargo queues | transfer jobs, congestion, arrival |
| Population | population cohorts, locally instantiated agents, welfare/staffing | capacity and worker skill availability |
| Military | units, component damage, formations, orders, sector capture | battle events, morale, command state |
| Recon | subterranean fog-of-war, confidence, sensing, contacts | discovered intel and stale info |
| Automation | scoped policies, plans, approvals, supervisor decisions | legal jobs/commands (never direct state mutation) |
| Presentation | camera, cutaway, animation, audio, particles, HUD | reads state and gameplay events ONLY |
| Persistence | snapshots, content versions, ordered events | load/migration/checksum |

**Single source of truth**: world simulation owns game truth, not the camera/UI. Changing views cannot create or delete simulation entities. Player and AI both submit the same validated commands. UI issues intents and renders results; it does not modify underground world geometry or ownership directly.

## Proposed core entity records
- `Bunker`: ID, owner faction, anchor, maxFloors=15, grid/chunk refs, access routes, automation policy and region links.
- `Floor`: bunker ID, `floorIndex` 1..15, depth envelope, excavated geometry refs, support refs, modules, per-sector control/operational flags.
- `Sector`: 3D boundary, owner, access links, structural state, military state, environment, discovered/visible by faction.
- `Facility`: module blueprint/version, slots, recipe, inventory connection, utility demand, occupation, health, task queues, upgrade state.
- `ExcavationJob`: source route, target geometry, borer class compatibility, terrain conditions, progress and consumed/removable material.
- `TransportLink`: source/destination, class (road/rail/lift), clearance, mass/throughput, schedule/queue, damage, power and current blockade.
- `Vehicle`: unit base ID, MB class, variant blueprint/version, physical envelope, cutter performance, component state, cargo capacity.
- `Policy`: scope, actor, allowed intents, priorities, spend authority, civil risk and escalation behavior.
- `IntelContact`: faction, source, evidence, estimate volume, confidence, freshness and expiry/uncertainty rule.
- `CollapseEvent`: cause, originating support/zone, affected chunks/structures, state, duration and aftermath references.

Define versioned IDs and referential integrity; faction capture alters ownership/policies without creating a duplicate facility/entity.

## Typical authoritative simulation frame
1. Apply player/AI commands and validate faction unlocks, authority, resources, movement legality and approvals.
2. Update active geology/excavation/work tasks and reserve consumed resources.
3. Rebuild dirty utility, access and route segments when topology changes.
4. Execute logistics, manufacturing, personnel aggregate services and maintenance.
5. Resolve active military, reconnaissance and sector-control events.
6. Resolve structural stress/damage and bounded cascades on affected zones.
7. Publish deterministic state changes and presentation events for HUD, audio, VFX.
8. Persist as needed using async snapshot creation of a consistent step boundary (rendering must not stall the simulation).

Actual order can be adjusted to engine constraints provided invariants are preserved, concurrency is deterministic, and no teleportation/duplicate item flow occurs.

## LOD: visual vs simulation
- **Near/active floor**: per-unit local navigation, visible project stages, detailed tactical behavior; fine collision and particles.
- **Nearby bunker, out of view**: normal strategic unit production and region movement, lower update rates for ambient systems, explicit hazards.
- **Distant bunker**: aggregated personnel/industry and abstracted route flow while still honoring stock, capacity, damage, ownership, supply and mission outcomes.
- **Far continental region** (full game): scenario-validated strategic approximation with deferred detailed reconstruction on camera approach.

Never silently skip critical events: enemy capture, material consumption, casualty loss, topology change or tech research. Detail can be reduced; outcomes remain governed by the same rule set. Switching LOD must conserve population, cargo mass, equipment counts and military strength.

## Persistence, seeds and reproducibility
Snapshot all installed modules, all floors, chunk modifications, current material deposit quantities, tunnel traversability, damage/ruins, captured sectors, outstanding construction jobs, cargo-in-transit, lift state, policies, unit/component health, intelligence per faction and ongoing structural-event state. On load: migrate schema, rebuild derived nav/utility caches, validate ownership and eliminate double-application of pending transactions. Repro seed includes map seed + defined feature content versions; use stable ordering for nondeterministic job choices. Log command intent + event ID + authoritative frame for test replay. Determinism targets must be explicitly measured, including mid-collapse and mid-lift saves.

## UI/presentation synchronization
Cutaway meshes and underground cameras are pure projections; no per-floor copies. Shared world selection IDs persist through camera switches. Complex VFX are GPU/animation consumers of authoritative events; optimize particle counts per quality tier. If the VFX lags or is disabled, gameplay geometry and damage still change correctly. Ground panels and lift collisions must remain synchronized with deployment state.

## Profiling and performance budgets
Do not promise numeric scale before testing on specified hardware. Instrument `sim-step p50/p95/p99`, active units by LOD, chunk dirty work, route recalculation time, structural events/sec, transport graph update time, AI decision budget, memory, scene draw cost, GPU particles and snapshot serialization spikes. Publish repeatable stress scenes: dozens of lifts in motion, a multi-floor collapse while two fights occur, many distant industrial cities, multi-bunker convoy routes and high-rate tunneling. Tune budgets based on measured data. Frame-rate quality settings may reduce VFX; simulation speed controls should not change outcomes given equivalent command/time input.

## Security and exploit-resistance within game rules
Restrict bunker-build commands to Modern Human. Validate captured-building usage by tech compatibility; do not allow unauthorized unique production from a stolen facility. Reject path commands that exploit unloaded chunks, shaft collisions or floor hiding. Queue cancellation/refund semantics must prevent duplicate resources. Ensure no secret-intel leakage through minimap, AI logs or UI cameras before discovery.
