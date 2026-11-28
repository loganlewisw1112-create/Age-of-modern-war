# 02 — Spatial world, 15 floors, excavation, geology and permanent destruction

## Spatial definition
A bunker is an installation with a surface access envelope, an anchored geographic footprint, a set of constructed floors `1..15`, linked horizontal excavation/tunnel regions, and optional remote bunker connections. Floor numbers are **named construction strata**, not a 15-layer cap on the whole world's geology; natural caverns, prospecting shafts and remote tunnels may exist at other elevations. A geographically separate installation is another bunker with its own 15-floor cap, not a way to add Floor 16 to the first.

Each floor records horizontal excavated footprint, room modules, support structures, cavities, access paths, owned sectors, power/life-support connections, hazard state, construction plans and navigability. Cross-floor structures (hangars, reactors, tall shafts) reserve space in each intersected level. Only sectors with legitimate support/access may be occupied.

**Canonical coordinates:** world X/Y plus elevation/depth Z; surface RTS and underground views share locations. The cutaway is a projection of these canonical coordinates, not a separate level. Surface subsidence and collapse alter the same authoritative geometry referenced by paths and rendering.

## Excavation orders
Player can plan `Expand Room`, `Excavate Route`, `Bore to Point`, `Connect Bunkers`, `Dig Shaft`, `Open Emergence`, and `Stabilize Sector`. Each produces a ghost plan with: path footprint; target cross section; slope/turn constraints; geology confidence; machinery fit; anticipated spoil; support requirements; cost, energy, schedule estimate; predicted hazardous layers; and surface conflict warnings. Engineering automation chooses approved equipment, routes compatible vehicles and stages the works. If geological reality differs, work pauses or proposes a reroute instead of silently destroying infrastructure.

Excavation is additive to the world geometry (new traversable space) plus material removals and geological state changes; it must be versioned and serializable. It may proceed in horizontal, vertical and diagonal paths when consistent with machine physics and structural constraints.

## Environmental strata and discoveries
Generate geology using map+seed+chunk IDs: rock class/strength, fractures and fault fields, water-bearing layers/pressure zones, thermal zones, recoverable deposits, natural voids, human ruins, ancient/non-human sites and rare/anomalous material sources. Distribution follows geographic rules; do not scatter equally random artifacts in every region. Potential discovery confidence is gated by sensor/tech level. Unknown material claims should remain explicitly uncertain until analyzed.

## Excavation equipment and structural material
Mechanical cutting, heavy drilling, robotic cutters, military assault boring, and high-tier hybrid molding share a capability system: bore profile, cutting capability versus rock, removal throughput, heat, energy, support-installation rate, operating signature, turning radius, dimensions and maintainability. A tunnel becomes operational for a unit class only when the passage is big enough and safety/path tags are valid. Extremely advanced tech accelerates progress but does not skip physical travel, cost, spoil or integrity checks.

Rock and lining have meaningful properties: integrity, local support, vertical load transfer, stiffness class, crack/damage state, environmental sealing and repair eligibility. Multiple large excavations close together reduce usable supporting mass; reinforcement and engineering policy can counteract this. Prevent physically unsupported multilevel rooms from being approved without structural remedies.

## Persistent destruction pipeline
1. **Cause:** Combat impact, deliberate demolition in gameplay, equipment accident, natural geological event, utility/fire failure, or progressive degradation.
2. **Damage propagation:** Record affected structural zones/supports; calculate only connected and loaded regions in a capped active neighborhood.
3. **Topology update:** If support/geometry changes, block/alter affected routes and corridors; update navmesh, shafts and utilities.
4. **Cascade:** Dependent floor/room elements may fail under load, causing physically justified vertical collapse and secondary damage. Cascades must have deterministic event budgets and bounded propagation per simulation step.
5. **Presentation:** High-quality procedural fractures + authored collapse clips + GPU particle dust/smoke + falling major chunks + impact sparks/lighting; VFX derived from simulation events but not authoritative for game state.
6. **Aftermath:** Debris fields, destroyed machinery, sealed passages, unsafe zones, salvageable wreckage, flooded cavities and permanent geographic change.
7. **Recovery:** Survey, isolate, excavate clearance, shore/reinforce, rebuild or abandon. Player issues `Restore Sector`, not individual rubble-lifting orders.

**Floor-collapse rule:** A collapse of Floor 6 may fall into Floor 7 if world vertical geometry and support fail; it does not arbitrarily remove all lower floors. Player sees warnings where engineering sensors could have detected instability. Unanticipated collapses still require physical cause.

## Underground water and life support
Handle groundwater intrusion and pressure as coarse connected zones, not expensive per-particle water physics. Pumping/drainage moves water between zones with capacity and power costs. Air exchange and contamination move across compartmentalized networks with door/security seals; oxygen/temperature are supply-service metrics updated at the zone level. Art-driven localized water, smoke and dust respond to these metrics.

## Data & simulation boundaries
Represent geology in sparse chunks using a canonical collision/topology layer, excavated-region mask, material IDs and deformation event patches. Simulate only dirty/active geometry chunks at high detail. Geometry must support reliable **idempotent save/load** of tunnels, bunker rooms, exposed artifacts, collapses, wrecks and surface breakout scars. World generation from same seed plus ordered event log should produce equivalent geology under identical content definitions.

## Acceptance samples
- Excavate Floor 1 → Floor 4 using shafts while leaving floors 2–3 mostly undeveloped; access, life support and reinforcement still required.
- A heavy borer cannot fit through an unmodified WRAITH-sized passage; auto-route proposes widening or alternate route.
- A room support failure can destroy a reachable lower room only when physically coupled; no damage teleportation.
- Surface crater/opening created by a vertical breakthrough persists and interrupts surface traversal until repaired or protected.
- Save during active excavation/structural cascade; load restores coherent damage, queued jobs and safe actors.


## Expanded gameplay design integration — 2026-11-27

Universal engineering templates and world generator validate physical footprint, geology, utilities, routes, support and legal stage/faction; no free resources, no decorative fake doors or clearance, no prohibited construction by other factions.

[Expanded master](../../EXPANDED_GAMEPLAY_MASTER_GDD.md) · [Integrated delivery](../../EXPANDED_GAMEPLAY_DELIVERY_PLAN.md) · [Shared scenario engine](../../DYNAMIC_SCENARIO_ENGINE.md). No implementation or gate completion claimed.
