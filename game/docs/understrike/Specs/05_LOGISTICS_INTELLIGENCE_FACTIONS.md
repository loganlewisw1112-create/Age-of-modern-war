# 05 — Transportation, surveillance, infiltration and faction exclusivity

## Fully customizable vertical transport
Each bunker may place multiple physically sized elevator shafts: concealed surface service lifts, multi-vehicle heavy lifts, ordinary personnel lifts, freight lifts, emergency lifts and specialized super-heavy platforms. A shaft and its top hatch consume permanent space; floor stops require alignment, access rooms, adequate width, power and structural support. Capacity is expressed by dimensions, load mass and occupancy; machine logic cannot overpack incompatible vehicles.

### Signature concealed surface elevator (non-negotiable)
1. Ground surface appears closed and visually integrated with terrain or approved cover infrastructure.
2. Deployment order reserves an appropriate lift; eligible vehicles move and queue to the loading bay.
3. Vehicles board **visibly**. Lift ascends through a tracked physical shaft (with travel time and operating state).
4. Terrain-style panels slide open with engineered mechanism before the lift crosses the surface plane; collision/nav obstacles update.
5. Lift docks, vehicles disembark and travel to requested rally point.
6. Platform descends or reaches safe stowed state; when clearance conditions are satisfied, ground panels slide closed and surface camouflage returns.
7. Reverse sequence retrieves vehicles underground. Breakdown, enemy occupation, power loss, route blockage and damaged hatches can halt normal operations, using safe recovery behavior.

## Horizontal and network transportation
Underground vehicle roads, multilanes/highways, specialized hauling corridors, conventional freight rail, armored military trains, personnel rail, and late-stage high-speed magnetic rail. Routing spans doors, road segments, tunnel clearance, junctions, transit hubs, freight stations, elevators, inventories and controlled territorial boundaries. Each transport has actual capacity, queue status, schedule, power/fuel cost, wear, risk and destination compatibility. Congestion and damaged tracks have meaningful consequences.

Transport jobs derive from orders, not direct micro: `Transfer 20 APCs to Bunker Delta` allocates train slots, routes compatible vehicles to a terminal, loads, travels, unloads and chooses elevators/roads to final stations. Missing capacity generates a recommended plan rather than silently moving vehicles. Enemy attacks can derail or block routes; AI re-plans if possible and warns when no feasible route exists.

## Subterranean intelligence
Independent surface/underground fog of war. Known ground, confirmed structure, suspected activity and last-known location are distinct data types. Confidence and timestamps decay based on elapsed time, changing conditions and sensor behavior. Signals include acoustic/vibration, excavation thermal signatures, electrical effects, geological scans, physical sightings and captured data (abstracted, not real-world actionable procedures). Quiet mode costs speed; high-output boring increases detectability. Mine/cavern geology changes sensor quality.

The sensor model should output: `Observed Evidence`, `Estimated Location/Envelope`, `Identification Confidence`, `Freshness`, and `Recommended Next Action`. A 64% confidence display is merely one user-facing illustration, not a hardcoded rule. Opposing AI may react only to information its own faction plausibly has.

## Covert operations and counterintelligence
Modern Humans can conceal approved tunnel exits, reduce operating signatures and deploy reconnaissance borers. Adversaries can invest in surface geology sensors, patrols, entrance discovery, decoys, false signals and temporary assault excavation. Long-term intelligence persists after scouts leave, but not as magically updated live data. Security installations can delay raids, alert officers and protect high-value facilities. Player retains manual/assisted/autonomous surveillance management.

## Explicit faction capability matrix
| Capability | Modern Human | Scavenger Human | Machine |
| --- | --- | --- | --- |
| Construct persistent 15-floor bunker | **YES** | **NO** | **NO** |
| Expand/create bunker networks | **YES** | **NO** | **NO** |
| Manufacture MB-01–MB-12 advanced military boring fleet | **YES** | **NO** | **NO** |
| Build specialized subterranean hybrid construction | **YES** via research | **NO** | **NO** |
| Use temporary assault tunnel equipment | **YES** | **YES**, limited | **YES**, limited |
| Discover underground passages/entrances | YES | YES | YES |
| Attack/infiltrate/capture bunker sectors | YES | YES | YES |
| Operate existing compatible captured facilities | YES | Limited/conditional | Limited/conditional |
| Salvage/loot/destroy infrastructure | YES | YES | YES |
| Automatically unlock bunker construction from capture | **NO** (already available via research) | **NO** | **NO** |

Other factions' temporary military tunnels are offensive/limited infrastructure, not complete self-sustaining bunkers, cross-continent civilian underground cities, or permanent 15-floor complexes. They may still control natural caves, abandoned pre-collapse structures and captured rooms as ordinary territory where gameplay allows. No faction should receive a functionally identical 'bunker' under a different cosmetic name.

## Capture rules
Ownership is tracked per connected sector and facility, not automatically per whole bunker. Captured sector may be `contested`, `occupied`, `isolated`, `operable by captor`, or `unusable pending repair`. Compatibility depends on power interface, controls, staffing, expertise, secured transport access and resources. A Machine unit cannot instantly operate human life-support or a proprietary hybrid fabrication line merely by standing in a room. Command center capture may impair coordination but does not teleport ownership of all disconnected floors.

## Military integration
Enemy commanders may coordinate surface sieges and underground raids; machine and scavenger factions can fight each other on surface or contest captured underground access where appropriate. Human command systems may delegate bunker defense, anti-infiltration monitoring, recovery and counterattacks. Tactical AI considers civilian-protection and infrastructure-preservation constraints assigned by player.
