# RTS: Age of Modern War — full roadmap to the finished game (owner-approved order 2026-10-31)

One list of everything still planned, from every source on record, grouped into slices in a proposed build order.
**Nothing below G7.1 is contracted yet.** The slice order and how the recorded G8 list is split across slices were
approved by the owner on 2026-10-31 (merge decisions at the end). Each slice gets its own owner Q&A, GOAL block and frozen Done-when before it starts, as
G6.1 / G7 / G7.1 did.

## Sources (the authority for each item stays in its own file)
| Source | What it holds | Status |
|---|---|---|
| `docs/G71_SCOPE.md` | G7.1 "Tide Line": parts A–J, 12 frozen Done-when checks, 6 waves | LOCKED 2026-10-31 |
| `docs/G7_REFERENCE.md` → "G8 SCOPE" + "G8 HEADLINE" | Everything moved out of G7; view rotation headline | Owner-recorded scope list |
| `docs/CAMPAIGN_VISION.md` | Campaign "Inheritance" (13 chapters), Living World, space, 6 ship rosters, arrivals | Vision record, every decision closed; not contracted |
| `docs/superpowers/specs/2026-11-23-ghost-exo-programme-design.md` | Ghost Exo Programme overlay (AI Conductor, Death squads, packages A–J) | Owner-approved 2026-11-23; G10/G15 gated |
| `docs/superpowers/plans/2026-11-23-ghost-exo-programme.md` | Ghost Exo integration + slice plan | Phase 0 docs done; engine gated to G10+ |
| `docs/understrike/` (new, from the owner's zip 2026-10-30) | UNDERSTRIKE: Human A underground bunkers, 32/32 decisions, 4 phases, 23 acceptance tests | Owner-approved design handoff; not built |
| `docs/understrike/References/Base_Project_v1.3/` | The original Master GDD + Development Roadmap v1.3 (G0–G6 + backlog F-001..F-025) | Base mechanics authority; long-term items folded below |
| `docs/vision/` | 6 owner mockups (continental map, stronghold sieges, company cards) | Visual direction |

## Shipped (for orientation)
G0 engine spike → G1 core RTS → G2 smart warfare → G3a/G3b slice content (3 factions, stages 7–9, maps) → G4 harden +
scale (save/load, walls, editor) → G5 (naval, air, hospitals, tutorial) → G6 (companies, armies, elevation, subs,
carriers, marketplace) → G6.1 "Field Command" (chain of command, suppression, fatigue, veterancy, belief fog) → G7
"Last Protocol" (Signalborne ports, counter-nanite line, LP mode; shipped 2026-10-30).

---------------------------------------------------------------------------------------------------------------------
## G7.1 "Tide Line" — the Last Protocol siege upgrade (LOCKED 2026-10-31, next to build; scope in `G71_SCOPE.md`)
- **A. Fixes and flow:** aircraft land on their own pads (home-pad registry), longer fuel, hot-pit service, FARPs,
  patrol loops, one-click deploy, auto logistics, mission templates, bigger hitboxes, roster panel, edge scroll, zoom
  to cursor, minimap, +20% speed.
- **B. Firepower:** rotary railgun, lasers, HPM, thermobaric / incendiary; component damage, plates, ricochets,
  nanite self-repair, death physics; MG crews, AT teams, .50 snipers, grenadiers; radial fire support, manual FPF,
  counter-battery; ammo tiers; Conductor gunship + wingmen; Vanta2.
- **C. The hive:** feel-based wave director to 1,000+ machines at ~60 min, breathers, dread meter, breaking-point
  wave; adapts, feints, regrows, hits logistics late; Gorilla brute, turret-eater swarm, siege walker, burrower;
  Reclaimer, hive Conductor, Glass stalkers; body-piles, flocks, liquid flow; wrecks as cover; Overmind voice, visible
  cores.
- **D. Defence + CN force:** hold + strike win, mid-siege objectives, supply drops, wall rotation and morale,
  runners, fallback lines, sorties, discipline and NCOs, kill-zone painting, threat forecast, hive codex, after-action
  report, one-order CN missions.
- **E. Look + perf:** night siege, layered sound, camera impact; beat every past build's fps and sim speed; effects,
  Machine art, terrain + lighting; animation last.
- **F. Robot companions:** UCAV, EW / relay drone, minelayer, UGV family, robot dogs, wall sentinels, mules, purge
  bots, hunter-tank; mesh network, telemetry, new drone bay + robot depot, ~150-robot fleet.
- **G. People + base:** engineers+, JTAC, medics+, NVG; MLRS, dozer tank, flame tank; flak towers, seismic sensors,
  wall tiers / anti-climb / firing ports / lifts; outposts; radio story; adaptive score; LP save / resume; mutators.
- **H. Offense:** multi-phase core raids, hunt the Conductor, Reclaimer hunts, rescues, op planner + auto-plan; sky
  carrier, fighter CAP; mini-bosses; creep spores; LP research; facility under siege + new CN gear + 70 s turnaround;
  military HUD; weapon sound; hive evolves; captured-machine study; persistent battlefield, smoke.
- **I. Command + world:** officer request queue, jammed-not-dead turrets, wall melee, gate defence, terrain mix,
  wind, fog, spreading fire, illumination, searchlights, darkness, hive ecosystem, machine deaths, 3 endings.
- **J. Dark Protocol (dark pass, owner-approved 2026-10-31):** full graphic gore with no slider (round-driven wounds,
  bodies and wrecks stay, burn / char, crush / trample); crawling wounded, triage and morphine; machine viscera and
  half-dead machines; the harvester swarm; nanite wound infection; trauma + decontamination hospital (medevac
  helicopters, drone ambulances, quarantine, prosthetics); horror atmosphere (silence before, night eyes, tide songs,
  bodies on display); Lazarus walker; cybernetics, stimulants, neural-link pilots; counter-nanite gas with masks and
  filters; plasma, coilguns, smart-dust, energy shields, light + heavy mechs; the separate reverse-engineering complex
  "Site Blackglass" (mountain site, 13 buildings, layered containment cells, dissection hall, breakouts and purge,
  own garrison + Warden gunship, self-destruct on overrun, capture teams, convoys, 5-stage study -> tech);
  the fallible AI war-mind; score / medal and ending cost for dark choices.

---------------------------------------------------------------------------------------------------------------------
## G8 "Four Sides" — view rotation + the visual generation (owner: rotation is G8's headline)
- **Full 4-side view rotation:** every building, prop, terrain edge and effect drawn from 4 sides (no mirroring);
  90° steps on Q / E + middle-mouse drag (rebindable); camera keeps its focus; selection, orders, minimap, fog, every
  display layer and depth sort follow the view; facing hints in the UI. (Today: 17 of 154 art generators multi-view.)
- **Art detail upgrade for all four factions**, full human redraw included. [PROPOSED placement: done with rotation,
  because rotation forces every sprite to be redrawn anyway, so each one is drawn once at the new detail level.]
- **General animation overhaul** beyond what G7 needed.
- **Presentation:** director-cam picture-in-picture for big moments, end-of-run highlight reel, end-of-run creep
  timelapse.

## G9 "Hive Reborn" — Machine overhaul + combat systems [PROPOSED split of the G8 list]
- **Machine faction, full overhaul:** the blended look; all 60+ defs; silhouettes; animations; hive network, adaptive
  evolution, nanite growth, modular units; minimal self-replication, eating the battlefield (wrecks included);
  hardest-but-fair tuning; glow team colour.
- **Its 13 other counters:** strike early / cut relays, EMP / EW / hacking in full, deny material, sweep and purge,
  network virus, decapitation, starve power, reverse-engineering, firebreaks and hostile ground, coalitions, dead
  zones, hunter-killer squads as a general unit, reprogramming captured units.
- **Combat systems:** destructible terrain; armour and ballistics (facing, angle, weak spots, ammo types) for every
  match type; EW, drones and cyber beyond the G7 minimum; digging in and field fortifications; vehicle crews; vehicle
  maintenance and breakdowns.
- Carries G7.1 hive tech (director, adaptation, siege units) from Last Protocol into skirmish where it fits.

## G10 "Shadow Coalition" — 4th faction — **CLOSED (`g10.lock`)**
- **Shadow Coalition (Syndicate):** identity, mechanics, full-parity Stage 7→10 roster, art, no counter-nanites;
  **Stages 1–6** (early raider bands) and **11–13** (late syndicate, Mk III exos, 100+ squads) ship **in G10** for
  this faction (owner 2026-11-23 — inverts CAMPAIGN_VISION resolution 4 deferral to G14). Scope doc:
  `docs/G10_SCOPE.md`. Lock: `.superpowers/sdd/g10.lock`.
- AI, diplomacy, research, territory, trade-route, gathered-resource and black-market depth moved forward and closed
  in `pre_g10.lock`; G10 scope is Coalition-only.
- **Deferred look (owner 2026-11-24, non-blocking):** TECHNICAL Humvee family, SAFEHOUSE, HATCH — redesign later;
  approved-core CELL/DEATH/WALKER/CLOSE AIR locked. G14 retains other factions' early/late forms only.
- **Ghost Exo Programme (owner-approved 2026-11-23):** seamless AI-first Conductor; tip echelon = **Death** squads
  (plus Shadow Corps + Anchor); full packages in
  `docs/superpowers/specs/2026-11-23-ghost-exo-programme-design.md`; slice plan
  `docs/superpowers/plans/2026-11-23-ghost-exo-programme.md`. G10 ships skirmish/Conductor core + Human A
  **Counter-Ghost full corps** (Interceptor/Bulwark/Seeker/Ward, specialties, vehicles + **Shade Dart** 4-op
  lift-fan infil/exfil; **each vehicle type has its own garage/pad/helipad**) — org in
  `docs/superpowers/plans/2026-11-23-faction-depth-decisions.md`. Campaign Hunter build-up waits for G15.
- **Difficulty bar (owner 2026-11-23):** whole Coalition (not only exos) = **super-difficult**, **super intelligent /
  strategic** foe — difficulty by intelligence/strategy, not cheats; beatable with counters, crushing if ignored.
- **Leftover dark + G7.1 ideas (moved from Parked, owner 2026-11-23):** fold into Coalition / LP-adjacent threat and
  toolkit depth where they fit the super-intelligent difficulty bar (pick in G10 Q&A; not all must ship):
  - Dark options: grafting, turning operators, Dead Hand strike, Overmind voice outside LP, mirror fortress, blackout,
    hollow ground; husk reanimation, infiltrators wearing our dead, machines built around human remains, infected
    vehicles; Screamer, flesh-hive spire, puppet-master, nanite plague bomber, hollow giant, Mourner; dead-radio /
    mimicked voices, mercy kills, last-moment actions, shell shock; tactical nukes, hive bait, tamed nanites in blood,
    gravity weapons, LP orbital lance, morale cost for dark acts.
  - G7.1 not-picked: wall breach holes, Protocol cooldown abilities, Colossus boss, hive gunship / bomber swarm /
    interceptor darts, Wreck mimic, Signal ghost, Ferro-tide, Mirror shell, Resonator, Creep seeder, Sky anchor,
    Lodestone, Storm-maker, Parasite riders, Silent clock, Sapper Architect, living siege tower.

## G11 "UNDERSTRIKE I–II" — underground bunkers, foundation + military (NEW, owner zip 2026-10-30)
Human A only (decision 28: no other faction can ever build bunkers or the borer fleet, even by capture). Unlockable
branch, not required in every mode. Needs G9's destructible terrain and persistent geometry.
- **Phase 1, bunker foundation:** bunker unlock at Stage 8; architecture for 15 floors; first floor + incremental
  expansion; basic geology clearance; modular rooms (security, barracks, workshop, storage, power, air); power and
  resource links to the surface economy; first automation policies and smart templates; surface / cutaway / floor
  cameras on ONE simulation; one concealed multi-vehicle elevator (ground panels slide open, vehicles drive off, lift
  returns, cover closes); save / load mid-operation; attackable entrance.
- **Phase 2, military:** underground exploration and fog; first combined-arms set from the 12 MB borers (MB-01 Wraith, MB-04 Delver
  … MB-12 Atlas, working names) + tunnel infantry, breach teams, underground commanders; sector capture, security
  barriers, alternate entrances; **Bore To Surface** breakthroughs that leave persistent openings; enemy temporary
  assault tunnels and raids (Machine / Human B can raid, occupy, loot, sabotage, never build); local geometry damage;
  tactical AI, maintenance, counter-recon.
- UX bar (decision 32): one objective = one order (`Expand Floor`, `Deploy Armor`, `Secure Sector`); approvals for
  major changes; every block explains what / why / next step; override any room, floor or army without turning
  automation off.
- Acceptance: UX-01..03, ELEV-01..02, GEO-01..03, MIL-01..03, FCT-01..02, INT-01, PER-01, PERF-01, AI-01, A11Y-01.

## G12 "Soldiers and Theatres" — human depth + maps and modes [PROPOSED split of the G8 list]
- **Human depth:** training facilities and courses, learning by doing, readiness; bunk and rotation with refresher
  courses; full base security (perimeter layers, threat states, hardening); combined arms, breaching and CQB, recon
  and sniper teams; mutual support calls; gear and vehicle upgrades; named soldiers and careers; specialists and kits;
  veterancy completion.
- **Maps and modes:** new biomes; urban warfare depth; procedural map generator; special operations missions;
  weather and day / night for every mode (seasons: frozen rivers, mud season, storms ground aircraft); after-action
  reports for every mode.
- **No pop-cap skirmish (owner 2026-11-23, was parked 13.9c-40):** optional uncapped (or soft-cap) population for
  skirmish; perf budgets, LOD, and AI pathing must hold; setup toggle; default capped mode remains.

## G13 "UNDERSTRIKE III" — the networked underground civilization (NEW)
Multiple bunkers (no fixed cap), each up to 15 floors; tunnels, military roads, rail / armoured trains, transport hubs,
automated cross-bunker shipments; late maglev; resident cohorts and visible people (inspectable, never
micromanaged); civilian districts and governance; closed-loop food / water / air / energy / medicine; energy grids
with storage and backups; specialized research; geological discoveries (natural first, plus ancient / nonhuman
structures and unknown materials; four material origins: extraterrestrial, lost advanced human, ancient nonhuman,
unresolved); the remaining borer classes and custom vehicle design (save / produce / retrofit variants); enemy
attacks on logistics and research. Tests LIFE-01, LOG-01..02.

## G14 "All Thirteen" — Stages 1–6 and 11–13 for every faction (original backlog F-025; campaign needs it)
Distinct playable mechanics for every stage and every faction, with full skirmish parity: Stages 1–6 (Scattered
Survivors → Industrial Revival), Stages 11–13 (Synthetic → Distributed → Apex). **Shadow Coalition** early/late stage
bands **moved to G10** (owner 2026-11-23); G14 covers **other factions'** 1–6 and 11–13 only. UNDERSTRIKE's 13-stage
unlock bands (early shelters, mechanized bunkers, advanced boring later).

## G15 "Inheritance" — the 13-chapter campaign (`CAMPAIGN_VISION.md` Part 1)
One Human A dynasty from the ash to Apex; founder (Ch 1–5) then heirs (Ch 6–13); the Healer / Dead Hand secret;
hand-crafted regional map per chapter (real-time, pausable hub) with authored operations; war director between the
beats; delayed orders by distance; carry-over of scars, people, grudges, builds; Story and Dynasty (Ironman) modes;
succession fights; named veterans; companion bloodlines; era rivals and generals who remember you; civilians and
conduct the world remembers; in-engine cinematics, voiced radio, illustrated panels, era score; ~60–80 hours.
Uses UNDERSTRIKE bunkers for its bunker floors, safehouses and tunnels; the Syndicate goes public in Chapter 9.
May reuse G7.1 J9 (cybernetics, stimulants) as dark story choices (note only).
**Ghost Exo campaign layer (approved 2026-11-23):** Ch9 reveal → Ch12–13 Death-squad build-up, Hunter + Harrow Cell,
Listeners, full intel memory, turn path — per
`docs/superpowers/specs/2026-11-23-ghost-exo-programme-design.md` Packages E/H/I/J and
`docs/superpowers/plans/2026-11-23-ghost-exo-programme.md` Phase 2.

## G16 "UNDERSTRIKE IV" — high-fidelity underground (NEW)
Mature chunk-based geology and groundwater; cascading multi-floor collapses with persistent ruins, surface subsidence
and advanced VFX (same outcome at any VFX level); programmable hybrid-material tunnelling (MB-12 Atlas route
blueprints); advanced vehicle variants; region-scale underground command; large-scale profiling and hardening;
**underground survivor view** (follow one person through the bunkers and tunnels; owner decision 1, underground only).
Tests DES-01..02, PER-01, PERF-01 at scale.

## G17 "Living World" — after the campaign (`CAMPAIGN_VISION.md` Part 1 + vision mockup 01)
Endless world on the same save: continue the dynasty or start a new life; zoom levels settlement / army / nation /
continent; AI rivals rise and fall, world crises, any civilization can slide down the stages; the continental war
map (territory %, fleets, convoy lanes, expeditionary forces, airlift, naval support). Original backlog F-021 (deep
markets, politics, generations) and F-023 (full continent + underground / naval warfare) land here.

## G18 "Orbit" — space and the arrivals (`CAMPAIGN_VISION.md` Part 2)
The station; the Scepter (dormant rod weapon, its hidden cost and layered reveal); the road to orbit; how space is
played; 6 ship rosters (Human A 21 hulls, Human B 22, Machine 24, Shadow Coalition 22, Vhessar 21, Unbound 19); the
arrival war with the Vhessar conquerors and the Unbound cult as two new full skirmish factions; endings, then the
endless crisis.
- **Vhessar depth (owner 2026-11-23):** max castes/beachheads/Ark/boarding; EaW+intents+Duel/Board; **no kneel
  gameplay**; player doctrine unlocks at tech stage then locks; AI mixes/adapts live; pressure = EMP/Healer/CN
  counters + Ark/beachhead denial. Arrival outcome **Viceroy** (ex-Kneel name). See
  `docs/superpowers/plans/2026-11-23-faction-depth-decisions.md`.
- **Unbound depth (owner 2026-11-23):** strip/defection/warband chaos/Free Yards + more content; Strip/Turn/Unseed
  buttons; warbands can ignore player; doctrine unlock at tech stage (AI adapts live); pressure = steal/turn + messy
  ally risk + unpredictability. Same plan file.

## G19 "Last Protocol: Combined Arms" — co-op Last Protocol (owner 2026-11-23; was parked)
Offline-first co-op siege on the **same** LP ruleset (Human A vs Machine, 512²+ map, 3 rings, CN facility, cores,
creep/countdown, Tide). Solo LP stays untouched as the 1v1 reference.

- **Players:** 2–4. Shared win/lose. Shared creep meter, doomsday countdown, core HP, Tide trigger. No friendly fire
  on humans by default (toggle for hardcore).
- **Command model:** one base, many commanders. Default = **sector/role claim** (Outer / Economy / Core+CN / Field
  Strike) with free override on unclaimed units; optional **full shared pool**. Defence AI Commander fills gaps only
  in unclaimed sectors.
- **Authority:** host is sim authority (deterministic lockstep or host-authoritative with input delay); late join =
  spectate until next checkpoint / mid-run save; disconnect = claimed units revert to defence AI, not enemy.
- **Scaling (fair, not cheats):** hive pressure, Weaver timing, Tide mass, and seed-nest count scale with player count
  via director curves — same counters, thicker tempo. Perf gate: co-op Tide must still hit shipped FPS floors.
- **Logistics:** one economy; CN teams/APCs/dropships are shared scarce assets with a claim/queue UI (no double-order
  races). Strike ops need a clear owner or a dual-confirm on the walking core.
- **Intel/UX:** shared belief fog + ping/mark layer; ring-breach and countdown alerts to all; split or PiP optional;
  one AAR with per-player medals + squad Remembered lists.
- **Modes:** Quick Co-op (scaled short run), Full Protocol (60–90 min), Iron Co-op (one shared save, no reload).
- **Out:** no PvP LP; no Coalition/Machine player slots here; no campaign save merge. Mutators reuse G7.1/G10 dark
  picks only after those ship.

---------------------------------------------------------------------------------------------------------------------
## Parked / undecided (not in any slice until the owner says so)
- Tactical pause with order queue (undecided since G8).
- Surface survivor controls: out for good (merge decision 1; underground survivor view is in G16).
- Co-op LP → **G19**. No pop-cap skirmish → **G12**. Leftover dark + G7.1 ideas → **G10** (owner 2026-11-23).

## Merge decisions (OWNER, 2026-10-31; these override the source files where they differ)
1. **Survivor view: underground only.** A survivor / follow-one-person view exists inside UNDERSTRIKE bunkers and
   tunnels (decision 13), placed in G16. On the surface and in the campaign there is still no playing as one person
   on foot. Original backlog F-022 is satisfied by this underground view only.
2. **Bunkers are Human A only, ever.** Human A (the modern human faction) is the only faction that builds bunkers or
   the MB borer fleet. Human B, the Machine, the Shadow Coalition, the Vhessar and the Unbound can raid, occupy, loot,
   sabotage and destroy bunkers, never build them, including by capture, editor, old saves or difficulty overrides
   (test FCT-01 covers every one of them). UNDERSTRIKE's "Scavenger Human" = our Human B.
3. **Names kept unique:** UNDERSTRIKE's MB-04 "MOLE-X" is renamed **MB-04 DELVER**. "The Mole" stays the campaign's
   exo tunnelling pod; "burrower" stays the G7 Machine unit; "sapper" stays the G7.1 Machine siege role. (UNDERSTRIKE
   names are working designations, decision register note; the role and Human A exclusivity are unchanged.)
4. **Speed and settings:** G7.1 stays as decided (no speed control, no visible quality trades). G11 adds game-speed
   controls and an accessibility menu (reduced shake / flash, UI scale, remappable keys, non-colour threat cues).
5. **Order approved:** G7.1 → G8 → G9 → G10 → G11 → G12 → G13 → G14 → G15 → G16 → G17 → G18 → **G19** as listed.
   The [PROPOSED] slice placements above are the owner-approved plan; each slice still gets its own Q&A and Done-when.
   (G19 co-op LP, G12 no-pop-cap, G10 leftover dark/G7.1 ideas added owner 2026-11-23.)
6. **Dark pass (2026-10-31): everything goes into G7.1** (part J), not a separate slice.
