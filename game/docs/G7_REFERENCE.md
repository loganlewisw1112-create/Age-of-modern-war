# G7 / G8 scope: Signalborne ports, counter-nanite line, Last Protocol

> **STATUS (2026-10-26): G7 RE-SCOPED and APPROVED by the owner "exactly as written", with the default on each of the
> 3 calls. ON HOLD. Do not start any G7 work (plan, briefs, agents, code or art) until the owner gives an explicit
> execution order, which will come only after the owner has finished testing G6/G6.1.**
>
> The **G7 master scope** below is the authority. Everything else that was planned for G7 has moved to **G8** (list
> below), with every owner answer kept. The "Planning history" further down is the full question-by-question
> record; where it conflicts with the master scope, the master scope wins.

## Calls settled at approval (owner took the defaults)
1. Weather and day/night: **G8.**
2. After-action reports: **G8.** G7 only records the per-squad deployment data that the strike team's after-action
   review needs.
3. Armbands: **in G7, by shrinking the team-colour area on the existing human soldier sprites** to an armband or
   helmet band. Vehicles and zoomed-out icons keep the full team colour. The full human redraw stays in G8.
4. Creep eating wrecks ("eats the battlefield"): left in **G8** (section 7 asked; default kept).

# G7 MASTER SCOPE (approved 2026-10-26; complete merged version, includes brainstorm B1–B20 and the final studio-level brainstorm in section 13)

**Status:** approved, **on hold** until the owner gives the execution order after testing G6.

**G7 =** all Signalborne ports (drone piloting, soldier realism, squad tactics including rebuilt formations,
battlefield look) + the counter-nanite line (unlock, facility, strike team, operators, APCs, stealth dropship) + Last
Protocol + 8 new Human A turrets + upgraded VTOL dropships + the minimum Machine and base systems these need.
Everything else is G8 (see "G8 SCOPE" below). This section is the single authority for G7; the brainstorm answers and
planning history below are the record it was built from.

## 0. Ground rules
- **Simulation vs display.** Anything that changes outcomes runs in the simulation with same-inputs-same-result
  checks. Cameras, fog look, ground marks and animation never write to the simulation (the existing on/off hash check
  proves it).
- **Replays:** player drone flying is recorded as commands each simulation tick, so matches stay exactly repeatable.
- **Heavy features scale down in big fights:** shrapnel rays, gait choices, senses, formation spacing and convoy AI
  get budgets per sim detail level (`tiers.gd`): full detail in close fights, cheaper approximations with the same
  rules in huge fights.
- **Performance targets** (slowest 10% of frames): 2k units on screen at 60+ fps; 10k units zoomed out at 30+ fps;
  2k-unit simulation time no more than 1.2× G6.1.
- **Art:** upgraded pixel art from the existing generators, with team-colour masks. No 3D.
- **Process:** one packaged build, 6 agents at once, a light finish line (section 11).
- **Look checkpoint** before the full roll-out: strike team, both APCs, the facility, both dropship types; drone
  camera, grey fog, wound and crawl animation, armbands; a staggered column, a herringbone halt, 2 new turrets;
  packhunter, Weaver, living core.
- **Signalborne is inspiration only:** no names, logo or assets.

