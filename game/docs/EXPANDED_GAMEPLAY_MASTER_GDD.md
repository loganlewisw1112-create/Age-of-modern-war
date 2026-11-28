# EXPANDED GAMEPLAY MASTER GDD

Owner-approved expanded design direction, 2026-11-27. All features planned; implementation and acceptance pending. Working names, proposed interfaces and test IDs are not source code or frozen gate contracts. Existing G10.1 regression remains open.

## Product contract and scope
This is the current additive design authority for the owner-approved expansion of gameplay, creative freedom, platform, player experience and production readiness. It extends the existing [G18 master](G18_MASTER_GDD.md), [roadmap](ROADMAP.md), [living simulation](NEXTGEN_SIMULATION_GDD.md) and existing 20 new-mode decisions. No new numbered gates or DLCs. G11–G17 progressively build reusable foundations; G18 finalizes all base-game experiences and launch-critical creator/platform/release capabilities. G19 Space Expansion and G20 Beyond Civilization follow full G18 acceptance. Mandatory G17 full XENOGENESIS (20 subsystems) and Myrieme Forge (15 engines, eight adapters, offline runtime) acceptance unchanged. Earlier frozen scopes remain unchanged until owner-approved gate contracts. No premature DLC production.
 
Maximum fun, replayability, intelligent autonomy and creative freedom; classic RTS selection, right-click, build/train/research, groups, operations, direct intervention. Quick presets, optional advanced controls, no mandatory micromanagement or grind. No mandatory external AI/cloud, no always-on world, no new global director. Preserve canonical lore, factions, stages, art style, resources, logistics and physics. All simulation features must produce meaningful player choices or be simplified. No surface individual-soldier control; no individual-soldier-follow in new modes. G16's existing underground survivor view in its authorized context remains. Offline play never needs an account.

## Eleven base-game experiences
| Mode | Offline solo | Online co-op | Online PvP | Scope |
|---|---|---|---|---|
| Skirmish | Yes | Yes | Yes | Existing custom battles, all legal faction/stage combinations |
| Last Protocol | Yes | Yes (2–4) | No | Existing Human A vs Machine siege |
| Inheritance | Yes | No | No | Authored 13-chapter dynasty, personally played battles |
| Living World | Yes | No | No | Autonomous persistent civilization, delegated battles allowed |
| DEAD SECTOR | Yes | Yes | Optional | Four horror scenarios, PATHOGEN only here |
| SUBTERRANEAN WARFARE | Yes | Yes | Yes | Five underground scenarios, DEEPWAR only here |
| BLACK OPERATIONS | Yes | Yes | Compatible scenarios | Seven elite military scenarios |
| SIEGE WARFARE | Yes | Yes | Compatible asymmetric scenarios | Seven fortress scenarios |
| CONQUEST | Yes | Yes | Yes | Six territorial scenarios |
| COMMANDER'S CRUCIBLE | Yes | Compatible challenges | Compatible challenges/optional rankings | Seven short challenge families |
| WAR THEATRE | Yes | Compatible campaigns | Compatible campaigns | Seven military campaign families |

Online support for new modes is a proposed compatibility plan within approved expanded scope, not unlimited player counts or online civilization campaigns. Initial 2–4 player target where applicable, validated by scenario and network testing; exact team sizes, ranked eligibility and asynchronous records subject to gate contract. Every scenario family has viable offline solo presets. Shared or independent command where legal; no campaign save merge, mandatory cloud or persistent online universe. Persistent online scenario saves resume by agreement when players host, not continuously running. Competitive roles must be fair and explicit. UNDERSTRIKE is an integrated Human A branch, not a mode/DLC; only Human A builds protected bunkers and borer fleets, including editor, capture, generation, mod and multiplayer boundaries. DLC civilization experiences offline solo; new official DLC factions playable only in Skirmish. DLC assets and faction-designed fortresses may appear as entitled AI opponents or compatible Skirmish configurations, never bypassing playable-faction rules. No new official faction promised.

