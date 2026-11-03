# G7.1 "Tide Line" — master scope, LOCKED 2026-10-31 by the owner ("lock it in and save it"); Done-when frozen

Built on the shipped G7 (C: tree, 173ad32). G8 (view rotation headline) follows G7.1. Owner: any G8 / roadmap item may
be folded in if it serves these goals ("I'll approve everything; my answers get folded into G7.1 in depth").
Owner's north star: Last Protocol should feel like the massive end battle in a modern war-vs-alien-swarm film: an hour
in, you are hit hard by waves of different timing and severity, from every angle, by a hive that thinks.
Labels: **[OWNER]** = owner picked it; **[PROPOSED]** = ORCH depth added where the owner asked "what else" (owner may cut).

---------------------------------------------------------------------------------------------------------------------
## A. Fixes and flow (the game must feel smooth before it gets bigger)

### A1. AIRFIX — aircraft return to their own pad ("titanium cement") [OWNER: all 4 craft types hover]
Reproduce first, in a headless run, for: helicopters, the regular VTOL dropship, the CN stealth dropship, the Vanta.
Suspected causes from reading the code (UNVERIFIED until reproduced):
1. The CN facility helipad and the Vanta roof pad are not Airfield fields (`cn_facility.gd` never registers them).
   The generic low-fuel return (`air.gd` `_return_pad`, ~l.822) searches Airfield fields only, so CN craft fly to
   the nearest airfield building (LP: in the base core = "over the middle of my facility").
2. Rotor return flies to the building's centre `b.pos` (`_tick_rotor_return`, ~l.862), not the pad slot.
3. No free pad found -> no order, no hold, no alert: the craft hangs where it is (~l.821-838).
4. The Vanta waits over its roof pad forever if the pad's occupancy record is stale (`vanta7.gd` ~l.338).
5. Fuel burns while hovering idle; return starts at 25% fuel.
Fix: one shared **home-pad registry** (helipads, VTOL pads, CN helipad, roof pads, FARPs); fly to the exact pad slot;
busy pad -> holding orbit beside it + alert; destroyed pad -> nearest pad of its kind, else land on open ground beside
base + alert; never hover over a building centre. Test matrix: 4 craft types x {own pad free, taken, destroyed, none}.

### A2. AIR OPS — endurance and servicing [OWNER: all four]
- Much longer fuel; near-zero burn while hovering / loitering inside own airspace.
- **Hot-pit service:** land, refuel + rearm in seconds with rotors / fans turning, then auto-return to the last task.
- **Forward arming and refuelling points (FARP):** buildable outside the walls; pads join the home-pad registry; the
  Machine learns to target them late game (see C2).
- **Auto patrol routes:** draw a loop; aircraft fly it and cycle service between runs, keeping a minimum on station.

### A3. FLOW — fewer steps to battle [OWNER: one-click deploy, auto logistics, mission templates]
- One-click "send to front" / "attack here" from any card or building; new units auto-form squads and go.
- Auto logistics toggles: refuel, rearm, reinforce, re-train, without babysitting.
- Mission templates: save a package (APCs + team + dropship + escort + support), launch in one click.
- Target: card -> fighting in <= 3 clicks.

### A4. CONTROL — clicking and camera [OWNER]
- Bigger hitboxes + hover outline for units, vehicles, buildings and wall-walk troops; unit roster panel.
- AoE-style edge scroll; faster pan; zoom-to-cursor; bigger minimap with incoming waves and click-drag.
  Difficulty unchanged.

### A5. SPEED — +20% movement for every unit, aircraft included [OWNER]

---------------------------------------------------------------------------------------------------------------------
## B. Our firepower (OP machines need a military that hits back like a real one)

### B1. New weapon classes [OWNER: rotary railgun, directed energy, thermobaric + incendiary]
- **Rotary railgun turret:** wall turret firing hypervelocity slugs at minigun rate; shreds swarms and over-penetrates
  through lines; spin-up, heat build-up, forced cooldown, glowing barrels, power draw from the grid.
- **Directed energy:** laser CIWS that burns drones out of the sky (beam dwell time, heat, weather and smoke cut range);
  high-power microwave (HPM) emitter that fries a swarm's electronics in a cone (short range, long recharge).
- **Thermobaric + incendiary:** fuel-air rockets for packed lanes; incendiary belts pre-laid in kill zones and
  ignited on command; fire also stops nanite self-repair (B2) and reanimation.
- [PROPOSED] Smart munitions stay as ammo tiers (B5): programmable airburst 30mm, top-attack AT missiles.

### B2. How machines take damage [OWNER: all four]
- **Component damage:** legs (limp / stop), weapons (go silent), sensors (blind, wild fire), armour (core exposed).
  Each machine type has its own part layout and weak spots (joints, cores, sensor clusters, ammo/energy cells).
