# 00 — Scope, authority, non-negotiable rules

## Game relationship
UNDERSTRIKE extends the offline-first RTS *Age of Modern War*. It does not replace classic skirmish, economics, military hierarchy, 13-stage civilization progression, surface battles, or later Survivor/Continental perspectives. The surface continues simulation when the camera is underground; underground facilities participate in ordinary faction resources, logistics, casualties, territorial control, technology, AI orders and saves. Understrike is **an unlockable Modern Human faction branch**, not a starting requirement for all RTS modes.

## Immutable design constraints
- Modern Human is the **only faction able to construct or expand persistent bunkers and create the specialized 12-class military boring fleet**. Scavenger Human and Machine factions may assault, enter, temporarily tunnel, capture sectors, loot and destroy—but cannot gain bunker construction rights through occupation or salvage.
- Each bunker has **at most 15 designated constructed floors**. Multiple geographically distributed bunkers can be built; there is no fixed total bunker-count cap. Expansion limited by geology, cost, technology, territory and measurable compute budgets.
- Floor architecture uses freeform excavation and structural engineering; facilities use **modular, upgradeable room/facility templates (Decision 11 B)**, NOT unbounded per-object micromanagement. Multistory modules allowed when connection dimensions permit.
- Dedicated surface, cutaway, floor-isolated and unit-following underground perspectives reflect **one canonical world state**.
- Player commands are concise. Routine tasks, logistics, staffing, energy, maintenance and emergency protocols are automated unless expressly overridden.
- Concealed **heavy-duty service elevators** lift multiple appropriately sized vehicles from underground; surface terrain-like panels **slide open** on arrival, vehicles disembark, lift returns, and the cover **closes**. Multiple custom elevator shafts and ancillary personnel/freight systems allowed.
- Tunnels and breakthroughs change persistent geometry. Structural damage can trigger spectacular, physically coherent multilevel floor cascades; salvage and rebuilding remain possible.
- A complete underground war exists with scouting, logistics, command, fog of war, territorial capture, combat, sieges, damage, surface coordination and intelligent enemies.
- Discoverable rare, extremely rare and anomalous ores/materials; plausible origins include extraterrestrial, pre-collapse advanced human, ancient nonhuman, and unknown. The origin should be discoverable, not omniscient at first contact.
- Deep population simulation is OPTIONAL to inspect; player governs housing, safety, policy and budgets, not daily household actions.
- Four implementation phases; every phase must run as a playable system and pass explicit tests.

## UX principles for Decision 32
1. **Progressive disclosure:** Quick actions visible; advanced configurations under one extra interaction. Not separate complexity traps.
2. **One objective = one order:** e.g. `Expand Floor`, `Make Factory`, `Deploy Armor`, `Secure Sector`, `Restore Power`.
3. **Approval boundary:** Automated systems may execute agreed projects/policies; they must NOT initiate major demolition, fleet design changes, territory offensives, irreversible exotic extraction, or major budget reallocations without consent.
4. **Explainability:** When blocked, indicate *what*, *why*, and *next practical action*; no silent queue failures.
5. **Intervention:** Player can override a room, floor, facility, vehicle or army without having to disable automation globally.
6. **Legibility:** Major collapse and combat animation must not conceal selection outlines, hazard indicators or actionable routes.
7. **Accessibility:** Remappable bindings, scalable UI/text, reduced camera shake, reduced flashes, togglable cinematic focus, distinct non-color threat cues, and speed controls.

## Approved vs proposed vs unverified
- **Approved:** all decisions listed in Decision Register (including exclusivity, 15 floors, C+ blueprints, automation, phases and UX).
- **Proposed implementation details:** internal entity schemas, naming, exact unlock costs, arbitrary dimensions, targeting rules and algorithm choices in these documents; these can be adapted without changing the intended player experience.
- **Unverified:** present-day source code state, save/load, real performance, combat AI, and screenshot-only behaviors. Inspect and test the existing repository before treating any depicted element as implemented.

## Out-of-scope assumptions
The original offline UNDERSTRIKE branch does not require multiplayer; G18's separate dedicated warfare scenarios support online play. No always-online AI, cloud services, mandatory user text prompts, universally destructible geological atoms, or unrestricted reality-defying material transformation. Cinematic quality is a target constrained by gameplay clarity and performance.


## G18 current approved design authority

G18 is final base-game completion: internet multiplayer, independently owned open-source gaming platform, Last Protocol co-op, Skirmish co-op/PvP, DEAD SECTOR (PATHOGEN), and SUBTERRANEAN WARFARE (DEEPWAR). Inheritance and Living World remain strictly offline solo. UNDERSTRIKE is an integrated Human A gameplay branch, not a separate expansion; dedicated warfare scenarios reuse it. New modes preserve existing faction rights, use traditional RTS controls and have no individual soldier-follow cameras. XENOGENESIS and Myrieme Forge must be fully accepted by G17. G19 Space Expansion and G20 Beyond Civilization follow G18 acceptance; civilization continuations remain offline, compatible owned expansion content extends Skirmish only for new playable DLC factions. No mandatory platform login offline, no Steam dependency. All G18 additions planned, not implemented.

[G18 MASTER GDD](../../G18_MASTER_GDD.md) · [G18 ONLINE MULTIPLAYER](../../G18_ONLINE_MULTIPLAYER.md) · [G18 OPEN GAMING PLATFORM](../../G18_OPEN_GAMING_PLATFORM.md) · [DEAD SECTOR GDD](../../DEAD_SECTOR_GDD.md) · [PATHOGEN DIRECTOR](../../PATHOGEN_DIRECTOR.md) · [SUBTERRANEAN WARFARE GDD](../../SUBTERRANEAN_WARFARE_GDD.md) · [DEEPWAR DIRECTOR](../../DEEPWAR_DIRECTOR.md) · [G18 DELIVERY PLAN](../../G18_DELIVERY_PLAN.md)
