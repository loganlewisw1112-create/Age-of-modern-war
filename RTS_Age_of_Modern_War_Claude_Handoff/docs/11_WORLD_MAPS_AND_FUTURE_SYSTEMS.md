# World, maps, persistence and full-game systems

Status: consolidated handoff; no gameplay implementation or verification claimed.

Sources: [Master_GDD_v1.3](../source_text/Master_GDD_v1.3.md), [First_Playable_Spec_v1.3](../source_text/First_Playable_Spec_v1.3.md), [GDD_v1.0](../source_text/GDD_v1.0.md)

11. World and Atmosphere
The setting is an original fictional post-nuclear planet with temperate landscapes, highlands, arid regions, wetlands, coastlines, metropolitan ruins, industrial corridors and cavernous underground networks. The deeper post-collapse scientific mystery is optional, not a mandatory quest gate. Civilizations keep operating when ignored. The full world supports day/night, seasons, families, succession and political upheaval. The first playable focuses on one industrial river-valley military region and its three RTS maps, followed by a larger combined-biome showcase.
Approved artistic baseline: grounded gritty high-detail pixel art with layered 2.5D depth, dramatic overcast light, weather and readable military silhouettes. Six approved mockup PNGs are retained byte-for-byte as design references; they are concept frames, not promised screenshots or strict UI layout blueprints.

3. Initial Skirmish Maps - Handcrafted + Validated Seed Variants
river_crossing_s - River Crossing | Scale and geography: Small valley: one major river, primary bridge, two secondary crossings, forests and ridges | Intended tactical lesson: Fast expansion, contesting a crossing | Distinct POIs / constraints: Fuel depot, crossing chokepoint; 2-4 initial spawn sites proposed
industrial_heartland_m - Industrial Heartland | Scale and geography: Medium river basin: factories, train yards, scattered towns, road loops | Intended tactical lesson: Build economy, defend industry, alternate attack routes | Distinct POIs / constraints: Refinery, rail siding, ruined plant, 3-6 spawn sites proposed
valley_conquest_l - Valley Conquest | Scale and geography: Large valley: multiple industrial pockets, foothills, river branches, complex roads | Intended tactical lesson: Larger formations, divided fronts and logistical vulnerability | Distinct POIs / constraints: Dam, tunnel portal as scenery, airfield, 4-8 spawn sites proposed
Number of map slots, map dimensions and kilometer scales must be performance-tested; above spawn counts are design fixtures, not fixed constraints. Procedural generation only changes legal seeded zones, never foundational crossings or core macro-geography without a verified alternate connectivity graph.

## Slice map authoring requirements

Keep authored macro geography distinct across all three maps. Define legal spawns, resource masks, movement classes, crossing capacities, strategic POIs and destructible graph links. Seeded foliage/ruins/resource placements must respect exclusion masks, traversal and opening viability. Store macro map revision and seed separately. Do not confuse a reskin or seed variant with a genuinely distinct map.

Destroyed bridges affect road routing, supply and AI decisions. Repairs restore connectivity via validated world change. Wrecks, building damage, capture and ownership persist. A tunnel portal may be scenery in the slice without implementing underground gameplay.

## Retained future scope

Living World adds vulnerable survivor movement/interaction, needs, scavenging, crafting, relationships, legacy and succession. Settlement simulation adds housing, water, sanitation, education, health, demographics and delegated jobs. Institutions introduce laws, legitimacy, treaties, elections/coups and emergent state change. Wider systems include rail, power/water/comms, banking/debt/trade, environment/seasons, excavation, underground networks, naval/air operations, editors and multi-scale strategic control.

These retain their v1.0 detail in the consolidated master and full source text. They are G5/G6 expansion work, not prerequisites for G0. New continents, complete history, map kilometers, canon factions and mystery plot are not invented here.


## Approved DLC addendum — 2026-11-27
[Universe bible](../../../game/docs/INTERSTELLAR_UNIVERSE.md): finite authored 50-system baseline, seven regions; one home system in DLC 2 and remaining 49 in DLC 3, deterministic planetary detail and dynamic political history. UNDERSTRIKE remains base-game addition.
