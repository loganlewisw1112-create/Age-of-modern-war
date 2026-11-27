# STELLAR SYSTEM BIBLE

Owner-approved direction, 2026-11-27. PLANNED / NOT IMPLEMENTED. All examples are non-executable documentation guidance. No runtime changes or gate changes authorized.

## Asterion (working name)
Fixed authored topology, 12 planets, 48 moons, five belts, comets, dwarf planets, rings, debris and hidden sites. Existing Earth/Moon references preserve campaign homeworld identity and story; fictional celestial catalog supersedes literal Solar System geography. Final canon reconciliation pending; no rewritten events.

| Planet | Moons | Environment | Resources | Role |
|---|---:|---|---|---|
| Veyra | 0 | Scorched metallic rocky | Thermacite; refractory metals | Heat-resistant industry |
| Ignaris | 1 | Volcanic/geothermal | Ignarium | Thermal metallurgy |
| Original Homeworld | 2 | Existing campaign geography | Existing terrestrial resources | Civilization/aerospace capital |
| Thalora | 2 | Ocean and marine ecosystems | Abyssium | Aquatic cities/underwater industry |
| Kharon | 3 | Arid mineral-rich | Ferranite | Major manufacturing/military cities |
| Nythera | 2 | Crystalline exotic geochemistry | Nytherium; Gravexite | Experimental science |
| Vesperon | 12 | Ringed gas giant, no solid surface | Vesperium | Atmospheric harvesting/orbital shipyards |
| Cryovex | 3 | Frozen terrestrial, subsurface oceans | Cryonex | Cryogenics/underground facilities |
| Orynth | 11 | Ice giant, no solid surface | Orynite | Outer logistics/atmospheric operations |
| Vaelith | 4 | Exotic biology, energy source requires validation | Biovex | Biotechnology/ecology |
| Erevos | 5 | Barren, buried structures | Aevorite | Archaeology/excavation |
| Noxaris | 3 | Remote frozen | Noxium | Deep exploration/propulsion |

## Individual moons
| Parent | Moon | Role |
|---|---|---|
| Ignaris | Pyrath | geothermal |
| Original Homeworld | Primary Moon | early space industry |
| Original Homeworld | Caelis | observation |
| Thalora | Neris | subsurface ocean |
| Thalora | Pelagos | aquatic research |
| Kharon | Ferron | metals |
| Kharon | Bastion | defense |
| Kharon | Draxil | manufacturing |
| Nythera | Xyren | exotic minerals |
| Nythera | Lumeris | electromagnetic research |
| Vesperon | Avar | atmospheric processing |
| Vesperon | Belos | volatiles |
| Vesperon | Ceryn | observation |
| Vesperon | Doran | mining |
| Vesperon | Elar | transit |
| Vesperon | Fyros | tidal heating |
| Vesperon | Garon | fleet logistics |
| Vesperon | Helix | orbital manufacturing |
| Vesperon | Ivara | subsurface ocean |
| Vesperon | Jorun | metals |
| Vesperon | Kyros | defense |
| Vesperon | Lethis | ancient discoveries |
| Cryovex | Iskara | ice |
| Cryovex | Glacis | underground ocean |
| Cryovex | Threx | cryogenics |
| Orynth | Maeron | mining |
| Orynth | Neral | frozen chemicals |
| Orynth | Orvex | military observation |
| Orynth | Pheris | atmospheric research |
| Orynth | Quorin | relay |
| Orynth | Rethal | industry |
| Orynth | Soryn | expedition |
| Orynth | Tavor | refueling |
| Orynth | Urel | supply |
| Orynth | Varyn | exotic prospecting |
| Orynth | Wexis | anomalies |
| Vaelith | Sylara | biology |
| Vaelith | Myrith | organic materials |
| Vaelith | Verdan | ecology |
| Vaelith | Ephyra | isolated biology |
| Erevos | Arkon | excavation |
| Erevos | Vestra | mining |
| Erevos | Othris | ancient materials |
| Erevos | Kaelor | remote science |
| Erevos | Morthis | dormant infrastructure |
| Noxaris | Noctis | mining |
| Noxaris | Umbrel | observation |
| Noxaris | Zephron | anomalies |

## Belts
Ember Belt: refractory metals/solar; Iron Expanse: heavy industry; Shattered Ring: contested salvage; Crystal Drift: exotic resources; Outer Veil: frozen resources/hidden sites. Dynamic orbital movement, collision mass balance, fragmentation, anchored bases, automated mining, finite deposits and physical freight. Aggregate minor debris.

## Physical catalog contract
Star {id,mass_kg,radius_m,luminosity_w,spectrum,age,activity}; Body {id,parent_id,type,mass_kg,radius_m,semimajor_axis_m,eccentricity,inclination,epoch,rotation_period_s,atmosphere_composition,pressure_pa,temperature_range,radiation,geology,habitability,deposits,chunk_seed,access_rules}; Moon adds tidal heat and orbit bounds; Belt adds size/orbit distribution and mass budget. SI authoritative units; readable display abstractions only. Validate Kepler periods, Hill/Roche bounds, non-crossing and long-horizon numerical integration; verify climate energy budgets (especially Vaelith), atmosphere retention and gravity. No actual numerical validation yet. Each body needs unique terrain, resources, environments, compatible infrastructure and events; solid surfaces persistent with hierarchical chunks, gas/ice giants atmosphere/orbit only. Specialized moons mostly mining/military/science with limited large settlements.
