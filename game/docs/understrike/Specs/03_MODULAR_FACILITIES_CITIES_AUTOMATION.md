# 03 — Modular facilities, population, energy and intelligent economy

## Facility construction (Decision 11 B is binding)
Room/facility building is **modular**, with curated attachable modules and automated utilities. Engineering excavation is freeform; equipment placement is *not* an endless individual-object designer. A facility template describes a footprint, compatible modules, capacity, staff qualifications, utility connections, supported upgrades and degradation modes. Examples:

| Base module | Optional expansions | Output / function |
| --- | --- | --- |
| Barracks | Training, medical point, equipment storage | Trained personnel and readiness |
| Armored workshop | Assembly line, fabrication, inspection | Repair and vehicle production |
| Boring vehicle plant | Cutter shop, composite fab, test bay | MB-series variants and retrofits |
| Geological lab | Survey analysis, containment | Resource identification and site intelligence |
| Material refinery | Ore sorting, exotic-material handling | Processed components |
| Power facility | Grid connection, storage, emergency unit | Available energy and redundancy |
| Life-support center | Air, water, sanitation, thermal | Habitable capacity |
| Hydroponics | Growth trays, processing, storage | Renewable provisions |
| Security sector | Sensors, hardened door, response unit | Compartmental control |
| Residential district | Housing, clinic, recreation, classroom | Population capacity and morale |
| Heavy hangar | Service bays, vehicle staging, freight loading | Underground fleet readiness |

Modules are not locked to specific floor numbers; structural suitability and available space are constraints. Rooms can connect across multiple floors through approved multi-floor templates.

## Smart building (Decision 22 C+)
Player chooses facility goal and capacity, location and budget. Blueprint planner composes legal modules, walkways, freight access, power/ventilation needs and support infrastructure, then shows `Construct Now / Plan Only / Modify`. Cost estimates identify scarce inputs and geological uncertainty. Major demolition, high-risk excavation or strategic facility relocation requires explicit approval. Approved tasks automatically queue engineering, materials, personnel and site access.

Save plans as versioned player blueprints; copy between bunkers with feasibility re-evaluation, not blind duplication. Automation may suggest optimizations; it must not discard player designs or reorder priorities secretly.

## Administrative control
Each room/floor/bunker/network inherits default policy with local overrides. UI inputs are primarily `Priority`, `Budget`, `Autonomy`, `Emergency Rule`, `Production Target` and `Reserve Threshold`. Automated agents handle staff rosters, resource transfer, elevators, queue filling, inspections, maintenance, repairs and daily services.

Examples:
- `Floor 6 → Produce armored vehicles → 60% of available manufacturing budget → Autonomous`.
- `Bunker Bravo → Civilian safety first; 100% self-sufficiency target; keep 30-day reserve` (**30-day** illustrative and configurable, not a fixed balance value).
- `Network → Keep logistics connected; maintenance before expansion unless player overrides`.

## Underground civilians (Decision 20 D; 21 C)
Permanent residents may have names, homes, occupations, skills, households, training progress, health, morale and movement. They are *visible to inspect*, not individually assigned by the player. Administrators maintain housing, jobs, education, medical access and social services. Population loss, displacement, deprivation and expertise deficits meaningfully affect operations. Distant populations advance via cohort-level statistical models; visible nearby residents receive richer behavior. Individual identity must remain stable across LOD changes and save/load.

## Self-sufficiency (Decision 24 D)
Support closed-loop agriculture, water treatment, air handling, energy storage/generation, medication production and essential industry. A `Self-sufficiency` goal displays projected production vs demand and days of stored reserves under an isolation scenario. `100%` is an **operating target**, not magical infinite survival: it requires correct inputs, power, maintenance and sustained capacity. Offline regional trade and external resupply remain optional as long as connections exist. Evacuations or sudden population surges can temporarily exceed services.

## Energy system (Decision 23 C + selected D)
Build generator/reactor modules, geothermal sites, high-stage experimental energy, storage and emergency feeds. Main distribution is automated by network graph with capacity, availability, loss and damaged-edge status. Player may set `Life Support > Defense > Production` priority during shortages. Individual cables normally abstracted as connections; major power corridors and distribution hubs remain physically exposed infrastructure with wartime consequences. Critical facilities should demand redundancy for resilience. High-stage power technology follows 13-stage research—not an early cheap building shortcut.

## Economy and material flow (Decision 29 D)
Use original game's credits and physical inventory model. Every project consumes time, machinery work, power, materials, transport slots and, where relevant, skilled labor. Excavation yields removable spoil that can be reused, processed, stored or transported as actual material. Inventories reside at sites with capacity and ownership, not automatically globally available. AI chooses feasible transports and honors player priorities; UI only warns on meaningful bottlenecks and shows estimated causes.

Manufacturing routes: raw materials → refinement/components → specialized fabrication → assembly/test → storage/transport → unit deployment. Exotic resources require the proper lab containment/refinery qualification; discovery does not equal production tech.

## Failures and recovery
Room state: `Planned`, `Constructing`, `Active`, `Throttled`, `Offline`, `Damaged`, `Contested`, `Captured`, `Ruined`. Scarcity leads to transparent throttling, not random production failure. Automated maintenance handles routine wear; disaster response follows authorized rules. Recovery can use `Repair`, `Rebuild`, `Reconfigure`, `Abandon`, `Salvage` and `Evacuate` strategic commands. Major plans need approval.

## Anti-micromanagement acceptance
A thousand-person underground town remains operational without player assignment of a single residence, job, meal, pump, elevator, shipment or shift; a player can still inspect population-level services, set budgets and respond strategically to major crises. If the simulation generates repeated minor notifications requiring clicking, it fails this design requirement.
