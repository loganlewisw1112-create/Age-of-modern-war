# 01 — Decision 32: seamless, concise UI with layered depth

## Player's 5-second mental model
**Surface | Bunker | Floor | Follow Unit**. Inside the Bunker view, the user can issue `Build`, `Upgrade`, `Excavate`, `Defend`, `Transport`, `Research` and `Manage` orders. Each has one primary action, a short preview and optional `Advanced` settings. Any operation not requiring a meaningful strategic choice should be delegated.

## UI hierarchy
**Layer 0 — Battlefield:** Standard surface RTS HUD, contextual selection/actions, minimap, existing game speed and alert language. Selecting Modern Human headquarters exposes `Underground Operations` only when unlocked. No change to other factions' build menus.

**Layer 1 — Bunker overview:** Vertical interactive cutaway, up to 15 floors, surface connection and adjacent tunnel segments. Floor tiles show function, construction, integrity, power, security, population, incident icons and simple capacity bars. Strong differentiation between no excavation, planned, active, active/damaged, contested, occupied and collapsed.

**Layer 2 — Floor:** Camera transitions to standard isometric RTS controls; show excavated boundary, modular rooms, unit movement and compatible building slots. One-click `Smart Build` presents ghost-layout of rooms, utilities, corridor and freight connections. Player can approve or revise; construction logistics are automated.

**Layer 3 — Detail (optional):** Selecting a factory reveals production, inputs, staffing status, upgrades, and current mission. Selecting a vehicle displays route, cargo, damage, fuel/power, operational mode and available actions. Hide diagnostics behind `Details`; expose only the next useful decision.

## Control pathways
- **Build a vehicle factory:** Bunker > Floor 6 > Build > Military Production > Armored Factory > preview total footprint, throughput, required supply/utility connections, cost, completion estimate > Approve. Auto-route construction orders.
- **Launch an underground offensive:** Select underground army/commander > objective marker > `Capture Sector` > optionally `Cautious / Balanced / Aggressive` > Execute. Commander chooses recon, routes, logistics and unit-level tactics within granted scope.
- **Concealed vehicle deployment:** Select fleet > `Deploy Surface` > select exit/rally point or `Auto Select Exit` > system checks dimensions, queues elevators, opens disguised surface cover, transfers units, automatically recloses when clear.
- **Respond to crisis:** One grouped alert `Floor 9 — Structural Emergency` > `View`, `Let AI Handle`, `Set Priority`. AI already follows authorized protocols for evacuation, isolation, fire response, power rerouting, and rescue.
- **Blueprint reuse:** Build > Saved Plans > apply to a site > show incompatibilities/automatic adjustments > player approves changes that affect strategic layout.
- **Switch perspectives:** One input returns to the previous camera; combat and queues remain active. Cutaway and split-level rendering never duplicate or pause simulation entities.

## Automation policies: a single consistent system
Scopes: `Room`, `Floor`, `Bunker`, `Network`, `Army`. Modes: `Manual`, `Assisted`, `Autonomous`. Priorities: `Safety`, `Military`, `Production`, `Research`, `Civilian Well-being`, `Economy`. Policy fields: budget ceiling, allowed actions, required approval classes, emergency rules and tactical risk.

Defaults: Standard mode = `Autonomous Routine` on; major spending > player-defined threshold requests approval. An expert can override one factory without breaking citywide routing; override expires at mission completion or persists via `Pin Manual` toggle.

## Alerts (severity, not spam)
- **Critical:** imminent structural cascade, hostile capture of command routes, life-support emergency; visible and audible unless accessibility settings mute audio.
- **Important:** production interruption, precious anomaly found, major objective completed, new invasion, research milestone.
- **Informational:** routine elevator arrivals, staff reassignment, ordinary repairs, construction progress; activity log only.
Batch repeated warnings by source/event; one player-visible issue card may summarize several related failures.

## Readability & art
Actual vehicle proportions, recognizable floors and routes, detailed but restrained camera effects. Use contextual camera-follow for an exciting collapse only when enabled; never forcibly hijack input during battle. Structural failure uses progressive cracking, support loss, debris, impact, dust, lights and lingering scars. Offer low-VFX and reduced-flash modes without removing gameplay-critical warnings.

## Guided experience (tutorial)
Tutorial in ≤5 missions: unlock bunker; place Floor 1 module; approve excavation of Floor 2; operate vehicle elevator; issue autonomous security order. Extend only when player requests advanced training. Objective text tells user the benefit of each step, not engine mechanics.

## Acceptance for Decision 32
A first-time RTS player can perform the five core tasks with standard selection/context interactions without issuing laborer, elevator, electrical cable or civilian orders. Detailed panels remain available, and no routine automation becomes unresponsive after manual intervention. Switching surface/bunker/floor views has consistent selection state and no duplicate unit movement.
