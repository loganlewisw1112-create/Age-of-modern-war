# UI, controls, onboarding and accessibility

Status: consolidated handoff; no gameplay implementation or verification claimed.

Sources: [First_Playable_Spec_v1.3](../source_text/First_Playable_Spec_v1.3.md), [Master_GDD_v1.3](../source_text/Master_GDD_v1.3.md)

8. User Interface and Input Contract
Left click / drag | Behavior: Select one / box-select team units (modifier for multiple)
Right click | Behavior: Smart context move / attack / harvest / repair; modifier for attack-move
Mouse wheel | Behavior: Smooth zoom while retaining fixed isometric tilt and stable target pivot
WASD/arrow/edge | Behavior: Pan camera; optional drag-pan
Ctrl+1–9 / 1–9 | Behavior: Save and recall control groups
Build | Behavior: Preview footprint, red/green legality, rotate, optional snap, cost, worker route
Production | Behavior: Queue, rally, cancel, list required components and blocked reasons
Top bar | Behavior: Credits, key stockpiles, power, population/supply alerts, stage
Lower HUD | Behavior: Unit/formation inspector, contextual orders and build/research panels
Map | Behavior: Fog, ally/enemy known contacts, objectives, camera jump
Alerts | Behavior: Classified by severity: building stalled, under attack, supply missing, tech unlocked
Menu flow: title → Skirmish → continent → map gallery → mode/preset → player/opponent slots → advanced rules → summary/validation → match. Keep options accessible via keyboard and mouse, scale the HUD and avoid hiding critical mechanics under cinematic VFX. The first playable excludes a free-rotating camera by explicit choice.

12. Camera, Interface and Accessibility
First playable camera is fixed-angle isometric. Enable scrolling/keyboard and edge pan, scroll zoom without arbitrary rotation, selection drag, control groups, unit follow hotkeys and smooth bounded travel. HUD uses familiar resource bar and minimap, bottom/context unit actions, construction/production panes, alert severity and readable overlays. Responsive UI scaling, remappable inputs, color-safe team indicators and reduced-flash modes are required design goals.
The complete game adds adaptive close/tactical/operational/strategic zoom, survivor control, modular movable dashboards, layered intel and saved layouts. These expansions must not compromise the first-playable traditional RTS control loop.

## Proposed screen responsibilities

Setup summary shows exactly granted assets, unsupported options and load warnings before Start. HUD exposes credits/materials, power, unit/supply status, selected stage, minimap and contextual actions. Production panels display blocked reason and missing prerequisites. Stage panel distinguishes science, tooling and usable equipment. Officer panel shows mission, phase and player override. Results explain each victory clause and allow Endless continuation where configured.

Use remappable input bindings, keyboard navigation, readable scalable text, redundant team markers, reduced flashing, subtitles/visual alerts, configurable gore, pause and speed control. No final exact hotkey for attack-move modifier is locked by the source. Building rotation is separate from the prohibited free camera rotation. A fresh player must complete HQ/depot/barracks/squad actions using contextual feedback; UI-01 is a playtest, not a documentation checkbox.


## 2026-11-27 — Current expansion design authority

DLC 1 is Space Expansion (G19); DLC 2 is Beyond Civilization (G20). UNDERSTRIKE is base game. True Dynasty is the primary earned continuous campaign → Living World → DLC 1 → DLC 2 path; preset/custom independent starts are separate new saves. Existing game code, gate statuses, campaign canon and rosters are unchanged. All additions are planned, not implemented.

Classic RTS controls, build/research/produce/move/attack, simple directive and authority presets, direct takeover; hierarchical navigation and actionable notifications.

[SPACE EXPANSION GDD](../../game/docs/SPACE_EXPANSION_GDD.md) · [STELLAR SYSTEM BIBLE](../../game/docs/STELLAR_SYSTEM_BIBLE.md) · [EXOTIC RESOURCE BIBLE](../../game/docs/EXOTIC_RESOURCE_BIBLE.md) · [SPACE TECHNOLOGY ARCHITECTURE](../../game/docs/SPACE_TECHNOLOGY_ARCHITECTURE.md) · [DYNAMIC SPACE ENVIRONMENT](../../game/docs/DYNAMIC_SPACE_ENVIRONMENT.md) · [HIDDEN CHRONICLE](../../game/docs/HIDDEN_CHRONICLE.md) · [AUTONOMOUS SPACE COMMAND](../../game/docs/AUTONOMOUS_SPACE_COMMAND.md) · [SPACE EXPANSION DELIVERY PLAN](../../game/docs/SPACE_EXPANSION_DELIVERY_PLAN.md)


## G18 design integration

Current G18 design: offline solo remains; Inheritance/Living World strictly offline single-player; internet Last Protocol co-op, Skirmish co-op/PvP, DEAD SECTOR and SUBTERRANEAN WARFARE. Independently controlled open-source gaming platform; indie-cost direct hosting and relay fallback; mode-exclusive PATHOGEN and DEEPWAR. UNDERSTRIKE is an integrated Human A branch, not DLC. G17 full XENOGENESIS/Myrieme Forge acceptance; G18 final base game; G19 Space Expansion; G20 Beyond Civilization. No code changes or implementation claimed.

Simple offline/online menu, presets, optional advanced settings, accessible alerts, lobby/reconnect, RTS command, no individual follow in new modes.

[Master GDD](../../game/docs/G18_MASTER_GDD.md) · [G18 delivery](../../game/docs/G18_DELIVERY_PLAN.md) · [Networking](../../game/docs/G18_ONLINE_MULTIPLAYER.md) · [Platform](../../game/docs/G18_OPEN_GAMING_PLATFORM.md) · [New mode designs](../../game/docs/DEAD_SECTOR_GDD.md), [SUBTERRANEAN WARFARE](../../game/docs/SUBTERRANEAN_WARFARE_GDD.md).


## Expanded gameplay integration — 2026-11-27

Military Academy, contextual assistance, unified dashboard, grouped alerts, encyclopedia, offline tactical pause, favorites and quick play, replay/spectator and full edit mode. [Player experience](../../game/docs/PLAYER_EXPERIENCE.md).

Eleven base-game experiences complete by G18; G17 full XENOGENESIS/Myrieme Forge acceptance and G19/G20 sequence retained. Seven directors only, Inheritance/Living World offline solo, UNDERSTRIKE Human A protected construction unchanged. Design only. [Expanded master](../../game/docs/EXPANDED_GAMEPLAY_MASTER_GDD.md).
