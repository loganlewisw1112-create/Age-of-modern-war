# SPACE TECHNOLOGY ARCHITECTURE

Owner-approved direction, 2026-11-27. PLANNED / NOT IMPLEMENTED. All examples are non-executable documentation guidance. No runtime changes or gate changes authorized.

## 13 technology branches
Aerospace; orbital engineering; industrial extraction; propulsion; environmental engineering; materials science; military engineering; robotics; biotechnology; cryogenics; advanced energy; archaeology/reverse engineering; megastructure engineering. Nonlinear faction-specific research separate from 13 stages.

| Family | Planned archetypes |
|---|---|
| Exploration | Survey ships, probes, long-range science craft |
| Mining | Asteroid excavators, anchored platforms, mining drones, fragment collectors, atmospheric harvesters, ice rovers, mobile refineries |
| Construction | Assembly ships, heavy platforms, construction drones, maintenance and structural carriers |
| Transport | Freighters, colony ships, personnel transports, landers, shuttles, tankers, evacuation |
| Planetary | Heavy haulers, extreme-environment rovers, excavation, underwater industrial vehicles, utility robots |
| Military | Patrol, strike, escort, corvette, frigate, cruiser, capital, carrier, command and transports; preserve six existing rosters |
| Support | Repair, replenishment, rescue, salvage, medical, tenders |
| Experimental | Exotic propulsion, armor, robotics, energy, hidden technologies |
| Command buildings | Civilization high command, planetary HQ, orbital command, fleet HQ, colony command, industrial/mining/science/logistics/defense command, observation, emergency operations |
| Facilities | Spaceports, pads, tracking, docks, habitats, factories, labs, refineries, storage, shielding, geothermal, underground facilities |
| Massive builds | Modular orbital cities, megastations, massive shipyards, fortresses, stellar collectors, feasible elevators, freight hubs, defense networks, environmental projects and experimental installations |
Each archetype requires role, credible dimensions, clearance, cost, production time, crew/automation, power, materials, environmental access, maintenance and counterplay. No decorative filler or mandatory command spam. Individual model specs pending.

## Proposed schemas
TechDef {id, prerequisites, faction_scope, discovery_requirements, research_cost, unlock_ids}; VehicleDef {id,dimensions_m,mass_kg,environment_mask,propulsion,cargo,capabilities,cost,production_facility}; BuildDef {id,footprint,clearance,modules,energy,crew,material_cost,construction_capability}; Project {id,site,phase,reserved_material,completed_work,assigned_fleet}. Reuse existing registries after audit. Validate acyclic prerequisites, reachable production, ownership, environmental suitability, actual transportation and resources. Player places projects and selects priority; automated construction executes.