## Approved proposal register (33)
| ID | Approved direction | Canonical spec |
|---|---|---|
| EX-01 | BLACK OPERATIONS, seven scenarios | BLACK_OPERATIONS_GDD |
| EX-02 | SIEGE WARFARE, seven scenarios and intelligent faction fortress generator | SIEGE_WARFARE_GDD |
| EX-03 | CONQUEST, six scenarios and meaningful territory | CONQUEST_GDD |
| EX-04 | COMMANDER'S CRUCIBLE, seven challenge families | COMMANDERS_CRUCIBLE_GDD |
| EX-05 | WAR THEATRE, seven persistent military campaigns | WAR_THEATRE_GDD |
| EX-06 | Advanced doctrine system | OPERATIONAL_INTELLIGENCE |
| EX-07 | Universal operation planning | OPERATIONAL_INTELLIGENCE |
| EX-08 | Simple persistent formation identity | WORLD_ARCHIVE |
| EX-09 | Causal intelligent strategic objectives | OPERATIONAL_INTELLIGENCE / DYNAMIC_SCENARIO_ENGINE |
| EX-10 | Simple automated recovery/reconstruction | OPERATIONAL_INTELLIGENCE |
| EX-11 | Engineering/construction templates | PROCEDURAL_WORLD_AND_ENGINEERING |
| EX-12 | Procedural scenario creator | DYNAMIC_SCENARIO_ENGINE |
| EX-13 | Full scenario and campaign editor, new mode configurations | CREATOR_TOOLKIT_AND_WORKSHOP |
| EX-14 | Community Workshop + Creator Store | CREATOR_TOOLKIT_AND_WORKSHOP / PLATFORM_PRODUCT_ROADMAP |
| EX-15 | Native modding architecture, safe SDK | CREATOR_TOOLKIT_AND_WORKSHOP |
| EX-16 | Complete replay system | REPLAY_SPECTATOR_AND_RECORDS |
| EX-17 | Eligible online spectator mode | REPLAY_SPECTATOR_AND_RECORDS |
| EX-18 | Achievements, medals, trophies, records, cosmetic rewards | REPLAY_SPECTATOR_AND_RECORDS / WORLD_ARCHIVE |
| EX-19 | Interactive Military Academy | PLAYER_EXPERIENCE |
| EX-20 | Contextual intelligent assistance | PLAYER_EXPERIENCE |
| EX-21 | Unified adaptive command dashboard | PLAYER_EXPERIENCE |
| EX-22 | Consolidated intelligent alerts | PLAYER_EXPERIENCE |
| EX-23 | Encyclopedia with spoiler boundaries | PLAYER_EXPERIENCE |
| EX-24 | Quick play, recommended scenarios, resume, favorites, tactical pause, accessibility and automation | PLAYER_EXPERIENCE |
| EX-25 | Intelligent procedural world generator | PROCEDURAL_WORLD_AND_ENGINEERING |
| EX-26 | Commander personalities/intelligence profiles | OPERATIONAL_INTELLIGENCE |
| EX-27 | Adaptive challenge and difficulty framework | DYNAMIC_SCENARIO_ENGINE |
| EX-28 | Seamless military reorganization | OPERATIONAL_INTELLIGENCE |
| EX-29 | Equipment/facility modernization | OPERATIONAL_INTELLIGENCE / PROCEDURAL_WORLD_AND_ENGINEERING |
| EX-30 | Hardware benchmark and performance assistant | PRODUCTION_RELEASE_FRAMEWORK |
| EX-31 | Save protection and long-term compatibility | PRODUCTION_RELEASE_FRAMEWORK |
| EX-32 | Universal content production/validation pipeline | PRODUCTION_RELEASE_FRAMEWORK |
| EX-33 | Production and commercial release framework | PRODUCTION_RELEASE_FRAMEWORK / PLATFORM_PRODUCT_ROADMAP |

All 34 new scenario families across five modes are approved design scope. Four DEAD SECTOR and five SUBTERRANEAN WARFARE families remain in earlier specifications (43 families across seven specialized modes; not 43 standalone engines). Seven existing directors remain; OPERATIONAL INTELLIGENCE, WORLD ARCHIVE and DYNAMIC SCENARIO ENGINE are three shared services, not new directors. Their capabilities reuse existing ledger, AI, scheduler, objectives, UI and persistence; no duplicate authority. Platform expands from game-specific multiplayer to reusable independently owned open-source product (library, launcher, accounts/social, multiplayer, creator catalog, replay library, developer portal, distribution, commerce, SDK/API, safety and recovery). Free creator sharing at launch, paid creator content phased behind policy/economic/legal validation; no pay-to-win. Base-game purchase/entitlement solution required for chosen business model. No assumption of full Steam-sized storefront at launch.

## Navigation
[BLACK OPERATIONS](BLACK_OPERATIONS_GDD.md) · [SIEGE WARFARE](SIEGE_WARFARE_GDD.md) · [CONQUEST](CONQUEST_GDD.md) · [COMMANDER'S CRUCIBLE](COMMANDERS_CRUCIBLE_GDD.md) · [WAR THEATRE](WAR_THEATRE_GDD.md).
[Operational Intelligence](OPERATIONAL_INTELLIGENCE.md) · [World Archive](WORLD_ARCHIVE.md) · [Dynamic Scenario Engine](DYNAMIC_SCENARIO_ENGINE.md) · [Procedural world and engineering](PROCEDURAL_WORLD_AND_ENGINEERING.md) · [Creator toolkit](CREATOR_TOOLKIT_AND_WORKSHOP.md) · [Replay/spectator/records](REPLAY_SPECTATOR_AND_RECORDS.md) · [Player experience](PLAYER_EXPERIENCE.md) · [Platform product](PLATFORM_PRODUCT_ROADMAP.md) · [Production/release](PRODUCTION_RELEASE_FRAMEWORK.md) · [Integrated delivery](EXPANDED_GAMEPLAY_DELIVERY_PLAN.md).
