# Economy, construction, production and research

Status: consolidated handoff; no gameplay implementation or verification claimed.

Sources: [Master_GDD_v1.3](../source_text/Master_GDD_v1.3.md), [First_Playable_Spec_v1.3](../source_text/First_Playable_Spec_v1.3.md)

7. Construction and Physical Economy
Construction interaction: choose template → transparent placement/footprint/connection preview → optional rotation and grid snap → commit validated build order → workers and trucks acquire real stockpiles → phased construction, repair or cancellation. Roads/walls/fences use drag paths. Player can save layouts later; customizable modular compounds and underground rooms are full-game systems.
Credits reside in treasury, and physical materials reside in named inventories with location and owner. Production facilities process input lots, power and labor to output lots; factories and depots can become bottlenecks. Material transit supports Standard/Simulation fidelity, while Arcade may group movements into transfers without violating finite-inventory conservation. Building damage changes production, connectivity and local pathfinding. Repaired bridges/roads reroute units and supplies. Workers may be assigned priorities and automatically restock production queues.

6. Buildings, Recipes, Resources and Technology
Headquarters / command | Human use: HQ | Machine counterpart: Core controller | First slice behavior: Production authority, basic territory and opponent elimination condition
Collector / salvage yard | Human use: Extraction crew yard | Machine counterpart: Reprocessor | First slice behavior: Acquires/recovers physical raw materials
Storage / depot | Human use: Logistics depot | Machine counterpart: Buffer depot | First slice behavior: Resource lots, delivery staging, supply radius
Power | Human use: Generator substation | Machine counterpart: Reactor/charging node | First slice behavior: Enables production and selected unit servicing
Refiner | Human use: Smelter/refinery | Machine counterpart: Material processor | First slice behavior: Raw material → processed input
Barracks / assembler | Human use: Troop training | Machine counterpart: Combat unit assembly | First slice behavior: Production queues, rally
Motor pool / crawler works | Human use: Ground vehicle plant | Machine counterpart: Tracked/walker assembly | First slice behavior: Vehicle queues, resource reservation
Research / comms | Human use: Research station | Machine counterpart: Pattern/compute node | First slice behavior: Research progress, capability unlock
Defense | Human use: Turret, wall, checkpoint | Machine counterpart: Sentry turret, barrier | First slice behavior: Terrain/LOS protection and destructible structure
Repair | Human use: Workshop / repair station | Machine counterpart: Repair/reconstitution bay | First slice behavior: Requires resources, recovers damaged equipment
Initial common resource fixture: credits, salvage, ore, alloys, components, fuel, ammunition, provisions and energy generation. Not every faction consumes each item identically. The ledger treats provisions for biological workers and charge/parts for machines as structurally distinct dependencies. Electricity is a produced/consumed flow, not unlimited instant stock. Recipes belong in versioned data; costs and rates are balance fixtures, not user-approved numbers.
Stage progression in first slice: Stage 7 permits mechanized baselines; Stage 8 adds modern integrated systems/training/reliable power and manufacturing; Stage 9 adds network/sensor/EW/drone improvements. The stage UI explains known designs vs available tooling vs actually produced vehicles. Manual advancement is gated by a demonstration of operating industrial capabilities and research prerequisites, and may require credits/materials depending on player-selected advancement rules.

## Proposed state machines and failure coverage

Build order: preview → validated/reserved → acquiring materials → constructing → complete; blocked/cancelled/destroyed are explicit states. Preview is reversible planning; committed demolition is a world action. Show missing material, no power, no worker or no route separately.

Production order: queued → inputs reserved → processing → output placed; stall when required power/input/tooling/workforce is absent. Define delivery ownership, reservation lifetime, cancellation refunds and output-space failure before coding. Every transfer has a source, destination, quantity and explicit consumption/production cause. Conservation must hold under loss, capture, cancellation, save/load and repeat commands.

Power is a connected capacity/consumption flow. Fuel and ammunition are physical stocks. Human provisions and machine charge/parts are distinct dependencies. Shared economy profiles change abstraction and service rules; they do not spawn unlimited stock or bypass the shared ledger.

Research changes knowledge; tooling enables manufacture; production creates actual gear. Stage advancement checks active capabilities and explicit grants. Destroyed infrastructure may remove capacity without erasing learned science. Exact rates, thresholds, costs, refund policies, markets and tax formulas remain provisional.


## 2026-11-27 — Current expansion design authority

DLC 1 is Space Expansion (G18); DLC 2 is Beyond Civilization (future unnumbered). UNDERSTRIKE is base game. True Dynasty is the primary earned continuous campaign → Living World → DLC 1 → DLC 2 path; preset/custom independent starts are separate new saves. Existing game code, gate statuses, campaign canon and rosters are unchanged. All additions are planned, not implemented.

Physical finite deposits, mining fleets, freight, refining, exotic resource research and modular construction; 15 materials and 13 branches; automate routine production.

[SPACE EXPANSION GDD](../../game/docs/SPACE_EXPANSION_GDD.md) · [STELLAR SYSTEM BIBLE](../../game/docs/STELLAR_SYSTEM_BIBLE.md) · [EXOTIC RESOURCE BIBLE](../../game/docs/EXOTIC_RESOURCE_BIBLE.md) · [SPACE TECHNOLOGY ARCHITECTURE](../../game/docs/SPACE_TECHNOLOGY_ARCHITECTURE.md) · [DYNAMIC SPACE ENVIRONMENT](../../game/docs/DYNAMIC_SPACE_ENVIRONMENT.md) · [HIDDEN CHRONICLE](../../game/docs/HIDDEN_CHRONICLE.md) · [AUTONOMOUS SPACE COMMAND](../../game/docs/AUTONOMOUS_SPACE_COMMAND.md) · [SPACE EXPANSION DELIVERY PLAN](../../game/docs/SPACE_EXPANSION_DELIVERY_PLAN.md)
