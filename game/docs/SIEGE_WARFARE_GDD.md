# SIEGE WARFARE GDD

Owner-approved expanded design direction, 2026-11-27. All features planned; implementation and acceptance pending. Working names, proposed interfaces and test IDs are not source code or frozen gate contracts. Existing G10.1 regression remains open.

## Purpose
Large asymmetric fortress warfare across every appropriate faction/era, not a reskin of Last Protocol. The installation must be a functional military/industrial system with believable architecture and logistics, not a random pile of buildings. Attackers and defenders may have different objectives. Reuse construction, physical resources, command hierarchy, air/naval/land/underground and fortifications. No dedicated new director.

| ID / scenario | Battlefield | Objective options |
|---|---|---|
| SI-01 Fortress Assault | Existing layered stronghold | Capture designated sectors or HQ, cut operational capability, extraction if configured |
| SI-02 Fortress Defense | Existing or player-built compound | Hold priority facilities, recover, survive or defeat attacking command |
| SI-03 Urban Siege | Interconnected metropolitan districts | Control routes, key infrastructure and objectives, civilian consequences where relevant |
| SI-04 Mountain Stronghold | Elevation, rock, passes and concealed sites | Secure access, defend or capture protected facility; legal underground links |
| SI-05 Island Fortress | Coast, harbor, airfields and naval approaches | Amphibious/air/naval combined arms; maintain landings and supply, hold or capture island |
| SI-06 Industrial Siege | Connected production sites and transportation | Preserve/capture/disrupt manufacturing and logistical capacity; avoid unnecessary destruction where mission requires |
| SI-07 Total Siege | Multi-stronghold persistent network | Attack, defend, repair, expand and sustain operations; chosen strategic win or endless |

## Faction-aware fortress generation
| Faction | Design grammar |
|---|---|
| Human A | Real-scale layered compound, military/aviation/industrial facilities, logistics, legal concealed bunkers and borers when unlocked |
| Human B | Salvaged industry, reinforced settlements, defensive barriers and armored formations; no protected bunker construction |
| Machine | Energy-linked adaptive hive, creep, relay network, production and defense; no Human A bunkers/borers |
| Shadow Coalition | Concealed/dispersed facilities, per-viewer states, intelligence and covert defense, legal garages/pads and access |
| Vhessar (DLC) | Existing occupation/Ark/beachhead military identity where owned |
| Unbound (DLC) | Existing warband/Free Yards and irregular industrial identity where owned |

DLC factions remain playable only in Skirmish; Siege can use entitled AI opposition or share siege-shaped maps/rules through compatible Skirmish, never grant extra official playable slots. All 13 stages constrained by actual available tech and production. Generator takes map topology, role, faction, stage, budget, defense style, available transport, threat and terrain; output functional layout, validation report and reproducible seed. Road/rail/port/air clearances, power/storage, physical supply, defensive coverage, exits and alternate routes, sustainable industrial capacity, defendable sectors, repair access and objective reachability. Do not compress buildings or fake access, use hierarchical visual detail. Concealment follows observer knowledge. Attackers get viable objectives and routes, not mandatory mirrored layouts. Validate pathing for vehicle classes, safe spawn, non-trivial counterplay, meaningful siege duration, resource budget. Human A-only protected assets enforced even capture/editor/mod/generator.

Players choose ready-made fortress, procedural generation, manually edit or import community design. Smart adaptation rotates or repositions legal modules, identifies conflicts and requests approval for major alterations; does not silently destroy player-authored layout. Defense AI expands/repairs and adapts within real resources, attacker AI seeks opportunities from observed intelligence; no arbitrary free reinforcements. Loop build/recon -> probe -> assault/defend -> recover -> exploit -> adapt. Offline solo, online shared defense/assault and compatible asymmetrical PvP; role objectives clearly communicated. Use existing G18 transport, saved sessions, replay and fog. [Generator](PROCEDURAL_WORLD_AND_ENGINEERING.md) · [Scenario engine](DYNAMIC_SCENARIO_ENGINE.md).

## Acceptance
All seven scenarios across representative legal faction/stage combinations; different meaningful fortress identities, functional industry/supply/defense, viable attacker and defender objectives, naval/air/land routing, underground exclusivity, seed reproducibility, editor and import validation, persistence and repair, online asymmetric fairness, no compulsory micro. No regression of Last Protocol's specific rules.
