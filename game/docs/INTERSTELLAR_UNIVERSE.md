# Interstellar universe and civilization bible — DLC 3
Owner-approved framework, 2026-11-27. Names below are working names except existing canon references (which themselves may be placeholders in Campaign Vision). No final star catalog, coordinates, planet inventories, unit roster or language packages yet. [Master DLC GDD](BEYOND_CIVILIZATION_GDD.md) · [Existing arrival canon](CAMPAIGN_VISION.md).

## Fixed geography, dynamic history
50-system planning baseline (40–60 approved design range), seven regions; includes home system. Base game starts on homeworld in Core; DLC 2 opens home system; DLC 3 opens 49 remaining systems. Geography, major origins and authored locations consistent between players; campaign outcome sets starting circumstances. Procedural environmental detail only inside authored finite bounds. No infinite map generation. Borders, danger, trade routes and faction power evolve. Exploration not artificially level-gated; propulsion, supplies, information, hazards and infrastructure constrain reach.

| Region | Systems | Identity |
|---|---:|---|
| Core Region | 5 | Home + four nearby systems, familiar origins, expansion gateway; not guaranteed safe |
| Sovereign Reach | 10 | Major powers, populations, organized armies, industrial and diplomatic centers |
| Veiled Territories | 9 | Isolated alien societies, exotic environments, limited contact |
| Broken Frontier | 7 | Contested colonies, pirates, mercenaries, independent settlements and wars |
| Meridian Expanse | 8 | Resources, mining, trade, industrial and colonial competition |
| Silent Verge | 5 | Ancient ruins, dormant infrastructure, lost technologies |
| Uncharted Reach | 6 | Remote hazardous routes, unknown life and discoveries |

Alternative system-role allocation (provisional, cross-cutting, not additive): 6 home, 8 colonial, 8 contested, 10 resource, 10 unexplored, 5 ancient, 3 dangerous. Authored region names other than Core provisional. Outer Rim-like frontier feel, original IP; sparse and densely developed systems in deliberate contrast. No filler worlds. Strategic corridors, gateways and open routes where technology permits. Fixed positions; dynamic travel/ownership. Authored celestial objects include stellar type, orbits, moons, belts, atmosphere, gravity, terrain, hazards, resources, life, settlements, orbital installations, subterranean sites, ancient history, hidden discoveries and routes. Suitable surfaces land/build/explore nearly anywhere using deterministic terrain chunks and authored POIs; unsafe landing is constrained by environment/technology, not arbitrary unlock grind. Persistent destruction, construction and discoveries.

## Roster
Five initial major powers, four minor/emerging concepts, one ancient layer. Minor powers can rise and majors fall. Each actual playable faction has full coherent unit/building/tech roster; ownership unlocks new DLC factions only in Skirmish; Campaign/Living World AI-controlled. No precursor playable status implied. Eight new concepts plus Vhessar/Unbound; no assumption each political entity is a distinct biological species.

| Civilization | Initial role | Identity and proposed gameplay |
|---|---|---|
| Vhessar | Major, existing DLC 2 | Preserve existing conqueror/seed/caste/beachhead/Ark/boarding doctrine and 21 hulls. No kneel mechanic. Verify details against Campaign Vision and existing faction-depth decisions. |
| Unbound | Major, existing DLC 2 | Preserve existing cult, defectors, stripped hulls, Free Yards, warbands, Strip/Turn/Unseed and 19 hulls. Existing origins/relationship unchanged. |
| Kharvethi Directorate | Major, new | High-gravity mineral-rich origin, dense anatomy; heavy conventional armor, artillery, fortifications, industry, military fleets; material/energy intensive; clipped vocal military registers. |
| Othalyrian Concord | Major, new | Oceanic amphibious pressure-adapted biology; underwater cities, submersible carriers, pressure engineering, aquatic superiority; habitat dependence; acoustic harmonics and visual signals. |
| Nexarith Continuum | Major, new | Independent extraterrestrial synthetic lineage, unrelated to Earth Machine; modular bodies, distributed compute, resilient manufacturing and adaptive fleets; energy/specialty material dependency; structured symbolic signals. |
| Zha'rek Broods | Minor | Eusocial caste specialization, organic infrastructure, biological manufacturing and rapid adaptation; acoustic/vibrational/chemical communication. |
| Vaelori Flotillas | Minor | Nomadic mobile habitats, carriers and industrial fleets; mobility, fleet logistics and inherited trade dialects. |
| Theryn Collective | Minor | Mineral-reinforced nonconventional organisms, unusual sensory modalities, exotic material specialization and environmental adaptation; resonant signals. |
| Eshari Peoples | Emerging | Lower-tech intelligent society with autonomous potential for development; evolving language and institutions. |
| Aevorath | Precursor | Lost civilization, authored interconnected history, ancient languages, abandoned cities, buried and orbital installations, dormant technology/remnants, uncertain fate. |

## Content contract
For every civilization: stable IDs, authored origin/homeworld and history, biology/lifespan/reproduction/habitat, culture/government/internal factions, goals/knowledge/doctrine, economy/resource constraints, architecture/materials/silhouettes, technology prerequisites, full unit/building/ship definitions for playable factions, strengths/weaknesses/counterplay, AI, Forge language family/modality/lexicon/glyph/audio, diplomacy and evolution bounds. Use existing thirteen stable terrestrial capability stages where appropriate; no extra numbered stages; aerospace capability milestones independent. No reskins, arbitrary biological combat buffs or unbounded generated roster. Preserve existing low-detail isometric RTS visual readability. New names are manually proposed, not actual Forge output. Myrieme Forge canon review must precede permanent names. Existing Vhessar/Unbound references and secrets remain unchanged.

## Catalog production schema and validation
System {id, regionId, canonicalNameId, coordinates, stellarClass, bodies[], routes[], authoredSites[], originHistoryRef}; Body {id, systemId, orbit, radius, gravity, atmosphere, climate, biomeSeed, resourceProfile, lifeProfile, landingRules, siteRefs}; Civilization {id, speciesId, originSite, initialTerritoryRefs, canonProfileRef, techProfile, languageFamilyId, rosterRef}; Site {id, bodyOrOrbitRef, kind, fixedLocation, historyRef, discoveryRules, initialOwner}; dynamic state stored separately. Exact values and IDs to be authored, no invented claims of completion. Validate unique IDs, 50 baseline systems, seven regions, connected feasible routes (including alternative discovery routes), reference integrity, authored identity and meaningful activity, environmental suitability, finite boundaries, campaign-dependent initial state, ownership gating, persistence and reproducibility. Content production and tests pending.