## 1. Signalborne A: drone piloting and the drone camera
- **Flyable drones:** recon (Human A's UAV and recon drones, Human B's recon drone, the G5 Drone Team's drones);
  strike (a new grenade or mortar-bomb munition on a recon airframe; limited drops, then it returns or crashes); FPV
  kamikaze (single-use, from the Drone Team or a new launcher).
- **Controls:** a hotkey opens a corner feed; a second key goes full-screen. The battle keeps running, with the minimap
  and alerts showing; B or Esc hands control back to the AI. Recon and strike: WASD flies, Q/E turns, the mouse wheel
  sets height (view range against how easy it is to spot), Space drops a munition (ballistic, with drift). FPV: the
  mouse aims, W/S sets speed, C detonates.
- **Feed:** greyscale or thermal (toggle; in thermal, soldiers and engines glow and cold terrain goes dark). Overlays:
  compass tape, heading, height, a dashed reticle with range, status prompts ("ARMED", "MUNITION AWAY", "RNG 20 M
  LIVE"). Noise grows with distance and jamming; "LINK LOST" plays on death, jamming or going out of range.
- **Simulation:** a real air unit with HP, battery and noise; enemy counter-drone, AA and jammers act on it normally
  (`counterdrone.gd`); munitions use `strikes.gd` with shrapnel. What it sees feeds your intel and your squads.
- **Art:** rotor blur, banking, release puffs, the FPV dive, distinct blasts for ground, soldiers, walls, roofs and air.

## 2. Signalborne B: soldier realism
- **Hit zones replace the infantry health bar.** Where a hit lands is weighted by posture, cover and the shooter's
  facing, using the simulation's repeatable random numbers.
  - Legs: slower movement; both legs hit means crawling only.
  - Arms: worse aim and slower reloads.
  - Torso: bleeding and a short knock-out.
  - Head: usually killed or knocked unconscious.
  - Each wound sets an out-of-action timer by where it landed; untreated bleeding leads to unconsciousness, then death.
  - UI: wound icons and a body diagram. Vehicles keep normal health.
- **Shrapnel:** a sampled fan of fragment rays (fewer in big fights). Walls and cover block them, so cover truly
  protects; each connecting ray causes a hit-zone wound; blasts make nearby soldiers flinch and pin them.
- **Casualty care, full chain:** (1) buddy aid slows bleeding; (2) the squad medic heals faster and stabilises; (3)
  soldiers drag casualties to cover; (4) stretcher teams, ambulances, APCs or helicopters evacuate them to the G5
  hospitals; (5) treated soldiers return and named soldiers keep their scars; (6) survival odds fall the longer a
  soldier waits.
- **Gait under fire:** each soldier weighs threat distance, route cover and suppression, then walks, crouch-walks,
  duck-runs or sprints; decided per squad on a schedule.
- **Backing off:** ordered fall-backs walk backwards facing the enemy and keep firing; only units whose morale has
  broken turn and run.
- **Visible panic:** cowering, freezing, fleeing, dropping weapons; G6.1 traits set the odds.
- **Realistic senses:** a view cone from the head (peripheral vision spots movement only); spotting by movement,
  silhouette and noise; gunfire heard with a direction; scopes narrow and lengthen the view; thermals and night vision
  see through smoke and darkness. All of it feeds `intel.gd`.

## 3. Signalborne C: squad tactics and formations
### Tactics
- **Bounding fire teams:** teams A and B cover and move in turns, slowing as contact nears.
- **Suppressive fire** on last-known positions or areas; soldiers know when they're exposed.
- **Hold and ambush:** ambushes hold fire until the kill zone, then break contact.
- **Assault** under covering fire; **break contact** with smoke, backing off and bounding to the rear.
- **Building clearing:** stack up, grenade first, room by room, fire from windows (`garrison.gd`); the roof cuts away
  while your troops are inside.
- **Grenades:** soldiers decide when to throw.
- **Per-squad knowledge:** each squad acts on what it saw, its radio net (G6.1 comms) and drones; squads cut off from
  the radio act on stale information.

### Formations rebuilt like a real military
All Human A and Human B units. G6.1's 8 types (line, wedge, column, box, echelon left/right, file, spread) are rebuilt,
not replaced.
- **Staggered column** on roads and tracks: two offset files, soldiers 5–10 m apart, vehicles 50 m+ apart,
  alternating sides, so one grenade, mine or missile can't hit several.
- **Wedge and diamond done right:** fire-team wedges inside a squad wedge or diamond, the leader at the front centre,
  the automatic rifle on the flank, real spacing.
- **Movement method picked automatically by threat:** traveling (contact unlikely), traveling overwatch (contact
  possible; a trailing element covers), bounding overwatch (contact expected).
- **Halts:** vehicles angle off alternately into a herringbone facing outward; longer halts form a 360° coil. Infantry
  form a 360° security ring.
- **Spacing by threat:** widens under artillery, drones or grenades; tightens in low visibility and close terrain.
  Never a clump.
- **Sectors of fire:** every soldier and vehicle watches its own sector (front, flanks, rear), moving and halted.
- **Terrain-aware shape:** follows roads, squeezes into file through gaps and reopens, hugs tree lines and walls,
  avoids open crossings, never walks through buildings or stacks.
- **Smooth reforming:** pivots around the leader, each soldier takes the nearest slot, nobody crosses through others.
- **Quality bar:** a formation that looks like a clump or a parade is a bug.

## 4. Signalborne D: battlefield look (display only)
- **Grey fog of war** showing what your units last saw; last-known enemy markers fade by age and confidence.
- **Ground marks:** blood, scorch, craters and debris linger up to a cap; bodies stay longer, also capped.
- **Explosions:** drifting brown dust columns, debris arcs, haze.
- **Armbands:** the team-colour area on human soldier sprites shrinks to an armband or helmet band; vehicles and
  zoomed-out icons keep full colour.

## 5. Animation needed by sections 1–4
- Posture and movement: smooth turning and speed changes, a planted foot when pivoting, posture transitions,
  crouch-walk, duck-run, firing while walking backwards.
- Hits: reactions by zone (stumble, limp, knock-back, blast knock-down), falls, unconscious, crawling.
- Care: buddy aid, medic treatment, dragging, stretcher carry.
- Combat poses: grenade throws, room entry, leaning and peeking, window fire, panic poses.
- Formations: smooth formation movement and reforming; vehicles angling into the herringbone.
- Drones: take-off, banking, release, dive.
- Checks: frame-name checks in the art tests; memory checked against the 10k fps target.

## 6. Counter-nanite line (Human A and Human B only; used only by you and your own AI Commanders)
### 6.1 Unlock
The last, very expensive research item. Prerequisites set in the plan (Stage 10 plus an EMP/EW line).

### 6.2 Counter-Nanite facility
A massive compound, built already gated and fortified. From the gate inward:
1. **Fortified outer gates and staging ground:** armoured gate and checkpoint, anti-vehicle barriers, crossfire, smoke
   cover while APCs form up.
2. **Decontamination zone:** APCs rinsed down before parking; soldiers walk an airport-security-style decontamination
   walkway (scan arches, spray, suit check); punctured suits cleared and repaired; mimics exposed.
3. **Central concrete loading area:** APCs pull out of their garages, load up and roll out through the gates.
4. **Garages for 5–8 APCs.**
5. **Helipad** fitted exactly to the stealth strike dropship.
6. **Overwatch drone bay:** a small garage and workbench.
7. **Mission planning room:** target, route, loadout, escorts, latest intel; AI missions use it too.
8. **Simulation range:** drills against Machine replicas that build team experience; only runs while the base is
   secure.
9. **Package lab:** a package production queue plus tier upgrades.
10. **Workshop and drone bay:** APC repair and upgrades; builds interceptor and defence drones.

- **Defences:** each side has a hardened tower with a remote weapon station, a counter-drone emitter, and interceptors
  against shells, rockets and drones; the perimeter has blast walls, a short-range EMP field and unhackable
  electronics.
- **If breached:** lockdown (blast doors seal the garages, lab and helipad; turrets pop out of the walls; the
  decontamination zone floods with counter-nanite mist); emergency evacuation of APCs and the dropship; backup power
  and self-repair.
- Training slows while the base isn't secure.

### 6.3 Strike packages and deployment
- **Loadout** chosen before each mission within each APC's capacity; no swapping in the field.
- **Package types:** standard purge (clears creep and seeds over an area, permanently); seed-hunter (tracks
  underground, kills dormant seeds over a wide radius); barrier (a permanent line creep can't cross); core-breaker
  (heavy, slow to arm; the only thing that finishes a doomsday core or a Machine HQ).
- **Deployment** (on the ground, by the strike team only): scanner technicians locate creep and seeds; EW specialists
  jam the local hive link; deployment specialists arm the packages under the shield dome; the ground is cleared
  permanently. Deaths or the dome failing stall it.
- **Holding the site:** the engineers decide by themselves where portable barriers (unfolded from the APCs) and
  unhackable sentry turrets go, and pack them up when leaving.
- **Hero detonation:** if a package can't arm in time, you can order one operator to stay and detonate it by hand:
  instant arming, certain death. The team gets a short window to pull out. The radio reads out the call sign, and the
  end screen lists them under "Remembered".

### 6.4 Strike team: 20 soldiers in 2 APCs
Two squads of 10, operating only as the full pair; they spawn inside their APCs and can get out or in at any time. One
team leader; if the leader falls, Squad A's second-in-command takes over.

| Role | Squad A | Squad B | Total |
|---|---|---|---|
| Team leader | 1 | 0 | 1 |
| Second-in-command / radio | 1 | 1 | 2 |
| Deployment specialist | 2 | 2 | 4 |
| Scanner technician | 1 | 1 | 2 |
| EW specialist | 1 | 1 | 2 |
| Security gunner (EMP grenades, anti-drone shotgun, limpets) | 3 | 4 | 7 |
| Combat medic / engineer | 1 | 1 | 2 |
| **Total** | **10** | **10** | **20** |

### 6.5 Strike-team APC: the most advanced human APC
- Larger than a regular APC: 10 soldiers plus packages (capacity set in the plan).
- **Unhackable:** immune to hacking, takeover, viruses and EMP.
- **Guns:** two manned .50 cals, front and rear, on rotating shielded mounts; gunners man them while moving and are
  replaced from inside if hit. **No main weapon.**
- **Pop-out micro rocket launcher (owner amendment 2026-10-26):** every counter-nanite APC (strike and tactical) gets a
  **pop-out 6-tube micro rocket launcher** on the roof, **top rear right, right behind the gunner pod**, outfitted with
  **up to 6 different round/canister types**. Its job: let the teams and convoys **put some hurt on heavy Machine walkers
  over time**; heavy walkers stay very difficult to take down, slightly easier with strong coordination and concentrated
  firepower. This amends "no main weapon": the launcher is a pop-out secondary, not a turret main gun. Proposed canister
  types (PROVISIONAL, the owner may change them): tandem anti-armour, EMP, thermite, HE-fragmentation,
  nanite-disruptor, smoke/obscurant.
- **Anti-walker pincer (owner addition 2026-10-26):** the counter-nanite teams/convoys take down heavy Machine walkers
  with "the right heavy strategic hit": one element **rushes the walker head-on** to fix it while others **flank it with
  heavy rounds** (launcher tandem anti-armour / EMP salvos, limpets, harpoons). Flank and rear hits on a walker fixed
  frontally do markedly more damage; a straight-on fight stays very hard. The group's AI chooses this pincer on its own
  against heavy walkers, and the player can trigger it with one order.
- **Tip them over and blow them up (owner addition 2026-10-26):** with the right approach, the head-on rush plus flanking
  heavy rounds **physically tips heavy Machine walkers over**, then the group blows them up. Leg hits from the flanks/rear
  while the walker is pinned frontally build up stagger; past a threshold it topples (can't move or aim for a window,
  belly and rear exposed) and hits in that window do heavy bonus damage. If the group fails, it rights itself. Straight-on
  fire builds almost no stagger. Art: the fall in the hit direction, lying exposed with legs flailing, getting back up,
  and a big destruction blast.
- **Defences:** a shield dome during deployment (recharge timer); active protection; an anti-drone laser or microwave
  emitter; a short-range EMP pulse that also knocks leeches off; side panels that pop open to fire interceptors,
  smoke and Anduril-style interceptor drones (fictional name in game); top-tier armour, chaff, a sealed cabin, a low
  heat signature.

### 6.6 Tactical operator squads
- 8 per squad, at most 3 deployed in normal matches; trained at the facility; spawn inside their own APC.
- Roles: leader; designated marksman (nanite-disruptor rounds); 2 hunter-killer assaulters (limpets, net and harpoon
  guns); EMP grenadier; anti-drone specialist (shotgun and jammer); purge and demolitions specialist (thermite and
  thermobaric charges); combat medic.
- Their APC holds 8, with one remote-operated rotating twin .50; same defences as the strike APC; plus the same
  pop-out 6-tube micro rocket launcher (owner amendment 2026-10-26).
- Job: escort, screen the flanks, clear ahead, hold the perimeter, cover the withdrawal.

### 6.7 Group movement (built on the section 3 formation system)
- **Motorcade convoy:** strike APCs in the centre; tactical APCs take the lead, the rear and the threatened flank. On
  contact the nearest tactical APC drives between the threat and the strike APCs. The convoy never stops in a kill
  zone: one squad peels off to hold a threat while the rest pushes through and regroups. Fixed spacing, everyone at the
  slowest vehicle's speed, roads where possible, a tighter column at chokepoints. One order moves everything; you can
  override any vehicle.
- **At a stop:** the operators set a perimeter before the strike team dismounts.
- **On foot:** soldiers stay on the hull's sheltered side with the APC at walking pace; APCs swing to block new
  threats; soldiers bound between cover while the .50s cover them; under heavy fire they remount under smoke and the
  dome.
- **Quality bar:** the most advanced human tactical force. If it ever moves or fights like ordinary units, that's a
  bug.

### 6.8 Suits and exposure
- Strike team and operators: sealed suits mean no risk unless punctured (a bullet, packhunter talons, a Weaver
  cocoon). Once punctured, exposure builds, hurting and slowing the soldier until decontaminated at the facility.
- Ordinary soldiers build exposure whenever they're on foot in creep.
- UI: a breached-suit icon and an exposure level on the soldier card.

### 6.9 Dropships and operation support
- **Stealth strike dropship** (counter-nanite only): stealth engines, no rotors, VTOL flight; lives on the facility
  helipad. **Internal cargo bay:** one vehicle up to strike-APC size plus its occupants plus one extra squad (e.g. a
  full strike APC with its 10 soldiers plus an 8-operator squad). With no vehicle loaded it carries 20–25 soldiers.
  During extraction it launches 5 defence drones (3 kamikaze, 2 machine-gun). Long cooldown; the landing zone must be
  held.
- **C-17-style loading (owner order 2026-10-26):** the stealth strike dropship loads like a C-17: a big rear cargo ramp
  lowers to the ground and the strike APC **drives in through the back** up the ramp (its squad walks in). Everything is
  **proportionate**: the dropship is enlarged so its bay visibly fits a strike APC plus a squad, and the facility helipad
  (and the facility if needed) is enlarged to fit the dropship.
- **Regular Human A VTOL Dropship (`a_vtol_dropship`), upgraded:** enlarged, with the same internal bay (one vehicle
  plus its occupants plus a squad, all inside); trained as now in normal matches.
- **Both dropships:** exfil, insertion, moving vehicles and squads between forward bases, relief runs. Animation: ramp
  lowers, vehicles drive in and out, the squad boards, the bay closes, the heavier aircraft settles on landing.
- **Overwatch drone:** circles the convoy and site, shares what it sees, warns of threats, can be flown; has its own
  bay.
- **Fire support on call:** the team leader calls artillery, rocket or air strikes from base on targets the team can
  see; limited calls per mission.
- **Relief convoy:** fresh operator squads or a reload APC sent from the facility.

### 6.10 Progression
- Named operators (name, call sign such as "Reaper 2-1", kill and purge record, wounds) and named teams (e.g. "Team
  Halcyon").
- Team experience levels from missions and drills (faster arming, tighter convoys, quicker dismounts); losing veterans
  costs levels.
- Specialist upgrade paths through the lab and workshop.

### 6.11 Operations UI
- **Operations panel:** every team's location and status, suit breaches, stock, dropship and drone status, jump-to.
- **Live deployment tracker:** arming progress, dome charge, time left, incoming forces.
- **Team cam:** overwatch feed or helmet cam, with call signs and radio subtitles.
- **Strategic overview map:** creep, seed nests, forward bases, relays, cores, countdown, routes.

### 6.12 Art and animation (the first units at the new detail level)
- New art: the facility (every area, build stages), both APCs (every facing, mounts, panels, dome, rear doors), both
  dropships, 20 strike soldiers and 8 operators with distinct kit, the packages, the counter-nanite spread effect.
- Animations: guns turning and recoiling, panels opening, drones launching; getting in and out, loading on the pad;
  the APC wash-down and the decontamination walkway; convoy turns; the deployment sequence; the hero detonation;
  dropship landing, loading and take-off.

## 7. Eight new Human A turrets (normal matches and Last Protocol)
In addition to the 9 existing Human A defences (Guard Tower, Wall Tower, ATGM Bunker, Pop-up Remote Turret, Laser CIWS,
SAM Site, Coastal Battery, Cruise Missile Battery, Radar Station):
1. **Heavy MG nest:** twin .50 behind sandbagged armour; against infantry, swarms and light walkers.
2. **Autocannon turret:** rotating 30 mm; against light vehicles, drones and packhunters.
3. **Hull-down tank turret:** 120 mm in a buried armoured casemate; the main anti-armour wall gun.
4. **Auto-mortar pit:** automated 120 mm firing over the walls; needs spotting from towers or drones.
5. **EMP projector:** stuns Machine units and drops drones at the wall; long recharge.
6. **Thermite flame turret:** burns creep, seeds and small Machine units on the approach; stops creep following a
   breach.
7. **Microwave anti-swarm turret:** fries swarms, micro-drones and leeches in a cone (soft-kill; complements the Laser
   CIWS).
8. **Rail cannon:** late game; extreme range and penetration against the biggest Machine units and the walking core;
   slow fire, heavy power draw.

Each gets every facing, build stages, a damaged state, traverse and recoil or beam animation, and muzzle and impact
effects. Stage gating set in the plan.

## 8. Machine systems G7 needs (current art; new units drawn in that style)
- **Creep and seeds:** creep spreads from Machine structures, powering and repairing what stands on it; dormant seeds
  and burrowed cores regrow it unless purged; counter-nanites clear ground permanently.
- **Minimum hacking and EMP:** Machine EW can jam or briefly take over normal human vehicles and drones; EMP stuns
  Machine units.
- **Doomsday cores and escalation phases.**
- **Learned reactions** (each with a "THE NETWORK HAS ADAPTED" alert): (1) after your first successful deployment it
  defends deployment sites; (2) after losing a set amount of creep it hunts strike teams (hunter packs, ambushes); (3)
  after a core or major structure falls it raids the facility; (4) late in the match it adapts to your routes and
  habits.
- **Threat units:**
  - **Burrowers:** erupt under convoys and inside deployment rings.
  - **Nanite spitters:** slugs that puncture suits.
  - **Mimic infiltrators:** look like friendly units until scanners or the decontamination walkway catch them.
  - **Packhunter walkers:** wolf and spider gait, clawed talons, packs of 4–6; flank convoys and tear into gunners and
    soldiers up close.
  - **Leeches:** latch onto APCs and physically wreck mounts, panels and the dome emitter; pried or shot off, or shaken
    off by the EMP.
  - **Weavers** (Last Protocol, only from 60–75% into the run): huge spider-mothers whose webbing slows vehicles and
    cocoons soldiers (counted as suit-breached) and hauls them to the creep. Any soldier can cut a cocoon slowly; the
    purge specialist and medic-engineers do it fast. A soldier dragged fully into the creep is lost.
- **Living cores:** they pulse, grow armour plating over time, and scream on your radio when hit. The last core's
  second phase: it tears itself out of the ground and walks; immobilise it with EMP, leg damage and barrier packages,
  then land core-breakers while the countdown runs.

## 9. Base systems G7 needs
- **Secure state:** secure, contested, under fire or breached, based on threats inside the perimeter and incoming
  fire. The state sets training speed.

## 10. Last Protocol (new game mode)
- **Skirmish lock (owner order 2026-10-26):** the Last Protocol map is completely inaccessible in skirmish mode; it
  only starts through Last Protocol.
- **Format:** strictly 1v1, you against the Machine at maximum difficulty; Human A only; its own main-menu entry with
  best-time and score records.
- **Map size (LOCKED by the owner, 2026-10-26): minimum 512×512 tiles**, 4× the area of today's largest map
  (256×256). Planning estimate behind it: the 3-ring base is about 140 tiles across (outer ring ~140, economy ring
  ~110, core ring ~70) around a Counter-Nanite facility of roughly 32×32 tiles (~220 m a side at ~7 m per tile).
- **Map:** a massive hand-built map, the largest in the game: urban areas, forest, tunnels, rivers for firebreaks,
  dead zones; **forward bases** you can retake (refuel, rearm and repair convoys; the Machine counterattacks them);
  **seed nests** that feed regrowth until cleared; **scanner relays** engineers repair to reveal creep and Machine
  movement; **3 doomsday core zones**.
- **Your base: three walled rings, fully pre-built.**
  - Outer ring, defence: walls, towers, bunkers, defending vehicles, stocked with the 8 new turret types alongside the
    existing defences.
  - Middle ring, economy.
  - Core ring, military: the airfield with **2 regular VTOL dropships**, artillery parks (out-ranging the outer wall),
    Company HQ, and the massive Counter-Nanite facility at the centre with the **stealth strike dropship** on its
    helipad.
  - Also: every Human A building; layered defences and air defence; jets, helicopters, drones and transports; infantry
    companies, armour, artillery, engineers, recon and logistics; hospitals, the exo-suit garage, power and research;
    armies organised under a chain of command. The base starts secure.
- **Main army, strict defence:** every non-counter-nanite unit mans turrets, towers, walls and vehicles, run by a
  defence AI Commander (moves reserves, rotates crews, sets repair priorities) that you can override. Leaving the walls
  is allowed but punished (exposure, no repairs, packhunters).
- **Air force:** defends base airspace; flies out only as fire support on call.
- **Breaches:** defenders fall back to the next ring and the gates seal behind them; income drops while Machine forces
  are in the economy ring; engineers rebuild walls and towers; creep follows the breach unless purged, burned by
  thermite turrets, or sealed with barrier packages.
- **Counter-nanite force:** the facility starts full: 2 strike teams and 4 tactical squads (8 APCs) plus the stealth
  dropship; normal caps are lifted.
- **Lose (any one):** (1) the creep meter reaches critical; (2) the doomsday countdown reaches zero (creep spread
  speeds it up); (3) the facility falls with no teams left in the field.
- **Win:** destroy all 3 cores (including the walking last core) **and** push creep below the threshold. Each core
  destroyed slows the countdown.
- **Run shape:** early, the Machine is entrenched (retake forward bases and relays, first purges); middle, escalation
  phases, faster creep, Stage 10 units, learned reactions unlocking; at 60–75%, Weavers arrive; **finale, THE TIDE**:
  triggered when the last core enters its second phase or the countdown reaches its final stage, the creep surges
  toward your base in one wave with every Machine unit it has left, the defence AI Commander goes to maximum posture,
  and you hold all three rings while strike teams chase the walking core.
- **Length:** 60–90 minutes. **Economy:** full, under heavy pressure; strike teams are slow and expensive to replace.
- **Presentation:** radio and command voice (briefings, call-sign chatter, core status, cores screaming, countdown
  warnings, adaptation alerts); end-of-run screen with time, creep purged, cores destroyed, teams lost and
  extractions, bronze/silver/gold medals, personal bests, and the "Remembered" list.
- **Set in the plan:** creep thresholds, the countdown and modifiers, phase timings (Weaver window, Tide trigger), the
  score formula, the map and ring layout, starting army sizes (within the fps targets).

## 11. Finish line (light)
You check by playing: look, feel, balance, the formation and strike-team quality bars, every feature, plus the look
checkpoint. Automated checks only cover:
1. The existing tests stay green, 0 SCRIPT ERROR.
2. Every new simulation system is same-inputs-same-result, including recorded drone flights.
3. FPS: 2k on screen p10 ≥ 60, 10k zoomed out p10 ≥ 30; 2k-unit sim time ≤ 1.2× G6.1.
4. Last Protocol: headless and AI-vs-AI soaks with 0 crashes and 0 invariant failures, including a full run on the
   massive map with the full base that reaches the Tide finale.
5. The packaged build launches from an empty folder with 0 SCRIPT ERROR.

## 12. Risks
- Last Protocol load: a 512×512+ map (4× today's largest; pathing, fog, creep and render costs must be proven early), a full 3-ring base stocked with turrets, 8 APCs, 3 dropships, the Tide and a
  walking boss at once. The heaviest scene the game has run; tune to the fps targets from day one.
- New AI: formations, convoys, moving cover, engineer site choices, Weaver hauling, the walking core's pathfinding.
- Simulation cost: hit zones, shrapnel, senses, exposure, formation spacing.
- Sprite memory: many large new units, 8 turrets, the facility and two dropship types.

## 13. Studio-level additions (final brainstorm, 2026-10-26, Q1–Q15)
Owner's brief: "high-level, outside the box, what a major game studio might add". Picks below are G7 scope.

### 13.1 Story and lore (Last Protocol)
- **In-engine opening cinematic** (60–90 s, built with the game's own engine): the first creep outbreak, the network
  waking, the order to activate Last Protocol, then the camera sweeps over the 3-ring base and hands you control.
- **Lore intel files:** recovered logs, black boxes and transmissions found across the map (forward bases, relays, seed
  nests, secret sites) that slowly reveal where the Machine came from and why the world is ending. Collected files
  stay readable in a codex.

### 13.2 Adaptive music
Layered score that reacts live: calm ambient while planning; tension layers as the countdown advances and convoys
roll; combat drums in firefights; a dedicated **Tide theme** for the finale; and **sudden silence just before the Tide
hits**.

### 13.3 Map set pieces (systemic levers on the massive map)
- **Blow the dam:** a strike team sabotages a dam to flood a valley, drowning creep and Machine forces and turning the
  river into a permanent firebreak, at the cost of one of your own convoy routes.
- **Bridge demolitions:** engineers rig key bridges; dropping one stops a Machine push (or the walking core) across a
  river but forces your convoys to detour.
- **Old power grid:** reconnect a derelict power station to feed the base and facility extra power (faster training
  and lab output), if you can hold it against the Machine.

### 13.4 Operators who feel alive
- **Voice barks by personality:** each operator has a voice and a personality (calm veteran, nervous rookie, joker,
  hardliner) that colours their radio barks under fire, when wounded, on kills and on hero detonations.
- **Bonds inside the team:** operators who survive missions together react to each other: they call out a buddy's
  wound, drag specific friends, and take morale hits when a close teammate dies.
- **Signature skills:** each named operator rolls one small signature skill (faster cocoon cutting, steadier gunner,
  quicker scanner sweep) shown on their card, so losing them hurts.

### 13.5 Endings
- **Total purge ending:** win and also purge every seed nest and nearly all creep: a special "world saved" ending with
  its own cinematic and a top-tier medal.
- **Pyrrhic victory:** win but lose most teams or a base ring: the ending shows the cost, with the "Remembered" list
  rolling over a darker epilogue.
- **Capture a core (secret alternate win):** instead of destroying the last core, subdue it (EMP-locked and contained
  by barrier packages) and capture it for study, unlocking a hidden ending. Its full story is revealed by the Machine
  origin site (13.8).
- **Defeat endings:** each way of losing has its own short cinematic (the creep swallowing the map, the countdown
  hitting zero, the facility falling).

### 13.6 Command screens: in-world presentation
- **Military command-tablet style:** the operations panel, live deployment tracker and strategic overview map are
  styled as rugged in-world military displays (scan lines, unit icons, map projections), matching the drone feed.
- **Holographic war table in the facility:** the mission planning room becomes a 3D-looking holographic table you can
  rotate and tilt, showing terrain height, creep, cores and planned routes.

### 13.7 Facility AI advisor ("PROTOCOL")
A voiced facility AI that flags opportunities and dangers ("Seed nest exposed at grid D4", "Convoy route crosses
packhunter territory", "Core 2 plating at 60%"). It suggests and never acts; it can be muted or turned off.

### 13.8 Secrets on the massive map (4)
- **Prototype weapon cache:** a hidden black-site bunker; a strike team that reaches and cracks it gets a one-off
  prototype (e.g. an orbital-strike designator or an experimental mega counter-nanite charge).
- **Lost squad rescue:** a trapped squad broadcasting faintly from deep in the creep; rescue them by dropship for a
  bonus team of veteran operators.
- **Machine origin site:** a hidden location tied to the lore files that reveals where the Machine began; reaching it
  unlocks the capture-a-core ending's full story.
- **Dormant human mech:** a buried pre-war prototype walker in an overgrown factory; engineers reactivate it as a
  one-of-a-kind heavy unit that fights alongside the strike teams.

### 13.9 A world that reacts to the spread (owner: "super realism breadth and depth")
- **Creep-warped terrain:** where creep sits long enough the land visibly changes: trees calcify into metal lattices,
  rivers darken, buildings sprout nanite growths. Purged ground slowly recovers its colour, so the map shows the state
  of the war at a glance.
- **Sky and light shift:** as the creep meter climbs, the sky darkens, light turns colder and haze settles; purging
  pushes it back. The mood of the whole map tracks how close the world is to ending.
- **Wildlife and civilian traces:** fleeing animals, abandoned vehicles, empty camps and distress beacons fill the
  map and react to fighting and creep.
- All of it is display-side (or derived from the creep state), within the fps targets, at full realism depth.

### 13.9a Creep fissures, canyons and growths (owner amendment, 2026-10-26: "add it in rn")
Owner: "the creep should open up large fissures/valleys/canyons in the ground with varying different complex
'growths' sprouting and rising from the creep and the fissures/openings."
- **The ground breaks open:** where creep has sat long and dense, the land splits. Thin cracks open first, widen
  into fissures, and the oldest creep tears open into long branching valleys and canyons with a glowing nanite floor.
  They are real terrain, not paint: cracks slow ground units, fissures block vehicles (infantry climb across slowly),
  canyons block all ground movement until bridged, so the creep reshapes the map's routes as it spreads. Air is
  unaffected.
- **Growths rise from the creep and out of the openings:** many different complex shapes (spires, crystal
  lattices, tendril stalks, rib arches, pulsing pods, antenna masts and others), rising slowly out of the creep
  and the fissures, bigger and denser in the canyons. The largest growths are destructible targets that feed the
  spread and the cracking around them; the rest are scenery.
- **Fighting it:** purging, burning or sealing stops a fissure growing and kills its growths; engineers can lay a
  span across a fissure or canyon; purged ground scars over and, held long enough, closes back to rough
  ground, so the map is never permanently cut. Fissures never open under buildings, walls, bridges or sterile and
  barrier ground. They can never cut a player's base off from the map.
- Numbers are PROVISIONAL (set by FISSURE7, reported). A match with no creep stays hash-identical; perf stays
  inside the fps targets on the 512 map.

### 13.9b Base layout that makes logistical sense (owner amendment, 2026-10-27)
Owner: "base has too many open spaces and dont need all that extra space -- make it make more logistical sense - the
layout -- the spacing -- roads -- lighting, camers, auto turrets, etc ** also fix the spacing inside the
counter-nanite facility".
- **Compact, purposeful layout:** the Last Protocol 3-ring base (and any pre-built base) loses its dead open ground.
  Rings sized to what they hold; buildings grouped by function (power and logistics together, production near the
  gates it feeds, the airfield and helipads with their fuel and repair, artillery parks with ammunition, barracks near
  the walls they man); short, sensible distances between the things that work together.
- **Roads:** a real road network: main roads from every gate to the core, ring roads behind each wall for moving
  reserves, service roads to every plot, the airfield and the facility; vehicles use them.
- **Lighting:** floodlights on walls and gates, street lights along roads, lit pads and aprons (display; costs no
  sim time).
- **Cameras and sensors:** security cameras on walls, gates and key buildings that watch their sector (real sight for
  the base) and towers / masts where they make sense.
- **Auto turrets:** automated turrets (pop-up turrets, the G7 turret line) covering gates, wall corners and approaches,
  placed where their fields of fire make sense.
- **Counter-nanite facility interior:** the compound's zones (gate, staging, decon, pad, helipad, drone bay, range,
  workshop, garages) packed tightly in the order a team actually moves through them (gate -> decon -> staging ->
  garages -> pad / helipad), with roads between them and no empty yard; applies to the facility in normal matches too.
- Numbers PROVISIONAL (BASE7). Perf targets on the 512 map still hold.

### 13.9c Base and facility, second pass: a fortress laid out for this fight (owner amendment, 2026-10-27)
Owner: "buildings inside counter nanite facility are flickering during gameplay // the walls for the facility need to
link together fix that issues -- base defenses howitzers, turretcs, etc need to be evenly distrubeted around the base as
necessary ----- the air field on base needs more space so the runway isnt under the wall + the landing sites for the
regular drop ships need to be enhance, upgraded, and made bigger to fit the new size of the dropship -------- what else
needs to be resized to properly match the new sizez, pixels??? *** base should preload with units that patrol the outer
inner wall --- better security + more cameras + better layout for the counter nanite strike facility (the size is about
right) make things more prportionate and make more millitary realism sense for how our facility + entire base would
ACTUALLY be laid out for a batle of this intensity and depth ----(research actuallbase building as necessary and take the
most mercilous and defensible positioning and base setup stance as necessary --- get it done right --- ask me questions
as necesssary *** a few interor buildings at the counter nanite facility dont make sense or arent fully
edited/updated/finalized/given true art"
- **Bugs:** facility buildings flicker in play (fix the cause); facility walls join into one continuous wall (corners,
  T-joins, gates), no gaps or overlaps.
- **Defences:** howitzers, turrets, auto turrets, AA and the rest spread around the whole perimeter by threat axis:
  interlocking fields of fire, no blind sector, artillery covering every approach, nothing bunched on one side.
- **Airfield:** room for the full runway and its clear zones inside the walls (no runway under a wall); aprons, taxiways.
- **Dropship landing sites:** regular (and stealth) dropship pads rebuilt bigger for the current dropship size: pad,
  markings, lighting, approach lane.
- **Scale audit:** list everything whose size no longer matches the new unit / vehicle / dropship scale and fix it
  (pads, garages, doors, bays, roads, gates, props).
- **Garrison:** the base starts with units that patrol the outer and inner walls (routes along the walls, real AI
  patrols), plus guards at gates; more cameras; better security (entry control at gates, layered rings).
- **Doctrine:** lay the base and the facility out the way a real fortified base would be for a siege of this intensity:
  defence in depth, standoff from the walls, entry control points, dispersal and hardening of high-value targets,
  protected ammunition storage away from barracks, kill zones on the approaches, the most merciless, defensible
  setup. Research real base / FOB / airbase design and cite what you used.
- **Counter-nanite facility:** about the right size; make it proportionate and militarily sensible; every interior
  building finished with true art and a purpose that makes sense.
- Numbers PROVISIONAL (BASE7-2 / ART7F). Perf and every Last Protocol / facility test still hold.

#### 13.9c-2 Facility entry and no overlaps (owner note, 2026-10-27)
Owner: "ensure for the counter-manure facility and all of its building — should be no overlap or conflict with the
layout amongst buildings, garages, the main stealth launchpads, desanitization cleaning hall for infantry, cleaning
entry for apcs right inside first layer of enforced gates (2 layer entry for apcs to get desanitzed in that entry zone),
training facilities, etc." ("counter-manure" = the counter-nanite facility.)
- **No overlap, no conflict:** every facility building, garage, stealth launch pad, the infantry decon hall, the APC
  decon entry and the training facilities have their own footprint and clearance; no footprint, door or lane overlaps
  another; a test checks it.
- **Two-layer reinforced entry for APCs:** outer reinforced gate -> APC decontamination wash zone -> inner reinforced
  gate. APCs are decontaminated inside the entry zone between the two gate layers.
- **Infantry decontamination hall:** its own cleaning hall on the infantry path.
- **Main stealth launch pads** and **training facilities** have clear places of their own.

#### 13.9c-3 Facility defences (owner note, 2026-10-27)
Owner: "the counter nanite facility needs better defenses - more hardened towers — better hardened walls that all
connect + sorround the towers and don't leave them unsecured".
- More hardened towers around the facility (corners, gates, along long wall runs) with real fields of fire.
- Hardened walls that join into one closed ring and wrap every tower: each tower sits inside / within the wall line,
  tied into it on both sides, never standing outside the wall or in a gap; no unsecured tower, no wall gap.
- A test checks the ring is closed and every tower is wall-joined.

#### 13.9c-4 More towers, wall sentry turrets, walkable walls (owner note, 2026-10-27)
Owner: "add 4 more of those large towers to the counter nanite faculty plus add smaller sentry turrets faced outworda
along the walls — + walls of facility need to be walkable for your units".
- **4 more large hardened towers** on the facility wall ring (on top of the ones already placed), tied into the wall.
- **Smaller sentry turrets along the walls**, facing outward, spaced along every wall run (real sentry turrets that
  fire at enemies outside; they belong to the facility owner).
- **Walkable walls:** the facility's own infantry can climb onto and walk along the wall top (a wall-walk): own foot
  units path along wall cells (enemies still blocked), stand on the wall with a height / cover bonus, and are drawn on
  top of the wall at the right depth. Access from inside the compound (stairs / at towers).

#### 13.9c-5 No resources inside the facility (owner note, 2026-10-27)
Owner: "NO ores, salv, etc should be found inside nanite facility at ALL". No ore, salvage or any other resource
deposit / node / pickup inside the counter-nanite facility compound (every map, every match); the site is cleared of
them along with terrain and props. A test checks it.

#### 13.9c-6 Missing facility buildings (owner choice, 2026-10-27)
Owner asked "is there any buildings we're might be missing inside the counter nanite facility?? Maybe an Ammo depot for
specialized rounds ... don't necessarily want to make the facility much bigger if we don't have to" and chose all of:
**special ammo magazine** (hardened, earth-covered bunker for counter-nanite rounds: disruptor charges, limpets,
harpoons, rocket-pod reloads; far corner, away from the ops room, blast walls), **armory + suit bay** (weapons issue,
hazmat/CBRN suit fitting, suit-breach repair; on the infantry path between the decon hall and staging), **aid station**
(triage + nanite-exposure treatment, attached to the infantry decon hall), **fuel/rearm point + ready room** (hot
refuel/rearm at the dropship pads and garages, alert-team ready room, backup generator), and asked "Anything else?".
ORCH added, folded into existing pieces (no new ground): a contaminated-runoff tank at the APC wash, a quarantine bay in
the aid station, a comms / EW mast on the ops building. Keep the compound about the same size (grow at most 2 tiles a
side only if it cannot fit). Each building has a real purpose in the sim where cheap (magazine = the teams' special
ammo resupply point and a priority target; armory/suit bay = suit repair; aid station = treats exposure/wounds; fuel
point = refuels/rearms dropships and APCs), finished art at the approved detail level, and the no-overlap rules.

#### 13.9c-7 A living facility: activity, atmosphere, sequences, detail (owner choice, 2026-10-27)
Owner: "any other small details that could add great depth, visuals, animations to our facility?? ask questions as
necessary for scope and my answers get directly implimented". Chosen (all options, plus "More fucking phenomenal depth"):
- **Activity:** staff moving around (technicians and guards on real routes, gate guards checking arrivals, a guard dog
  on the inner wall); vehicles at work (forklifts carrying ammo crates magazine -> APCs / pads, a fuel truck servicing
  the pads, a tow tractor moving dropships); training on the range (drills, pop-up targets, kill-house lights during
  live fire); drones and hangar doors (a perimeter drone circling, drone-bay and garage doors rolling open / shut).
- **Atmosphere:** alarm state (attack / lockdown: red rotating beacons, flashing wall lights, tower searchlights
  sweeping, blast doors closing); night lighting (floodlight pools, blinking pad / runway edge lights, lit windows,
  light spilling from open garages); smoke, steam, mist (generator exhaust, steaming vents, drifting decon mist,
  windsock and flags in the wind); wear and ground detail (tyre tracks and wet asphalt after the wash, oil stains on
  pads, hazard stripes, unit insignia and numbers on garages).
- **Mission sequences on screen:** launch (alarm, crews run to the APCs, garages open, APCs roll up the ramp, ramp
  closes, rotor spool-up with dust, take-off); return + decon (dropship lands, APCs through the wash with spray, crews
  walk the decon hall and come out clean); casualty flow (medics carry stretchers pad -> aid station, quarantine-bay
  lights for exposed soldiers); resupply flow (ammo carts load the APC rocket pods and special rounds before launch).
- **Building detail:** damage states (cracks, fires, smoke, ruins); moving parts (radar dish, blinking comms-mast
  lights, glowing ops screens, tower cupolas tracking targets); ops-room activity (staff at screens, a map table showing
  live strike-team positions); signage and markings (building signs, lane arrows, gate numbers, warning boards).
- **More depth:** each agent adds further touches of its own in the same spirit and lists them.
All display-only (state hash identical with it on / off), fps gates hold, follows the approved art detail level.

#### 13.9c-8 Inner APC gate turned; a hardened foot entry (owner note, 2026-10-27)
Owner: "honestly almpst everyting is perfect on this base --- one sugeestion: the first level (decontamination zone for
apcs is perfect ; BUT that big sideways blocky section seems to cut off where the apcs come out of the (decontamination
zone) ?? maybe turn it and redesign it so it makes more sense?? ... + the entry point on foot is MUCH to unguarded and
not even fortified -- redesign that entry/decontamination point for ground units on foot WAY better -- more secure is
the key."
- **Keep** the outer APC gate and the APC wash exactly as they are (the owner: "perfect").
- **Inner APC gate:** the block after the wash stands sideways across the APC lane, so it reads as cutting off the exit.
  Turn it to the same orientation as the outer gate (its opening on the APC travel axis, the APC visibly drives
  straight out of the wash through it) and redesign it to match the outer gate as the second reinforced layer.
- **Foot entry:** replace the small booth + barrier arm with a fortified pedestrian entry control point built into the
  wall line: a hardened gatehouse, a serpentine / blast-walled approach outside, a two-door mantrap (airlock: only one
  door open at a time), an ID / scan station, a guard bunker with firing ports covering the approach, overwatch from the
  flanking towers, then the infantry decon hall, then a reinforced inner door into the compound. Lockdown seals every
  door. It must look and play secure (the defenders fight from it; attackers cannot walk straight in).

#### 13.9c-9 Unmanned wall turrets; an enclosed APC wash (owner note, 2026-10-27)
Owner: "all of the new manned sentry guns you added around the facility are wrong: i need unmaned AI turrets attached to
the sides of some of the walls (can be selected and destroyed + rebought and placed elswhere along the outer or inner
walls of facility only) ** ALSO + the wash/decontam zone for apcs is perfect just add outer walls so thats a secure zone
to wsah apcs off securely before entering ; second inner gate that will match the design and thickness walls as the
outer gate - is linked together with that new 'link' wall same thickness at each gate to sorround the apc wash zone".
- **Remove** the manned sentry nests (a_t7_hmg_nest) from the facility.
- **Wall turrets:** unmanned AI turrets mounted on the face of the facility walls (some walls, outer and inner faces),
  facing out from the face they hang on. Each is a real entity: selectable, can be destroyed, can be bought again and
  placed, but ONLY on an outer or inner face of a facility wall segment (placement rule; no other spot). The facility
  starts with a sensible set of them.
- **Enclosed APC wash:** the wash itself stays as it is ("perfect"). Add walls on both sides of the wash so it is a
  closed, secure zone: outer gate -> wash -> inner gate, the inner gate redesigned to match the outer gate's design and
  wall thickness (supersedes the "turn it" part of 13.9c-8), and new "link" walls of the same thickness joining each
  gate on both sides, surrounding the wash zone.

#### 13.9c-10 Sentinels: the facility's own guard force (owner note, 2026-10-27)
Owner: "all of the hardend towers sorrounding the facility should be able to hold up to 4 specialized NEW units only
available from the right building that trains /houses these units (that building must be able to garrison up to a
company of these units at any given time) ; these new units are specialized near hybrid human sentry guards - think slim
nanotech self heal armour with specialized weapons from the facility of course (up to 7 different types specialty units
within this unit structure - but NO command strucure just capabilites and weapons types *youre in charge* or your ai
commander obviously) --- they man the walls (the guards youre animating in for the walls) as well as the interior or the
facility on patrol + they can garrision at the infantry walk in new designed booth/scan point (max 15 in that one) //
they are very strong and incredible on defense againts humans AND machine --- dont make them invincible thouhg..."
ORCH decisions (owner: "youre in charge"; all numbers PROVISIONAL):
- **Sentinels** (Human A and Human B variants): near-hybrid human sentry guards, slim nanotech armour that self-heals
  (regenerates out of combat; stops while under fire / suppressed / EMP'd), weapons from the facility. No officers, no
  squads-with-leaders: each is commanded directly (or by the AI commander). Seven types:
  1. **Sentinel Warden** - disruptor carbine (anti-personnel + anti-nanite), the line guard.
  2. **Sentinel Marksman** - long disruptor rifle, thermal optics; tower / wall overwatch.
  3. **Sentinel Gunner** - rotary disruptor gun; suppression, kills Machine swarms.
  4. **Sentinel Bulwark** - nanoweave shield + breaching shotgun; holds doors, gates and the mantrap.
  5. **Sentinel Lancer** - harpoon / limpet launcher; anti-walker and anti-vehicle.
  6. **Sentinel Arc** - EMP / EW specialist; EMP grenades, drone and Machine-link jamming.
  7. **Sentinel Mender** - nanite field kit; heals Sentinels and repairs walls, towers and wall turrets.
- **Sentinel Barracks** (the "ready room" of 13.9c-6 becomes this): the only building that trains them; houses
  (garrisons) up to a company, 120 Sentinels. Inside the facility.
- **Garrisons:** every hardened facility tower holds up to 4 Sentinels (Sentinels only); the new foot entry
  booth / scan point holds up to 15 (Sentinels only).
- **Duties:** they man the facility walls (wall-walk) and patrol the interior: the wall guards LIFE7 animates become
  these real units. The facility starts with a Sentinel garrison (walls, towers, entry, interior patrol).
- **Strength:** very strong on defence against humans AND the Machine: a defence bonus inside / on the facility
  (walls, towers, garrisons) and resistance to nanite exposure; NOT invincible: expensive, slow to train, high pop
  cost, weaker away from the facility (bonus only inside its radius), EMP-vulnerable armour (self-heal stops), and
  anti-armour / artillery still kill them.

#### 13.9c-11 Sentinel coordination, ammo, bearers and facility engineers (owner note + choice, 2026-10-27)
Owner: "give these new specialzied facility guard units better coordination, structure, organization, patrol
capabilites, tactical efficiency and profficiency capabailites, etc ** when their main weapon is empty they switch to
secondary pistol or something and when THAT is empty they have to go grab more ammo (idk from where yet.. ideas?) and
then reload (dont do too much with their reload animation)". Asked where ammo comes from, the owner chose: "Ready-ammo
lockers" and "new ammo bearer unit for this specialized unit -- + we need to add an additional unit that act as
engineers fixing things automatically around the base or assisting in reloading lockers and working forklifts, filling
up gas in apcs and stealth dropship".
ORCH decisions (still no officers / chain of command, per 13.9c-10; numbers PROVISIONAL):
- **Watch structure:** Sentinels work in buddy pairs (two-man teams that move and fight together; one reloads while the
  other covers), each pair assigned a post or sector (a wall run, a tower, the entry, an interior zone) on a duty roster
  (on post / patrol / rest in the barracks, rotating). A facility guard net shares targets seen by any Sentinel, tower,
  camera or wall turret with every Sentinel.
- **Alarm drill:** on attack every off-duty Sentinel runs to a pre-assigned stand-to position; a quick reaction force
  (6-8 from the barracks) goes to any breach; pairs bound along the wall-walk to reinforce the threatened face.
- **Patrols:** deterministic routes with varied timing and direction that cover the cameras' blind spots, inner wall,
  interior lanes and the entry; patrols check in at posts.
- **Tactical proficiency:** use cover and firing slits, prefer elevated positions, focus fire on the biggest threat,
  pull back wounded pairs to the Mender, hold doors with Bulwarks, Lancers prioritise walkers/vehicles, Arc prioritises
  drones and Machine links.
- **Ammo:** primary empty -> switch to a sidearm (machine pistol); sidearm empty -> run to the nearest stocked
  **ready-ammo locker** (armoured lockers at every tower base, at the wall-walk stairs and in the entry booth), take ammo,
  reload (simple, short reload animation), return to post. Lockers hold a limited stock and run dry.
- **Sentinel Ammo Bearer** (new unit, trained at the Sentinel Barracks): carries ammo to Sentinels on post (restocks
  them where they stand, like the G6.1 ammo bearer) and refills lockers.
- **Facility Engineer** (new unit, trained at the facility; no weapons beyond a pistol): automatically repairs damaged
  walls, towers, wall turrets and buildings; refills ready-ammo lockers from the special ammo magazine (driving a
  forklift); refuels APCs and the stealth / VTOL dropships at the fuel point and pads. The forklifts and fuel truck LIFE7
  animates are driven by these engineers when they do these jobs.

### 13.9d Last Protocol has no population cap (owner note, 2026-10-27)
Owner: "for this endgoal protocol mode dont put a cap on the unit/population at all". In Last Protocol every side's
supply cap is unlimited (Economy floor UNCAPPED); the HUD shows "POP n (NO CAP)". Skirmish keeps its caps.

#### 13.9c-12 Facility staff run themselves (owner note, 2026-10-27)
Owner: "factility engineer, sentinel ammo bearer, sentinel(s) ALL work automatically without need for player to
position, move them, make them go to walls, nothing - they each have their own mind in a minor sense and coordinate max
efficiency and accurately within their facility roles, jobs, current state, etc- EVERYTHING".
- Sentinels, Sentinel Ammo Bearers and Facility Engineers are fully autonomous from the moment they exist: they take
  posts, patrols, roster shifts, stand-to positions, garrisons, resupply runs, locker refills, repairs and refuelling on
  their own, with no player orders needed. Each unit picks its next job from its role and its own state (ammo, health,
  fatigue, exposure, distance, what is already covered) and the facility's state (threat, damage, empty lockers, low
  stock, APCs / dropships needing fuel), through one shared facility job board so they coordinate (no two take the same
  job; the most urgent job gets the nearest fit unit; re-planned every few seconds, staggered).
- A newly trained one walks out of its building and joins the roster by itself.
- The player MAY still give an order (player control first, G7 rule); a hand-ordered unit returns to automatic duty when
  its order completes or after a short timeout. The AI commander's side uses the same automation.

#### 13.9c-13 Sentinels: realism and expert tactics, no gimmicks (owner note, 2026-10-27)
Owner: "sentinels coordination, movement, animation, everything should be very based in realism and expert tactical
depth no gimmicks". Sentinel behaviour follows real infantry / security-force practice: buddy-team bounding and
covering, cutting the pie at corners and doors, moving along walls and between hard cover, never standing in the open
or skylined on a wall without a parapet, sector-of-fire discipline, interlocking fields of fire from the posts, ammo
discipline (aimed fire, reload behind cover with the buddy covering, communicate "reloading"), casualty drill (buddy
drags the wounded to cover, Mender comes forward), withdrawal by bounds, no instant turns or teleport-like moves,
believable gait (walk on patrol, rush under fire, crouch in cover), animation matched to the action (aim, fire, reload,
crouch, drag). Numbers and effects stay grounded: no glowing super-moves, no superhuman speed or accuracy; their
strength comes from armour, training and position.

#### 13.9c-14 Taller signature buildings and a new gunship (owner note, 2026-10-27)
Owner: "make the training facility 2 stories ALL indoor high tech cqb and other type training + an outdoor
rifle/explosive testing range next door --- barracks need to be at minim a 3 story builfing high tech design and
secured/hardned with a roofttop landing pad for a stealth apache style but supermodernized and futuristic tech 'rotorless
design' (NEW AIR VEHICLE designed specifically for the couter nanite team(s)) super mission adaptable can equip with
drone launchers/missles/machine guns/antidrone tech/advance flares/detterents/etc ) /// fix the floating "RED LIGHT"
warning lights placement so its realistically placed and not hovering at all /// /command center for facility should be
a 4 story beautiful futurisct tactical buildign ??"
- **Training facility:** a 2-storey, fully indoor, high-tech training building (CQB shoot house floors, simulators,
  other training), plus an outdoor rifle / explosives testing range right next to it (replaces today's open range +
  kill house).
- **Sentinel barracks:** at least 3 storeys, high-tech, secured and hardened, with a rooftop landing pad for the new
  gunship.
- **New air vehicle (counter-nanite teams only):** a stealth attack gunship in the role of an attack helicopter, but a
  futuristic ROTORLESS design (e.g. ducted / vectored fans or thrusters, faceted stealth hull); mission-adaptable
  loadouts chosen per sortie: drone launchers, missiles, machine guns / cannon, anti-drone systems, advanced flares and
  deterrents. Based on the barracks rooftop pad (rearm / refuel there). Name and numbers PROVISIONAL (ORCH: "CN Vanta").
- **Command centre:** the facility's ops / planning building becomes a 4-storey, striking futuristic tactical
  building (the facility's tallest), still on its current ground footprint unless it cannot fit.
- **Red warning lights:** the alarm beacons / red lights must sit on real fixtures (parapets, posts, walls, roofs);
  nothing hovers.
- Taller buildings keep their footprints where possible (the owner does not want the facility much bigger); depth,
  occlusion and every display layer (LIFE7 / ATMO7 / SEQ7 heights) updated to the new heights.

#### 13.9c-15 CN Vanta hardpoints (owner note, 2026-10-27)
Owner: "CN vanta should be able to be outfitted with weapons/atachment as discussed on the sides/rear/and main front nose
of the airvehicle". The Vanta has hardpoints on the front nose (main), both sides (stub wings / side bays) and the rear;
each hardpoint takes a weapon or attachment from the 13.9c-14 list (drone launcher, missiles, machine gun / cannon,
anti-drone suite, advanced flares, deterrents), chosen per sortie, each visible on the art at its mount and firing
from it (nose gun / missiles forward arc, side mounts their sides, rear mount covers the tail: flares / deterrents /
anti-drone / rear gun).

Owner follow-up (2026-10-27): "if you place any attachments on one side its also added to the other side (takes up
those two slots obviously) then can pick independt rear and front nose attachmetns/weapons obviously". The two side
hardpoints are a mirrored PAIR: one choice fills both sides with the same weapon / attachment; the front nose and the
rear are chosen independently. So a loadout = nose + side pair + rear (3 choices).

#### 13.9c-16 APC driving inside the facility (owner note, 2026-10-27)
Owner: "fix the apcs driving animation/route within the facility (smoother) more realistic - 2 at a time at that top
open staging area for the apcs for loading/etc when departing can select on or both together and they depart one after
another not going over buildings/overlapping/nothing just smooth looking natural driving out of the facility or where i
direct it (back to its specific garage/outside facility/etc)".
- Smooth, realistic driving inside the compound: APCs follow the lanes (never cut across or drive over buildings),
  turn with a real turning radius (no pivoting on the spot, no snapping headings), accelerate / brake smoothly, keep a
  safe following gap, never overlap another vehicle.
- The open staging area holds 2 APCs at a time for loading etc. (two marked bays); more wait their turn in order.
- Departure: the player can select one APC or both and order them out; they leave one after another (convoy order,
  spacing kept) through the gates, out of the facility or wherever the player directs: back to that APC's own garage,
  to the staging bays, out of the facility to a map point.
- Applies to the facility's automatic flows (launch, return, wash, garages) and to player orders alike.

#### 13.9c-16a CN APC movement: smooth, crisp, realistic everywhere (owner note, 2026-10-27)
Owner: "counternanite team(s) apcs need smoother driving/movement animatoins more crisp and realistic -- its kinda jumpy
now and flashy not holding true to the realistic depth they need with their movement". For the strike / tactical APCs
inside AND outside the facility: no jumps (position pops between ticks, heading snapping between the 8 sprite facings),
no flashing (frame / sheet swaps flickering: track, gun, panel, VIS7 frame swaps, overlay on / off, damage frames),
smooth acceleration / braking, turning on a radius with intermediate headings, body pitch / suspension feel at
starts and stops, track / wheel animation matched to ground speed, dust / tracks consistent; reads as a heavy vehicle.

#### 13.9c-17 Lockdown only on a breach (owner note, 2026-10-27)
Owner: "factility ONLy goes into full lockdown/harden mode when facility is breached". Full lockdown / harden mode (red
alarm beacons and wall lamps, searchlight sweep, blast doors and shutters closing, decon mist flood, staff sheltering,
range cold, lockdown states on every building) happens ONLY when the facility is breached (an enemy ground unit inside
the compound: BaseState7 "breached"; the sim's CnFacility lockdown already follows this). "Contested" and "under fire"
show an amber alert only (amber beacons; Sentinels stand to; normal facility life otherwise continues). Lockdown lifts
when the breach is cleared.

#### 13.9c-18 Barracks where the drone bay was; drone bay on the workshop; nothing see-through (owner note, 2026-10-27)
Owner: "place the multi story barracks with a helipad at the top in place where the drone bay is currently and move the
drone bay so its a second story above the workshop seamlessl -- make it beautiful (also NO transparent anything - no see
through )".
- The multi-storey Sentinel barracks with its rooftop helipad / gunship pad moves to the drone bay's current site.
- The drone bay becomes a second storey built on top of the workshop, one seamless building (shared walls / structure,
  launch deck on the drone-bay roof), beautiful at the approved detail level.
- **No transparency anywhere:** nothing in the facility is drawn see-through: no roof cut / ghosted building when
  units are inside or behind it, no translucent walls, glass x-ray or cut-away views, no ghost overlays. Units hidden
  behind a building are simply hidden (or shown by an opaque marker / outline, not by making the building transparent).
  The earlier owner rule against the transparent dropship version stands too.

#### 13.9c-19 Ops-room inset removed (owner choice, 2026-10-27)
Owner: "maybe lets just get rid of the 'ops room' view?? it looks shitty and doesnt add anything at all"; asked, chose
"Remove it": the floating ops-room inset drawn over the command centre (LIFE7: staff at screens, map table) is deleted
entirely. The command centre reads as a building only (lit windows, radome, mast lights). The live strike-team map stays
in the F4 Ops Room panel.

#### 13.9c-20 Counter-nanite armoured suits from the armory + suit bay (owner note, 2026-10-27)
Owner: "way beter designed - less weird looking more tactical and properly millitrayily thought out and
re-engineered/designed in totality (all the different few variations available to the conter nanite facility and teams)*
* [the ones that get produced from the armory suit bay]"; asked which units: "the armoured suits ones that get produced
from the armory suit bay (each is manned by one gunner )".
- The armory + suit bay produces the counter-nanite teams' armoured suits: one-man powered armour, each crewed by one
  gunner (the G6 Exo mechanics: pilot inside, the pilot survives / ejects when the suit is destroyed), Human A and B.
- A small family of variants, each with a clear military role for counter-nanite work (e.g. rifle / heavy-gun suit,
  anti-armour / anti-walker missile suit, anti-air / anti-drone suit, an anti-nanite suit with the facility's disruptor
  weapons); ORCH / the agent pick the final 3-5 with the owner's "properly militarily thought out" bar.
- Redesigned in totality: believable powered-armour engineering (load paths, armour plates, joints, sensors, weapon
  mounts, ammo feed, hatch / pilot access), less odd-looking, more tactical; at the approved art detail level with
  realistic, grounded animation (13.9c-13).
- The generic G6 exo suits (a_exo_*, built at the exo garage) stay as they are unless the agent finds a shared art fix
  that improves them without changing their stats.

#### 13.9c-20a CN suits: complete redesign, slim nanotech armour (owner note, 2026-10-27)
Owner, on the first suit sheets (bulky, boxy, toy-like): "those suit designs are trash and lok like toys --- should feel
like nanotech stark tech thats slim and form fitting -- very tactical -- operation capable -- completely redesign all of
these suits". Replaces the art direction of 13.9c-20 (roles / mechanics stay):
- Slim, form-fitting powered armour on a human frame: barely bigger than the gunner (about 1.1x a soldier), human
  proportions and posture, no boxy torso, no stubby mech legs, no toy-like blocks.
- High-tech nanotech look: close-fitting segmented armour plates over a sealed under-layer, a sleek sealed helmet with a
  visor slit / sensor band, clean panel lines, small accent lights; original design (no copy of any film / comic suit).
- Very tactical, operation-capable: muted military finish, kit that makes sense (mag / cell pouches, comms antenna stub,
  low-profile back module), weapons integrated or carried like a soldier's (forearm / shoulder mounts that are compact;
  the Bastion carries its rotary gun, not a giant arm block).
- Each of the 4 roles still readable at game size by silhouette (Bastion heavy gun + back feed, Breaker shoulder missile
  cells, Aegis back radar / sensor array, Purifier forearm projector + back cell bank), and distinct from the Sentinels
  (heavier plates, sealed helmet, role kit, suit colour).
- Animation grounded and human: walk / run / aim / fire / reload like a trained operator in armour.

#### 13.9c-20b CN suits: stances, animation and movement overhaul (owner note, 2026-10-27)
Owner: "suit bearers also need tactical aggressive stances and better stances when firing, moving, etc - full overhaul
on that plus their animations and movemnt ** smoother,". For every CN suit (13.9c-20a):
- Aggressive, tactical stances: weapon up and ready at idle (low-ready / high-ready, not arms hanging), bladed stance,
  knees bent, weight forward; firing stance braced (rear foot back, shoulders into the weapon, recoil absorbed);
  moving in a tactical walk / run with the weapon kept on target (no arm swing with the weapon down).
- Full animation overhaul: more in-between frames for walk / run / aim / fire / reload / turn so the motion is fluid;
  readable recoil and muzzle; reload done like a trained operator (short, as 13.9c-11 asked for the Sentinels).
- Smoother movement on screen: stride matched to ground speed (no foot sliding), smooth turning between facings and
  accel / decel (display-side; no sim change unless needed).

#### 13.9c-20c CN suits are big amplified exosuits; the suit foundry resized and redesigned (owner note, 2026-10-27)
Owner: "think of these armour suits as extensoions of the users giving them more capabulites and strengh and wepons and
movement and adaption --- almost avatar movie size suits ** (noticebly larger than the sentinels, counterstrike team
and spec ops, + all other basic units) resize its building accordingly and redesign the building for the armoured suits
foundry". Supersedes the "about 1.1x a soldier" size in 13.9c-20a; the rest of 13.9c-20a/-20b stands.
- Size: a large amplified exosuit, about 2-2.3x a soldier's height (about 4 m), clearly bigger than Sentinels, CN
  operators, spec ops and every basic infantry unit, smaller than a walker / tank. The pilot sits inside an armoured,
  sealed cockpit in the torso (opaque: no glass canopy, 13.9c-18), seen through a sensor visor band; the suit is an
  extension of the pilot: it moves like an athletic human (mirrors the pilot), with strength, weapons and mobility a
  soldier lacks.
- Design language from 13.9c-20a still applies at this scale: sleek, athletic, high-tech nanotech plating, tactical
  military finish, original design; never boxy or toy-like. Stances / animation per 13.9c-20b, with weight: heavy
  footfalls, planted stance when firing big weapons.
- Sim: footprint / radius grows to match; suits use the vehicle routes (gates, lanes, the APC wash), never the infantry
  mantrap / decon hall, never the wall-walk or garrison slots for men; the gunner ejects as before.
- The armory + suit bay becomes the **Suit Foundry**: resized and redesigned for suits this size: tall bay doors, gantry
  cranes, suit cradles / charging and arming racks, a pilot entry gantry, test apron; still inside the facility (no growth
  of the wall ring; re-plan neighbours if it needs space), no overlap, doors onto lanes the suits can use.

#### 13.9c-20d CN suits: a distinct design per role (owner note, 2026-10-27)
Owner, on the 4 m redesign board: "for the aormoured suits need to push for more defined roles/specializations (maybe a
different design for each dependant on role/specialty?) ** make them DOPE". Each role gets its own suit design, not one
body with a different weapon: its own frame build, armour layout, helmet / sensor head, back module and stance, all
shaped by the job, readable by silhouette at game size and in the icon:
- Bastion (heavy gun): the heaviest build: broad shoulders, thick chest and forearm armour, braced wide stance, big
  rotary gun on a support arm with a visible belt feed from a large back drum.
- Breaker (anti-armour): a launcher frame: tall shoulder missile rack / tubes rising above the head, armoured cheek /
  side plates against backblast, targeting sight head, kneeling-brace launch pose.
- Aegis (counter-air): a sensor-heavy, lighter build: raised folding radar / sensor array on the back, high-elevation
  cannon that tilts up, upward-tracking head, quick-turning stance.
- Purifier (anti-nanite): sealed hazard look: heavier sealed collar / rebreather, forearm disruptor projector with
  emitter coils, glowing capacitor bank on the back, shielded hands; deliberate advancing stance.
Same scale (13.9c-20c), same tactical finish and quality bar ("make them DOPE"), same stances / animation rules (13.9c-20b).

#### 13.9c-20e Suit Foundry: push everything further (owner note, 2026-10-27)
Owner, on the first Suit Foundry pass (it still read like a plain warehouse): "for suit foundry push everything even
more". The Foundry becomes a signature building at the approved detail level: heavy armoured hangar (layered armour
panels, buttresses, blast shutters, hardened roofline with parapet / antenna / sensor mast / heat exchangers), a
massive armoured bay door (multi-panel, track rails, hazard framing, status lights), the inside visible through the
open door (suit cradles, overhead crane rails, arming / charging racks, a suit being fitted), an outdoor test apron with
a gantry, pilot boarding gantry and charging pedestals, a nanotech / power plant annex (capacitor banks, cooling),
lit signage, believable small details (cable trays, vents, maintenance ladders, warning stencils), proper night lights
mounted on it (13.9c-24); opaque (13.9c-18); same footprint as now (re-plan only if the owner asks).

#### 13.9c-21 Fuel truck parking spot (owner note, 2026-10-27)
Owner: "fix the oil tanker positionoing and give it a specified parking spot withint facility it will alwasy park at
unless actively working". The fuel bowser (Facility Engineer's sim bowser and LIFE7's display truck) has one marked
parking bay inside the facility (out of every lane, pad, bay and route); it always returns there and parks there
whenever it is not actively refuelling.

#### 13.9c-21b Fuel bay beside the dropship helipad (owner choice, 2026-10-27)
FACB7-6's exhaustive search found no spot both visible and outside every margin. Owner, asked: "besides the dropship
helipad (expand that area as needed nothing crazy thouguth so its parking bay/station can proportionately fit there with
no issue and still give the drop ship/loading apcs/PLENTY of operational rom w NO conflicts ---- make sense??". So: the
fuel bay / refuel station is a marked bay beside the dropship helipad; the helipad apron may grow modestly to fit it;
the dropship's landing area and the APC loading flow keep plenty of room with no conflicts (bay outside the dropship's
landing / rotor-wash footprint and the APC lanes / bays, never in front of a door, garage or gate, in the camera's
sight). Authority record for test_life7::test_fuel_bay_makes_sense: the "pad / helipad edge +1" margin no longer applies
to this one bay ON the helipad apron side (it still applies to the loading pad, and to the dropship's own footprint).

#### 13.9c-22 Outer APC gate hardens when enemies are near (owner note, 2026-10-27)
Owner: "outer apc entrance gate into the wash station needs to have a hardened mode when enemies are close by that seals
it up (unless you explicetly allow apcs to leave/enter as needed obviously ** stays hardedn and locked on that outer
heavy gate until enemies arent near the base any longer ----- dont make this gimicky".
- The outer APC gate (gate_outer) goes to HARDENED (closed, locked, heavy door down) whenever enemies are near the base
  (a real threat radius around the facility / base, not only a breach; this is separate from the breach-only full
  lockdown of 13.9c-17).
- While hardened it opens ONLY for an explicit player order (or an automatic facility launch / return the player has
  allowed) for own APCs to pass: it cycles open, the APC(s) pass, it closes again behind them. The wash works as a
  sally port: the outer and inner gates are never open at the same time.
- It stays hardened until no enemies have been near the base for a short time, then returns to normal.
- No gimmicks: realistic gate timing (opening / closing take real seconds), a visible closed / open state, and it is a
  real obstacle (enemies cannot pass a closed gate; they must breach it).

#### 13.9c-23 Castle-style hardened wall-walk, futuristic (owner note, 2026-10-27)
Owner: "all the facilty walls need a walkway at the top thats secure/hardened/ and sentinels can crocuh behind when
reloading, etc --- like a castle has just futuristic and modernized for human faction obvioulsy".
- Every facility wall gets a real walkway on top (a wall-walk deck wide enough for a man) behind a hardened, armoured
  parapet on the outer face: a modern crenellation (armoured battlement panels with firing slots / gaps), like a castle
  but futuristic Human-faction engineering; the towers join it.
- Sentinels on the wall stand behind the parapet: they crouch behind it to reload, when suppressed, and between shots,
  and rise to fire through / over it; they are drawn ON the walkway (correct depth, never floating), never transparent.
- The parapet is the cover the sim already grants on the wall (heavy cover); visible, solid, believable.

#### 13.9c-21a Fuel bay placement must make sense (owner note, 2026-10-27)
Owner: "fuel tanker marked parking bay should not be placed in front of any door, garage, etc its placement HAS to make
sense". The bowser bay (13.9c-21) is never in front of (or in the swing / approach of) any door, garage door, gate,
blast door, pad / helipad edge, lane mouth or another bay; it is a lay-by off a lane, against a building side or the
wall's inner face, near where refuelling happens (the helipad / loading pad apron, the garages), with a clear drive-out
onto the lane. The whole truck fits inside the marked bay.

#### 13.9c-24 Facility lights placed for real, nothing floating (owner note, 2026-10-27)
Owner: "fix the lighint/fog lights/facility lights have all proper realistic placement nothing floating". Every
facility light (beacons, searchlights, flood / fog lights, pad / edge lights, door lamps, mast lights, window glow)
is mounted on something real (a wall top, tower roof, mast, pole, building face / roof edge, pad edge) at that thing's
drawn height, with its fixture drawn; nothing hangs in the air; light pools fall on the ground where the fixture points;
no translucent light volumes over buildings (13.9c-18).

#### 13.9c-24b Outward floodlights much brighter (owner note, 2026-10-27)
Owner: "outer facing floodlights in facility need to be much brighter (light up the night as a real bases floodlight
would be )". The wall-top / tower / gate floods aimed out over the clear zone light it like a real base perimeter at
night: a bright, wide, even wash on the ground outside the walls (the glacis / approach / clear zone), strong enough
that units out there are plainly visible at night, with a hot core near each fixture and soft falloff; still ground
light only (no translucent volume over buildings, 13.9c-18), fixtures as placed in 13.9c-24a.

#### 13.9c-24c Lit windows read as lit interior rooms (owner note, 2026-10-27)
Owner, on the first lit-window pass (solid bright blocks over the windows): "fix the lit up window panes so the are more
proportionate and look like actual lit up interior rooms nOT just lit up blocks over the windows". Each lit window sits
inside its drawn frame at the right proportion (frame, mullions, sill visible; glass inset, not a block covering the
window), and reads as a room behind glass: a soft interior gradient (ceiling light falloff), hints of interior (a
ceiling strip light, a partition, a screen glow, blinds half-drawn, a silhouette now and then), varied warm / cool
rooms, many dark or dim, nothing pure-white; opaque art, no see-through overlays.

#### 13.9c-24d Compound interior lit properly at night (owner note, 2026-10-27)
Owner: "interior lighting shouldnt be so dark add more lighting and/or upgrade to brighter floodlights design similar to
outside facing ligtings/floodlights/spotloghts". Inside the walls at night: lanes, aprons, pads, staging, garage fronts,
the APC wash, the decon hall approach and the Suit Foundry apron are lit like a working military compound: mast / pole
floodlights and wall-mounted floods aimed inward (same fixture design and brightness class as the perimeter floods,
13.9c-24b), continuous coverage with no dark pockets where units work, units clearly visible; ground light only (no
translucent volumes over buildings, 13.9c-18); fixtures on real mounts (13.9c-24); light count within the cap.

#### 13.9c-25 APC entrance / wash: vehicles and CN suits only (owner note, 2026-10-27)
Owner: "NO infantry or ground units can enter through the facilities apc entrance/wash area [except the armoured suits
obvioulsy who can use it leave + decontaminate up to 4 at a time when entering]". The two-gate APC entry and the wash
between them pass only the facility's APCs / vehicles and the CN armoured suits; infantry and every other ground unit
(own, allied or enemy) must use the foot entry (mantrap + decon hall) and are never routed through the APC gates even when
open. CN suits leave and enter through it; entering, they decontaminate in the wash up to 4 at a time (more wait outside
the outer gate in order), like the APC cycle.

#### 13.9c-24a Lighting overhaul (owner note, 2026-10-27)
Owner, after the glow-box fix: "lighting and light fixtures still need upgrading and more realistic approach/placement/
everything". A full lighting pass over the facility (and the base lighting it shares), day and night: real fixture
types where a military compound has them (wall-top flood lights angled out at the clear zone, tower searchlights,
mast / pole area lights over lanes and pads, bulkhead lamps over doors, pad edge / approach lights, obstruction
beacons on the tallest roofs, red / amber alarm beacons only where a real alarm light sits), each fixture drawn and
mounted (13.9c-24), consistent light direction and colour temperature, believable light pools and falloff on the
ground and on wall faces, no translucent volumes (13.9c-18), no floating light dots.

#### 13.9c-26 APC gate blast doors redesigned (owner note, 2026-10-27)
Owner: "for the inner and outer gates for the apc entrance and wash area -- redesign the blast doors -- better design
more details for the door --- better open and close animation ---- make the mf feel secure as hell fr". Both APC gates
(outer and inner) get heavy armoured blast doors: thick multi-layer door leaves (sliding or bi-parting on rails, with
locking bars / bolts, hydraulic rams, guide rails, hazard striping, warning beacons, a hardened door frame / portal tied
into the wall), detailed at the approved art level; a real open / close animation (warning light + bolts retract, leaves
travel at a heavy, steady speed, bolts drive home) driven by the sim gate state (open / closing / hardened / opening,
13.9c-22); a closed gate reads unmistakably sealed; opaque.

#### 13.9c-27 Drone bay: defence drone garrison (owner note, 2026-10-27)
Owner: "how many drones does the drone bay have?? ... should it have a max amount it can garrison in its "garage" inside
the building?? could add in as part of the base defense it releases the garrison as necessary??". Answer given: today
it launches one overwatch recon drone per strike team on a mission and holds no defence drones. Adopted (ORCH default
from the owner's own suggestion; the owner did not pick from the offered options, so these numbers are PROVISIONAL and
change on his word): the drone bay garrisons up to 12 defence drones in its hangar (interceptors vs drones / rockets,
gun drones and kamikaze drones vs ground attackers); it releases what the threat needs when the base is threatened,
recovers them to its launch deck, rearms, and rebuilds losses slowly; the player can also launch / recall from the bay;
it keeps its recon overwatch job.
Owner confirmed (2026-10-27): "drone bay should also hold a defense garrison yes btw ---  should be launchable either
maually or automatically as a default": automatic release is ON by default (a toggle on the bay turns it off); manual
launch / recall always available. Garrison size 12 stays ORCH's PROVISIONAL number until the owner names one.

#### 13.9c-27a Defence drones fight as a hive mind (owner note, 2026-10-27)
Owner: "make defense drones have better tactical capabilites/functionalities/formations/etc -- they should operate likea
hive mind to defend the facility at all cost". The drone bay garrison (13.9c-27) acts as one networked swarm:
- Shared picture: every drone, the facility sensors (towers, cameras, radar) and the Sentinels feed one threat board;
  the swarm assigns drones to threats by priority (what most endangers the facility first: breaching units, anti-air,
  heavy armour at the walls, enemy drones / missiles inbound) and re-balances as threats appear or die.
- Formations and tactics: interceptors fly a layered screen (outer picket, inner close-in ring over the facility) and
  intercept inbound drones / missiles; gun drones work in pairs / fire teams, orbit and strafe from different angles,
  converge on one target to focus fire, never stack on one spot; kamikazes strike the highest-value threat, coordinated
  with the gun drones' suppression; drones screen damaged / reloading drones, rotate back to the deck to rearm while
  others hold the line (never all down at once), and relaunch.
- At all cost: when the facility is breached the whole garrison commits, the bay rebuilds and relaunches as fast as it
  can, and drones will ram (kamikaze-style last resort) to stop a breach of the core.
- Readable on screen: visible formations / orbits, and the hive card shows its tasking (screen / strike / rearm counts).
Deterministic, saved, hashed; numbers PROVISIONAL; no facility = no cost.

#### 13.9c-28 Muzzle flashes from the barrels, everything that fires (owner note, 2026-10-27)
Owner: "fix where the muzzle flash comes from for all sentry guns, guns, turrets, wepons systems, everything that fires
__should come directly from its barrel(s)--- realistic approach asf". Every unit, turret, wall turret, tower weapon,
vehicle, aircraft, drone, suit and soldier that fires shows its muzzle flash (and tracer start, smoke, casings) at the
tip of the barrel that fired, per facing / turret facing and per pose (standing, crouched, prone, on a wall, in a
garrison port), alternating barrels on multi-barrel weapons; no flash from a unit's centre or feet.

#### 13.9c-28a The APC's rear mounted gun animated when it fires (owner note, 2026-10-27)
Owner: "donte forget the mounted gun on the back of the apc -- thats needs to be animated correctly when shooting too".
The counter-nanite strike / tactical APCs' rear roof-mounted gun (g7_cn_strike_apc / g7_op_tactical_apc and B
versions; frames fire_r / traverse today, no separate turret sprite) traverses on its own to the target (independent of
the hull heading), shows recoil and a muzzle flash / tracer / casings from ITS barrel tip (13.9c-28), at a believable
rate; when both guns fire, each flashes at its own barrel; an idle gun returns to its travel position.

#### 13.9c-29 CN strike teams and spec ops never on base defence (owner note, 2026-10-27)
Owner: "counternanite strike team and spec ops team(s) are NEVER to be on base defense -- strictly to go run their
missions (as weve already discussed and planned out for how they operate/function)". Restates B16 (the main army
defends; the counter-nanite strike teams and tactical / spec-ops squads run missions). Rules:
- No automatic system ever gives a CN strike-team / tactical-squad unit (cn_team, g7_cn_* / g7_op_* operators, their
  APCs) a defence job: the LP defence commander, the LP garrison, the AI controllers / commanders of any side, Sentinel
  job boards / QRF, wall-walk manning, garrison / turret crewing, base-state lockdown, squad AI sallies.
- Between missions they stay in their garages / barracks / staging, mounted or stood down; inside the base they do not
  chase or sally at attackers (they may return fire if hit where they stand, never leave their post to engage).
- They leave the base only on missions (launch flow, planning room, the player's mission orders). The player keeps
  direct control (B16 override), but nothing automatic puts them on defence.

#### 13.9c-30 Every turret turns to its target before it fires (owner note, 2026-10-27)
Owner: "ensure all turret types actually turn towards enemies and fire towards them -- it currently reads as they shoot
at enemies but never actually turn their barrel(s) to face them before shooting -- make it realistic". Every turret
type (base defence turrets and gun / missile / AA / SAM / CIWS emplacements, G7 tower weapons and wall turrets, tank /
IFV / APC turrets and remote weapon stations, ship guns): the turret / barrel visibly traverses toward its target at a
believable rate for its size (light RWS fast, heavy guns slow), fires only once it is laid on the target (within a small
tolerance), tracks a moving target, and its drawn barrel, muzzle flash and tracer all point at the target; idle turrets
scan / return to a rest bearing. Deterministic; numbers PROVISIONAL; balance kept (a short lay time, not a nerf).

#### 13.9c-31 Nothing walks through anything; smooth movement everywhere (owner note, 2026-10-27)
Owner: "ensure NO units walk throuhg buildings/walls/other units/etc in the facility and elswhere ** smooth animations
and walking and movement at all times". In every mode and map, inside the facility and outside it: no unit's drawn body
overlaps a building / wall / tower / gate footprint or another unit (infantry keep a small personal gap, vehicles their
hull, aircraft excepted in flight); paths go round obstacles; crowds queue / flow at doors, gates, mantraps and lanes
instead of stacking; no jitter, teleport, snap or sliding: smooth accel / decel, turns with a believable rate, walk / run
cycles matched to ground speed, display interpolation between sim ticks without pops. Deterministic; perf budget kept.

#### 13.9c-32 Rotary CIWS turrets on the command centre roof (owner note, 2026-10-27)
Owner: "add in phalanx style turret(s) on top of main command building inside facility / future modified anti machine
version of the us phlanx Gatling style turret belt fed". The 4-storey command centre carries close-in weapon systems on
its roof (2, PROVISIONAL, on opposite corners for all-round cover): a self-contained rotary-cannon mount in the style of
a naval CIWS (search / track radar dome over a multi-barrel Gatling gun, belt / drum feed, the whole mount trains and
elevates), modernised for the Machine war: anti-drone / anti-missile / anti-rocket point defence first, and able to
engage Machine units (crawlers, swarms, light walkers) that reach the inner compound; armour-piercing anti-nanite rounds.
Behaviour: it traverses and elevates onto the threat before firing (13.9c-30), fires short high-rate bursts with the
flash / tracer stream / brass from the barrel cluster (13.9c-28), spins the barrels up and down, belt / drum runs dry and
reloads (an engineer / ammo resupply, PROVISIONAL), idle radar sweep. Part of the facility (not buildable elsewhere),
destroyable with the building, opaque art at the approved detail level, an original design (no copied real model).
Numbers PROVISIONAL; balanced against the facility's existing CIWS / counter-drone layer, no gimmick.
Owner answers (2026-10-27): **2 mounts, opposite corners**; **air first, ground too** (drones / missiles / rockets /
shells first, also Machine crawlers / swarms / light walkers inside the compound); **Facility Engineers reload it** (a
drum swap by an engineer who goes up to the roof; the mount is silent until done).

#### 13.9c-32a CIWS signature sound, straight-line fire, spread with range (owner note, 2026-10-28)
Owner: "CIWS turrets need to have that signatture phlanx BBRRRRTTTTTTTTTT shooting sound + shooting in a strait line
wherever the barrel is point w realistic bullet spread the further they shoot". (1) Sound: the rotary-cannon signature,
a continuous tearing "BRRRRT" burst (very high rate of fire, the individual shots fuse into one buzz), with barrel spin-up
before and spin-down after the burst; positional like every other weapon, original synthesis (no sampled real recording).
(2) The tracer / round stream leaves the barrel tips and flies in a straight line along the way the barrel points (bearing
and elevation of the mount at that moment), never curving to the target. (3) Realistic dispersion: the rounds spread in
a cone, so the group is tight close in and wider the farther they fly; at long range more rounds miss (they fly past or
strike the ground), close in almost all hit. The sim hit share follows the same cone (deterministic), so range matters in
play, not just in the picture. Numbers PROVISIONAL.

#### 13.9c-32b CIWS depression limit: realistic ~25 deg (owner choice, 2026-10-28)
Asked (CIWS7-5 drew aim bands down to -60 deg so the barrels followed the stream onto crawlers right next to the
building; a real naval CIWS depresses only to about -25 deg), the owner chose **"Realistic: ~25 deg limit"**: the roof
mount cannot aim lower than about 25 deg below level. From the 15.5 m command-centre roof that leaves a blind ring for
ground targets about 8-9 tiles around the building (the mount simply cannot engage there; Sentinels, towers and wall
turrets cover it); ground targets beyond it out to ground range and everything in the air stay covered. The drawn
barrels never point below the limit. Air targets stay engageable inside the ring (they fly above the depression
line; ORCH, 2026-10-28). Numbers PROVISIONAL.

#### 13.9c-33 The facility is a fortress: ~4x to break (owner choice, 2026-10-28)
Asked (the new drone hive + CIWS + traverse made the facility hold against a combined-arms assault worth 2.5x its
Sentinel garrison, which before narrowly broke in), the owner chose **"Fortress: needs ~4x"**: the full facility
(Sentinels + towers + wall turrets + drone hive + roof CIWS) holds against a well-built combined-arms push at 2.5x and
only a much larger assault (about 4x the garrison value) breaks in. The Sentinels themselves stay "very strong, not
invincible" (13.9c-10): the Sentinel balance checks measure them with the drone hive off; the facility checks measure
the whole facility at 2.5x (holds) and ~4x (breaks in). Numbers PROVISIONAL.
Authority record for test_sent7 test_balance_fight: the old "Sentinels lose vs combined arms x2.5" check predates the
drone hive / CIWS; it becomes "the full facility holds at 2.5x" + "a ~4x combined-arms assault breaks in" (owner quote
above), and the Sentinel-only balance runs with the drone bay off.

#### 13.9c-34 Last Protocol: an 80+ Sentinel reserve in the barracks (owner note, 2026-10-28)
Owner: "last protocol game mode your facility should start with at min the sentinels and units already within the
facility + an extra 80+sentinels in the barracks garrison *** (make a tactically strategic way that they filter out as
necessary and conflict gets more heavy in defending the facility from being breached/takenover --ask me quesionts".
In Last Protocol the pre-built counter-nanite facility keeps its normal starting garrison and units, PLUS a reserve of
80 or more Sentinels held in the Sentinel Barracks (barracks garrison slots 120). The reserve is not dumped on the field
at the start: it filters out in a deliberate, tactical way as the fighting grows heavier, so the facility gets harder
to breach or take over the longer and harder it is pushed. Owner answers (2026-10-28):
- **Size: 100 Sentinels** in reserve, on top of the normal starting garrison and units (barracks 120: about 20 slots stay
  free for wounded who come back in to rest and refill).
- **Release: tiered by pressure.** Step 1: replace casualties at wall / tower posts one-for-one. Step 2: when a wall
  sector or gate is under heavy attack, quick-reaction squads of 4-8 go there, bounding from cover. Step 3: on a real
  breach (enemies inside the walls), a big counter-attack surge to throw them out. A last-stand group (about 20% of the
  reserve) is always held back to guard the command centre and the core rooms.
- **Control: automatic by default + manual**, like the drone bay (13.9c-27): from the barracks card the player can
  release a squad, recall, or switch auto off.
- **Replenish: finite pool, slow trickle.** The reserve is what the facility starts with; the barracks trains a few
  replacements slowly (costs resources), so a long siege grinds the defence down but never empties it at once.
Numbers PROVISIONAL. Last Protocol only (skirmish facilities keep the normal garrison).

#### 13.9c-35 No firing through walls from inside (owner note, 2026-10-28)
Owner: "in the facility the sentinal units that quick react when theres a side/area being hit hard by the machines - NO
unit can shoot from inside outside the walls UNLESS they are on the wall walkways our outside the wall(s)". A unit
standing inside a walled compound cannot fire at a target outside that wall (and the reverse: the wall stops direct
fire both ways); only units up on the wall-walk or outside the wall can engage across it. Applies to the quick-reaction
squads, the surge and every other unit. Exemptions (owner answer 2026-10-28, **"Realistic exemptions"**): what really
can fire over a wall still can: indirect fire that arcs over (mortars, howitzers, artillery), raised mounts (towers, the
roof CIWS, rooftop guns) and anything flying (drones, helicopters, dropships). Everyone else (rifles, machine guns,
tanks, APC guns) must be on the wall-walk or outside the wall to fire across it. An open gate is a gap: direct fire may
pass through the open gate cell; a closed gate blocks like the wall.

#### 13.9c-36 Last Protocol base is too big: shrink it drastically (owner note, 2026-10-28)
Owner: "i feel like the base now is TOO mf big for the last protocol game mode help me decide HOW and what to remove to
shrink it down drastically so its more realistically difficult -- obviously facility stays same in center with all of
its upgrades/etc". Today (census 2026-10-28, map last_protocol 512x512): three walled rings, outer 87x87 tiles, economy
73x73, core 53x53; 874 wall segments; outer ring ~160 defensive buildings (24 howitzer pits, 39 cameras, 12 autocannons,
11 HMG nests, 8 automortars, 8 EMP, 8 laser CIWS, 7 thermite, 6 ATGM bunkers, 6 SAM, 3 microwave, 3 hull-down, 2 railguns,
2 radars, 17 depots); economy ring 45 generators, 29 depots, 8 refineries, 7 barracks, 6 research, 3 hospitals, 3 exo
garages, 3 motor pools; core ring the counter-nanite facility (unchanged) plus HQ, company HQ, airfield, 3 heavy hangars,
2 VTOL pads, 2 helipads, 4 howitzer pits, 5 SAM, 4 laser CIWS, 3 barracks, repair bay. The facility stays exactly as it is
in the centre with all its upgrades. Owner answers (2026-10-28):
- **Layout: two tight rings.** The middle economy ring is deleted. An inner wall around the facility + HQ + air pads and
  ONE outer defensive wall close around it, about 55x55 tiles across (roughly 60% less ground); the kept economy sits in
  the gap between the two walls.
- **Defences and army: cut to about half** (about 80 defences, keeping the turret mix; about half the starting army).
- **Economy: about half** of everything (generators, depots, refineries, barracks, research, hospitals, suit garages,
  motor pools, airfield / hangars / VTOL pads), **plus more helipads, each with a helicopter loaded at the start**.
  ORCH decision on the helipads (owner: "decide how many and what type"): **6 helipads** (2 existing + 4 new): **3 Attack
  Helicopters** (rocket fire support for a hard-pressed wall), **2 Transport Gunships** (door guns; lift a squad to a
  threatened sector), **1 Airlift Transport** (heavy lift / evacuation). PROVISIONAL.
- The counter-nanite facility in the centre is unchanged (with the 100-Sentinel reserve of 13.9c-34).
- Follow-up answers (2026-10-28, after LPSHRINK7 built it at 69x69 because the facility + HQ + runway + dropship pad need a
  47-wide core): **"Squeeze to ~59"**: drop the outer ring road and merge the defence row into the turret row (outer band
  about 6 tiles, base about 59x59, ~54% less ground than the old 87x87; vehicles use the service lane). The Airlift
  Transport is a fixed-wing plane (needs a heavy hangar), so the **6th helipad holds a 4th Attack Helicopter**: pads =
  4 Attack Helicopters + 2 Transport Gunships; the Airlift parks in a heavy hangar.
Authority record: tests that assert the three-ring layout, ring counts or the old building / army totals change with
this note (owner quote above); every other check stays.

#### 13.9c-37 Drone bay / barracks reserve cards only when their building is selected (owner note, 2026-10-28)
Owner: "the drone bay, and barrack reserve panel should only be shown when I (player) clicks either of their respective
buildings". The DRONE BAY card shows only while the player has the drone bay (the workshop's 2nd storey, 13.9c-18)
selected; the BARRACKS RESERVE card only while the Sentinel Barracks is selected. Otherwise both stay hidden.

#### 13.9c-38 Heavier always-on Sentinel watch on walls, towers and the entrance (owner note, 2026-10-28)
Owner: "the sentinels should always be manning the entrance/all walls/towers on rotation basis ALWAYS --- w the obvious
dispatch more to walls from garrison as attacks increase , etc etc as we've already planned out --- I should be seeing
heavier sentinel patrol force on the walls and near entrances". Owner choice: **"Double the watch"**: the starting
Sentinel garrison goes 24 -> 48 in every mode. At all times: a patrol pair walking every wall face on the wall-walk,
every tower manned, a 4-man team at the entrance checkpoint and the gates; shifts rotate with the barracks (rest /
refill) so the watch never empties and nobody stands forever. As attacks grow, more go to the walls from the garrison
(13.9c-10/-11 stand-to) and, in Last Protocol, from the 100-man reserve (13.9c-34). The fortress balance (13.9c-33:
holds 2.5x, breaks in ~4x) is re-checked and kept with PROVISIONAL tuning. Numbers PROVISIONAL.
Follow-up (2026-10-28): with 48 men the 13.9c-33 assault (a multiple of the garrison value) doubled and the facility
fell at 2.5x. Owner choice: **"Scale the defences up too"**: keep measuring against the new 48-man value (2.5x = ~313
attackers holds, ~4x = ~500 breaks in); grow the drone hive (12 -> 24 drones) and add anti-armour lancers to the mix
(PROVISIONAL), Sentinels alone (drone bay off) still lose at 2.5x.
Infantry checks (owner choice 2026-10-28, **"Full facility vs infantry"**): the infantry x2 / x3 balance checks run with
the whole facility (drone hive on, as in a real game) at the new 48-man value; the "Sentinels alone are beatable" rule
stays on the combined-arms 2.5x check (drone bay off loses). Authority record for test_sent7 test_balance_fight.

#### 13.9c-39 Roof mounts out of reach of ground melee and demolition (owner choice, 2026-10-28)
Found by FLOWA7 (ciws7 flow): a Machine breacher crawler at the command centre's foot blew up a roof CIWS mount in one
hit, because combat measured reach to the mount's ground footprint, not to the roof (~15.5 m up). Owner choice: **"Yes,
out of reach"**: melee, demolition / shaped charges and other short-range ground attacks cannot hit roof-mounted guns
(the CIWS and any other roof mount). Guns, rockets, artillery and aircraft still can. Small sim change; hashes
re-checked.

#### 13.9c-40 No population cap in skirmish either (owner choice, 2026-10-28)
Found by FLOWC7 (facint7 flow): in skirmish the facility's free 48-man Sentinel watch (pop 2 each) used 96 of the 120
cap, so the player could barely train anything once the facility was up. Asked how the garrison should count, the owner
answered: **"Remove the 120 population cap"**. Skirmish now has no population cap, the same as Last Protocol (13.9d):
every side's supply cap is unlimited and the HUD shows "POP n (NO CAP)". Supply buildings keep their other roles. The
AI sides get the same rule. Authority record for any test that asserted the skirmish cap of 120.
**Moved to the next slice (owner, 2026-10-28):** "STOP focusing on the skirmish - I mainly want the end protocol game
mode ... give me that packaged asap in full totality ... leave the rest for next slice". Not built in G7; skirmish keeps
its 120 cap for now. The facint7 all-in-one facility flow (skirmish-hosted, last run 97/10: night-assault phase, facility
security cameras, tactical APC garage return unverified) is parked with it.

### 13.10 Decided against for G7
- **Moved to G8:** director-cam picture-in-picture, end-of-run highlight reel, end-of-run creep timelapse.
- **Undecided, not in G7:** tactical pause with order queue (may be added later).
- **Not wanted:** slow-motion beats, meta-progression between runs, doctrine cards, commander briefing, map-editor
  support for Last Protocol (official map only).

## Look checkpoint decision (owner, 2026-10-26)
Shown a side-by-side of today's units vs the first G7 samples (`.plan/shots/ARTCN7/compare_today_vs_g7.png`), the owner
chose **"Rework: bigger, more detailed"**: the first samples' soldiers came out smaller and harder to read than today's,
and the vehicles were big but flat and blocky. Direction for the rework: soldiers about 1.5x today's on-screen size with
real kit detail and shading; vehicles, dropships and the facility with proper panel lines, wear and depth; a grounded
military look closer to Signalborne; memory budgets re-sized so the fps gates still hold. The owner reviews the reworked
samples (same side-by-side format) before any full roll-out.

## Look checkpoint rev2 decision (owner, 2026-10-26; supersedes the "1.5x" size line above)
Shown rev2 (`.plan/shots/ARTCN7/compare_today_vs_g7_rev2.png` + an in-game shot), the owner did NOT approve roll-out:
- **Stealth dropship: complete redesign.** "shits a fucking box --- make it feel like a true vtol". It must read as a
  real VTOL aircraft (sleek faceted stealth fuselage, tilting/ducted lift rotors or fans, wings, tail, cockpit), not a
  box. The owner's C-17-style rear-ramp loading (APC drives in through the rear ramp, everything proportionate) still
  stands. The regular XL VTOL dropship gets the same treatment (it was the same flat slab).
- **APCs: complete design overhaul.** "they look like shit give them a dynamic and realistic look". Realistic modern
  wheeled APC proportions and silhouette (think real 8x8 armoured vehicles), dynamic shapes, believable armour, wheels,
  suspension, optics, mounts, with the shielded .50 gunner pods and the pop-out 6-tube rocket pod (6.5) kept.
- **Scale: shrink the soldiers to the correct size.** "the units are too big compared to the vehicles and tiles shrink
  them correctly but keep their high detail and quality". Soldiers, vehicles, aircraft and buildings follow ONE real-world
  scale against the 64x32 tile grid (a soldier is ~1.8 m next to a ~8 m long, ~2.7 m tall APC). Keep the rev2 kit detail
  and quality at the smaller size. The rev2 "about 1.5x today's on-screen size" target is withdrawn.
- Roll-out still waits for the owner's review of the rev3 side-by-side.

## Look checkpoint rev3 decision (owner, 2026-10-27)
Shown rev3 (`.plan/shots/ARTCN7/compare_today_vs_g7_rev3.png` + in-game shots), the owner approved the direction:
- **Approved as is:** "infantry and nanite counter strike and operators all look fucking solid". The rev3 scale (4 m per
  tile, 18 px soldier, 8 m strike APC) stands; the rest of the G7 art follows it.
- **Both VTOL dropships (stealth + regular):** "fucking fire just clean them up and make sure the drawings make perfect
  sense depth wise and everything - no flaws".
- **Dropship loading:** "make sure dropship loading looks accurate and realistically correct from every angle (dont show
  a person thats behind the dropship(s))". The transparent cutaway must become cleaner and more cohesive, or go
  entirely in favour of animating units loading up the lowered rear ramp. ORCH decision: drop the see-through cutaway;
  show the bay only through the open rear ramp (lit interior), with the APC driving and soldiers walking up the ramp
  and disappearing into the bay, every figure correctly hidden by the hull wherever the hull is in front of it.
- **APCs:** "fucking tough (make the guns / weapons look better though - make their weapons firing / loading animations
  even better)".
- "fix the weak spots you see and can find in totality": the nose-on stealth VTOL tail fins reading as ears, pale APC
  roofs, soldiers hidden on the ramp when it faces away, and anything else found.

## G7 brainstorm answers (owner's record, B1–B20; all merged into the master scope above)
(appended as the owner answers)

- **B1, strike package types and loadout:**
  - **Loadout before each mission (owner):** "these teams have to decide what to equip before heading out on a
    mission". Before leaving the facility, the player (or the AI) picks the package mix that fills each APC's
    capacity. There's no swapping in the field; restock and re-equip at the facility.
  - **Standard purge package:** the base counter-nanite charge from 6.3.
  - **Seed-hunter package:** spreads slowly but tracks underground, killing dormant seeds and burrowed cores over a
    wider radius. The answer to regrowth.
  - **Barrier package:** lays a permanent counter-nanite line (a firebreak) creep can't cross, to wall off the base, a
    route or a captured zone.
  - **Core-breaker package:** a heavy, slow-to-arm charge, the only thing able to finish a doomsday core in Last
    Protocol (or a Machine Core/HQ in normal matches). The team must hold the site while it arms.
  - Not picked: the EMP-laced package.
- **B2, facility interior (all four picked, plus the owner's layout):**
  - **Layout (owner):** APC garages around a **central concrete loading area**. APCs pull out of their garages onto
    the concrete centre, load up (teams, packages, drones), and when ready drive out through the facility's main
    fortified gates. Loading is visible and animated (APCs reversing out, teams boarding, packages loaded).
  - **Mission planning room:** a briefing screen before each mission to pick the target, route, package loadout and
    escort squads, with the latest intel (creep, seeds, known Machine forces). AI-run missions use the same plan.
  - **Simulation range:** a training range with Machine replicas; between missions, teams run drills to gain team
    experience (faster deployment, better convoy discipline). Runs only while the base is secure.
  - **Package lab:** produces strike packages over time (a production queue and stockpile); lab upgrades unlock better
    package tiers (bigger radius, faster arming).
  - **Workshop and drone bay:** repairs and upgrades APCs (armour, dome capacity, panel stock) and builds interceptor
    drones; damaged APCs come back for repair between missions.
- **B3, Machine reactions to strike teams (all four, learned over time):** the owner likes all four "but never all at
  once -- maybe as game progresses each of these becomes an adapted reaction the machines learn". Reading: the
  Machine starts with none and **learns each reaction in stages**, triggered by what the strike teams do to it (not by
  the clock alone). Proposed order and triggers, to confirm in the plan:
  1. **Defends deployment sites** (learned after the first successful deployment): when a deployment starts, it
     converges on the site from across its network, so the hold gets harder.
  2. **Strike teams become top-priority targets** (after it loses a set amount of creep): it tracks their signals,
     sends hunter packs after the convoy and sets ambushes on likely routes.
  3. **Counterattacks the facility** (after a core or major Machine structure falls): raids on the Counter-Nanite
     facility to hit APCs, packages and the lab.
  4. **Adapts to strike tactics** (late): learns your habits (routes, deployment patterns) and shifts seed placement
     and defences.
  In Last Protocol these line up with the escalation phases. The HUD shows a short alert when the Machine learns a new
  reaction ("THE NETWORK HAS ADAPTED").
- **B4, operation support (all four picked, plus the owner's additions):**
  - **Overwatch drone:** each mission gets a dedicated overwatch drone that circles the convoy and the site, shares
    everything it sees with the team, warns of approaching Machine forces, and can be flown through the drone cam.
    **Owner addition:** it has its own **smaller garage and workbench bay** inside the facility for repair and upgrades.
  - **Emergency extraction, owner's design:** a **massive stealth heavy-lift extraction VTOL** with stealth engines
    instead of rotors, flying VTOL-style. It carries **up to 20–25 soldiers** (enough for one full strike team; APCs
    are left behind). While extracting it deploys **up to 5 defence drones** (Anduril-style small drones, fictional
    name in game): **3 kamikaze and 2 machine-gun drones** that attack enemies around the landing zone. Long cooldown;
    the landing zone must be held.
    **Helipad (owner):** a landing pad **inside the facility grounds**, sized to fit the VTOL exactly; the aircraft is
    based, landed and parked there when not flying. Art and animation: the VTOL's thrust nozzles swivel for take-off
    and landing, the ramp opens, soldiers board, drones launch from its bays.
  - **Fire support on call:** the team leader calls artillery, rocket or air strikes from the base on targets the team
    can see; limited calls per mission.
  - **Relief convoy:** a second wave (fresh tactical squads, or a reload APC with packages and drones) can be sent from
    the facility to reinforce a long operation.
- **B5, progression, picked:**
  - **Named operators and call signs:** every strike-team soldier and operator has a name and a call sign (e.g.
    "Reaper 2-1"), a kill and purge record, and wounds; teams get unit names (e.g. "Team Halcyon"). This is a G7-only
    slice of named soldiers, limited to the counter-nanite line; general named soldiers stay in G8.
  - **Team experience levels:** teams level up from completed missions and simulation-range drills (faster arming,
    tighter convoy, quicker dismounts); losing veterans costs levels.
  - **Specialist upgrades:** each role gets an upgrade path through the package lab and workshop (better scanners,
    stronger jammers, faster deployment kits, heavier gunner shields).
  Not picked: commendations and the memorial wall.
- **B6, Last Protocol depth, picked:**
  - **Mission radio and command voice:** a command voice and the strike-team radio narrate the run (briefings, team
    call-outs using call signs, core status, countdown warnings, "the network has adapted" alerts). Builds on G6.1
    radio chatter.
  - **Score medals and run stats:** an end-of-run screen with time, creep purged, cores destroyed, teams lost and
    extraction count; bronze, silver and gold medals, and a personal best per stat (feeds the mode's best-time and
    score record).
  Not picked: mid-match crisis events, mutators.
- **B7, who runs counter-nanite operations:**
  - **Last Protocol is strictly 1v1 (owner):** "YOU against the machines on max". No allies and no other factions on
    the map.
  - **You, and your own AI Commanders:** you can hand the whole counter-nanite group to one of your AI Commanders as
    a role ("purge operations"); it plans missions in the planning room, picks loadouts and runs convoys by itself,
    and you can take over at any time.
  - **No other AI uses it:** AI opponents and allied AIs never research or run counter-nanite operations, in Last
    Protocol or in normal matches.
- **B8, deployment-site hold:**
  - **The engineers decide, not the player (owner):** the team's engineers (the medic-engineers, helped by the
    operators) choose what to set up and where, based on the site, the threat directions and the expected hold time.
    The player doesn't place these.
  - **Portable barriers:** armoured barriers and sandbag walls that unfold from the APCs into an instant defensive ring.
  - **Sentry turrets:** small unhackable automated guns with limited ammo, covering approaches while the team works;
    packed up again when the team leaves.
  Not picked: sensor posts and tripwires, anti-Machine mines.
- **B9, nanite exposure (owner's design):**
  - **Sealed suits:** strike-team soldiers and operators wear sealed protective suits, so they carry essentially no
    exposure risk **unless the suit is punctured** (a bullet hit, or a close-up enemy attack). A punctured soldier
    starts building nanite exposure, which slowly hurts and slows them until decontaminated; the card shows a
    breached-suit icon and the exposure level. Ordinary soldiers have no suits and build exposure whenever they're on
    foot in creep (assumed; confirm in the plan).
  - **Decontamination zone at the facility entrance:** right inside the hardened outer gates, so the inner facility
    stays clean.
    - **APCs are rinsed down** in the zone before they drive on to park (an animated wash-down).
    - **Soldiers walk through a decontamination walkway** before entering the facility, like an advanced airport
      security line (scan arches, spray, suit check). Punctured soldiers are cleared and their suits repaired there.
  - Layout order inside the gates: outer gates, then decontamination zone, then the central loading area, garages,
    helipad and buildings.
- **B10, Last Protocol map content:**
  - **Map size (owner):** "make this game mode map massive". Last Protocol gets the largest map in the game, well beyond
    today's biggest skirmish maps. Plan check: confirm path, fog, creep and render costs at that size against the fps
    targets, and use the existing detail levels and zoom LOD.
  - **Forward operating bases:** abandoned outposts you can retake and fortify. A held FOB refuels and rearms convoys,
    repairs APCs and shortens missions to far cores; the Machine tries to retake them.
  - **Seed nests:** dense clusters of dormant seeds in caves, ruins and tunnels that feed regrowth across the map;
    clearing one with seed-hunter packages permanently slows the creep.
  - **Scanner relays:** old human relay towers that engineers can repair to reveal creep, seeds and Machine movement in
    a wide radius, feeding the planning room.
  Not picked: distinct fortress types per core.
- **B11, defending the facility (all four picked):**
  - **Context (owner):** the facility is massive in itself, and in Last Protocol the whole starting base (walls,
    defences, economy) **surrounds it**. The facility sits at the heart of the base, so the Machine has to fight through
    every layer to reach it. Breaches should be rare and late, not routine.
  - **Lockdown protocol:** a breach triggers lockdown. Blast doors seal the garages, lab and helipad, inner turrets
    deploy from the walls, and the decontamination zone floods with counter-nanite mist that hurts Machine units.
  - **Emergency evacuation:** APCs and the VTOL can scramble out with teams and packages before the facility falls, so
    the force survives to rebuild.
  - **Backup power and self-repair:** backup generators keep defences running when base power is cut; facility
    engineers repair walls and towers between attacks.
  - **Losing the facility is critical in Last Protocol:** losing it with no teams left in the field ends the run (a
    third way to lose, alongside the creep meter and the countdown).
- **B12, operations UI (all four picked):**
  - **Operations panel:** every team and squad listed with location, status (in garage, loading, en route, deploying,
    extracting), suit breaches, package stock, and VTOL and overwatch-drone status, with one-click jump-to.
  - **Live deployment tracker:** during a deployment, arming progress per package, dome charge, time to completion, and
    incoming Machine forces on a mini-map ring around the site.
  - **Team cam:** watch a team through the overwatch drone feed or a helmet-cam style close view, with call signs and
    radio subtitles. This is limited to the counter-nanite line; the general follow cam stays out of scope.
  - **Creep and core overview map:** a full-screen strategic map of the whole massive map with creep coverage, seed
    nests, FOBs, relays, cores, the countdown and planned routes drawn.
- **B13, Machine units aimed at strike teams (new G7 Machine units, drawn in its current style):**
  - **Burrowers:** tunnel under the creep and erupt beneath convoys or inside deployment rings, so barriers alone
    aren't enough.
  - **Nanite spitters:** ranged units firing nanite slugs built to puncture suits; the main source of suit breaches
    and exposure (ties into B9).
  - **Mimic infiltrators:** disguised as friendly soldiers or vehicles to slip into convoys and the facility; scanner
    technicians and the decontamination walkway expose them.
  - Not picked: signal hunters. The owner asked for **more**; see B14.
- **B14, more Machine threats:**
  - **Packhunter walkers (owner's look):** fast walkers that **move like wolves or spiders, with clawed talons to rip
    apart your team**. They hunt in packs of 4–6, flank convoys from several sides at once, go for the APC mounts and
    gunners, and tear into soldiers in close combat (a main cause of suit punctures). Animation: low, scuttling gait,
    leaps, talon swipes, pouncing on targets.
  - Not picked: shield breakers, creep surges, swarm cloud. The owner asked for "something fresh and new"; see B15.
- **B15, fresh threat, picked: Leeches.** Small crawlers that latch onto APCs and drill in. They can't hack an
  unhackable APC, so they **physically wreck** the gun mounts, side panels and dome emitter, part by part. The crew,
  a dismounted soldier or another squad must pry or shoot them off; the APC's EMP pulse also knocks them loose.
  Visible on the hull (art: clinging crawlers, sparks, damaged-part frames).
  Not picked: revenants, the Siren, nanite fog.
- **Assumptions confirmed (owner, 2026-10-26):** (1) ordinary soldiers without suits build exposure whenever they're on
  foot in creep; (2) losing the facility with no teams in the field is a third way to lose Last Protocol.
- **B16, base layout and the main army's role (owner note):** the main army (every unit that is not counter-nanite
  strike team or tactical operator) is on **strict defence of the base**, manning turrets, towers, walls where
  available and vehicles. Sending it outside the outer walls "serves you no good". The base has **3 walled rings**:
  - **outer ring:** all defence;
  - **middle ring (1st inner wall):** all economy;
  - **core ring (main inner wall):** military buildings surrounding the massive Counter-Nanite facility at the centre.
  Follow-up answers (owner, 2026-10-26):
  - **Scope:** **Last Protocol only.** Normal matches keep free base building and armies that can attack anywhere.
  - **Leaving the walls:** **allowed but punished.** You can order main-army units out, but outside they're in creep
    (no suits, so exposure), cut off from repair and easy prey for packhunters. Nothing stops you; it's just a bad idea.
  - **Who runs defence:** **a defence AI Commander, with your override.** It mans walls, towers and turrets, shifts
    reserves to threatened sectors and rotates crews; you can take direct control of any sector or unit at any time.
  - **Breaches (all four):**
    - **fall back to the next ring:** survivors of an overrun ring withdraw through the gates to the next wall, and the
      gates seal behind them;
    - **economy takes the hit:** Machine forces in the economy ring wreck refineries and depots, cutting income until
      cleared and repaired, so outer losses ripple into the strike programme;
    - **walls can be rebuilt:** engineers repair breached walls and towers, under fire or after the attack, with the
      defence AI Commander setting repair priority;
    - **creep follows breaches:** creep spreads through breached sections into the rings unless purged; strike teams
      or barrier packages can seal the base edge.
  - **Air force:** **air defence plus on-call strikes.** Fighters and AA-capable aircraft defend base airspace;
    strike aircraft and helicopters fly out only as the strike team's fire support on call, then return. No
    free-roaming air war.
  - **Layout:** **airfield, artillery parks and Company HQ in the core military ring** around the facility, hardest to
    reach; artillery out-ranges the outer wall to shell attackers. The outer ring holds only walls, towers, turrets,
    bunkers and defending vehicles; the middle ring holds the economy.
- **B17, dark brainstorm (owner picked 4 of 12):**
  - **Weavers, held back until late (owner):** huge spider-mother walkers that **don't appear until 60–75% of the way
    through a Last Protocol run** (tied to the late escalation phases). They spit nanite webbing that slows vehicles and
    **cocoons soldiers**, then haul the cocoons back toward the creep. Any soldier can slowly cut a cocoon open; the
    purge and demolitions specialist (thermite) and the medic-engineers do it fast. A cocooned soldier's suit counts
    as breached, so exposure builds inside. A cocoon dragged fully into the creep means that soldier is lost.
    Animation: towering multi-leg gait, web spit, wrapping, dragging, cut-free.
  - **Living cores:** the doomsday cores are alive. They pulse, grow armour plating over time (so delays make them
    harder), and **scream on your radio** when hit. **The last core has a second phase:** when it drops low, it rips
    itself out of the ground and walks, a mobile boss. Teams must immobilise it (EMP stuns, leg damage, barrier
    packages to block its path) and land core-breakers on it while the countdown still runs.
  - **Hero detonation:** when a core-breaker (or any package) can't arm in time (dome down, site overrun), you can
    order one operator to stay behind and detonate it by hand: instant arming, certain death. The rest of the team gets
    a short window to withdraw clear. The radio reads out the operator's call sign, and the end-of-run screen lists
    them under "Remembered".
  - **The Tide (finale):** the final phase. The creep surges toward your base in one massive wave carrying every
    Machine unit it has left, and the defence AI Commander switches to maximum posture. You must hold all three rings
    while your strike teams chase down the walking last core. It triggers when the last core enters its second phase
    (or the countdown reaches its final stage), so the finale is the Tide and the boss at the same time.
  Not picked: grafting, turning operators, Dead Hand strike, Project Lazarus, the Overmind's voice, mirror fortress,
  blackout, hollow ground.
- **B18, VTOL dropships with internal cargo bays (owner):**
  - **Two kinds of dropship:**
    - the **stealth strike dropship** (the advanced, no-rotor, stealth-engine VTOL) is built only for the counter-nanite
      line and sits on its helipad inside the Counter-Nanite facility at the centre of the base;
    - the **regular Human A VTOL Dropship** (the existing `a_vtol_dropship`), upgraded.
  - **Internal cargo bay on both (owner):** each carries **one vehicle (up to strike-APC size) plus that vehicle's
    occupants plus one extra squad, all inside the cargo bay**, never slung underneath. Both airframes are enlarged as
    needed so this looks believable. The stealth dropship can lift a full strike APC with its 10 soldiers plus a
    tactical squad (8) or a second squad. It keeps its 20–25 soldier troop capacity when no vehicle is loaded, and its
    5 extraction defence drones (3 kamikaze, 2 machine-gun). Art and animation: rear ramp lowering, the vehicle driving
    in and out, the squad boarding, the bay closing, the heavier aircraft settling on landing.
  - **Uses:** exfil, insertion, moving vehicles and squads between forward bases, relief runs and other transport.
  - **Last Protocol start:** **2 regular VTOL dropships at the airfield in the core ring**, plus **1 stealth strike
    dropship on the facility helipad**. (Normal matches: the facility builds its stealth dropship; regular dropships
    are trained as now.)
- **B19, six-plus new Human A turrets (owner: "I thought we did this already??").** Not yet. Human A today has 9
  defensive structures (Guard Tower, Wall Tower, ATGM Bunker, Pop-up Remote Turret, Laser CIWS, SAM Site, Coastal
  Battery, Cruise Missile Battery, Radar Station), most added in G6. G7 adds **8 new turret types** (the owner picked
  all 8), for normal matches and Last Protocol, stage gating set in the plan:
  1. **Heavy MG nest:** a twin .50 emplacement behind sandbagged armour; shreds infantry, swarms and light walkers.
  2. **Autocannon turret:** a rotating 30 mm turret; strong against light vehicles, drones and packhunters.
  3. **Hull-down tank turret:** a 120 mm turret in a buried armoured casemate; the main anti-armour wall gun.
  4. **Auto-mortar pit:** an automated 120 mm mortar firing over the walls at massed attackers and burrower eruptions;
     needs spotting from towers or drones.
  5. **EMP projector:** EMP bursts that stun Machine units and drop drones at the wall; long recharge.
  6. **Thermite flame turret:** burns creep, seeds and small Machine units on the approach, which stops creep following
     breaches.
  7. **Microwave anti-swarm turret:** fries swarms, micro-drones and leeches in a wide cone (soft-kill, complements the
     Laser CIWS).
  8. **Rail cannon:** late-game electromagnetic gun with extreme range and penetration against the biggest Machine
     units and the walking core; slow fire, heavy power draw.
  Each gets full art (every facing, build stages, damaged state) and animation (traverse, recoil or beam, muzzle and
  impact effects). In Last Protocol the outer ring is stocked with them.
- **B20, formations rebuilt like a real military (owner: formations "still look stupid").** G6.1 already has 8
  formation types (line, wedge, column, box, echelon left/right, file, spread); the problem is how they move and look.
  G7 rebuilds them for all Human A and Human B units (this is part of Signalborne package C, squad tactics). All
  picked:
  - **New and rebuilt formations:**
    - **staggered column** on roads and tracks: two offset files, soldiers 5–10 m apart and vehicles 50 m+ apart,
      alternating sides, so one grenade, mine or missile can't hit several;
    - **wedge and diamond done right:** fire-team wedges inside a squad wedge or diamond for open ground, the leader
      near the front centre, the automatic rifle on the flank, every soldier with a sector, true spacing.
  - **Movement techniques, chosen automatically by threat:** **traveling** (contact unlikely), **traveling
    overwatch** (contact possible; a trailing element covers) and **bounding overwatch** (contact expected).
  - **Halts:** vehicles stopping on a road angle off alternately into a **herringbone** facing outward; longer halts
    form a 360° **coil**. Infantry take a 360° security ring.
  - **Behaviour fixes:**
    - **real spacing by threat:** spacing widens automatically under artillery, drone or grenade threat and tightens in
      low visibility or close terrain, never the current bunched clump;
    - **sectors of fire:** every soldier and vehicle faces its own sector (front, flanks, rear security) while moving
      and halted, so formations look alert and cover 360°;
    - **terrain-aware shape:** formations bend along roads, squeeze into file through gaps and reopen after, hug tree
      lines and walls, avoid open crossings, and never walk through buildings or stack;
    - **smooth reforming:** changing formation or direction pivots around the leader, with each soldier taking the
      nearest slot and nobody crossing through others.
  - The counter-nanite convoy (motorcade) is built on the same system. Quality bar for playtests: if a formation looks
    like a clump or a parade, that's a bug.

# G8 SCOPE (moved from G7 on 2026-10-26; every owner answer kept in the planning history below)

## G8 HEADLINE: view rotation (owner, 2026-10-27)
Owner: "add an easy way to rotate the view like in stronghold crusader -- make it seamless and easy". Asked how, the owner
chose "Full rotation as G8's headline": finish and ship G7 first; G8 makes every building, prop, terrain edge and effect
drawable from 4 sides (no mirrored or wrong-looking art), with rotation in smooth 90-degree steps on Q / E and a
middle-mouse drag (rebindable), seamless: camera keeps its focus point, selection / orders / minimap / fog / every
display layer and depth sort follow the view, UI hints show the facing. Today only 17 of 154 art generators have any
multi-view states; the renderer assumes one fixed isometric angle.

- **Strategy and economy:** dynamic single-player campaign on a dynamic map; deeper matches; richer evolutions and
  upgrades; research tree overhaul; civilians and territory; AoE3-style trade routes with location resources;
  black-market tier.
- **Combat systems:** destructible terrain; armour and ballistics (facing, angle, weak spots, ammo types); EW, drones
  and cyber beyond the G7 minimum; digging in and field fortifications; vehicle crews; vehicle maintenance and
  breakdowns.
- **Human depth:** training facilities and courses, learning by doing, readiness; Bunk and rotation with refresher
  courses; full base security (perimeter layers, threat states, hardening) beyond the G7 minimum; combined arms,
  breaching and CQB, recon and sniper teams; mutual support calls; gear and vehicle upgrades; named soldiers and
  careers; specialists and kits; veterancy completion.
- **Maps and modes:** new biomes; urban warfare depth; procedural map generator; special operations missions;
  weather and day/night (call 1); after-action reports (call 2).
- **AI:** adapts to the player; named rival generals; diplomacy and multiple factions; difficulty by intelligence;
  AI chain of command running its own operations.
- **Art and animation:** detail upgrade for all four factions (full human redraw included); the general animation
  overhaul beyond what the G7 ports need.
- **Machine faction, full overhaul:** the blended look; all 60+ defs; silhouettes; animations; hive network, adaptive
  evolution, nanite growth, modular units; minimal self-replication, eating the battlefield (incl. wrecks);
  hardest-but-fair tuning; glow team colour; its other 13 counters (strike early/cut relays, EMP/EW/hacking in full,
  deny material, sweep and purge, network virus, decapitation, starve power, reverse-engineering, firebreaks and
  hostile ground, coalitions, dead zones, hunter-killer squads as a general unit, reprogramming captured units).
- **Shadow Coalition (new 4th faction):** everything decided (identity, mechanics, full-parity roster, Stage 7→10,
  art, no counter-nanites).
- **Presentation (moved from the final G7 brainstorm):** director-cam picture-in-picture for big moments, an
  end-of-run highlight reel, and an end-of-run creep timelapse.
- **Undecided:** tactical pause with order queue.
- **Dark ideas not picked (kept as options):** grafting, turning operators, Dead Hand strike, Project Lazarus, the
  Overmind's voice, mirror fortress, blackout, hollow ground.

---

# Planning history (2026-10-26, question by question; superseded where it conflicts with the master scope)

Prepared 2026-10-26 from read-only research; this file is the only thing added to the repo. The frame images named
below (`sb_*.jpg/png`, `ours_machine_current.png`) were not copied into the repo. They live in that session's temporary
scratchpad folder (`...\scratchpad\g7_ref\`) and may be cleaned up.

## TL;DR

- **Signalborne** is a solo-built, early-development, top-down tactical RTS in **Unreal Engine 5**. Its Instagram is
  `@signalborne.game` (6,300 followers). The site is **signalborne.net**. `signalborne.game` is only the Instagram
  handle; that domain doesn't exist.
- It's a **small-scale squad game**: 5v5 on a farmstead, rifles only, no economy. You give orders and the soldiers decide
  how to carry them out. Its strengths are **believable soldier AI**, **two-way fog of war** (both sides act only on what
  they've seen), **per-body-part wounds with no health bars**, **player-flown drones** (recon, grenade-drop, FPV
  kamikaze) and a **grounded, realistic look**.
- **Our game is a different kind of game**: an isometric pixel-art base builder with up to 10k units and three
  factions. G6.1 already covers much of Signalborne's "thinking soldier" layer: suppression, fatigue, traits,
  veterancy, intel/belief, a chain of command and squad AI. The best ports are the parts we don't have yet:
  last-known-position fog, body-part wounds, drone piloting with a drone-cam view, backing off while facing the enemy,
  bounding fire teams, roof cutaway on garrisons, persistent bodies, and the realistic palette with armband team colours.
- **The machine faction's art is the weakest in the game.** It's grey boxes with cyan trim, a four-legged "table"
  walker and a brick-shaped tracked platform. The overhaul is justified. The biggest decision is the **art pipeline**:
  our procedural pixel drawers can't reach Signalborne's realism, and Blender isn't installed.

## 1. Sources (what was actually opened)

| Source | Status | What it gave |
|---|---|---|
| instagram.com/signalborne.game | Opened (logged out) | Bio, follower count, link to signalborne.net. **Only the 3 newest reels are visible without login.** |
| Reel `DeXZJoUi2T6` (Oct 11, 44 s, 9.5K likes) | Watched, 12 frames | AI showcase: blue vs white teams, flanking, leaning around a corner, wounded seeking cover |
| Reel `DeZ1yJvihCN` (Oct 12, 21.5 s, 7.5K likes) | Watched, 10 frames | Grenades: "650 fragments… each traced like a bullet", body-part wounds |
| Reel `Deh0QyVCtId` (Oct 15, 35 s, 1.6K likes) | Watched, 12 frames | Drone strike/FPV/recon drone with a full drone-cam HUD |
| signalborne.net | Opened | Tagline, Discord link, 60 s gameplay loop (`hero-720.mp4`), watched in 8 frames |
| signalborne.net/roadmap (updated 17 Oct 2026) | Opened | **Complete feature list with status: 21 in game, 4 in progress, 17 up next, 3 later** |
| Discord invite | Opened | Server name only; reading it needs an account |
| Web search (YouTube, TikTok, Reddit, Steam, press) | Searched | **Nothing found.** No Steam page and no coverage. Commenters compare it to *Defilade*. |

**Not reached:** older Instagram posts (they need a login; a direct-API attempt was blocked, so I stopped there) and the
Discord contents. If you log in to Instagram in the browser pane, I can go through the full post history.

Engine: the reel captions tag `#unrealengine5` and one says "Signalborne is a top-down tactical RTS that I'm building in
Unreal Engine 5". It's a solo developer ("I'm building this squad-level RTS solo").

## 2. Units, squads and gameplay (from the roadmap and reels)

**Already in their build (21):** squads and orders (move, take position, hold, push, search an area, fall back; soldiers
handle cover, aiming and firing) · squad movement (spread out, move in turns, watch sectors) · moving under fire
(weighs enemy distance and whether cover hides the whole route, then picks crouch, duck or sprint) · **backing off under
fire facing the enemy, still firing** · temperaments (recruit vs veteran) · **no health bars: hits land on body parts,
soldiers bleed, drop out or die** · hit reactions and realistic falls · **fog of war both ways** (the enemy also acts
only on what it saw or was told) · **fog shown in colour only where your soldiers see; elsewhere the last picture they
sent, greying as it ages** · last-known positions that fade · recon drone · strike drone (drop a mortar round) · FPV
drone · different drone blasts for ground, soldiers, walls, roofs and air · grenades thrown over cover and through
doorways, with layered explosions · new animation system (walk, run, turn, stop) · new soldier models · realistic
ground, plants and lighting · battle ambience · the arena (5v5 farmstead) · three small test maps (village, desert
compound, farmstead).

**In progress (4):** senses that follow the body (eyes and hit zones where the body is) · fixing "AI stupidities" such
as everyone halting at once when one soldier spots an enemy · weather (wind, rain, snow, fog, foliage) · procedural
house generation.

**Up next (17):** bounding · two fictional factions (Lattice, Nullband) · assaults and breaking contact · hits that
cost time · visible panic · fire teams · drone intel passed to squads · enemy commander · menus · holding ground and
ambushes · **clearing buildings, with the roof fading when your soldiers go in** · soldiers choosing when to throw
grenades · skirmish · missions with patchy intel and a debrief · casualty care (medics, dragging wounded) · suppressive
fire · a proper HUD.

**Later:** machine guns and support weapons · vehicles with optics · more maps.

## 3. Look and feel

- **Camera:** a high 3/4 top-down view of about 60°, pulled in close. Soldiers are small but readable.
  See `sb_reel2_grenade.jpg` and `sb_reel3_ai_a.jpg`.
- **Palette:** muted and realistic, with dusk-like lighting, long soft shadows, worn farm buildings, hay bales and crop rows.
- **Team identity:** realistic camo, with team shown by a **small coloured armband or helmet band** (blue team), not by
  colouring the whole unit (`sb_reel2_wounds.jpg`).
- **Buildings:** roofless or partly roofed ruins so you can see the fight inside. The planned roof fade formalises this.
- **Aftermath:** bodies stay on the ground, blood marks on the soil, wounded soldiers crawl
  (`sb_reel3_ai_b.jpg`, `sb_reel2_wounds.jpg`).
- **Explosions:** big brown dust clouds with debris that linger and drift, rather than bright fireballs.
- **Drone-cam HUD:** a compass tape at the top, a dashed circular reticle, prompts ("MUNITION AWAY", "ARMED", "LINK LOST",
  "RNG 20 M LIVE"), key hints along the bottom ("A-S-D FLY · Q-E TURN · SPACE RELEASE · B EXIT", "MOUSE AIM · W-S SPEED
  · C DETONATE") and a mission timer (`sb_reel1_*.png`, `sb_reel1_fpv_drone.jpg`).
- **Site branding:** a greyscale, thermal-style drone feed of the desert compound with soldiers glowing white, "REC
  12:57:48Z" timecode, corner brackets and an orange slashed "S" (`sb_site_hero_thermal.jpg`).

## 4. Animation seen in the videos

Smooth walk, run and turn transitions · crouched movement near cover · leaning or peeking around corners · hit
flinches by body zone · ragdoll-style falls · crawling wounded · grenade-throw arcs · FPV dive from horizon to target ·
grenade release seen from above · drone-feed shake and the "LINK LOST" cut on impact.

Viewer critique on reel 3 (useful for us too): "smooth out the direction and velocity changes". Another viewer pointed
out that retreating soldiers turned their backs, and the developer has since shipped backing off while facing the enemy.

## 5. What viewers ask for (demand signal)

Fire and manoeuvre with a support element · names, personalities and doctrines for soldiers · concussion or knock-down
states · terrain variety (desert, mountain, jungle) · custom flags and uniforms · tripping and jumping · "is this real
time or more like XCOM?" Several commenters mistook it for *Defilade*, so this niche (realistic squad RTS) is getting
crowded.

## 6. Port map: what fits our game, and where it would go

Rule for every port: **detail is only drawn when zoomed in.** Our zoomed-out 10k-unit view and the fps gates (2k p10 ≥
60, 10k p10 ≥ 30) stay untouched, and nothing presentation-only may change the sim hash.

| # | Signalborne feature | We already have | Port | Touches (our code) | Fit / cost |
|---|---|---|---|---|---|
| 1 | Fog shows the last picture, greying with age | `sim/systems/intel.gd` tracks last-known contacts with decaying confidence; `entity_layer.gd` ghosts remembered buildings | Draw enemy **unit** last-known markers that desaturate and fade with `conf`/`age`; tint the fogged map grey instead of dark | `entity_layer.gd`, `fog_layer.gd`, `overlay_layer.gd` (view only) | High fit, low-medium cost |
| 2 | No health bars; body-part wounds; hits that cost time | HP plus suppression and morale (`morale.gd`) | Infantry get hit zones (legs slow them, arms reduce accuracy, torso or head down them), a wounded or crawling state and bleed-out. Optionally hide HP bars for infantry when zoomed in. (Your earlier G7 pass kept "wounds/field medicine" as an unchosen option.) | `combat.gd`, `damage.gd`, `morale.gd`, a new wounds system, `batch_art` (wounded/crawl frames already exist from ANIMA61) | High fit, medium cost (determinism and perf) |
| 3 | Player-flown drones with a drone-cam view | Drones exist (recon UAV, loitering munitions in `strikes.gd`, counter-drone, EW) | A "take control" mode: picture-in-picture or full-screen feed of our own map, zoomed, with a greyscale or thermal shader, a compass tape, a reticle, drop/dive keys and LINK LOST on hit or jam. It ties into the EW, drones and cyber scope you already picked for G7 (Q3). | `strikes.gd`, `counterdrone.gd`, a new drone-cam view plus shader, `camera_rig.gd`, the HUD | Very high fit (the clearest "wow" port), medium cost |
| 4 | Shrapnel traced per fragment | Splash damage | A **deterministic sampled** version: N fragment rays (N scaled by tier) blocked by walls and cover, so cover really protects | `combat.gd`/`damage.gd` and the native core | Medium fit; 650 rays per grenade is too heavy at 10k, so it needs a budget |
| 5 | Back off facing the enemy | Retreat on morale break (turns and paths home) | A walk-backwards and fire posture for ordered fall-backs; run only when broken | `squad_ai.gd`, `motion.gd`, frames | High fit, low cost |
| 6 | Moving under fire (crouch, duck or sprint) | Suppression, pinned, prone frames (ANIMA61) | Pick gait from threat and cover along the route | `movement.gd`/`squad_ai.gd`, `motion.gd` | High fit, low-medium cost |
| 7 | Bounding and fire teams | G6.1 SQUAD61 formations and squad AI, team panel | Split squads into A and B teams: one covers (suppressive fire) while the other moves | `squad_ai.gd`, `formations` | High fit, medium cost; viewers ask for it too |
| 8 | Roof fades when soldiers go in | Garrisons (`garrison.gd`) | Cutaway building sprite variant (roofless) drawn while it holds own troops or is under your view | building art, `entity_layer.gd` | High fit, medium art cost |
| 9 | Bodies, blood and dust linger | ANIMA61 corpses fade with a cap | Longer-lived ground decals (blood, scorch, craters, debris), capped by count | `fx61_*`, `fx_layer.gd` | High fit, low cost |
| 10 | Realistic palette and armband team colours | Whole-unit team mask (`*_mask.png`) | Shrink the team mask to an armband, helmet band or vehicle stripe, with a realistic base palette (needs a readability check at 10k zoom-out, where LOD icons keep the team colour) | all unit drawers, `batch_art.gd`, `lod_icons.gd` | Depends on the art-direction decision |
| 11 | Temperaments, panic you can see | G6.1 traits, veterancy, morale break | Visible panic animation (cower, flee, drop weapon) and a temperament tag in the soldier card | `motion.gd`, frames, the HUD | High fit, low cost |
| 12 | Weather | Not in scope (kept as an option in your G7 pass) | Rain, fog and wind layers with a sight-range effect | new system | Your call |
| 13 | Drone intel shared with squads | `intel.gd` belief per side | Already broadly there: sightings feed side belief. The new part is per-squad knowledge (soldiers know only what they or their net saw) | `intel.gd`, comms (CHAIN61) | Medium fit |
| 14 | Missions with patchy intel and a debrief | Stages, scenarios | Fits your G7 dynamic campaign (Q1) and after-action reports (an unchosen option) | campaign layer | Campaign-dependent |

**Not to copy:** names (Signalborne, Lattice, Nullband), the "S" logo, the exact HUD layout or any assets. The
mechanics and the general look are fair inspiration; the specific branding is theirs.

## 7. Animation upgrades on top of G6.1

G6.1 is already delivering a big pass. ANIMA61 added walk/run ≥ 6 frames, prone, crawl, fire poses, reload, throw,
die ×3, wounded and idle breathing. ANIMB61 added turrets, recoil, tracks, banking and wakes. ANIMC61 is wiring the
vehicle frames on screen **right now**. G7 should build on that, not redo it:

1. **Direction and velocity smoothing:** accelerate into turns, plant and pivot, no instant 180s (the same note viewers
   gave Signalborne).
2. **Transitions:** stand↔crouch↔prone, start and stop steps, so state changes stop popping.
3. **Hit reactions by zone:** leg hit → stumble or limp, torso → knock-back, explosion → thrown or knocked down (the
   concussion request).
4. **Context poses:** lean or peek at corners, fire over walls, fire from windows (garrison), grenade wind-up and throw.
5. **Wounded loop:** crawl to cover, being dragged by a squadmate (if casualty care is in).
6. **Vehicles:** suspension settling after stops, dust trails by speed and ground type, hull rock on hits, crew bail-out.
7. **Explosions:** layered dust columns that drift with wind (the Signalborne look), debris arcs, lingering haze.

## 8. Machine faction overhaul

**Today** (`tools/art/faction_m*.gd`, `g3b_machine.gd`, `faction_m_walker.gd`, `faction_m_drone.gd`; preview in
`ours_machine_current.png`):
- **Roster:** 60+ `m_` defs across units, air, naval, buildings and G6 companies: Scout Crawler, Tracked Platform, Heavy
  Walker, Siege Crawler, Colossus, Hover Tank, Stalker Synth, Lancer, Swarm and Swarm Queen, Mimic/Stealth/Shield
  drones, Assimilator, command nodes, the Overmind and others.
- **Look:** flat grey slabs with cyan light strips. The walker and Colossus are a box on four straight legs. The
  Tracked Platform is a brick with tank treads. Silhouettes are hard to tell apart and read as placeholders next to the
  human factions.
- **Animation:** the G6.1 brief gives Machine walkers ≥ 6-frame leg cycles, drone hover bob and energy pulse frames.
  That's motion added to the same weak designs.

**Overhaul scope (proposal):**
1. **One design language.** Pick a fiction: grounded near-future military robotics (quadruped UGVs, tracked robot
   carriers, sensor masts, matte olive or grey with IR strobes), insect or hive bio-mech (segmented legs, carapace
   plates, swarming), or sleek sci-fi (hover, light strips). That's the first question below.
2. **Silhouette per role:** scouts low and fast (hex or quad legs), assault walkers digitigrade, artillery a deployable
   mortar or rail spider, the Colossus a multi-leg siege platform, drones distinct by rotor or wing count.
3. **Machine-only animations:** leg gaits per chassis (quad trot, hex ripple, biped stride), deploy and undeploy
   (legs splay, mast rises), sensor sweep (head or mast scanning), self-repair (arms or nanite shimmer), assimilate
   (beam plus reassembly), hover drones banking and swarming in flocking patterns, death by **breaking apart**
   (sparks, legs buckle, core flash), not a human-style fall.
4. **Machine readouts** borrowed from Signalborne's HUD style: target brackets, scan lines and a "network" overlay when
   a Machine unit is selected (relay links from `rules_machine.json` relay ranges).
5. **Scale:** every `m_` unit, wreck and icon (about 40 unit defs, plus buildings if you want them in scope).

## 9. Constraints and risks

- **Pipeline vs realism.** Our art is drawn by GDScript generators into pixel sheets (8 facings plus team mask).
  Signalborne-level realism needs either much larger, detailed procedural sprites or **pre-rendered 3D**: model,
  render 8 facings × N frames, pack into our sheets. **Blender isn't installed** (checked); adding it needs a download.
- **Memory:** ANIMC61 is fighting atlas growth right now (vehicles went from 87.7 to 164.7 MB decoded, infantry from
  30 to 110 MB). More frames at higher resolution makes this worse, so mirroring and packing must carry over.
- **Determinism:** wounds, shrapnel and gait-from-threat change the sim. They need hash tests like every G6 system.
  The drone cam, fog look, decals and animation are view-only.
- **Timing:** G6.1 agents are live on board `board_g61.jsonl` (ANIMC61, INTEG61-2, PERF61). G7 should start after
  G6.1 lands to avoid collisions in `entity_layer.gd`, `batch_art.gd` and `squad_ai.gd`.
- **Style coherence:** a realistic Machine faction next to pixel-art humans would clash. Either the whole game moves,
  or the machine pass becomes the pilot for a game-wide move.

## 10. G7 questions (asked one at a time)

1. Art direction and pipeline for the overhaul.
2. Machine faction fiction and design language.
3. Which Signalborne ports go in G7 (from section 6).
4. Body-part wounds and casualty care: in or out.
5. Drone piloting: full-screen take-over or picture-in-picture, and which drones.
6. Machine overhaul scope: units only, or units plus buildings.
7. Delivery shape (one big drop like G6.1, or staged).

## Answers log

(filled in as you answer)

- Q1 art pipeline (2026-10-26): **Upgraded pixel art.** Keep the procedural pixel pipeline, with bigger and more
  detailed sprites, better silhouettes and more frames. No Blender. Realism comes from palette, shading, silhouettes and
  animation, not 3D renders.
- Q2 machine look (2026-10-26, owner's words): "a mix of grounded military robots but advanced + hive/insectoid
  bio-tech + sleek sci-fi 1000 years technologically advanced from humans". Reading: a three-layer blend. The base is
  grounded military robotics (believable chassis, purposeful hardware), grown with hive/insectoid bio-tech (segmented
  legs, carapace, swarming, organic growth), and finished like far-future tech (seamless surfaces, energy, hover, no
  visible human-style engineering). Each layer can map to the faction's tiers: early stages read most "military
  robot", Stage 10 reads most "1000 years ahead".
- Q3 ports (2026-10-26): **all four packages.** Drone piloting and drone cam; soldier realism (body-part wounds, hits
  that cost time, crawling wounded, gait under fire, backing off facing the enemy, visible panic); squad tactics
  (bounding fire teams, suppressive fire, ambush/hold, building clearing with roof cutaway); battlefield look (grey fog
  with fading last-known positions, lingering decals, dust explosions, armband team colours).
- Q4 drone cam (2026-10-26): **both, player toggles.** Starts picture-in-picture; a key switches to full-screen; the
  battle keeps running.
- Q5 machine scope (2026-10-26): **everything Machine.** Every m_ unit, drone, naval unit, building, wreck and icon
  (60+ defs) redesigned in the blended language, with new animations.
- Q6 fit with earlier G7 scope (2026-10-26): **everything in G7.** All the earlier G7 scope (campaign, research tree,
  civilians and territory, destructible terrain, armour and ballistics, EW/drones/cyber, named soldiers, specialists,
  adaptive AI, rival generals, diplomacy) plus all of this, in one slice.
- Q7 realism at scale (2026-10-26): **full rules, budgeted by sim tiers.** Same rules for every soldier; the expensive
  parts (fragment rays, per-step gait choice) are tier-budgeted. Deterministic, and the perf gates stay.
- Q8 delivery (2026-10-26): **one drop plus an early look checkpoint.** You approve the blended Machine design from 3–4
  sample units (frame strips) before all 60+ defs are drawn; then one packaged build at the end.

Still open for the G7 plan (not asked yet): exact Done-when numbers, agent wave size, and whether armband team colours
also apply to the Machine faction (markings vs light colour).

## Second pass (2026-10-26): 4th faction, conflicts, depth

- **4th faction in G7, fully overhauled (owner directive, 2026-10-26).** The 4th faction gets a complete overhaul with
  much better, detailed graphics for every unit, building, vehicle and everything else. Today it exists only as 4
  concept assets in `docs/g6_art_kit` (Technical, Tunnel Network, Ambush Cell, Captured Tank; `x_*` ids) plus a
  headscarf variant in `tools/art/g6_infantry.gd`. It has no content defs, sim rules or AI, so G7 builds the faction
  end to end.
- Conflict 1, weather + day/night: **in G7, full dynamic.** Setup option Off / Fixed / Dynamic. Rain, fog, snow, wind
  and a day/night cycle affect sight, accuracy, movement and drone flight. Night brings night vision, thermals and
  flares.
- Conflict 2, casualty care: **full chain.** Buddy aid and squad medics treat on the spot; soldiers drag wounded to
  cover; stretcher teams, vehicles or helicopters evacuate to the G5 hospitals. Treated soldiers return; named soldiers
  keep scars and careers. Time-to-treatment ("golden hour") matters.
- 4th faction identity (owner's words): "some cross between irregulars being done properly + private military company
  + insurgents + PMC backers + terrorist group". Reading: a fictional asymmetric coalition, in the tradition of C&C
  Generals' GLA. Insurgent and irregular fighters on the ground (technicals, tunnels, IEDs, ambush cells, captured
  kit), a radical cell wing (raids, sabotage, suicide-drone and VBIED-style shock tactics, fear and propaganda), and a
  PMC patron selling elite contractor teams and high-end support for money, loot or territory. Fictional names only,
  no real-world groups.
- 4th faction mechanics, picked: **hide among civilians** (blend in until they act; telling them apart needs recon or
  intel; civilian harm costs support) · **tunnels and caches** (unseen moves between hidden entrances; caches resupply
  and respawn cells; collapsible by destructible terrain) · **contracts and patron** (money buys PMC teams and patron
  support such as drones, advisers and air strikes on contract timers; favour grows with territory and loot) ·
  **IEDs, traps and shock raids** (roadside bombs, booby-trapped buildings, drone-borne charges, car-bomb-style shock
  units, sabotage cells hitting supply, power and comms) · **scavenge and capture** (salvage wrecks for income, capture
  and refit enemy vehicles and weapons, scrap-armoured technicals).
  Not picked: recruitment and propaganda, mobile hidden bases. The owner asked for "even more depth - brainstorm",
  so the brainstorm follows.
- 4th faction brainstorm, picked: **weld-shop technicals** (a garage customises technicals and captured vehicles part
  by part: MG, rockets, AA, recoilless, slat armour, mortar bed; improvised artillery such as truck rocket racks) ·
  **black market and mercenary loyalty** (a black-market tier of the G6 marketplace for smuggled gear; PMC contractors
  desert or switch sides when pay runs late; fanatics hold to the last on home ground).
  Not picked: cell command, informants and hacked drones.
- Art across factions: **all four factions get the full detail upgrade.** Every unit, vehicle, building, wreck and
  icon in the game is redrawn at the new detail level (upgraded pixel art), with realistic uniforms and armband team
  colours. Machine and the 4th faction are also fully redesigned.
- Logistics depth (owner's words): "some sort of supply chain line similar to Age of Empires 3 (when you own that
  building or trade route you get the income for that location/territory + resources according to that location)".
  Reading: trade routes across the map with posts or nodes to capture; holding a post pays steady income, and each
  territory or location yields its own resource mix. Fits the G7 territory and campaign scope. Also picked: **dig in and
  field fortifications** (foxholes and trenches dug over time; sandbags, wire, tank ditches and minefields that persist)
  and **vehicle crews** (named driver, gunner and commander; hits kill or wound crew; crews bail out and fight on foot;
  empty vehicles can be re-crewed or captured, which ties into the 4th faction's capture mechanic).
  Not picked: convoy-based physical supply lines, industry chains.
- Command and fire support, picked: **special operations.** Raids, high-value-target snatches, sabotage, hostage
  rescue and exfil under fire, playable inside matches and the campaign.
  Not picked: call-for-fire with observers, radio delay and jamming, rules of engagement.
- Presentation and replay, picked: **after-action reports.** After each battle: a timeline map of moves and kills,
  casualties by cause, MVP soldiers, decisive moments and what the enemy general did; feeds named-soldier careers.
  Not picked: replays and cinematic camera, soldier follow cam, photo mode.
- Maps and modes, picked: **new biomes** (desert, mountain, jungle, arctic, dense urban, each with its own terrain,
  cover, weather and building styles) · **urban warfare depth** (multi-floor buildings, room-by-room clearing, sewers
  and rooftops, rubble that changes routes) · **procedural map generator** (seeded random skirmish and campaign maps
  with terrain, elevation, rivers, towns, trade routes and civilians placed fairly).
  Not picked: co-op vs AI (multiplayer stays out).
- Machine gameplay, **all four picked:** **hive network** (shared sensor and intel picture over relay links; cut relays
  isolate units, which drop to simpler local AI) · **adaptive evolution** (studies what kills it mid-match and evolves
  countermeasures such as armour against your main gun type or new drone variants) · **self-building and nanite
  growth** (structures grow outward like a living network, reprocessing wrecks and terrain, spreading over territory)
  · **modular units** (drones merge into walkers, walkers split into swarms, modules swap roles in the field).
- Machine team colour: **glow colour.** Sensor eyes, energy seams and relay links glow in the team colour; readable at
  night and in the drone feed.

## Third pass (2026-10-26): remaining open items

- 4th faction name: **Shadow Coalition.** The PMC patron gets its own fictional sub-name, to be set in the plan.
- Shadow Coalition roster: **full parity**, about 60 defs, the same breadth as the other three factions. Infantry
  cells, technicals, captured armour, drones, boats, buildings, company types, officers, air support through the
  patron, and a full Stage 7→10 path with its own Stage 10 elite units. Ready for skirmish, survival, editor and
  campaign.
- Done-when (owner's words): "keep it light, I'll be testing this in large part via gameplay -- your test should only
  focus on what I can't complete myself in gameplay". Reading: automated checks cover only what play can't show:
  - the existing suite stays green (no regressions);
  - determinism and hash checks for every new sim system;
  - perf and fps numbers (2k on screen p10 ≥ 60, 10k zoomed out p10 ≥ 30);
  - headless long-run and AI-vs-AI soaks for crashes and invariant failures (no winner requirement);
  - the packaged build launches from a clean folder with 0 SCRIPT ERROR.
  The owner checks feel, look, balance and features by playing, plus the look checkpoints (Machine samples, Shadow
  Coalition samples, final art). The G6-parked 10k-speed and soak-winner targets stay parked.
- Agent wave size: **6 live** (the standing cap, as in G6.1).

## Fourth pass (2026-10-26): human depth + Machine threat

- **Human factions: deeper military capability (owner directive).** In the owner's words: "our human units need even
  better military training/operations/tactical capabilities/better teamwork/everything for even more depth and
  upgrades". This builds on what G6.1 ships (officer battle drills, company training, squad AI and formations,
  suppression, fatigue, veterancy, traits, chain of command, comms, intel).
- **Machine faction = the hardest faction to face (owner directive).** In the owner's words: "AI faction is the hardest
  faction to face and they grow like cockroaches without the right tactical advantages taken against it -- not
  impossible to beat though". Reading: the Machine snowballs (nanite growth, self-building, modular units, adaptive
  evolution) unless the opponent uses specific counters. It must stay beatable through tactics, with its strength
  coming from its rules, not hidden cheats, consistent with "difficulty by intelligence, not cheats".
- Human training, picked: **training facilities and courses** (ranges, shoot house, driving and gunnery range, officer
  school; timed courses such as marksmanship, CQB, medic, demolitions and drone pilot teach skills and unlock kit) ·
  **learning by doing** (skills grow with use and persist with named soldiers across the campaign) · **exercises and
  readiness** (readiness drops with losses, fatigue and fresh replacements and rises with field exercises behind the
  lines; well-drilled companies get cohesion bonuses). Not picked: player-designed drills.
- **Owner note, a secured base is a core strategy:** "building a secured base to allow training facilities to operate
  unadulterated is a huge factor in this game for player to strategically increase chances of winning --- more
  realism -- better base building in G7". Reading: training, courses and exercises only run at full speed while the
  base is secure; enemy pressure, raids, shelling or infiltration interrupt or degrade them. Base building gets a
  realism and depth pass in G7.
- Base building, picked: **perimeter and security layers** (walls, fences, gates, watchtowers, checkpoints, cameras,
  floodlights, patrol routes; "secure" only when the perimeter is closed and watched) · **base threat states**
  (secure / contested / under fire / breached set training, production and repair speed; indirect fire, drones and
  saboteurs can degrade a base without a full assault) · **hardening and bunkers** (blast walls, camouflage nets,
  underground shelters, air-defence cover; hardened sites keep training running). Not picked: layout rules (road
  access, power lines, blast spacing).
- Human tactics, picked: **combined-arms teamwork** (infantry screens armour from AT teams, armour gives mobile cover
  and fire, engineers breach, drones spot, artillery on call) · **breaching and CQB** (stack on doors, flashbang or
  frag, room entry with sectors, wall-breaching charges, vehicle-assisted breaches) · **recon and sniper teams**
  (sniper and spotter pairs, long-range recon patrols, observation posts, camouflage and stalking, counter-sniper
  drills).
- **Owner note, AI uses operations itself:** "AI command structure can utilize operational capabilities as available
  and possible to execute their own missions/approaches". Reading: the AI chain of command (AI Commanders on your side,
  enemy generals, captains and lieutenants) plans and runs its own multi-phase missions with whatever capabilities it
  has: combined arms, breaching, recon and snipers, special ops, drones and fire support. The player-facing
  operations-planning tool was not picked as a separate feature.
- Human teamwork and upgrades, picked: **mutual support calls** (units call for covering fire, smoke, medevac, armour
  support or resupply on their own; free friendly units nearby answer, even across companies) · **gear and vehicle
  upgrades** (optics, suppressors, body-armour tiers, night vision, radios; vehicle kits such as active protection,
  reactive armour, thermal sights, remote weapon stations). Not picked: cohesion bonds, doctrine trees. The owner asked
  for "more realism depth", so a realism follow-up comes next.
- Human realism, picked:
  - **Rest and rotation (owner's design):** "human units need to rest in a new building 'bunk' after their energy
    reaches near depletion to restore their stamina for battle -- this will require some sort of squad rotation that
    makes sense realistically how they'd operate on the front lines in real war". Reading: a new Bunk (barracks
    quarters) building restores stamina; near-depleted units must rotate back. Front-line rotation follows real
    practice: units cycle between the line, support or reserve positions, and rest, so the line stays manned. This
    builds on G6.1 fatigue.
  - **Vehicle maintenance and breakdowns:** wear by use and terrain, thrown tracks, engine faults, bogging in mud or
    snow; recovery vehicles tow and repair; maintained fleets break down less.
  - **Realistic sensors and sight:** a view cone where the head points; spotting by movement, silhouette and noise;
    hearing gunfire to locate the enemy; optics, thermals and NVG change what is seen.
  Not picked: ammo counts and weapon handling (jams, overheating).
- Rotation management: **chain of command runs it, the owner can override.** Lieutenants and captains rotate squads
  (line → reserve → bunk → back) under a per-company rotation policy; the owner can force or block any rotation.
  **Owner addition:** after resting, a squad is either redeployed or sent to a short course at a training facility
  "to better their skills (learn what they did wrong last deploy and enhance)". Reading: a debrief step uses the
  squad's last deployment (from the after-action data: e.g. losses to flanking, poor cover use, missed shots) to pick a
  targeted refresher course; the course improves exactly those skills. It only runs at full speed while the base is
  secure.
- Machine growth drivers, picked: **minimal self-replication** (owner: "we don't want to make them unbeatable just
  difficult"; fabricators can add a little, without compounding runaway growth) · **eats the battlefield** (reprocesses
  wrecks, rubble, destroyed buildings and enemy dead vehicles into material; careless fighting feeds it) · **dormant
  seeds** (hidden seeds and burrowed cores survive a base wipe and regrow unless scanned and destroyed) · **spreading
  creep** (a nanite network spreads across the ground, expanding territory, powering and repairing everything on it,
  and slowly converting terrain).
- Machine counters, **all four picked:** **strike early and cut relays** (isolated units drop to dumb local AI; creep
  stops growing on cut-off ground) · **EMP, EW and hacking** (EMP stuns, jammers blind the hive network, cyber teams
  briefly hijack or shut down nodes; a dedicated anti-Machine tech line) · **deny it material** (salvage, thermite and
  scorched earth so it can't eat wrecks; recover your own wrecks first) · **sweep and purge** (scanners and drones reveal
  seeds and creep cores; flamers, thermobarics and demolition sterilise ground so it can't regrow).
- Machine hardness: **hardest, but fair.** At equal difficulty it is the toughest opponent. A player who ignores the
  counters loses most games; one who uses them wins most. In AI-vs-AI it beats each other faction more often than
  not, but not every time. This is a balance target for tuning and your playtests, not an automated Done-when gate
  (Done-when stays light).
- **More ways to beat the Machine (owner, 2026-10-26):** "we need more ways to beat the AI faction since it'll be so
  difficult as they ARE supposed to be superior in tech". Six more counters picked, for ten in total:
  - **Network virus:** capture or hack a node and plant a virus that spreads through the relay network (cascading
    shutdowns, units freezing or turning on each other). High payoff, hard setup; a special-ops mission.
  - **Decapitation strikes:** killing Overmind, Commander, Captain or Lieutenant nodes collapses coordination in that
    area until rebuilt. They're heavily defended high-value targets.
  - **Starve its power:** destroying charging hubs, power cores and relay lattices leaves units on reserve batteries;
    low-power units slow, stop repairing and go dark.
  - **Reverse-engineer its tech:** recover Machine cores and wrecks to research counter-tech (nanite-disruptor rounds,
    captured sensor tech, hardened electronics). The more you kill and study it, the better you fight it. Competes
    with the Machine's own "eats the battlefield", so wreck recovery becomes a race.
  - **Firebreaks and hostile ground:** creep can't cross water, burnt, salted or cratered ground. Engineers cut
    firebreaks and trenches to contain spread, and weather (lightning storms, heavy rain, deep cold) slows it.
  - **Coalitions against it:** through diplomacy, other factions (even enemies) form temporary truces or joint
    operations against an over-strong Machine, then return to rivalry once it's pushed back.
  Not picked: baiting its adaptation, low-tech immunity.
- **Further Machine counters (brainstorm round 2):** four more picked, for fourteen in total:
  - **Dead zones:** its network signal fails underground, in tunnels, deep urban canyons, dense mountains and storms;
    units there lose the hive link, so terrain choice becomes a weapon (ties into the hive network, Shadow Coalition
    tunnels, urban warfare and weather).
  - **Hunter-killer squads:** specialist anti-Machine infantry with magnetic limpet charges, net and harpoon guns that
    tangle walker legs, EMP grenades and anti-drone shotguns; trained at the new training facilities.
  - **Reprogram captured units:** disable Machine units with EMP, then engineers or cyber teams reprogram them to fight
    for you permanently, at lower efficiency and only while kept off its network.
  - **Counter-nanites, owner's design:** "make it a late game unlock that's super expensive + add a counter-nanite
    strike team that will unlock with its own training facility that trains the strike team and specialized armoured
    APCs with advanced shielded tech and weapons capabilities". Reading: a top-tier, very expensive research unlock that
    releases counter-nanites to eat creep and dormant seeds over an area and permanently clear ground. It also unlocks a
    **Counter-Nanite facility** (its own training building) that trains a **Counter-Nanite Strike Team** and builds
    **specialised armoured APCs** with advanced shielding and weapons to carry and protect them. **Human A and Human B
    only** (owner confirmed 2026-10-26); the Shadow Coalition can't buy it, even through its patron.
    **Facility size (owner note):** the Counter-Nanite facility is a **large compound**: garage bays housing **5–8
    APCs**, plus the actual training facilities (plural) inside it. A full deployed group is 5 APCs (2 strike + up to
    3 tactical), so the bays fit the whole group with spares. APCs are built, parked, repaired and restocked there.
    **Facility defences (owner):** the facility has its own defences **on each side** of the compound and at the
    **entrance and staging ground**. Proposed, to confirm in the plan:
    - each side: a hardened defence tower with a remote weapon station, a counter-drone emitter, and interceptors that
      shoot down incoming shells, rockets and drones;
    - the perimeter: blast walls, a short-range EMP field against Machine units at the walls, and the same unhackable
      electronics as the APCs;
    - the entrance and staging ground: an armoured gate and checkpoint, anti-vehicle barriers, overlapping fire from
      the side towers, and smoke launchers that cover APCs while they form up and roll out.
    These count toward the base's "secure" state (base threat states), so training keeps running under pressure.
    The owner approved this defence set ("exactly what I'm looking for", 2026-10-26).
    **Comes fully fortified (owner):** the facility is built **already gated and fortified**: perimeter walls, the
    armoured gate and checkpoint, the side towers and all the defences above are part of the building itself. They
    complete when construction completes, with no separate wall or tower orders. Its high cost covers them.
    **Delivery rule (owner note):** counter-nanites can only be placed by that faction's own Counter-Nanite Strike
    Teams, on the ground. There's no remote or off-map release: the team (protected by its APCs) has to reach the
    creep or seed site and deploy them there.
    **Team and vehicles (owner, revised):** a full Counter-Nanite Strike Team is **20 soldiers in two 10-soldier
    squads**, each riding its own **modified APC**, so **2 APCs** per team. It operates **only** as the full pair:
    one squad alone can't run a deployment. Each APC is **larger than a regular APC**, big enough for its whole squad
    plus its share of nanite **"strike packages"** (the counter-nanite charges). The owner asked for more security
    than the 10-soldier draft. **Only ONE leader for the whole 20-soldier team (owner).** Proposed roles, to confirm
    in the plan:
    - Both squads: 1 second-in-command and radio operator (squad B's runs that squad under the team leader), 2
      deployment specialists, 1 scanner technician, 1 EW specialist, 1 combat medic and engineer.
    - Squad A (with the leader): **1 team leader** (commands all 20, picks the deployment site) and 3 security gunners.
    - Squad B (no leader): **4 security gunners** (the freed leader slot becomes another gunner).
    Team totals: **1 leader**, 2 seconds-in-command/radio, 4 deployment specialists, 2 scanner technicians, 2 EW
    specialists, **7 security gunners** (hunter-killer kit: EMP grenades, anti-drone shotgun, limpet charges), 2
    medic-engineers = 20. If the leader falls, squad A's second-in-command takes over (matches the G6 rule that the
    next in line steps up). The APCs' package capacity and their reload point (the Counter-Nanite facility) get set in
    the plan.
    **APC transit guns (owner note):** each strike-team APC has **two mounted .50 cal machine guns, one front and one
    rear**, on rotating mounts with **protective gun shields** around the gunner. While the APC is moving (to the
    mission site, or back to base or the facility garage), each mount is manned by one of the team's security gunners:
    2 per APC, 4 across the team (squad A uses 2 of its 3 gunners, squad B 2 of its 4). The gunners are visible on the
    mounts and each traverses independently toward threats; when the team dismounts at the site, they climb down and
    join security on foot. Art and animation: the mount traverses through all facings, shows a shielded gunner figure,
    muzzle flash and recoil per gun, and the gunner can be hit and replaced from inside.
    **Most advanced human APC (owner):** on top of the two .50 cals, the strike-team APC is the most advanced APC any
    human faction fields, with advanced weapons and defences (as asked earlier: "advanced shielded tech and weapons
    capabilities"), and it is **unhackable**. Proposed kit, to confirm in the plan:
    - **Unhackable:** hardened, shielded electronics with a manual fallback. Immune to Machine hacking, takeover,
      network viruses and EMP. Its own systems can't be jammed off, and the Machine's adaptive evolution can never
      learn a way to hijack it.
    - **Shield dome:** a deployable energy shield over the APC and the team while they arm and place strike packages;
      it soaks fire for a limited time, then needs to recharge.
    - **Active protection:** hard-kill interceptors that shoot down incoming missiles, shells and kamikaze drones.
    - **Anti-drone emitter:** a directed-energy (laser or microwave) emitter that burns down drones and swarms around
      the vehicle.
    - **EMP pulse projector:** a short-range pulse that stuns nearby Machine units and drones (the APC itself is immune).
    - **Side pop-out defence panels (owner):** armoured panels on both sides of the hull pop open to fire:
      - **side interceptors:** short-range interceptor rounds against incoming missiles, shells and drones from the flanks;
      - **smoke bombs:** smoke screens to hide the APC and the team (fired from the same panels);
      - **interceptor drones** (the owner's reference is Anduril-style counter-drones; in game they get a fictional
        name, no real brand): small autonomous drones launched from the panels to hunt and ram enemy drones and swarms
        around the APC, then return or expend themselves; limited stock, restocked at the Counter-Nanite facility.
      Art and animation: the panels visibly open and close, with launch puffs, smoke plumes and drones leaving the rails.
  - **Counter-Nanite Tactical Operators (owner, new unit):** a trainable tactical squad that escorts and defends the
    main 20-soldier strike team on the front line and helps it push the Machine back.
    - **Squad size and cap:** **8 operators per squad**, at most **3 squads deployed at a time** (24 operators).
    - **Training:** trained directly at the **Counter-Nanite facility**; each squad **spawns inside its own APC**.
      **Tactical APC (owner):** holds the 8-operator squad and has **only one roof-mounted, rotating, dual-barrel .50
      cal**, **remote-operated** from inside (owner), so no operator is exposed on the roof. Defences are **the same as
      the larger strike APC** (owner): unhackable, shield dome, active protection, anti-drone emitter, EMP pulse, side
      pop-out panels (interceptors, smoke, interceptor drones), top-tier armour, chaff, sealed cabin, reduced heat
      signature.
    - **Specialisations:** every operator has their own specialisation and gear loadout, plus special anti-Machine
      gear. Proposed 8 roles, to confirm in the plan:
      - squad leader;
      - designated marksman (nanite-disruptor rounds, picks off sensor eyes and relay nodes);
      - 2 hunter-killer assaulters (limpet charges, net and harpoon guns against walkers);
      - EMP grenadier (EMP grenade launcher to stun groups);
      - anti-drone specialist (anti-drone shotgun and a portable jammer);
      - purge and demolitions specialist (thermite and thermobaric charges to burn creep and wrecks);
      - combat medic.
    - **Job:** move with the strike team, screen its flanks, clear Machine units and drones ahead of the deployment
      site, hold the perimeter while the packages are placed, and cover the withdrawal. Human A and Human B only, like
      the rest of the counter-nanite line.
  - **Convoy movement, motorcade style (owner):** when the full package moves across the map (the 20-soldier, 2-APC
    strike team plus its 2–3 tactical operator squads), it moves as one **tight formation**, using "pure tactical
    movement (think presidential motorcade)". The tactical squads' APCs protect, defend and **physically shield** the
    strike APCs from enemies while moving. Proposed behaviour, to confirm in the plan:
    - **Layout:** the two strike APCs ride in the centre. Tactical APCs take the lead, the rear and (with 3 squads)
      the threatened flank. With 2 squads, lead and rear, sliding to the threat side when contact comes.
    - **Shielding:** on contact, the nearest tactical APC moves between the threat and the strike APCs, taking the fire
      and using its own defences (side panels, smoke, interceptor drones).
    - **Keep moving:** the core never stops in a kill zone. One tactical squad can peel off to counter-attack and hold
      the threat while the rest of the convoy pushes through, then rejoins.
    - **Spacing and pace:** fixed spacing between vehicles, the speed of the slowest vehicle, roads where possible, and
      a tighter column through chokepoints.
    - **Stops:** at the deployment site or any halt, the tactical squads dismount and form a perimeter around the
      strike APCs before the strike team gets out.
    - **Command:** one move order moves the whole convoy; the formation is kept automatically and you can override any
      vehicle.
    - **Art and animation:** vehicles hold formation smoothly through turns (no bunching or overlap), with visible
      shielding moves.
  - **Spawning and dismounting (owner):** when trained or bought, the 20-soldier strike team **spawns inside its two
    APCs** (10 per APC, by squad), the same as the tactical squads. Any squad or soldier can **dismount or remount at
    any time**.
  - **Mixed movement, troops on foot with the APCs (owner):** when part of the strike team or tactical operators move
    outside the APCs, the movement must be tactically sound, with the **APCs protecting the soldiers on foot** in
    coordinated movement. Proposed behaviour, to confirm in the plan:
    - **Moving cover:** dismounted soldiers walk beside or behind an APC, on the side away from the known threat. The
      APC slows to walking pace and keeps its hull between the threat and the soldiers.
    - **Threat side switches:** when contact comes from a new direction, the APCs reposition to block it and the
      soldiers shift to the sheltered side.
    - **Bounding with vehicles:** soldiers bound between APC cover and terrain cover; the .50 cal gunners and the
      tactical operators give covering fire while they move.
    - **Under heavy fire:** soldiers remount under the APC's smoke and shield cover, or go to ground behind the hull.
    - **Pace:** the group moves at the slowest soldier's speed (wounded, carrying strike packages), and nobody is left
      exposed in the open.
    - **Animation:** soldiers move crouched beside the hull and the APCs creep at walking pace, with visible
      mount and dismount sequences at the rear doors.
  - **Design pillar for the whole counter-nanite group (owner):** the team "must move swiftly, effectively, as a full
    unit however they are deployed -- no matter what they must be the most advanced tactical squad deployable in the
    game as a human faction". In every mode (all mounted, all on foot, or mixed), the group acts as one coordinated
    unit: fast, cohesive, no stragglers, no bunching, no units left exposed, and the best tactical AI and movement of
    any human unit. **This is why the unlock is so expensive and only available late game** (owner note): the cost and
    the late unlock pay for the most capable human force in the game. Quality bar for the owner's playtests: if the
    group ever moves or fights like ordinary units, that's a bug.
    - **No main weapon (owner):** no autocannon or missile station. The roof is taken by the two manned .50 cal mounts,
      front and rear, and they're the APC's only guns. Its other capabilities are the defensive systems listed here.
    - **Armour and survival:** top-tier composite and reactive armour, smoke and chaff launchers, a sealed cabin that
      keeps the crew safe inside creep, and a reduced heat signature.
  Not picked: decoys and spoofing, sensor blinding, feigned-retreat lures, mid-transformation timing.

## New game mode: Last Protocol (owner, added 2026-10-26 after the G7 approval; same hold applies)

Owner's brief: start as a fully advanced human faction with every capability unlocked, against a Machine faction at
maximum difficulty; "your task is to use your nanite strike teams to stop the end of the world (the map)". The match
starts with a fully pre-built, defended, protected base with armies, units, infrastructure, and the Counter-Nanite
facility fully equipped with its maximum number of teams.

- **Name:** Last Protocol. Its own main-menu entry from day one, **always at maximum Machine difficulty**, with a best
  time and score record so you can chase better runs.
- **Faction:** **Human A (Modern Military Power) only.**
- **Map:** one **dedicated hand-built map**, large: your fortified base on one side, Machine-infested ground and the
  doomsday cores across a varied battlefield (urban, forest, tunnels, rivers for firebreaks, dead zones).
- **Start state:** every research and stage unlocked (Stage 10 included). The Counter-Nanite facility is **full: all
  8 bays filled**, meaning **2 complete strike teams** (40 soldiers, 4 APCs) plus **4 tactical squads** (32 operators,
  4 APCs). This mode raises the normal caps so two strike operations can run at once.
- **Starting base must be expansive (owner note):** "your starting base must be expansive and have everything from
  defense, air support, ground support, everything". The base comes pre-built with:
  - every Human A building type;
  - full perimeter security, hardening and layered defences (towers, air defence, counter-drone, bunkers);
  - an airfield with air support (jets, helicopters, drones, transport);
  - ground forces (infantry companies, armour, artillery, engineers, recon, logistics);
  - training facilities, a Company HQ, hospitals and medevac, bunks, the exo-suit garage, power, economy and
    research infrastructure;
  - armies already organised under a chain of command;
  - the base starting in the "secure" state.
  Layout and exact army sizes are set in the plan, within the fps targets.
- **How you lose (both rules):** (1) the **creep meter**: creep spread is shown as a share of the map, and reaching
  the critical level ends the world; (2) the **doomsday countdown**: the Machine builds doomsday cores, and the
  countdown reaching zero ends the world. Creep spread also speeds up the countdown, so you have to contain creep and
  race the cores at the same time.
- **How you win:** destroy **all doomsday cores** and **purge creep below a set threshold** (owner: "destroy cores and
  purge / push creep below a threshold"). Only strike teams can place counter-nanites, so they stay central to winning.
- **Cores and length:** **3 doomsday cores**; each one destroyed slows the countdown, and the last one ends the
  doomsday threat. Target run length is **60–90 minutes**.
- **Economy:** **full economy under high pressure.** Income, trade routes, production and research all run, so you
  can rebuild, but the maximum-difficulty Machine makes every loss hurt. Strike teams are slow and expensive to
  replace.
- **Machine start and escalation:** **entrenched, then escalating phases.** It starts spread across much of the map
  (creep, seeds, outposts, the core zones). As the countdown advances, phases add new unit tiers, faster creep, Stage
  10 units (Colossus, Swarm Queen and others), and all-out assaults on your base near the end. Its normal rules still
  apply (adaptive evolution, eating wrecks, dormant seeds, hive network), as do all 14 counters.
- **To set in the plan:** the exact creep-loss and creep-win thresholds, the countdown length and how much each core
  and creep level shifts it, the phase timings, the score formula, and the hand-built map and base layout.