- **Plates + ricochets:** armour plates shear off visibly; shallow-angle hits ricochet with sparks; armour thickness
  and angle vs round class (extends ballistics8's 27 round classes).
- **Nanite self-repair:** damaged machines regrow unless burned, EMP'd or finished; repair visible as silver flow over
  wounds. Forces commitment over chipping.
- **Heavy death physics:** brutes topple and crush what's under them; walkers collapse into walls; wrecks keep
  momentum, then become cover (C6).

### B3. Infantry weapons [OWNER: all four]
- **Crew-served MGs:** belt-fed nests, sustained / rapid / cyclic rates, barrel overheat + swaps, beaten zones,
  traversing and searching fire.
- **AT teams for real:** gunner + loader, reload cycles, backblast danger zone, top-attack vs brutes.
- **Anti-materiel snipers:** .50 cal teams with a spotter who calls weak spots and cores at long range.
- **Grenadiers:** airburst over swarms; frag / smoke / thermite types.

### B4. Fire support [OWNER]
- **Selection UI:** hold a key for a **radial menu** (HE, smoke, illumination, thermobaric, incendiary, precision,
  gunship) then **shape the strike**: point, line (barrage along a lane), box (saturate), or creeping barrage that walks
  toward the enemy.
- **Final protective fire (FPF), manual only:** each wall face gets a pre-planned strip 30-60 m out where artillery,
  mortars and the wall's MGs are already laid. One press = every assigned weapon fires its max rate into the strip
  for ~30-60 s. Heavy ammo cost, cooldown, danger-close to anything of ours in the strip. The player can repaint lines.
- **Counter-battery:** radar tracks siege-walker shells back to their source; our guns auto-answer.
- **Gunship orbit:** see B6.
- [PROPOSED] Real call-for-fire under the hood: observers / drones / radar must see the target for precise rounds;
  unobserved fire scatters wider.

### B5. Ammo tiers, researched during the match [OWNER]
AP / HE / HEAT / airburst / top-attack / incendiary / rail slugs, unlocked and upgraded through the match so firepower
keeps pace with harder waves. Ammo use and supply drops (D2) make tier choice matter.

### B6. CONDUCTOR — new base-orbit gunship + loyal wingmen [OWNER: "Conductor + wingmen; needs weapons as well"]
- A sleek, heavily armed command gunship orbiting the facility, flying with **4-6 autonomous loyal-wingman drones** in
  a rotating formation. It passes targets to the wingmen; they peel off to strike, screen it, and sacrifice themselves
  to block drone dives or missiles.
- **Its own weapons (owner: required):** rotary railgun chin turret, side-mounted heavy cannon for orbit fire, laser
  CIWS vs drone swarms, missile cells, flares / decoys. Wingmen: light guns, missiles, kamikaze option.
- Orbit placed by the player (radius, side, altitude); returns to its own pad through A1's registry; hot-pit serviced.
- Name and numbers PROVISIONAL.

### B7. VANTA2 — gunship rework [OWNER: keep rotorless]
Fast, smooth, agile and aerodynamic: higher cruise speed and acceleration, banking turns, strafing runs, momentum (no
instant stops), twin MGs on the left and right of the front body, sharper silhouette, motion trail.

---------------------------------------------------------------------------------------------------------------------
## C. The Machine hive (Last Protocol only)

### C1. Wave director: pacing by feel [OWNER: "less of a timed thing, more of a FEEL; ~60 min ramp to peak"]
Reads the fight (wall health, turret count, ammo, our losses, our morale, time) and sends waves of varying timing and
severity. Probes early, mixed assaults around 30 min, full combined siege near 60 min. Combined tactics: small swarms
test walls, drone clouds strip turrets, brutes and walkers break in. **Peak: 1,000+ machines** [OWNER].
- **Breathers to rebuild** after big waves; shorter as the peak nears [OWNER].
- **Dread meter** on the HUD: tide strength / hive anger rising [OWNER].
- **Breaking-point wave:** the director's climax: Overmind voice line, the tide's roar, music swell, director cam
  [OWNER, round 1].
- **One fixed difficulty**: "this is the LAST PROTOCOL gamemode for a reason" [OWNER].

### C2. Hive intelligence [OWNER: adapts, feints, retreat + regrow, logistics late]
- **Adapts to you:** learns what killed it most and counters it next wave (more armour vs MGs, EMP vs drones, smoke /
  dispersal vs lasers).
- **Feints + diversions:** fake push on one wall, real hammer blow on another; probes find your weakest face.
- **Retreat + regrow:** pulls badly damaged machines back to repair and returns them.
- **Logistics strikes in the final stretch:** late in the run it learns to hit ammo bunkers, power, radar, fuel,
  FARPs and aid stations, so a properly set-up and defended rear is as vital as the walls.

### C3. Siege units [OWNER: all four]
- **Gorilla brute:** charges walls head-on, pounds them, fires heavy shots.
- **Turret-eater swarm:** fast flying drones that dive and latch onto turrets.
- **Siege walker:** long-range artillery shelling walls from outside turret range (counter-battery bait).
- **Burrower / sapper:** tunnels under or blows through walls; jammer that blinds turrets.

### C4. Out-of-the-box machines [OWNER picked]
- **Reclaimer:** eats wrecks and bodies and prints new machines on the battlefield: a forward factory to hunt.
- **The Conductor (hive):** a hidden commander machine buried inside the tide; every machine near it moves and fights
  in perfect sync. Find it (drones, recon, intel) and kill it: the tide near it stumbles and breaks formation.
  (Not to be confused with our B6 gunship; rename one at build time.)
- **Glass stalkers:** light-bending camo, nearly invisible; seen on thermal, drone cam, in rain / smoke, or when hit.

### C5. Swarm motion [OWNER]
- **Body-pile climbing:** swarms stack into living ramps up the wall.
- **Aerial flocks:** murmuration drone clouds that split and re-form around flak.
- **Flow like liquid:** pour around obstacles and pool at weak points.

### C6. Wrecks become cover [OWNER]
Dead brutes and walkers stay as wrecks that block and give cover; the next wave climbs over or routes around them;
Reclaimers eat them.

### C7. Look, sound, face [OWNER]
- Eye clusters with glow that flares on lock-on; a metallic shriek / click language; the whole tide roars at the
  breaking point.
- **Overmind voice:** rare distorted transmissions hijacking our radio: taunts, reacts to the player's plays,
  announces the breaking point.
- **Visible hive core:** LP's doomsday cores become visible, heavily defended and hardened structures on the horizon
  that pulse brighter as the siege grows; striking them is part of winning (D1).

---------------------------------------------------------------------------------------------------------------------
## D. Defence, command and the counter-nanite force

### D1. Match objectives [OWNER]
- **Win by holding + striking:** survive AND hit the hive core with strike teams to end the Tide sooner (fits LP's
  existing core win).
- **Escalating objectives mid-siege:** save a cut-off outpost, recover a downed crew, retake a lost turret.

### D2. Siege economy [OWNER: supply drops]
Scheduled resupply flights that you must protect on approach (extends supply8's airdrop op).

### D3. Holding the walls for an hour [OWNER: all four]
- **Rotation + morale:** each wall sector has morale and fatigue; fresh squads rotate in, tired ones rest in the
  barracks (extends 13.9c-43); a sector held too long starts to crack.
- **Runners under fire:** ammo runners, medics and engineers move along the wall-walk in real time; cut their routes
  and the wall starves.
- **Fallback lines:** ordered fallback ring 1 -> 2 -> core; rear guard covers; abandoned turrets are blown; gates seal.
- **Counter-attacks:** sally out to smash a sapper trench or recover a turret, then pull back in.
- [PROPOSED, owner had no preference on power plays] Hold-the-line rally by an officer and emergency VTOL
  reinforcement onto a breaking wall-walk; no cooldown "superpowers".

### D4. DISCIPLINE — a real army [OWNER: all of round 1 + NCOs, radio, hand signals]
- Formation keeping, no drifting; real cover use (hug, peek, bound cover to cover); threat-based target choice and
  focus fire; sectors of fire, overlapping fields, staggered reloads.
- **NCO leadership:** sergeants keep squads tight, call targets and shifts; lose the NCO and the squad gets sloppy.
- **Radio callouts:** "Contact front!", "Reloading!", "Man down!", "Sector 3 is breaking!", tied to real events.
- **Hand signals + stacking:** visible signals, stacking on doors, buddy-covered cover-to-cover moves.

### D5. KILLZONE — kill-zone painting [OWNER]
Beautiful, easy, never "step 16": select any turret / unit / squad / platoon / team / company / army and drag a fire
sector. Anything left unset gets a sensible zone automatically (turrets cover their wall face and overlap neighbours;
squads cover their sector). FPF strips (B4) are drawn in the same view.

### D6. Command info in the chaos [OWNER]
- **Threat forecast:** recon + radar warn what's coming and where ("brutes, north face, 40 s").
- **Hive intel file:** a codex that fills in as you meet machine types: weak spots, counters, behaviour.
- **After-action report:** end-of-run stats, kill heat map, where the walls nearly broke (pulled from G8).

### D7. CN strike teams and spec ops that get the job done [OWNER side note: "very capable, smooth, efficient"]
- **Dispatch:** click a known creep node = go purge it; paint an area = search it (drones up, sweep pattern), then
  purge what they find. One order; they handle the rest.
- **Smart approach:** route around the tide, convoy spacing, stop short, scout with drones before committing.
- **Clean dismount + task:** APCs park in cover; the team dismounts in formation and sets security; suits purge,
  operators breach / clear, engineers seal.
- **React to contact:** suppress, call Vanta / support, break contact or push; casualties evacuated to the APC.
- **Chain + exfil:** node done -> next node in the area -> exfil by APC or dropship when ammo / health is low;
  report back.
- **Feedback:** mission card shows every step live (en route, scouting, dismount, purging 60%, exfil); helmet / drone
  cam view; team-leader radio reports.
- [PROPOSED "what else"]: overwatch element left on high ground during the purge; rules of engagement per mission
  (stealth / standard / aggressive); abort-and-extract button that always works; automatic re-plan when the route
  is blocked; zero stuck states (any step that can't progress for N seconds re-plans or reports why).

---------------------------------------------------------------------------------------------------------------------
## E. Presentation, performance, art, animation

### E1. End-battle atmosphere [OWNER]
- **Night siege lighting:** flares on parachutes, tracers lighting the sky, explosions casting real light and shadow.
- **Layered soundscape:** distant artillery thunder, the tide's roar growing, crisp close gunfire, muffled concussion
  after big blasts.
- **Camera impact:** subtle shake, drifting dust and ash, heat haze over burning lanes (toggleable).

### E2. PERF — beat every past build [OWNER]
"As fast / smooth as possible; needs to beat all past versions: best fps, frames, everything."
- Choppy today: LP map, zoomed out / panning.
- Allowed: LOD for far units (only where it's invisible at that zoom), GPU-batched swarm drawing. **No visible quality
  trades** (owner: "no trades"): no graphics-quality downgrade to reach the gates.
- Gates: sim ms/tick at or below the FASTEST past build (G6) on the same PC and load; fps p10 above every past
  build's figure in each case (2k, 10k, LP zoomed out, LP panning, LP peak with 1,000+ machines, >= 60).

### E3. LOOK — visuals [OWNER]
Combat effects (explosions, smoke, fire, debris, tracers, light flashes); high-detail Machine art (every new unit +
existing Machines); terrain + lighting. In-depth visible hits: tracers, sparks, armour chunks, smoke-trailed missiles,
persistent wrecks, craters and scorch.

### E4. ANIMATION — last, in full expert depth [OWNER: "as if the best animation teams across the globe assist"]
- Weight + momentum: feet plant, bodies lean into turns, recoil kicks, vehicles squat on brakes and rock on suspension.
- Procedural aim / look: heads and weapons track smoothly; turrets and soldiers lead moving targets.
- Machine locomotion: legs adapt to terrain, scramble over walls and each other, gait changes with damage.
- Death / destruction variety: many distinct deaths, wreck break-ups, part loss on machines.

---------------------------------------------------------------------------------------------------------------------
## F. Our machine companions: drones and robots (owner Q&A 2026-10-30, round 3; LAST PROTOCOL ONLY)
Owner: fully autonomous, encrypted robots that protect and defend the human side during Last Protocol: "our 'machine'
military companions". Builds on what Human A already has (recon / combat / FPV / interceptor / lifter / munitions /
shield / stealth-strike drones, defence-drone hive, drone carrier, loitering-munition truck, robotic UGV, repair bot,
maintenance swarm). New units are **Last Protocol only** [OWNER].

### F1. New units [OWNER]
Air:
- **Heavy strike UCAV:** high, long-endurance orbit; precision missiles + guided bombs on brutes / walkers; laser
  designator for the kill chain (F4).
- **EW + relay drone:** jams the hive's sync and the hive Conductor's link (C4), spoofs Machine sensors, and extends
  our mesh network (F5).
- **Incendiary / minelayer drone:** seeds kill zones with scatter mines or thermite / incendiary carpets ahead of a
  wave (feeds B1, D5).
Ground:
- **Armed UGV family:** tracked robots with modules (heavy MG, ATGM, mortar, rotary railgun); hold wall gaps and kill
  zones.
- **Robot dogs:** quadrupeds that scout, climb rubble, enter tunnels, carry guns / charges; packs that hunt Glass
  stalkers and burrowers.
- **Wall sentinel robots:** combat robots patrolling the wall-walk around the clock, never tiring; they fill gaps
  when squads rotate out (D3).
- **Robotic mules:** autonomous carriers hauling ammo, wounded and repair kits along the wall under fire (they are
  the D3 "runners") and recovering downed robots (F7).
Specialist:
- **Purge / decon bot:** sprays counter-nanite agent on creep and wrecks so they can't regrow or be reclaimed.
- **Heavy hunter-tank [OWNER: "think Terminator / Skynet"]:** an ORIGINAL design in that spirit: an unmanned,
  low-slung super-tank with tank-grade armour, rail cannon, rotary guns, laser CIWS, and its own deployable drones.
  Slow, terrifying, expensive. 2-4 in the starting fleet.

### F2. Control and autonomy [OWNER]
- Three ways to run them, all at once: **normal RTS units** (select and order), **attached to squads** (a squad /
  team carries drones / dogs that work for its leader automatically), **autonomous hive** (base-defence robots run
  themselves, like the defence-drone hive). G7 direct piloting through the drone cam still applies to drones.
- **Fully autonomous lethal fire** against Machine targets; encrypted; their job is to protect the player's side.
- **No control-bandwidth or operator limit** [OWNER].
- [PROPOSED] Never fire through our own troops; stray8 friendly-fire rules apply to them like any shooter.

### F3. Survivability and armour [OWNER]
- **Hardened electronics:** shielded cores with optical-fibre / laser-link backups; EMP stuns briefly instead of
  killing; hardening tiers upgradable.
- **Anti-hack + self-wipe:** encrypted with rotating keys; a Machine hack attempt is fought off; a robot about to be
  lost wipes itself / self-destructs so it is never turned.
- **Countermeasures:** flares, decoys, smoke, and active protection that shoots down incoming rounds (heavy hunter-tank
  and UGVs).
- **Self-repair + recovery:** field-repair micro-drones; downed robots recovered by mules and rebuilt cheaper.
- **Armour by size class:** small drones fragile, UGVs / dogs light, sentinels medium, hunter-tank tank-grade.
  **Reactive + modular plates** that blow off or are swapped, with visible damage like the Machines' (B2).

### F4. Weapons and attack [OWNER]
- **Swappable modules** at the drone bay / robot depot: MG, ATGM, laser, rail, flamer, mine dispenser.
- **Swarm tactics:** synchronized dives, decoys draw fire while strikers hit, one target saturated from all sides.
- **Cooperative targeting:** one drone lases / marks, the UCAV, artillery or UGVs strike; kill chain in seconds.

### F5. Comms network [OWNER: all four]
- **Mesh network:** every robot relays for the others; range grows with the fleet; relay drones fill gaps; the mesh
  is drawn on the map.
- **Jamming fights:** the hive jams sectors; robots switch to fibre / laser links or local autonomy; EW drones jam
  back.
- **Shared sensor picture:** what any robot sees, every unit and turret sees (fog lifts along the mesh).
- **Leader re-election:** kill a swarm leader and the swarm elects a new one at once.

### F6. Telemetry [OWNER: all four]
- **Unit HUD strip:** battery / fuel, signal strength, health by part, ammo, current task, autonomy mode.
- **Live feeds:** picture-in-picture camera / thermal from any robot; multi-feed grid.
- **Fleet board:** counts by type, docked / charging, damaged, lost, in production.
- **Robot radio voice:** synthetic callouts ("Sector 2 contact, engaging", "Link degraded", "Returning to charge").

### F7. Drone bay, robot depot and fleet logistics [OWNER: "make the drone bay bigger, better design, bay doors, smart as f***"]
- **Bigger drone bay:** armoured launch doors and roof hatches that slam open, rapid launch tubes and catapult rails;
  doors seal under fire.
- **Automated hangar line:** robot arms swap batteries, reload, fit modules and repair on a moving rack, visible
  through the open doors.
- **Robot depot + garage:** a separate ground-robot depot; UGVs, dogs, sentinels and the hunter-tank roll out of a
  ramp gate.
- **Charging network:** charging pads / docks on walls, towers and FARPs, so robots recharge near the fight; docks
  join A1's home-pad registry.
- **Battery endurance:** real endurance per robot; auto-return to the nearest free dock.
- **Wreck recovery:** mules / lifters recover downed robots before the Reclaimer eats them.
- **Power grid draw:** fleet charging pulls base power; late-game hive power strikes (C2) slow the whole fleet.

### F8. Companion behaviour [OWNER]
- **Bodyguard humans:** shield wounded soldiers, carry them out, step in front of fire for squads.
- **Learn + improve:** the fleet learns hive patterns over the match, just as the hive learns ours.
- **Last stand:** in the final stretch the whole fleet links up as one coordinated army to hold the core.

### F9. Numbers, balance, look
- **Starting fleet ~150 robots** [OWNER]: sentinels on every wall, UGV packs, dog packs, mules, 2-4 hunter-tanks,
  UCAVs aloft. Counted in the E2 perf gates.
- **Weaknesses** [OWNER]: power + charge downtime (grid strikes slow them); our robot wrecks feed the Reclaimer if not
  recovered.
- **Look** [OWNER]: clean military tech (matte grey / olive, blue-white status lights, hard angles), clearly ours vs
  the Machines' organic chrome; IR strobes, searchlights and laser sights at night; expert animation (dogs gallop and
  climb, UGVs rock on tracks, sentinels move with weight), rolled into E4.

---------------------------------------------------------------------------------------------------------------------
## G. People, vehicles, base engineering, world, session (owner Q&A 2026-10-30, round 4; Last Protocol)

### G1. Soldiers [OWNER]
- **Combat engineers+:** lay wire, rebuild walls under fire, place demo charges, build bunkers / firing steps mid-
  siege; work with the auto repair crews (G4).
- **Forward observers / JTAC teams:** spotters that make fire support precise (B4's observed-fire rule) and call the
  heavy strike UCAV (F1) and the Conductor gunship (B6).
- **Combat medics+:** triage, drag wounded, stabilise, run casualties to the aid station; a field surgery tent near
  the walls (extends G7 casualty care).
- **Night vision / thermal gear:** a real NVG / thermal edge at night; Glass stalkers (C4) show on thermal.
- No named heroes or characters: "keep it about the battle" (owner picked None).

### G2. Vehicles [OWNER]
- **Rocket artillery (MLRS):** thermobaric / cluster / smart rounds that sweep whole wave lanes; ties into B4's
  radial menu, line and box strikes.
- **Breacher / bulldozer tank:** armoured dozer that clears wreck piles (C6), pushes sapper trenches in, builds earth
  berms.
- **Flame / thermite tank:** heavy flamer that burns swarms and stops nanite regrowth (B2).

### G3. Defences [OWNER]
- **Flak cannon tower:** proximity-fused flak bursting inside drone clouds; the main answer to aerial flocks (C5).
- **Sonic / seismic sensors:** ground sensors detecting burrowers and Glass stalkers, shown on the minimap and in the
  threat forecast (D6).
- **Wall tech:** armour tiers (steel -> composite -> nanite-resistant coating); anti-climb (overhangs, electrified
  tops, fire-pour points against body-piles); hidden firing ports and pop-out gun slits along the wall face; fast
  wall lifts moving troops and robots onto the wall-walk.
- No preference on obstacle belts / field fortifications: ORCH keeps them to what engineers (G1) and dozers (G2)
  already build. [PROPOSED]

### G4. Infrastructure [OWNER: keep power simple]
- **Auto repair crews:** engineers prioritise walls / ammo / sensors / docks by threat on their own.
- Power stays simple: no new grid map. F7's "fleet charging draws power" becomes one base power number that the
  late hive strikes (C2) can lower.

### G5. World and story [OWNER]
- **Outposts beyond the walls:** forward listening posts / observation towers giving early warning; they fall first
  and can be retaken (fits LP's existing forward bases).
- **Radio story:** HQ / PROTOCOL updates through the hour: other bases falling, last evacuations, "you're the last
  line".
- **Adaptive score:** music layers rise with the dread meter: ambient -> drums -> full score at the breaking point.
- No preference on set pieces: [PROPOSED] the run drifts from dusk into night so the peak is a night siege (E1).

### G6. Session and feel [OWNER]
- **Save / resume mid-run** for Last Protocol (deterministic state; a save loads to the same hash).
- **Order acknowledgements:** instant visual + voice ("Moving", "Engaging") on every order.
- **Replay value:** random seeds (wave mix, routes, twists vary per run), score + medals + personal bests (extends
  LP's medals), mutators (e.g. no air, double swarms, night only).
- No tutorial or hint advisor (owner picked None).

---------------------------------------------------------------------------------------------------------------------
## H. Offense, air war, research, facility, sound, aftermath (owner Q&A 2026-10-30/31, round 5; Last Protocol)

### H1. Core assaults [OWNER]
- **Multi-phase raid:** recon finds the core's defences -> artillery / UCAV soften -> CN teams + robots breach ->
  purge the heart. Each phase can fail, and the raid reports which one did.
- **Core fights back:** cores spawn guardians, pulse EMP, and call the tide home to defend. A strike takes pressure
  off the walls.
- **Air-assault insert:** dropship / VTOL insert straight onto the core under Conductor (B6) + Vanta (B7) cover.

### H2. Other operations outside the walls [OWNER]
- **Hunt the Conductor:** find and kill the hive's hidden commander (C4) inside the tide with a strike package.
- **Reclaimer hunts:** raids on Reclaimer forward factories before they print an army.
- **Rescue ops:** downed crews, cut-off outposts and lost robots recovered under fire (fits D1's objectives).
- **High risk, high reward:** outside the walls means packhunters, no repairs and exposure. Success slows the countdown
  or thins the next wave.

### H3. Operation planning [OWNER]
- **Op planner board:** pick the target, assign packages (recon, fires, assault, exfil), set H-hour; everything
  launches on time. Builds on cn_mission8 / specops8 and D7's one-order missions.
- **Auto-plan suggestion:** the facility AI (PROTOCOL) drafts a plan; the player tweaks and approves it.

### H4. Air war [OWNER]
- **Hive sky carrier:** a huge floating hive ship that births flyers, a priority kill. It's the only new hive flyer
  picked.
- **Fighter CAP:** jets fly combat air patrol and intercept hive flyers before the walls (patrol loops from A2).
- **Air threat warning:** radar tracks raids and warns with direction and type (feeds D6's threat forecast).
- **Dogfight visuals:** missile trails, flares, burning flyers falling into the tide.

### H5. Mini-bosses [OWNER: several, not one Colossus]
Elite variants mid-match, for example an armoured Gorilla alpha and a mega siege walker. Each has its own weak points,
and the director (C1) uses them as wave spikes. [PROPOSED] Each one gets an entry in the hive intel file (D6).

### H6. Creep inside the walls [OWNER: creep spores]
Hive bombers / seeders start creep patches inside the walls; purge bots (F1) and CN teams must clean them before they
spread. [PROPOSED] Spores arrive with the sky carrier and in late waves.

### H7. Research in Last Protocol [OWNER]
- **Siege tech tree:** a short LP-only tree (ammo tiers B5, wall tiers G3, robot hardening F3, sensor upgrades), about
  2-4 min per item.
- **Lab studies kills:** bringing machine parts to the facility lab speeds counters for that machine type.

### H8. Counter-nanite facility in G7.1 [OWNER: all four]
- **Facility under siege:** late in the run the hive targets the facility itself; its own defences, lockdown and a
  last-ditch evacuation (extends G7's breach lockdown and emergency evac).
- **New CN gear:** new suit modules and weapons for strike teams: purge cannons, nanite grenades, shield drones.
- **Faster turnaround:** teams return, heal, rearm and redeploy through the airlock with no waits (the 13.9c-50
  ~70 s exit target that G7 missed becomes a G7.1 gate).
- **Facility upgrades:** upgrade its labs, bays and foundry during the run.

### H9. HUD and scoring [OWNER]
- **Cleaner military HUD:** redesigned bars and panels, tactical and crisp, readable at a glance.
- **Minimal mode:** hide most of the HUD for cinematic play.
- **Score:** weighs time held, lives lost, creep purged and cores destroyed, plus **efficiency grades** for ammo use,
  fire-support accuracy and mission success (extends LP's medals).

### H10. Weapon sound [OWNER: all four]
- **Distance-real audio:** close gunfire cracks, far gunfire thumps; sound from distant artillery arrives after the
  flash.
- **Unique weapon voices:** railgun snap, laser hum, MG belts, MLRS ripple; every weapon class sounds like itself.
- **Impact sounds:** rounds clang off armour, thud into ground, shatter plates.
- **Mix for 1,000 units:** smart mixing (voice limits, priority, distance culling) so huge fights stay clear.

### H11. Wildcards [OWNER]
- **Hive evolves mid-run:** machines visibly change form at stages (new armour, limbs) as they adapt (shows C2's
  adaptation on the models).
- **Captured machine study:** capture a disabled machine alive and contain it in the lab for a big tech reward, with
  a breakout risk.

### H12. Aftermath [OWNER]
- **Persistent battlefield:** craters, scorch, shell casings and wrecks build up over the hour (inside the E2 perf
  gates).
- **Smoke columns:** burning wrecks raise smoke that drifts with the wind and blocks sight.

### H13. Not picked this round
Co-op (parked for later), armoured thrust, sapper raids, phase lines, hive gunship / bomber swarm / interceptor darts,
layered air-defence rings, the single Colossus, infected structures, containment walls, doctrine choice, damage
numbers, ring status widget, ring-integrity bonus, signal-flare lure, scorched earth, base damage visuals.

---------------------------------------------------------------------------------------------------------------------
## I. Command, wall operations, world, hive ecosystem, endings (owner Q&A 2026-10-31, round 6; Last Protocol)

### I1. Command [OWNER: request queue]
- **Request queue:** AI officers (the LP defence AI Commander and sector leads) send requests the player approves or
  denies in one click: "North needs an AT team", "Fire mission AA03?", "Request fallback, sector 2". Unanswered
  requests fall back to the AI's own call after a short time. [PROPOSED]
- No preference on order controls, intel depth or overload helpers: kept as they are today. [PROPOSED] Last-known
  enemy markers in the fog ride along with D6's threat forecast, since that system needs them anyway.

### I2. Turrets and walls [OWNER]
- **Disabled, not dead:** heavy hits jam or disable turrets; engineers revive them fast.
- **Drone repairs:** maintenance drones repair turrets in the middle of a wave.
- **Hand-to-hand on the walls:** when crawlers reach the wall-walk: close combat, bayonets, shotguns, flamers.
- **Gate defence:** gates are focal points with murder holes, pop-up guns and gate reinforcement.
- **Wall-walk choke points:** doors and towers that seal to stop crawlers running along the wall.
- **Turret firing look:** barrel recoil, ejected casings that pile up, heat glow and steam during cooldown, visible
  tracking lasers / IR at night before firing.
- No preference on turret ammo feeds, heat wear, target priority or modules: the kill-zone tool (D5) carries target
  sectors; nothing else is added. [PROPOSED]

### I3. Map, terrain, weather [OWNER]
- **Terrain mix on the LP map:** ruined city outskirts (cover for both sides), scorched farmland (long sight lines,
  natural kill zones), forest + hills (the tide hides in the woods, artillery uses the hills), industrial zone
  (refineries, rail yards, power plants that can burn and explode).
- **Wind:** drives smoke (H12), fire spread and gas; shown as a HUD indicator.
- **Fog mornings:** low fog shrinks sight early in the run, then burns off.

### I4. Fire as a system [OWNER: all three]
Grass, forest and fuel burn and spread with the wind, and a fire line blocks the tide. Fire hurts our troops and
robots too, so they route around it. Fires light up the night battlefield.

### I5. Night [OWNER: all three]
- **Illumination rounds:** artillery / mortar flares light a sector for a short time (added to B4's radial menu).
- **Searchlight towers:** wall searchlights sweep or lock onto threats.
- **Darkness matters:** without light or NVG (G1), units see less and miss more (extends accuracy8's visibility term).

### I6. Hive ecosystem [OWNER: all four]
- **Creep feeds it:** more creep on the map = faster machine production; purging starves it.
- **Nests + relays:** visible nests and relay spires join into a network; cut a relay to isolate a section.
- **Eats the land:** creep consumes trees, buildings and wrecks into raw material.
- **Hive heartbeat:** waves pulse with a rhythm the player can learn and exploit (the director (C1) keeps the rhythm
  but shifts it after feints).

### I7. Machine deaths [OWNER: all four]
Power-cell blasts with chain reactions through packs; silver nanite bleed that seeds creep unless burned; break-up
into limbs, plates and cores; last-gasp attacks and self-destructs near troops.

### I8. Endings [OWNER]
- **Victory:** the cores fall, the tide collapses, dawn over the walls, survivors cheer.
- **Last-stand loss:** the core ring is overrun; final radio calls as the facility goes dark.
- **Pyrrhic win:** you win but almost everything is gone; the cost is shown before the score.

### I9. Not picked
Sector commanders, posture dial, full manual mode switch, satellite pass, event timeline, split view, crewed turrets,
rain, clear-only weather, simple result screen.

---------------------------------------------------------------------------------------------------------------------
## J. "Dark Protocol": gore, horror, harvest, dark advances (owner Q&A + approval 2026-10-31; Last Protocol)
Owner placed every item of the dark pass in G7.1. Campaign (G15) may reuse J9 later as story choices (note only).

### J1. Full graphic gore, no slider [OWNER]
- **Round-driven wounds** (one wound outcome per ballistics8 round class): rifle = bleeding wounds / knock-downs;
  MG = heavier wounds; **.50 / anti-materiel = severed limbs**, bodies thrown (blast8); cannon = body destroyed;
  **railgun = clean through-holes, often several soldiers in a line**; airburst = shredded; thermobaric = charred and
  thrown.
- **Bodies and broken machines stay all match** unless dragged away (medics recover ours, harvesters (J4) drag them
  into the tide, dozers (G2) clear wreck piles). Blood soaks the ground; dragged wounded leave trails.
- **Burn + char:** soldiers caught by fire run burning a few steps, then fall; charred bodies smoke.
- **Crush + trample:** tanks and brutes crush bodies flat; swarms trample the dead into the ground.
- Determinism and perf: the sim records the outcome (limb lost, death); gore is drawn from those events, so results
  are hash-identical. Settled bodies become batched static images and count in the E2 perf gates.

### J2. The wounded [OWNER]
- **Crawling wounded:** soldiers missing limbs crawl, scream, clutch wounds, call for medics (extends G7 wound/crawl).
- **Mercy and triage:** medics tag green / yellow / red / black, save who can be saved first; black-tagged soldiers
  get morphine and are made comfortable.

### J3. Machine gore [OWNER]
- **Mechanical viscera:** silver nanite fluid, sparks, cable "entrails", pulsing cores.
- **Half-dead machines:** torn-apart machines keep crawling, twitching and dragging their torso; a threat until
  finished.

### J4. The harvest [OWNER]
- **Harvester swarm (new hive unit):** fast spider-like collectors sprint in after each wave and drag bodies and
  wrecks back into the tide while you watch.
- Harvested bodies and wrecks speed hive production (with I6's creep economy). Killing harvesters or recovering bodies
  first denies the material.

### J5. Nanite wound infection [OWNER]
Wounds from nanite weapons start a timer with visible silver veins; medics or the decon ward must purge them in time.
Otherwise the soldier turns hostile; a turn inside quarantine triggers a hospital lockdown (J6).

### J6. Trauma and decontamination hospital [OWNER: "bigger, better designed, more capable"]
Replaces the aid station.
- Triage bay (tags), surgery theatres, ICU, recovery ward (badly wounded return to the fight later).
- Nanite decon showers, a scan gate, a sealed quarantine ward that locks down if a patient turns.
- Rooftop medevac pad; **multiple medevac helicopters** (pads in A1's registry); **fast tracked drone ambulances**
  pulling soldiers off the battlefield under fire.
- Prosthetics bay: soldiers who lost limbs return with cybernetic prosthetics (feeds J9).

### J7. Horror atmosphere [OWNER]
- **The silence before:** before a big wave every machine sound stops, birds go quiet, radios hiss; then the ground
  vibrates.
- **Night eyes:** at night hundreds of glowing eye clusters open across the dark field at once, staring at the walls.
- **Tide songs:** the hive's shriek grows into a vast droning chord as the tide builds (tied to the dread meter and
  adaptive score).
- **Bodies on display:** a few fallen comrades strung up on spires or across the battlefield, not many, found as you
  push toward the nodes. [PROPOSED] Strike teams can recover them.

### J8. Lazarus walker (parked dark idea, now a mini-boss) [OWNER]
A huge machine stitched from the remains of one of your destroyed tank companies; appears after heavy armour losses;
fights with your tanks' salvaged turrets; weak points at the stitched joints; killing it lets you recover the remains.

### J9. Dark human advances [OWNER]
- **Cybernetic soldiers:** veterans get reinforced limbs, optic implants, reflex boosters; stronger, need upkeep at the
  prosthetics bay, can't use some gear, vulnerable to EMP.
- **Combat stimulants:** faster, steadier, pain-blind for a time, then a crash; addiction risk and lasting health
  damage; medics administer them.
- **Neural-link pilots:** pilots wired into drones, vehicles and mechs: near-perfect control, they feel every hit, and
  burn out or are injured when their machine dies.

### J10. Counter-nanite gas and gas masks [OWNER]
- Counter-nanite gas cloud kills machines and hurts any of our troops without masks; wind carries it (I3).
- Masks go on visibly when gas is near; masked units lose a little vision and accuracy.
- Masks from lockers, armory stock and storage crates near the gates; ammo bearers carry a few spares for nearby units
  plus their own.
- Filters wear out during long exposure; fresh filters must be fetched from the armory, crates or lockers.

### J11. Late sci-fi arsenal (LP endgame, unlocked by reverse-engineering, J12) [OWNER]
Plasma cannons / rifles (melt armour, glowing slag); coilgun infantry (pierce several machines in a line); smart-dust
(our tamed micro-drones eat machines from inside); energy shields (dome / wall, absorb until overload, draw base
power); mechs, both kinds: light one-pilot mechs in squads of 4 + a few heavy 2-crew, 3-storey battle mechs (arm
cannons, shoulder missiles, CIWS, step over walls and wrecks).

### J12. Reverse-engineering complex — a separate site [OWNER] (full design: J15)
About 2/3 the size of the CN facility, completely apart from the main base, with its own command and defence
(heavy drone garrison, hardened walls, turrets), more defended than the base. Containment cells, dissection bays,
anomaly vault; breakouts with guards, turrets, purge vents; recovery convoys (trucks, lifters, dropship) the hive
hunts; each machine type studied unlocks one specific advance. Replaces H7 "lab studies kills" and H11 "captured
machine study".

### J13. AI war-mind: human, not always right [OWNER]
- Runs the whole base defence (positions, ammo routing, FPF timing); forecasts the hive's next feint and real attack
  with confidence shown; is the brain of the robot fleet and drone mesh; drafts core raids and launches them only if
  allowed.
- Fallible like a person: **biased by history** (over-defends where it was hurt, falls for feints that worked before),
  **fooled by bad intel** (Glass stalkers, jamming, fake contacts), **asks you at hard calls** (abandon a sector, send
  the last reserve). When defences slip or missions go bad, the player takes over.
- Voice: a calm, tired staff officer who reports and admits mistakes. Separate from PROTOCOL; it sends I1's requests;
  everything is overridable; it never abandons troops without asking.

### J14. Cost of crossing the line [OWNER]
Gas that hits our own troops and other dark choices cost score and block gold medals, and change the ending scene and
epilogue text. No morale penalty.

### J15. Reverse-engineering complex, full design (working name "Site Blackglass") [OWNER Q&A + approval 2026-10-31]
**Location and shape.** Cut into a mountain, forward toward the hive but not too close (near fresh wrecks and live
captures, but not first in the tide's path). About 2/3 the size of the CN facility, fully separate from the main base.
Labs, containment and the anomaly vault are deep in the rock; capture yard, airfield, rail spur and outer defences sit
in the valley mouth in front. Look: black-site brutalism outside (massive grey concrete, no windows, blast walls,
hazard stripes, red containment lights); clean high-tech labs inside (white and steel, glass observation decks,
blue-white light, cleanroom airlocks); lit at night (searchlights over the valley, floodlit capture yard, red strobes
on containment).

**Buildings.**
1. Capture yard + intake: convoys unload; scan and EMP-pin before anything goes inside; the only way in for specimens.
2. Containment block: rows of sealed cells above and below ground (see Cells).
3. Dissection hall: wrecks and restrained machines hung on gantries and taken apart.
4. Anomaly vault: deepest, most secure room: cores, rare materials, things nobody understands yet.
5. Prototype works: reverse-engineered tech built and refined (plasma, coilguns, smart-dust, shields, mechs).
6. Test range: live-fire testing of prototypes on restrained machines.
7. Burn pit / incinerator: failed specimens and infected material destroyed.
8. Hive signal lab: intercepts and decodes hive transmissions; feeds the war-mind's (J13) forecasts.
9. Nanite cultivation tanks: sealed vats growing tamed nanites for smart-dust and counter-nanite gas (J10, J11).
10. Staff quarters + lockdown shelter: scientists, guards, the site's own barracks.
11. Own airfield: landing pads, heavy-lift pad, site hangar (pads join A1's registry).
12. Rail spur + armoured road: the only ground routes in, both covered by the defences.
13. Ops room bunker deep in the rock: cameras on every cell and every approach.

**Containment cells.** Layered: thick glass observation wall, EMP grid floor, magnetic restraint clamps, nanite-proof
lining, ceiling purge nozzles. Sized by class: small cells (drones, Glass stalkers, harvesters), mid bays (Gorilla
brutes, walker parts), a giant pit with an overhead crane (siege walker, mini-bosses incl. the Lazarus walker). Living
specimens move, test the glass, track scientists; some go perfectly still and wait. Cell state shown on the cell and in
the UI: stable / agitated / breaching / purged.

**Dissection hall.** Gantry teardown (robot arms + suited scientists strip plates, cut open cores, log parts); parts
shelves of labelled limbs, plates and cores that fill up as you study; live vivisection (active machines opened under
restraint + EMP: faster tech, higher breakout risk); an observation deck the player can click into.

**Breakouts.** Escalating alarms (agitated -> breach warning -> breakout; respond at each stage); chain breakouts (an
escaped machine can open other cells); sector seal + purge (blast doors seal the block, vents flood it with
counter-nanite gas or fire, killing everything inside, staff included if not out). **An escaped machine can signal the
hive ONLY once it is outside the complex compound** [OWNER]; if it does, a hive raid on the complex follows. Hunter
drones and the Warden gunship exist to stop that.

**Defences.** Mountain fortifications (hardened blast doors in the rock, cliff-face gun casemates, a single armoured
approach road); wall + towers across the valley mouth (rotary railguns, lasers, flak); a drone fortress (large
hive-mind defence-drone garrison per 13.9c-27a + its own interceptor and strike drones); minefields, wire and seismic
sensors on every approach.

**Garrison.** Containment security troopers (heavy armour, flamers, EMP lances, purge gear; first in on breakouts); a
specialized Sentinel detachment trained to defend this compound [OWNER]; robot garrison (sentinels, UGVs, robot dogs in
the compound and cell corridors). Site air force, some AI-flown [OWNER]: **Warden gunship** (AI-flown, circles the
mountain, heavy guns + EMP cannon vs escapees); **hunter drones** (AI-flown, track any escapee before the compound
edge); **containment VTOL** (drops containment troopers onto a breach); **sky-crane lifter** (heavy-lift recovery).

**Command.** Site commander AI (runs defence and lockdowns, reports to the player and the war-mind); ops room bunker;
research director (picks the next study unless the player sets priority; pushes for risky live studies); its own
alert level, separate from the base: normal / heightened / lockdown / purge.

**If the hive overruns it** [OWNER: "must self-destruct, so retaking it takes a very fast response"]. On breach-in a
self-destruct countdown starts AND the hive starts learning. Research data can be flown out during the countdown
(what gets out survives). A fast-response force that retakes the complex before zero saves it, damaged. At zero a deep
charge buries the complex in the mountain; the hive keeps counters to the tech it studied, in proportion to how long
it held the site.

**Capture.** Disable then bind: EMP or precise fire knocks out legs / core, then capture teams bind with magnetic clamps
and nanite-suppression foam. New unit: **capture team** (EMP lances, foam guns, restraint harnesses) + a tracked
**capture carrier**.

**Recovery convoys.** Armoured heavy recovery trucks (low-loaders with cages and cranes); sky-crane heavy-lift with a
caged machine slung below; armoured rail freight on the spur; every run escorted, and the hive tries to free or
destroy the cargo en route (a C2 logistics target).

**Study -> tech.** Five stages per machine type, each unlocking something: scan (codex entry + weak spots) -> teardown
(passive upgrade vs that type) -> live study (needs a live capture; unlocks a direct counter) -> prototype (built and
tested at the range) -> production. Type -> tech map [PROPOSED pairings]: Glass stalker -> active camouflage; Gorilla
brute -> heavy composite armour; Reclaimer -> field fabricators; hive Conductor -> swarm control for our drones; sky
carrier -> drone hives; siege walker -> long-range rail accelerators; turret-eater swarm -> anti-swarm proximity fuses;
burrower -> counter-tunnel seismic drills; harvester -> recovery drones; Lazarus walker -> salvage reassembly.
Combined finds unlock the rarest tech (J11) [PROPOSED]: walker core + Gorilla plate -> plasma weapons; siege walker
accelerator + turret-eater guidance -> coilgun infantry; Reclaimer + cultivation tanks -> smart-dust; sky carrier field
+ hive Conductor -> energy shields; Gorilla frame + Lazarus walker joints -> mechs (light squads first, heavy later).

**Not picked:** deep-behind-the-base location, scarred-and-patched look, simulation core, net drones, lure traps,
prototype misfires.

---------------------------------------------------------------------------------------------------------------------
## Settled
- Drive: stay on C:; sync to D: after a D: health check at the end.
- Not picked: wall damage / breach holes, Protocol cooldown abilities, graphics-settings downgrades, difficulty modes,
  salvage / reverse-engineering economy, sector status board, ammo dashboard. Most machine concepts offered beyond
  those listed in C3-C4 (kept as options for G8).

## Pre-start decisions (owner Q&A 2026-11-02; clarifications, no Done-when check weakened)
- **Check-ins:** run all 6 waves straight; screenshots forwarded as features land; stop only at the wave-5 look
  checkpoint and at the end (plus any Stop-if rule).
- **E2 sim gate reading:** sim ms/tick <= G6 is measured on the existing 2k-unit benchmark load. The LP 1,000+ peak is
  judged by fps (p10 >= 60) and by beating G7's LP figures. Every other E2 / Done-when 3 condition stands as written.
- **Names:** our B6 gunship stays **CONDUCTOR**; the hive's hidden commander (C4) is **the Hollow King**.
- **Voice + music:** generated in-house, no outside services. Locally synthesized speech, processed per voice (radio
  filter, distorted Overmind, synthetic robot voice, tired war-mind officer); adaptive score built procedurally from
  script-made synth and drum layers.
- **Difficulty (the one fixed level):** brutal but winnable. Most first runs end in a last stand; a good player who
  secures the rear, uses kill zones and raids the cores wins about 1 run in 3; pyrrhic wins are common.
- **After the ~60-min peak:** the tide holds at full siege (with breathers) until the cores fall or the core ring is
  overrun. No timer ending.
- **[PROPOSED] items:** all kept, built as written.
- **Look checkpoint format:** in-game frame strips of every sample sent to the owner, plus a small packaged showcase map;
  each sample approved or rejected individually.
- **Limit:** none. Finish every wave to the frozen Done-when.
- **Order:** the build order below, unchanged.
- **Before wave 1:** commit the G7 leftovers on C: (staged by path), health-check D:, copy G7 to D: if the drive is clean,
  then cut branch `g71`.

## Done-when (FROZEN 2026-10-31; never weaken a check to make it pass — stop and ask instead)
1. Full suite 0 FAIL / 0 SCRIPT ERROR, every new G7.1 suite included; determinism hash identical across two runs.
2. AIRFIX matrix green: every aircraft type x pad state lands centred on a correct pad or holds with an alert; 0
   hovering over a building centre (headless test + packaged flow).
3. Perf beats every past build (E2), including LP peak with 1,000+ machines and zoomed-out panning, p10 >= 60 fps.
4. LP soak through the ~60-min peak siege: every new machine type fights, the director runs feints and late logistics
   strikes, CN missions complete node purges with 0 stuck states; 0 crashes, 0 invariant failures.
5. Packaged build in Downloads; README / PLAY_ME accurate; owner look checkpoint approved before the full art roll-out
   (Conductor gunship, Vanta2, the siege units, Reclaimer, Glass stalker, hive core, effects samples, night lighting,
   hunter-tank, robot dog, wall sentinel, UCAV, the new drone bay).
6. LP soak: the ~150-robot fleet charges, recovers, re-elects swarm leaders and survives a jamming sector with 0 robots
   hacked to the hive side.
7. LP save / resume: a mid-run save reloads to the same state hash and the run continues to its ending.
8. LP soak includes a full multi-phase core raid (H1) that ends in a purge or a reported failed phase, and a CN team
   cycle through the airlock (return -> heal -> rearm -> redeploy) in <= 70 s.
9. Gore outcomes are hash-identical between runs, and the fps gates hold while bodies accumulate over 60 minutes.
10. An infected soldier is purged in time (one test) and turns into a quarantine lockdown (another); gas + masks +
    filter wear work as specified.
11. The war-mind falls for a repeated feint and asks before abandoning a sector; the RE complex survives a breakout
    and a convoy raid.
12. RE complex full chain: capture a live machine -> convoy -> cell -> all five study stages -> working prototype; a
    breakout ends in a purge with no hive signal while the machine stays inside the compound; an overrun runs the
    countdown, with a fast-response retake in one run and the self-destruct in another.

## Build order
- Wave 1: A1-A5 (fixes / flow / control / speed) + E2 perf profiling and the big perf wins (needed before 1,000+
  machines and ~150 robots can exist).
- Wave 2: B (firepower) + G1-G3 (soldiers, vehicles, defences) + I2 (turret / wall fights) + D4-D5 (discipline, kill
  zones) + D7 + H8 (CN missions and facility) + J1-J3, J6, J10 (gore, wounded, hospital, gas and masks).
- Wave 3: F (robot fleet, drone bay) + C (director, hive AI, siege machines) + I6-I7 (hive ecosystem, deaths) + H4-H6
  (air war, mini-bosses, spores) + J4, J5, J8 (harvest, infection, Lazarus walker).
- Wave 4: D1-D3, D6, H1-H3 (objectives, wall life, core raids, ops planner) + H7 (research) + I1 (request queue) +
  G4-G6 (infrastructure, story, save / resume) + H9 (HUD, score) + H11 + J9, J11-J14 (augmentation, sci-fi arsenal,
  RE complex, war-mind, conduct cost).
- Wave 5: E1, E3, H10, H12, I3-I5 (atmosphere, art, sound, aftermath, terrain, fire, night) + I8 endings + look
  checkpoint before the full art roll-out + J7 (horror atmosphere) and the gore art.
- Wave 6: E4 animation last, in full depth.
- Perf gates and the full suite re-run after every wave.
