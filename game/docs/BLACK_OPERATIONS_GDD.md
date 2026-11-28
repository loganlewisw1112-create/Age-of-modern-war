# BLACK OPERATIONS GDD

Owner-approved expanded design direction, 2026-11-27. All features planned; implementation and acceptance pending. Working names, proposed interfaces and test IDs are not source code or frozen gate contracts. Existing G10.1 regression remains open.

## Purpose
Elite formations, tactical RTS, intelligence, adaptive security and consequences; smaller force scale than classic economic buildup. Quick operation or persistent covert military campaign. Reuse Coalition Ghost Exo/Conductor, Human A Counter-Ghost, faction recon, fog, security, transportation, logistics, medical, operation planner and underground links. No new faction or universal cloak entitlement; covert roles are era/faction appropriate. No individual soldier control or follow camera.

| ID / scenario | Start and objective | Variability and victory |
|---|---|---|
| BO-01 Ghost Protocol | Small legal special operations group; recover intelligence or an asset and extract | Multiple lawful RTS routes, patrol shifts and support availability; secure objective/extract before collapse |
| BO-02 Counterstrike | Defending command detects hostile covert activity; protect assets and identify/neutralize threat | Competing incomplete beliefs, decoys, asset protection and counterintelligence; defeat hostile operation or preserve priority assets |
| BO-03 Deep Recon | Deploy scouting formations into unknown territory | Discover installations, confirm intelligence, return or establish contact; partial intelligence has value |
| BO-04 Asset Recovery | Recover isolated personnel, captured equipment or experimental technology | Changing target location based on actual movement, transport and escort constraints; rescue/recover/extract |
| BO-05 Silent War | Rival covert organizations compete across connected sites over several operations | Intelligence, detection, influence, asset loss, changing priorities; strategic objectives or persistent play |
| BO-06 Black Fortress | Assault, infiltrate or defend a classified installation | Generated or authored functional security layout, multiple approach classes, surface/underground when legal; capture, protect or extract |
| BO-07 Total Black Operations | Persistent campaign with all previous mission families | Surviving formations, intelligence, equipment, replacement reserves, changing opposition; defined campaign win or endless |

Loop: brief -> select formation/mission loadout -> recon -> act -> adapt -> recover/extract -> debrief -> next operation. Mission objectives support partial success, alternate routes and withdrawals where appropriate. Dynamic complications arise from detected movement, reinforcement capacity, compromised communications, damaged routes or other real state, not omniscient enemies or guaranteed ambushes. Fog and uncertain intelligence remain meaningful. Mission briefing marks confirmed and unconfirmed information, objective and extraction options; one-click operational directives and direct tactical override. Routine repair, medical, fuel/ammo and replacements automatic within resources. Preserve persistent formation ID, battle honors and career records; no manual personnel roster chore. Equipment customization optional, standard presets default.

## Multiplayer and creator support
Solo all scenarios; online shared or allied roles and compatible competitive attack/defense/covert objectives, with explicit teams and asymmetric win conditions; no arbitrary faction access or hidden information leakage. Initial 2–4 target, validate each family. Persistent saves use G18 session save rules. Procedural and authored missions share objective state machines, validated starts and legal assets; full editor allows reusable mission templates and shareable seeds. Mission generation never fabricates new tech or leaks campaign secrets. Replay/spectator follows permitted viewpoints. Award medals for objectives, recovery and meaningful outcomes, not raw casualty counts or grind.

## Acceptance
All seven families authored + generated examples; meaningful distinct objectives, fair fog/security, legal loadouts and faction rights, counterplay for elite units, transport/extraction and resource persistence, partial success and failure, reconnect, no individual-follow UI, quick start and long campaign playtests. Baseline RTS controls and existing G10/LP/Skirmish unchanged. [Shared scenario engine](DYNAMIC_SCENARIO_ENGINE.md) · [Operations](OPERATIONAL_INTELLIGENCE.md).
