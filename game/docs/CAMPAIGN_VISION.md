# Campaign and Living World vision (brainstorm record)

> **STATUS (2026-10-26):** brainstorm output, built from the owner's answers to 103 one-at-a-time questions
> (62 on the campaign and Living World, 41 on space). **Updated 2026-10-27:** 18 more questions designed the Scepter,
> and 22 closing questions settled every open decision. 29 more questions (2026-10-27) settled the space ship rosters
> for all six factions, so nothing is left on the to-do list.
> This is a **vision record, not approved build scope**: nothing here
> is planned into a G-slice, contracted or implemented. Where it conflicts with `G7_REFERENCE.md` (the G7/G8 scope
> authority), that file wins until the owner says otherwise. Working titles and names are placeholders.

---

# Part 0: How this fits RTS: Age of Modern War (added 2026-10-28)
Everything in this file is **the campaign and expansion for the existing game**, not a separate project. It runs on the
same Godot 4.7.2 + Rust `rts_core` engine, the same three factions (plus the G8 Shadow Coalition), the same stages,
units, maps and battle simulation. Campaign battles are ordinary matches of the shipped RTS; the campaign adds the
layers around and above them.

## What the campaign reuses from the shipped game (G0–G7)
| Vision piece | Already in the game | What the campaign adds |
|---|---|---|
| Battles in every chapter | The full skirmish sim: economy, power, supply cap, build and train, armour classes, wrecks (G0–G1) | Battles launched from the regional map, with scars and units carried over |
| Supply (item 7) | Ammo and fuel, depots, supply trucks, refinery (G2); ammo bearers (G6.1) | 2–3 new gathered resources; rare finds by era |
| Orders delayed by distance (item 6) | Chain of command, radio-delayed orders, cut-off units on last orders (G6.1) | The same rule on the regional map, between armies |
| Fog and intel (item 5) | Belief-based fog: fading last-known positions, decoys (G6.1) | Nothing extra on the regional map (no spy war) |
| Officers, companies, generals | Officers on missions (G2); companies, armies, Commanders (G6); AI generals and battle drills (G6.1) | Generated officers who rise from named soldiers, ambitious officers, coups |
| Soldiers stay tactical (item 3) | Suppression, fatigue, veterancy, leader traits (G6.1); wounds and casualty care (G7) | Named veterans carried across chapters |
| Enemy doctrine AI (item 9) | Military doctrine AI: overwatch, flank, raids, exfil, hold high ground (G6) | Per-faction doctrine for all four factions; exo memory across generations |
| Stages 1–13 | Stages 7–10 playable; research and advance (G3b, G6) | Stages 1–6 and 11–13 |
| Water (items 19–20) | Naval war, shipyards, amphibious landings (G5); subs, carriers (G6) | River front lines; navies arriving by era |
| Air | Airfields, helicopters, VTOLs (G5); compact airfields (G6); stealth VTOL dropships (G7) | Exo silent rotor and stealth transport |
| Ghost exo squads | Exo-suits and loadouts (G6); counter-nanite operators (G7) | Syndicate active-camo exos, Mk I–III, the exo complex |
| Black markets | Marketplace (G6); black-market tier (G8 scope) | Syndicate black markets and mercenary hiring |
| Machine threats | Nanite creep, fissures, Weavers, THE TIDE; burrowers, mimics, leeches (G7) | The Healer/Dead Hand story; creep as the cover for seed ground |
| Black site size reference | The Counter-Nanite facility (G7) | The prison black site, smaller than it |
| Hospitals, medics | Medics, ambulances, hospitals (G5) | Medic bloodline runs them; black-site medical wards |
| Walls, mines, fortifications | Walls, gates, towers (G4); mines and fieldworks (G6) | Bunker floors, disguised safehouses, tunnels |
| Elevation | 4 height levels (G6) | Hand-built story maps that use it |
| The dam (Chapter 4 set-piece) | Valley Conquest's central dam; the River Dam survival map (G3b, G6) | The authored flood-and-storm battle |
| Battle sound and radio | Generated battle sound and radio chatter (G6.1) | Distance-real sound, regional-map soundscape, voiced cast |
| Scenario editor | Map and scenario editor with triggers (G4) | Nothing: the campaign isn't moddable, and the editor stays maps and scenarios |
| Tutorial | 16-step tutorial (G5) | Chapters 1–3 teach the campaign; the skirmish tutorial stays |
| Last Protocol | Its own mode (G7) | Stays separate; the Chapter 10–11 Machine war must feel different |

## Where it sits in the roadmap
- **G8 already scopes several pieces this file deepens:**
  - a single-player campaign on a dynamic map;
  - the Shadow Coalition as the 4th faction (here it becomes the Syndicate Shadow Coalition);
  - weather and day/night;
  - named rival generals, diplomacy, and an AI that adapts to the player;
  - training facilities, named soldiers, a black-market tier;
  - the full Machine overhaul;
  - view rotation, which all campaign art will need.
- **Still to be placed in a G-slice:** Stages 1–6 and 11–13 content for every faction; the regional map; the Living
  World; the space expansion. None of it is contracted yet.

## Conflicts resolved (owner's answers, 2026-10-28)
These eight were found by checking this file against the shipped game, the G8 scope and itself. All are now settled,
and the text below has been updated to match.
1. **The campaign map is fixed, and play on it is dynamic.**
   - The campaign's regional map is hand-crafted and the same every time.
   - It's made dynamic by the war director, carry-over and your choices.
   - The Living World is the fully dynamic map.
   - G8's "dynamic single-player campaign on a dynamic map" should be read that way; `G7_REFERENCE.md` itself was not
     edited.
2. **Fog: battles keep the shipped fog, and the regional map adds nothing.** Battles keep G6.1's belief-based fog
   (fading last-known positions, decoys) unchanged. The regional map uses plain fog: you see what your armies see, with
   no spy network and no aging intel estimates.
3. **The exo tunnelling pod is renamed "the Mole".** The G7 Machine burrower keeps its name. "Mimic" stays as both a G7
   Machine threat unit and a Machine ship, since both belong to the Machine.
4. **The Shadow Coalition is built in two steps.**
   - G8 ships its full Stage 7→10 roster as planned.
   - Its other forms are added when those stages are built for every faction: the early raider bands (Stages 1–6) and
     the late syndicate (Mk III exos, 100+ squads, Stages 11–13).
   - G8 is not widened.
5. **The Healer speaks at a few earned moments,** not once. Part 1 now says so.
6. **The hunter lasts by syndicate cryo cycling.** Like the chairman, the hunter sleeps in bunker cryo between hunts and
   wakes for each generation of your heirs (item 84).
7. **The syndicate works in secret from Chapter 1 and goes public in Chapter 9.**
   - Before Chapter 9: agents, the merchant, quiet deals and rumoured ghosts.
   - In Chapter 9 it gathers the people you crushed into the Coalition and goes public, fielding its first 4–6 exo
     squads openly (item 70).
8. **The founder background is the implanted false past.** It's the life the original wrote into the copy. The skills
   are real, because the original gave them, but the memories are fake, and the late reveal recasts the choice you made
   (item 18).

---

# Part 1: Campaign and Living World

## The pitch
A 13-chapter campaign about one Human A dynasty climbing from a handful of survivors in the ash to an Apex
civilization. The founder carries a buried secret: before the war, they helped build the thing that is now eating the
world. The campaign's ending then opens into an endless Living World on the same save, shaped by what you did.

Working title to react to: **Inheritance** (the dynasty, the secret and the key).

## Structure
- **13 chapters, one per stage**, from Chapter 1 (Scattered Survivors) to Chapter 13 (Apex Civilizations).
- **Chapters 1–5 are one lifetime**, played as the founder, a single hero with an authored story. **Chapters 6–13
  cover generations**, played as heirs.
- **Each chapter has a real-time regional map you can pause**, and that map is the hub. Each chapter also has authored
  story operations that trigger at key points.
- **Geography mixes old and new.** The homeland persists and grows the whole way through, and some chapters send
  expeditions to distant theaters.
- **Everything carries over:** battlefield scars, named people, reputation and grudges, and everything you built.
- **Length grows by chapter.** Early chapters run 1–2 hours and late ones 8–10+, for about 60–80 hours in total.
- **You play every battle.** No auto-resolve and no handing a battle to an officer until the Living World unlocks.
- **Two modes:**
  - **Story:** retry freely.
  - **Dynasty (Ironman):** every loss is permanent and the campaign carries on in a worse state.
- **The world is fixed.** The homeland is hand-crafted and the same on every playthrough. Replays differ through
  choices and endings. The war director and carry-over make play on it dynamic, and the Living World is the fully
  dynamic map (Part 0, resolution 1).

## The story spine
- **Opening:** the last day before the war. The founder escapes a pre-war facility, shot so you only understand much
  later that it was where the Healer was built.
- **The Machine's truth:** it started as **the Healer**, repair nanites meant to clean the planet, built with the
  founder's help. Pre-war militaries seized it and bolted on **the Dead Hand**, an automated retaliation system. Two
  directives now fight inside one mind.
- **Chapters 1–7:** only traces of it, such as dead zones and strange regrowth.
- **Chapters 4–6:** the founder, and then the first heir, fight small flare-ups and cover them up. These are playable
  secret operations with a loyal squad: burn the site, collect the remains, and decide what happens to each witness
  (pay, exile or silence). Every witness left alive is a thread the later reveal can pull on.
- **End of Chapter 5:** the founder dies in one fixed, authored scene.
- **Chapter 8:** the first open outbreak. From here, fragments of the founder's voice leak through the Machine's
  broadcasts.
- **Chapter 9:** the heirs find the founder's files and bury them.
- **Chapters 10–11:** open war with the Machine.
- **Chapter 12:** the truth has to come out.
  - The heir can confess on their own terms.
  - If they wait too long, the Machine broadcasts it at the end of the chapter, leading straight into Chapter 13.
  - Either way, four things change forever: the world turns on you; your own people split; the Healer becomes
    reachable; the dynasty's name carries a permanent stain.
- **Endings, all earned, each opening a different Living World:**
  - **Purge:** the Machine is destroyed completely.
  - **Restore the Healer:** the hardest by far (see the key below).
  - **Merge / Apex:** your civilization joins the network.
  - **Fall:** a darker outcome.
- **The founder's key** is the only path to Restore:
  - **Fragments across all 13 chapters.** Miss one and the path quietly closes.
  - **Conduct gate.** The Healer judges how you fought.
  - **Final test.** One brutal operation inside the Machine's heart. Failing it becomes the Fall.
  - **Hints are whispers only.**
  - **Voice:** the Healer speaks in the founder's voice at a few earned moments (key fragments, the confession, the final
    test; item 21), and that voice haunts the broadcasts all along.
- **Last Protocol stays a separate mode.**
- **You only ever play the dynasty.** No interludes from the Machine's side or a rival's.

## Draft chapter outline (titles and beats are proposals for the owner to react to)

| Ch | Stage | Working title | Core beats |
|---|---|---|---|
| 1 | Scattered Survivors | Ashfall | Prologue on the last day; first winter; a small band, scavenging; the companions are introduced |
| 2 | Organized Camps | The Camp | Building the camp; the first raider warlord as the era's villain |
| 3 | Frontier Settlements | The Frontier | Pushing into the valley; farms, convoys, evacuations; the first strange dead zones |
| 4 | Reclamation Townships | Reclamation | Retaking a dam and a power plant; first flare-up; first cover-up and the first witnesses |
| 5 | Workshop Confederacies | The Confederacy | Townships unite; another cover-up; the heir as a young officer; the founder's death |
| 6 | Industrial Revival | Smoke and Iron | First heir; Human B rises as the industrial rival; the last cover-up |
| 7 | Mechanized States | Steel Tide | The first mechanized war with Human B, fought over the founder's old trench lines |
| 8 | Modern Nations | Nations | Full modern war; the first open outbreak; the founder's voice in the static |
| 9 | Networked Powers | The Files | The secret is found and buried; the Shadow Coalition grows out of those you crushed |
| 10 | Automated Technocracies | The Network | Full base-building unlocks; open Machine war; linked operations |
| 11 | Synthetic Civilizations | Flesh and Lattice | Escalation; humanity itself turns synthetic |
| 12 | Distributed Civilizations | The Broadcast | Confess or be exposed; the world turns on you; your people split |
| 13 | Apex Civilizations | Apex | The orbital strike (Part 2); the final war and choice; the endings; the Living World unlocks |

## Systems
- **The regional map (the hub):** settlements and territory, armies and fronts with supply, trade routes and
  logistics, research, people and heirs.
- **Battle maps:** hand-built for story sites and famous places, generated from the real spot everywhere else. Both
  kinds keep their scars.
- **Operations:** special-ops squads; sieges and last stands; convoys and evacuations; missions flown by drone.
- **Base-building by era:**
  - Chapters 1–9: settlement building that grows each chapter.
  - Chapters 10–13: full RTS base-building battles.
  - **Big battles:** two to four prep operations change how the battle starts, and one or two side operations open
    live in the middle of it.
- **The economy grows with the era:** survival scarcity first, then industry and trade, then energy and exotic
  materials.
- **Heirs are shaped by:** what they lived through as children; upbringing choices; mentors from the companion
  bloodlines; their own wounds.
- **The leader on the field:** optional. It inspires the troops but carries real risk; in Dynasty mode the leader can
  die.
- **Cast:** companion bloodlines whose loyalty and grudges are inherited; a fresh supporting cast for each era;
  generated officers who rise from your named soldiers.
- **Rivals:** different ones per era, with one or two authored villains per era plus generated enemy generals who
  remember you. Human B is the main rival in the middle chapters; the Shadow Coalition comes late.
- **Civilians:** deep and consequential. Your conduct can include scorched earth, forced labour and executions, and
  the world remembers it.
- **Diplomacy:** story-driven only (in the campaign).
- **Tone:** shifts by era but stays dark, grim and gory. Gore is graphic, with no slider.
- **Presentation:** in-engine cinematics; voiced radio; illustrated panels with text; an adaptive score and sound for
  each era.
- **Signature features picked:** returning battlefields; the adaptive score with its era sound.
- **Build order:** chapters in order from Chapter 1. Stages 1–6 content gets full skirmish parity.

## Living World (after the campaign)
- **Who you are:** you choose to continue the dynasty or start a new life in the world it shaped.
- **Zoom levels:** settlement or squad, army or RTS battle, nation or continent, and (Part 2) orbit. No playing as a
  single person on foot.
- **What keeps it alive:** AI rivals rise and fall on their own; world crises; long-term ambitions; any civilization
  can slide back down the stages, yours included.
- **Each world stands alone.** Finished worlds do not become the buried history of new ones.

## Turned down
A history book written from your campaign; a family tree with ancestor portraits; a Machine or rival point of view;
turn-based or seamless-zoom maps for the campaign; branching chapters; seeded worlds; playing as a single person on
foot; finished worlds becoming the past of new ones; the campaign going to space.

## Decisions closed (Part 1, owner's answers 2026-10-27)
1. **Dynasty-mode losses: altered start states.** Each chapter keeps its story beats, but you start it worse off: lost
   territory, dead officers, a scarred homeland, stronger rivals. No variant chapter states.
2. **Battle fatigue: a cap plus a variety rule.** Each chapter caps how many regional-map battles can trigger (about
   6–10 in late chapters). Battle types must vary (sieges, convoys, squad ops, drone missions), so no two in a row are
   alike. The "play every battle" rule stands.
3. **Living World diplomacy: systemic but war-first.** Treaties, ceasefires, alliances, tribute and vassals, trade
   pacts and betrayals, all driven by memory and grudges. No deep trade sim and no council votes. The campaign keeps
   story-only diplomacy.
4. **The founder's facility is revisited late.** You escape it in the prologue; an heir returns there around Chapters
   9–11 to recover a key fragment. It's a returning-battlefield moment that bookends the founder's story.
5. **Lineage: a succession panel.** It shows the current ruler, the living heirs in line (with traits, wounds and
   mentors) and a short text list of past rulers. No tree, no portrait gallery.
6. **Person zoom: reinterpreted, not deleted.** The master doc's "inhabit a physical survivor" is met by the squad
   zoom level and by named characters (founder, heirs, officers), not by direct control of one person. Add a
   clarifying note to the master doc; don't strike the line.
7. **Skirmish parity: early forms for both.**
   - In Stages 1–6 skirmish, the Machine is a creeping early-growth faction with primitive nanite units.
   - The Shadow Coalition appears as raider and warlord bands.
   - Skirmish is a sandbox and isn't bound by the story's timeline.
8. **Accessibility: reduced flash and reduced motion.** A mode that tones down flash and camera shake from orbital
   strikes, Scepter impacts and explosions. It is separate from gore and never tones gore down.
9. **Build order: Chapter 1 first, as planned.** Chapters are built in order and systems are proven as they're
   needed. The owner accepts that this is the largest scope in the project.
10. **The Machine war (Chapters 10–11): total war on many fronts.** Last Protocol is one tight duel. The campaign war
    is regional:
    - the Machine also fights Human B and the Coalition;
    - you choose which fronts to hold, and cities fall;
    - linked operations decide the big battles.

---

# Part 2: Space in the Living World

## The pitch
The campaign ends when something in orbit erases a battlefield and leaves only your heir alive. Every surviving power
looks up, and the Living World opens with a race to reach that station. The race leads to the original founder asleep
in a cryo-pod, to proof that the founder invited an alien conqueror race to Earth, and to the generations-long war when
they finally arrive.

## What's up there: the station
- **One huge pre-war station with three sections**, built by pre-war factions that didn't trust each other:
  - **The cradle:** where the Healer was designed. The original Healer code is aboard.
  - **The eye:** the Dead Hand's command and targeting platform.
  - **The ark:** cryo-pods holding the pre-war elite, scientists and soldiers.
- **It has been watching the whole time.**
  - **In the campaign:** clues that only make sense in hindsight; one founder's-key fragment points to it.
  - **In Chapter 13:** a massive orbital strike, built to look spectacular. It erases the whole battlefield (both armies
    and the Machine) except a perfect circle around your heir's command post. Saved or marked? Nobody knows.
- **After the strike the eye goes silent until someone boards it.** Whoever takes it gains orbital strikes.
- **A dormant weapon sleeps in the station's main computer:** the Scepter (see the next section).

## The Scepter: the dormant rod weapon (owner's note and 18 follow-up questions, 2026-10-27)
- **What it is:** a kinetic bombardment array that drops tungsten rods from orbit. There's no warhead, only mass and
  speed, which fits the design doc's "nothing magical" rule. It's a weapon for planetary domination, a tier above the
  eye's ordinary orbital strikes.
- **Names:** "the Scepter" in the station files, which is the founder's own name for it; "the Quiet Rain" among the
  people who live under it, after the silent streaks before impact.
- **Who built it:** the original founder, as part of the alien deal. **It is the viceroy's scepter:** the founder was to
  rule Earth for the makers, and the rods were how a viceroy keeps a planet in line. That's why it can't hurt the makers
  at all; their seed-ships shrug off kinetic rods. It was only ever meant for ruling humans.
- **It has never fired.** The Chapter 13 strike came from the eye (woken remotely by the makers), not the Scepter.
  Nobody living has seen the rods fall.

### Unlocking it
- **Bloodline key.** The computer answers only to the founder's bloodline. To anyone else holding the station it is a
  locked, unexplained file.
- **Rivals have two ways in:**
  - a slow, risky technical crack;
  - a captured or defected member of your bloodline, which is faster. This makes kidnapped heirs, defectors and
    marriages part of the fight for the sky.
- **The unlock moment is a full playable scene:**
  - a boarding team pushes through the station to the core;
  - the key is used;
  - a cold system prompt narrates as the array unfolds outside the hull ("AUTHORITY RECOGNISED. KINETIC ARRAY
    ONLINE."). There's no explanation and no warm founder message, only the machine.

### Firing it
- **Three salvo sizes:**
  - **One rod:** precision, for a bunker, a command post or a ship on the pad.
  - **A salvo:** city-scale. It erases a city or a base complex and leaves a permanent crater.
  - **A domination barrage:** all rods at once, enough to break a whole nation.
- **Two-view presentation:**
  - targets are picked on the orbital zoom level;
  - the camera drops to the ground for a streak through the sky, a flash, the shockwave, then silence and a crater;
  - the sequence is unskippable the first time.
- **Ammo:**
  - It starts with a finite pre-war magazine; every rod fired is gone.
  - Once the magazine is empty, the holder can only restock by building orbital foundries (moon or asteroid mining),
    which ties the Scepter to the space tiers.

### What holds it back
- **World reaction, scaled by salvo size and mixed between fear and resistance:**
  - a single rod draws diplomatic anger;
  - a city salvo turns neutral powers hostile, while some powers submit out of fear (vassals, tribute, and rebellions
    against both);
  - a domination barrage pushes the rest of the world into a coalition against the holder.
- **The station can be taken.** Holding the Scepter makes the station the world's top siege and boarding target.
  Thieves still have to crack it or use a stolen heir before they can fire it.

### The hidden cost (the player must not know until the makers arrive)
- **Every firing does two hidden things:**
  - **It signals the makers.** A log of each strike is sent toward them as proof that the viceroy is "keeping order".
  - **It seeds the crater.** Each crater slowly grows what looks like ordinary Machine nanite creep, so players blame the
    Machine. It is really seed ground, loyal to the makers.
- **Nothing in the game hints at this** before the arrival. The player fires believing it is their birthright.
- **Restraint matters, but only in hindsight:**
  - fewer firings mean fewer beachheads and a weaker signal, so the makers land with less footing;
  - but restraint only helps if the station also stays out of rival hands. Someone always reaches for the Scepter, and
    if a rival fires it, the makers name that rival as their viceroy.

### The reveal, in layers, when the makers arrive
1. **The craters wake.** Every strike site erupts into seed ground loyal to the makers. Your own strikes become their
   beachheads.
2. **The envoy names the viceroy** in front of every human power, thanking whoever fired the most for preparing the
   way.
3. **Later, the rebel cult explains the whole truth:** what the Scepter was for and what the founder agreed to.

### After the reveal
- **Scuttle it:** a costly boarding operation that destroys it for good.
- **Turn it:** with the cult's help, rewire it so it stops signalling. It still can't touch the makers, but it can
  strike their seed beachheads on the ground.

## The road to orbit
- **Space comes after Apex.** The 13 stages stay fixed; space is the open frontier beyond them, marked by milestones
  rather than new stages.
- **The race:** every surviving power races for orbit, and you also get a guided chain of milestones (rebuild, find a
  launch site, first orbit, first docking). The pace depends on you and the AI powers, not a fixed clock.
- **What makes it hard:**
  - **Lost knowledge:** pre-war spaceports, engineer bloodlines and guidance computers are recovered as ground
    objectives.
  - **Ruinous cost:** launches can push a civilization back down the stages.
  - **Sabotage:** rivals raid launch sites, steal designs and kill engineers.
  - The eye does **not** shoot down launches.
- **How you get up:** rockets from spaceports, and spaceplanes from airfields. No space elevator, no mass driver.
- **Your campaign ending changes the road a lot:**
  - **Purge:** the planet is poisoned, so space is a desperate escape.
  - **Restore:** the Healer helps you rise.
  - **Merge:** your network gives you a head start, at a cost.
  - **Fall:** you start crippled.
- **Tiers:** orbit, then the moon, then the home system. The stars stay a far horizon, and that is where the arrivals
  come from.

## How space is played
- **An orbital zoom level** above the continent view, real-time with pause.
- **The ground war for space:** spaceports and tracking stations are huge siege targets; assets in orbit feed the
  battles on the ground.
- **Boarding operations** inside stations and ships, using the squad, close-quarters and wound systems.
- **Fleet battles:** grounded and brutal, but epic in scale, with massive capital ships. Star Wars capital ships set
  the sense of scale only; every design must be original.
- **People:** named crews with space-specific traits; colonies can break away; a dynasty can rule from orbit.

## The story under it
- **The ark pod holds the original founder.** The founder played in Chapters 1–5 was a copy, made by the original
  before going into cryo as insurance: send a version down to fix things, wake me later.
- **The copy knew everything** and hid it even in the files the heirs found. The Chapter 12 confession only exposed
  the smaller lie.
- **The bigger lie:** before the war, **the original founder answered an alien signal and made a deal.** The Healer
  was the down payment.
- **Woken, the original wants one thing: to finish the Healer.**
- **The moon** holds the founder's relay (proof of the deal and the switch to call the makers), in the middle of a
  lunar Machine garden: the Healer's "child", grown without the Dead Hand.
- **The deal comes out by whichever happens first:** the original confesses, using it as leverage; a rival reaches the
  relay and broadcasts it; the arrivals thank your bloodline by name in front of every human power. Who exposes it
  shapes the alliances in the coming war.

## The arrivals
- **Who they are:** reptilian beings who built the seed (the original nanite intelligence the Healer copies) and have
  since become its servants. They come as conquerors.
- **A rebel cult among them:** corrupt, divided and done with being slaves. It arrives inside the conquerors' fleet and
  reveals itself during the war.
- **What brings them (any of three):** the station's old message; someone using the transmitter again; the Healer
  calling its makers.
- **The Healer is torn,** pulled toward its makers. Whether it stays with humanity depends on how the dynasty treated
  it and what the cult offers it.
- **Look, by caste:** elites and ships fused with the seed (biomechanical); a disciplined, ritualised soldier caste;
  the cult comes from the lower castes and strips off the seed-tech.
- **Real weaknesses** (the design doc's "nothing magical" rule): dependence on the seed's network (EMP,
  counter-nanites and the Healer all hurt them); supply lines across light-years; biology that struggles on Earth's
  ground; the cult sabotaging from inside.
- **Both the conquerors and the cult become full factions,** ready for skirmish.
- **The arrival war is a true finale** with its own outcomes and cinematic. After it, the world carries on as an
  endless crisis.

## Decisions closed (Part 2, owner's answers 2026-10-27)
1. **The prologue: the copy is dropped from the station.** It is made aboard and dropped to the ground facility on the
   day the war starts. Its implanted memory says it worked there all along, so the escape is real but the past is
   false.
2. **The Chapter 13 strike: the makers fired the eye remotely.** Their long-range signal woke the eye to protect the
   bloodline of their future viceroy. That's why your heir's circle survived. Once the Scepter's purpose is known, this
   reads as chilling.
3. **Restore is secretly the worst ending.**
   - It looks like the best ending and is framed that way.
   - Underneath, it sets up the strongest maker arrival: a freed Healer pulled toward its makers.
   - Only the Living World reveals the trap.
4. **Scope: space ships as one expansion** after the Living World, not in phases.
5. **Names: from their own language, with human nicknames on top.**
   - The conquerors take a name in their own tongue, something like "the Vhessar"; soldiers call them "scales".
   - The cult calls itself something like "the Unbound".
   - All of these are placeholders; the final names come later.
6. **The eye's limits:**
   - a long recharge, so it's a rare, decisive card;
   - the same world backlash as the Scepter, scaled to how hard you strike.
7. **The arrival war has four outcomes, each leading into its own endless crisis:**
   - **Repel:** the makers are driven off, Earth is scarred, and the seed beachheads remain as a blight to clear.
   - **Kneel:** you or a rival rule as viceroy, and a human resistance becomes the new crisis.
   - **Alliance with the cult:** the makers are broken and the cult settles on Earth; the crisis is an uneasy
     coexistence.
   - **Lost:** Earth falls, and humanity holds out in orbit and on the moon, rebuilding.
8. **The Scepter, closed:**
   - **Numbers:**
     - about 12 rods in the pre-war magazine: enough for a few precision shots, two or three city salvos, or one
       domination barrage;
     - several in-game months to reload between salvos;
     - foundries add rods slowly.
   - **AI use is set by personality:**
     - ruthless powers race to crack it and fire freely;
     - cautious powers hold it as a threat;
     - honourable powers may refuse to use it;
     - a stolen heir is the AI's favourite route in.
   - **Fair-play clues, all readable only in hindsight:**
     - "Machine creep" spreads from craters in places the Machine never reached, and the real Machine avoids it;
     - the Scepter's files use words like "viceroy" and "keep order for them", which read at first as odd translation
       errors.
   - **Each campaign ending changes the seed:**
     - **Purge:** the poisoned ground slows it, so craters wake weaker.
     - **Restore:** the Healer secretly speeds it, which fits "secretly the worst".
     - **Merge:** your network hides it best, so nobody notices.
     - **Fall:** it grows freely.
   - **If the original wakes first, the original takes it.** The original's key outranks the bloodline's, so a woken
     founder seizes the Scepter as a rival viceroy-in-waiting. Your dynasty then fights its own ancestor for the sky.

## Space ship rosters (owner's answers to 29 questions, 2026-10-27)
All ship names are placeholders. The Machine names nothing, so its names are human soldiers' nicknames; the Vhessar
names are nicknames too, until their own-tongue names are set.

### Shared rules
- **One ladder of seven hull rungs**, filled differently by every faction:
  1. Lifters: spaceplanes, rockets, shuttles (landers for the Vhessar and the Unbound).
  2. Strike craft: fighters, bombers, drones, boarding pods.
  3. Corvettes.
  4. Frigates.
  5. Line ships: destroyers and cruisers.
  6. Capitals: battleships and carriers.
  7. Flagship: unique and named (the Machine and the Vhessar have two).
  - A support column runs beside the ladder: cargo and tankers, tugs and repair, miners, troop carriers.
- **Shipyards:** lifters launch from the ground (rockets from spaceports, spaceplanes from airfields). Once a power has an
  orbital yard, the yard builds everything else.
- **What feeds the yards: the ground first, space later.**
  - Orbit tier: cargo lifted from the ground, so spaceports stay vital.
  - Moon tier: lunar mines and foundries cut the lift cost.
  - Home-system tier: asteroid miners make yards self-fed.
  - Cargo lifters and tankers are raid targets.
- **Tiers unlock rungs (human powers):**
  - orbit: rungs 1–4;
  - moon: rungs 5–6 (the first capitals);
  - home system: heavy capitals and the flagship.
  - The Vhessar arrive with every rung. The Unbound start with no yards; their first ships are defected Vhessar hulls.
- **Combat physics:**
  - **Weapons:** railguns, coilguns and autocannon; missiles and torpedoes (nuclear only at the top tier, with world
    backlash); large lasers as main guns on late human capitals and on the Vhessar; lasers and guns as point defence.
  - **Defence:** armour, spaced plates, decoys and flares.
  - **Limits:** heat (radiators can be shot off), ammo and reaction mass.
  - **Damage:** hull breaches, fires and vented crew. Wrecks stay as boarding sites.
- **Shields, two kinds:**
  - **The human Screen**, unlocked at the home-system tier and very expensive. It is a magnetic/plasma layer (strong
    against lasers, weak against slugs), reactive plates and a point-defence net. It draws heavy power and heat, and the
    guns fire slower while it's up, so it can be raised and dropped.
  - **A true energy shield**, rare and deliberately bending "nothing magical": flagships only, reverse-engineered from
    Vhessar tech after first contact.
  - **The Vhessar seed skin** soaks damage and regrows until the seed network is cut (EMP, counter-nanites, the Healer).
- **Upgrades, in three layers:**
  1. **Hull marks:** Mk I (orbit), Mk II (moon), Mk III (home system). Older ships are refitted at a yard.
  2. **Doctrines:** three branches per faction with about 5 steps each. You can max one and take half of a second.
  3. **Refits:** weapon, defence and utility slots, swapped at a yard; refits take time.
  - Named crews earn traits on top.
- **Marks for the other four factions, each on its own clock:**
  - **Machine:** generations, advancing as it adapts to whatever is killing it.
  - **Coalition:** no marks of its own. Stolen ships keep the mark they had, and PMC hulls match the contract tier.
  - **Vhessar:** hull age (young, grown, elder). Elders are far stronger and slow to replace.
  - **Unbound:** marks come from Free Yards progress and from the age of the hull they stole.
- **Huge armadas:** dozens of capitals per side in the biggest battles. There's no hard cap; each faction pays upkeep in
  its own scarce resource:

  | Faction | Upkeep |
  |---|---|
  | Human A | fuel and precision parts |
  | Human B | steel and yard time |
  | Machine | power and network bandwidth (relay ships) |
  | Coalition | money (contracts lapse and crews desert when pay runs late) |
  | Vhessar | seed growth (hulls are grown, slowly) |
  | Unbound | salvage and defectors |

- **Your campaign ending gives your own fleet one trait:**
  - **Purge:** hardened escape hulls, tougher but costlier.
  - **Restore:** Healer-assisted repair, which secretly also feeds the seed.
  - **Merge:** ships linked into the network, with faster coordination but weak to network attacks.
  - **Fall:** a crippled start, but hardy scavenged hulls that are cheap to replace.

### Human A: the modern navy (21 hulls)
- **Look:** long, faceted, spear-like grey hulls like modern stealth destroyers, with radiator fins aft and a crew ring
  amidships on big hulls. Navy grey and black, white hull numbers, the dynasty crest. It wins by sensor fusion,
  stand-off missiles and precise spinal railguns. Every ship is costly, so every loss hurts.
- **Doctrines:**
  - **Precision Strike:** sensor fusion, missile range, railgun accuracy, target-sharing with ground forces. Capstone:
    the kill web (any ship can fire on any other ship's lock).
  - **Carrier Wing:** more hangars, faster launch cycles, drone wingmen, ace pilots. Capstone: a supercarrier refit.
  - **Orbital Marines:** boarding pods, breaching gear, troop capacity, orbital drop into ground battles. Capstone: drop a
    full company from orbit into any ground battle.
- **Roster:**

  | Rung | Hulls |
  |---|---|
  | 1 Lifters | Kestrel spaceplane (crew, cargo, recon; flies from airfields) · Pillar heavy rocket (reusable; lifts hull modules) |
  | 2 Strike | Lance fighter (railgun cannon, missiles) · Hammerhead torpedo bomber · Breacher boarding pod (one squad) |
  | 3 Corvettes | Picket sensor/jammer · Halberd gunboat |
  | 4 Frigates | Bulwark point-defence escort (lasers) · Shade stealth hunter (runs cold, torpedoes) · minelayer (smart mines seeded across orbits; unnamed) |
  | 5 Line | Spear destroyer (missile cells, railgun) · Warden command cruiser (kill-web hub) · Marine assault ship (a company and its dropships; unnamed) · bombardment monitor (slow armoured gun ship that fires down on ground battles; unnamed) |
  | 6 Capitals | Meridian battleship (twin spinal railguns; main lasers at Mk III) · Aerie carrier (about 60 strike craft) · battlecruiser (battleship guns on a fast hull; hunts carriers, raids supply; unnamed) |
  | 7 Flagship | **The Heirloom:** the dynasty's own ship; the ruler can rule from it; takes the true shield after first contact |
  | Support | Mule cargo/tanker · Tender tug/repair · Prospector miner |

### Human B: armoured industrial brutalism (22 hulls)
- **Look:** thick slab and riveted armour, big turreted guns and mass-driver cannons, welded-on extra plating, rust red
  with yellow hazard stripes. Modular hulls are stamped out in numbers and rebuilt from wrecks. Slow, tough and cheap: it
  wins by weight and by repairing faster than you can kill. Weak at sensors and networking.
- **Doctrines:**
  - **Ironclad:** thicker plate, damage control, crews who patch breaches mid-fight. Capstone: a ship fights on at zero
    hull for a while.
  - **Salvage:** tugs drag wrecks home, faster rebuilds, captured hulls refitted (Vhessar ones included). Capstone:
    field-rebuild a wreck mid-battle.
  - **Siege:** heavy guns, orbital forts and armed stations, bombarding ground spaceports. Capstone: a mobile fortress.
- **Roster:**

  | Rung | Hulls |
  |---|---|
  | 1 Lifters | Furnace cheap cluster rocket · Drayman cargo spaceplane |
  | 2 Strike | Rivet armoured gunship-fighter · Sledge heavy bomber (unguided slugs, rockets) · Crowbar boarding ram (drills in; a squad pours out) |
  | 3 Corvettes | Spike flak corvette (kills strike craft) · Tinker repair corvette |
  | 4 Frigates | Plate armoured escort · Grapple salvage frigate (harpoons, tows wrecks, captures hulls) · Caltrop minelayer |
  | 5 Line | Anvil destroyer (turreted mass-drivers) · Ironside broadside cruiser · Breaker siege monitor (bombards ground spaceports) |
  | 6 Capitals | Monolith battleship (the biggest guns in human space) · Kiln carrier (a converted bulk hauler with swarms of cheap fighters) · massive dreadnought (slow, over-armoured, outlasts anything; unnamed) |
  | Fort | Redoubt armed station, towed into place by tugs |
  | 7 Flagship | **The Foundry:** a mobile shipyard-fortress that builds and repairs ships in the field |
  | Support | Scow cargo/tanker · Winch tug · Dredge miner · troop barge (a whole battalion, for boarding stations and wrecks; unnamed) |

### The Machine: a grown swarm fleet (24 hulls)
- **How it works:** no crew spaces, so hulls are dense, odd and asymmetric: insect-like segmented frames with sleek
  glowing seams.
  - Small drones merge into bigger ships and split apart again.
  - Ships repair by eating wrecks.
  - Relay ships carry the network; cut them and nearby ships drop to simple local AI.
  - It reaches orbit by seizing spaceports and pre-war launch sites; the lunar garden later gives it a moon base.
- **Doctrines** (the campaign ending tilts which branch is cheapest):
  - **Dead Hand:** cold retaliation, nuclear torpedoes, kill-on-detect. Capstone: a fleet-wide retaliation strike when a
    relay dies.
  - **Healer:** repair, wreck-eating, regrowth, clearing debris. Capstone: rebuild destroyed ships from the battlefield.
  - **Swarm:** merge and split, drone numbers, bandwidth. Capstone: one huge merged ship.
- **Two flagships, one per mind.** The Cathedral belongs to the Dead Hand and the network, the Mercy to the Healer. The
  doctrine you lean into, and the campaign ending, decide which is cheaper or available.
- **Roster:**

  | Rung | Hulls |
  |---|---|
  | 1 Lifters | Husk (a seized human rocket, flown unmanned) · Cicada (self-grown lifter; lands on its legs) |
  | 2 Strike | Mote micro-drone (merges into bigger ships) · Wasp interceptor · Tick boarding pod (latches on, releases combat robots) · Stinger ramming torpedo-drone packs (Dead Hand) |
  | 3 Corvettes | Spindle relay ship (carries the network) · Hornet gunboat |
  | 4 Frigates | Mantis (12 Motes merged; splits back) · Lacewing point-defence/jammer · Burr drone minelayer · Mimic ambusher (hides among wrecks posing as debris) |
  | 5 Line | Centipede destroyer (segments detach and fight alone) · Scarab cruiser (armoured wreck-eater; repairs others) · Sower (drops real nanite creep onto ground battles from orbit) · Scorpion brawler cruiser (spinal laser lance) |
  | 6 Capitals | Gravestone battleship (Dead Hand nuclear torpedoes) · Hive carrier (grows Motes in flight) · the Knot megaship (Mantises and Centipedes fused into a capital; splits apart when badly hurt) |
  | 7 Flagships | **The Cathedral:** a vast grown network core and factory; if it dies, the space network splits · **The Mercy:** the Healer's hospital flagship; regrows ships, cleans debris, saves its own |
  | Support | Grazer wreck-eater · Borer miner · Tether tug |

### The Shadow Coalition: pirates and a PMC navy (22 hulls)
- **How it works:** two halves, as on the ground.
  - **The cells** fly armed civilian freighters (Q-ships that look like ordinary traffic until they fire), hijacked ships,
    space IEDs and suicide boats, from hidden asteroid and wreck-field bases. Weld-shop refits carry into space: any
    captured hull gets bolt-on guns.
  - **The PMC patron** rents real warships, up to capitals, on contract timers. They leave or switch sides when pay runs
    late.
- **Doctrines:**
  - **Raiders:** Q-ships, disguise among civilian traffic, space IEDs, suicide boats, hidden asteroid bases. Capstone: a
    whole fleet that reads as civilian traffic until it strikes.
  - **Contracts:** cheaper and longer PMC contracts, bigger rented hulls, loyalty that holds when pay is late. Capstone:
    rent a PMC capital battle group.
  - **Hijack:** boarding, capture and refit, weld-shop bolt-ons. Capstone: steal a capital ship mid-battle (Vhessar ones
    too, through cult defectors).
- **Roster:**

  | Rung | Hulls |
  |---|---|
  | 1 Lifters | Jackrabbit black-market spaceplane (flies from dirt strips) · Bottle cheap rocket from hidden pads |
  | 2 Strike | Gnat converted shuttle-fighter · Firecracker crewed suicide boat · Leech boarding sled (latches on, cuts in) |
  | 3 Corvettes | Technical (an orbital tug with a weld-shop gun mount; the signature unit) · Rattler rocket-pod corvette |
  | 4 Frigates | Trojan Q-ship (looks like a civilian freighter) · Magpie hijack/refit frigate · Scatter (hides mines in debris) |
  | 5 Line | Junkyard cruiser (welded from wrecks) |
  | 6 Capital | Prize (any captured capital, refitted by the weld shop) |
  | Shock | Fireship (an explosive-packed bulk freighter rammed into stations) |
  | PMC, rented | Retainer escort frigate · Warrant destroyer · Charter cruiser · Mandate battleship · Holdings carrier (sleek corporate look; the PMC's sub-name is still to be set) |
  | 7 Flagship | **The Bazaar:** a hollowed asteroid with engines bolted on; hideout, yard and black market in one |
  | Support | Runner smuggler cargo · Scrapper salvage tug · Claimjumper miner |

### The Vhessar: grown by caste, fed by beachheads (21 hulls)
- **How it works:** ships are grown, not built. The hulls are seed-fused and biomechanical, with ridged hide armour and
  the regrowing seed skin.
  - **Crews follow caste.** Elites are fused into the capital ships. The ritual soldier caste does the boarding. The
    lower castes do the dirty work, and they are the ones who defect to the cult (the Gorger, Caravan and Clutch crews
    most of all).
  - **They arrive as one great fleet** around an irreplaceable Seed Ark.
  - **New hulls grow slowly in orbit** and faster from seed beachheads on the ground, so every Scepter crater feeds their
    shipbuilding.
- **Doctrines:**
  - **Seedbond:** deeper fusion, faster skin regrowth, weapons grown mid-battle. Capstone: a capital regrows from a
    single surviving seed-core. Each step also deepens their weakness to EMP and the Healer.
  - **Ritual War:** soldier-caste boarding, champion duels, ramming and grappling. Capstone: a boarding host that takes a
    human capital in one action.
  - **Dominion:** seeding the ground from orbit, beachhead growth, envoys that make human powers kneel. Capstone: turn a
    whole region into seed ground from orbit.
- **Roster:**

  | Rung | Hulls |
  |---|---|
  | 1 Landers | Dropseed pod (lands and grows into a beachhead) · Wyrm heavy lander (carries ground hosts down and back) |
  | 2 Strike | Talon fighter (fused pilot) · Spitter bomber (flechette spines, torpedoes) · Fang boarding ram (soldier caste) |
  | 3 Corvettes | Skink fast picket · Thornback gunboat |
  | 4 Frigates | Shellback point-defence escort · Lure decoy/jammer (fakes human signals) · Clutch minelayer (seed-egg mines that latch on) |
  | 5 Line | Viper laser destroyer · Basilisk heavy cruiser · Blight seeder (fires seed spikes into the ground to make beachheads) |
  | 6 Capitals | Matriarch battleship (an elite fused into the hull) · Brood carrier (grows Talons in flight) · Hierarch temple-ship (soldier-caste boarding host) |
  | 7 Flagships | **The Seed Ark, "the Throne":** the irreplaceable seed core that grows their hulls; kill it and growth stops · **The Herald:** the envoy's ship that names the viceroy in front of every human power; a story ship that can be hunted |
  | Support | Gorger asteroid-eater (seed food) · Nurse regrowth ship · Caravan star-supply hauler (rare and raidable) |

### The Unbound: stripped hulls, rough rebuild (19 hulls)
- **How it works:** they defect with the ships they crewed, then tear the seed out.
  - Stripped ships lose the regrowing skin, but they are immune to EMP, counter-nanites and the seed network being cut.
  - The hulls look flayed and scarred, patched with salvaged plate (later human plate).
  - They can't grow ships. They take, strip and hand-repair them until a human ally or a captured yard lets them build.
  - They are split into rival warbands, so some ships may turn back or sell out.
- **Doctrines:**
  - **Defection:** turn Vhessar crews mid-battle, faster stripping, warband loyalty. Capstone: a whole Vhessar squadron
    switches sides in battle.
  - **Saboteur:** agents inside the Vhessar fleet who blind sensors, poison seed growth and open ships to boarders.
    Capstone: cripple the Seed Ark's growth for a time.
  - **Free Yards:** their own hulls from human tech and scrap, and an alliance shipyard. It only opens with a human ally
    or a captured yard. Capstone: their first true-built capital.
- **Roster:**

  | Rung | Hulls |
  |---|---|
  | 1 Landers | Shuck (stripped Wyrm lander) · Ember drop-pod (troops only, no beachhead) |
  | 2 Strike | Kite (stripped Talon, hand-flown) · Gutter bomber · Chainbreaker boarding ram (boards Vhessar ships to free lower-caste crews) |
  | 3 Corvettes | Jackal raider · Whisper saboteur boat (runs cold; slips agents aboard Vhessar ships) |
  | 4 Frigates | Scar patched escort · Lantern defection beacon (broadcasts to the lower castes mid-battle) · Cutter (hand-built gun frigate on human plate; Free Yards) |
  | 5 Line | Turncoat destroyer (stripped Viper) · Flayed cruiser (stripped Basilisk) |
  | 6 Capitals | Unchained battleship (a stripped Matriarch taken whole) · Freehold carrier (a stripped Brood flying hand-built craft, since it can't grow them) · Firstborn (their first true-built capital; the Free Yards capstone) |
  | 7 Flagship | **The Exodus:** a captured Caravan turned mobile commune and temple, carrying the cult's people |
  | Support | Picker scavenger · Mender hand-repair ship · Unseeder (strips the seed from captured hulls in the field) |

## Expansion round (owner's answers, 2026-10-28)
Ideas for more depth, dynamism, AI and realism, added one answer at a time.

1. **A war director is the core "living" engine.** It's an unseen AI that reads how you're doing and how you fight,
   then shapes the pressure on you: counter-offensives, refugee waves, betrayals, weather windows and quiet stretches.
   This gives every campaign a different rhythm inside the fixed world.
2. **The director works between the beats.** It controls pressure, events, timing and enemy moves, but never changes
   an authored story beat, a death scene or a chapter's ending.
3. **Soldiers stay tactical.** Named soldiers carry experience and wounds only. There's no combat-stress or
   psychology layer.
4. **The land changes the war:**
   - **Seasons and weather:** winter freezes rivers into crossings and kills unsupplied troops; mud season stalls
     armour; storms ground aircraft. The director times offensives around them.
   - **Lasting destruction:** shelled ground stays cratered, bridges stay down until rebuilt, forests burn, and cities
     become ruins you fight through for generations.
   - **Day and night:** night fighting matters, with night vision, flares, ambushes, and tech that changes who owns the
     dark.
   - Not chosen: pollution and fallout as a simulated system.
5. **Intelligence: no extra layer on the regional map.** There, you see what your armies see, with no aging intel
   estimates and no spy war. Battles keep the shipped G6.1 belief-based fog (fading last-known positions, decoys)
   unchanged (Part 0, resolution 2).
6. **Orders are delayed by distance.** On the regional map, orders travel by courier or radio (faster as eras
   advance), so far-off fronts react late. If a line is cut, that army keeps acting on its last orders.
7. **Supply: keep the current setup, and widen the materials.**
   - **More gathered resources:** add 2–3 new resources (for example fuel and rare metals) that are gathered in every
     era, so the economy is wider in every battle.
   - **Rare finds by era:** a few era-specific rare materials found on the regional map (pre-war caches and fuel early;
     rare earths and oil fields mid-campaign; exotic materials late). They're worth fighting over and unlock special
     units or tech.
8. **Threats from inside the dynasty:**
   - **Succession fights:** when a ruler dies, rival heirs, generals or companion bloodlines can contest the succession,
     sometimes as a civil war you play.
   - **Ambitious officers:** famous generated generals may defy you, demand power or attempt a coup if you neglect or
     humiliate them.
   - **Factions of your people:** groups such as the army, workers, the faithful and the pro-Machine want different
     things, and can strike, riot or rebel.
9. **Enemy AI in battle:**
   - **Real doctrine per faction:**
     - Human A: combined arms and recon-by-fire.
     - Human B: massed armour and artillery.
     - The Machine: swarms and adapts.
     - The Coalition: ambushes and runs.
   - **Retreat and regroup:** enemies break, fall back to better ground, call reinforcements and counter-attack,
     instead of fighting to the last unit.
   - **Uses the terrain:** it seeks cover, high ground, night and weather, sets ambushes, and avoids kill zones it has
     seen before.
   - Not chosen: interceptable enemy radio chatter.
10. **How the war is remembered (all four):**
    - **Memorials in the world:** famous battles leave monuments, cemeteries and named places on the map ("Harlow's
      Stand"), and later generations fight around them.
    - **Battle replays:** any battle can be saved and rewatched with a free camera.
    - **People remember:** characters and enemy generals bring up past events in dialogue and radio ("your grandfather
      burned this valley").
    - **A statistics ledger:** casualties, battles won and lost, and cities taken, per chapter and per ruler.
11. **Offline and private.** The game stays fully offline and single-player, with no shared stats or leaderboards.
    Your dynasty is yours alone.
12. **Conduct has consequences:**
    - **Enemies answer in kind:** if you execute prisoners, enemies stop surrendering and fight to the death; mercy
      earns surrenders and defectors.
    - **Civilians remember:** regions you brutalised spawn partisans and refuse to supply you for generations; regions
      you protected send volunteers.
    - **Surrender and POWs (owner's addition):** overwhelmed enemies can surrender and be taken as prisoners of war.
      They are held in a new **prison black site**, a large campus-style facility, smaller than the counter-nanite
      facility.
13. **What you can do with POWs at the black site:**
    - **Interrogate:** reveals enemy positions, plans or tech on the regional map. Harsh methods are faster but count
      against your conduct.
    - **Turn them:** some prisoners can be recruited as defectors, bringing their own units and knowledge, at a loyalty
      risk.
    - **Labour:** forced work for resources. It's a dark option that counts heavily against conduct and civilian
      memory.
    - Not chosen: prisoner exchanges and ransom.
14. **The black site is part of the war (all four):**
    - **Rescue raids:** enemies raid your site to free their people, and you can raid theirs. Sites are targets in
      battle and on the regional map.
    - **Breakouts:** under-guarded or overcrowded sites can riot and break out, releasing angry prisoners behind your
      lines.
    - **A story site:** one authored campaign operation takes place at a black site, for example where the heirs hid
      witnesses from the cover-ups.
    - **Capacity limits:** each site holds a fixed number. When it's full, you must refuse surrenders, release
      prisoners, or worse.
15. **Time between dynasty chapters: a played-out interlude.**
    - Between chapters, a short "years pass" sequence runs on the regional map.
    - You set a few long-term policies: build up, expand, raise the heir.
    - A summary of events, deaths, births and border changes then plays out before the next chapter.
16. **Research has three layers:**
    - **Rediscovery:** much tech is recovered from pre-war ruins and caches, as objectives.
    - **Exclusive choices:** at key points you pick one branch and lock out another, so each dynasty's arsenal differs.
    - **Captured tech:** you can capture and reverse-engineer enemy equipment, including Machine and later alien tech.
17. **Audio beyond the score:**
    - **Distance-real sound:** gunfire and artillery sound different by distance and terrain (a far crump, a near
      crack), so you hear a battle over the hill before you see it.
    - **World soundscape:** the regional map has living ambience: refugee columns, factory noise, and Machine hum that
      spreads as the creep grows.
    - Not chosen: voiced soldier callouts.
18. **Replay value:**
    - **Different founders:** at the start, you choose a founder background (soldier, engineer, medic, scavenger). It
      changes your starting companions, early tech and how some story scenes play, while the world stays fixed. In the
      story, the background is the false past the original implanted in the copy: the skills are real, the memories
      are not (Part 0, resolution 8).
    - **Endings and key hunts:** the four endings and the hidden key path carry the rest.
    - Not chosen: campaigns for other factions; challenge modifiers.
19. **War on the water, at every scale:**
    - **Rivers** are front lines and highways: boats, ferries, bridges and river crossings under fire.
    - **Coastal war** comes in later chapters: gunboats, landings and shore batteries.
    - **A full blue-water navy** with carriers and submarines is its own layer of the war.
20. **Navies arrive by era:** river boats from the early chapters; coastal craft from Industrial Revival (Chapter 6);
    the full blue-water navy from Modern Nations (Chapter 8) onward.
21. **The Healer speaks rarely, and you have to earn it.** At a handful of moments (key fragments, the confession, the
    final test) it speaks in the founder's voice. It is always ambiguous and never explains itself fully. *This widens
    the earlier rule that it speaks only once, at the key moment.*
22. **Cities grow visibly.** Each settlement grows through the eras: camp, town, city, arcology. Its look reflects
    what you built and what it suffered (war scars, factories, memorials). Big cities become battle maps.
23. **Long-term goals in the Living World (all three):**
    - **Ambitions:** big goals you set yourself, with milestones, rewards and story events. Examples: unite the
      continent, reach the moon, wipe out the Machine, restore every ruined city.
    - **World crises:** generated crises that every power must answer (plague, famine, a Machine resurgence, the
      arrivals), which reshuffle alliances.
    - **A legacy score:** monuments, deeds and stains built up over generations. It's compared only against your own
      past runs.
24. **The story is the tutorial.** Chapters 1–3 introduce one system at a time inside the story: scavenging, then the
    camp, then squads, then the regional map. There's no separate tutorial, and each later system is introduced in the
    first chapter that uses it.
25. **Difficulty uses split settings:** one for battle difficulty (the enemy AI) and one for strategic pressure (how
    hard the war director pushes). These sit on top of the Story and Dynasty modes.
26. **Saving depends on the mode:**
    - **Story mode:** save anywhere, in many slots.
    - **Dynasty mode:** one autosave, taken at every chapter, battle and interlude, with no reloading.
    - Several separate dynasties can exist side by side.
27. **The Editor makes skirmish maps only.** It has no campaign or operation tools, and the main campaign is not
    moddable.
28. **The UI is in-world and changes by era.** Menus are physical objects in the world: a map table, a field radio, a
    war room. Their look climbs with the stages:
    - early: scrawled paper and maps;
    - industrial era: typewriter and teletype;
    - modern era: green CRT;
    - late game: clean holographic.
29. **Voice tone, three layers:**
    - **Grounded and clipped by default:** real radio procedure and tired, under-acted voices. Most of the horror lands
      through restraint.
    - **Cinematic at key moments:** bigger, dramatic performances and the occasional speech, kept for the story's
      peaks.
    - **Shifts by era:** rough and improvised early; formal radio procedure in the modern era; cold and clinical in the
      late synthetic eras.
30. **Four companion bloodlines start with the founder in Chapter 1:**
    - the soldier (the army);
    - the engineer (industry and tech);
    - the medic (people and mercy);
    - the scavenger (scouts and smugglers).

    Each companion starts a family line whose descendants hold that role for generations, and their loyalty can split.
31. **The founder's background replaces one companion.** The founder backgrounds from item 18 match the companion
    roles. Whichever role your founder takes, that companion is replaced by a fifth bloodline, the preacher or the
    merchant. Every run has four companions, but which four changes.
32. **Era villains are mirrors and grudges.** Some villains reflect what your dynasty could become: a warlord who rules
    by fear (early), an industrialist who works people to death (mid), a technocrat who'd merge with the Machine
    (late). Others carry grudges against your bloodline, often as descendants of people your ancestors wronged,
    including cover-up witnesses. Some villains are both.
33. **Each ending's cinematic goes from personal to wide.** It opens on your last heir in a quiet personal moment,
    pulls back across the world you made (memorials, scars, cities), and ends on the sky, setting up space.
34. **The Shadow Coalition is several movements under one name, with conflicting goals:**
    - **The victims' cells:** survivors of your dynasty's wars and cover-ups, out for revenge. They're the first to
      learn your secret, and they use it against you in Chapter 12.
    - **A Machine-cult wing:** they worship the Machine as humanity's next stage and aid it in Chapters 10–11.
    - **Profiteers:** the PMC patron sells war to every side and keeps the chaos going for profit.
    - **The patron's hidden goal:** reaching the station first.
35. **The patron holds the Coalition together, and its secret breaks it.** The PMC patron secretly funds every wing
    for its own ends. When the victims' cells learn that the patron is also arming the Machine cult, the coalition
    fractures. In Chapter 12 or 13, the victims can become reluctant allies against the patron.
36. **The patron is a war-profiteering syndicate with pre-war roots.** At its core is a pre-war corporation that
    survived intact in hidden bunkers. It was one of the station's three original builders, and it wants back what it
    helped make, above all the eye. Around that core, a ruthless war company grew in the ashes. Together they deal in
    war profit and advanced tech.
37. **The syndicate's tech (all four):**
    - **Pre-war prototypes:** weapons hoarded in the bunkers, such as experimental drones, stealth craft and
      exoskeleton troops. They're few, but they outclass anything of their era.
    - **Sold to everyone, including you:** the price is debts, favours, or a backdoor in every unit they sell.
    - **Machine samples:** captured nanite samples they experiment on, producing dangerous, unstable hybrid weapons.
    - **A secret pre-war launch site that doesn't work (owner's twist):** they hold it but can't make it work, and they
      don't know why.
38. **It's dead because of the bloodline lock.** The original founder locked every pre-war launch system to the
    bloodline key, the same way the Scepter is locked. The syndicate needs your heirs, which is why it hunts them, and
    why stolen heirs matter so much. Launch systems built after the war aren't locked, so rivals can still reach orbit
    the slow, costly way.
39. **The syndicate is run by a board in the bunkers, under a hidden chairman.**
    - A pre-war board of directors rules from the bunkers; some are kept alive by cryo or crude augmentation.
    - Below the board are field divisions (contractors, arms dealers, labs), each run by a named executive with their
      own ambitions.
    - The board answers to a chairman nobody has seen.
40. **The chairman is the founder's pre-war rival, now working for the cult.**
    - Before the war, the founder and this rival answered the alien signal together, and then the founder cut the rival
      out of the deal.
    - The rival found the makers' rebel cult and became its agent on Earth.
    - The rival has been secretly arming humanity to resist the makers. It isn't kindness: humans are tools for the
      cult's liberation, and for the chairman's revenge on the founder's line.
41. **The chairman survives in two stages:**
    - **First, cryo cycling.** Like the founder, they sleep in cryo and wake only for key decisions, so each generation
      of your heirs meets the "same" chairman.
    - **Then, a cult-made body.** When cryo stops being enough, the cult rebuilds them with seed-stripped alien
      biotech: long-lived, scarred and part reptilian. It's a living preview of the arrivals, hidden until the reveal.
42. **How your dynasty deals with the syndicate (all four):**
    - **Tempting contracts:** at key moments it offers you prototypes, mercenaries or intel. Accepting helps now, but
      every deal adds a debt, a backdoor or a favour they'll call in later, sometimes at the worst moment.
    - **Executives as characters:** named division executives approach you separately. One may defect, another may
      betray the board, and you can play them against each other.
    - **War on the syndicate:** you can hunt its bunkers on the regional map. Each one you crack yields prototypes and
      secrets, but provokes the board.
    - **The chairman's offer:** late on, the chairman reveals themselves to your heir and offers an alliance against
      the makers. The price is the founder's legacy.
43. **The chairman steps out right after the Chapter 12 truth.** After the confession or broadcast, when the world has
    turned on you and you're most alone, the chairman offers the only hand left. Accepting or refusing shapes Chapter 13.
44. **What the offer does:**
    - **Accept:**
      - syndicate prototypes and troops fight beside you in the finale;
      - but the chairman gains access to your bloodline key, so the dead launch site wakes;
      - the Restore path closes, and a unique syndicate-backed Merge variant opens.
    - **Refuse:**
      - you fight alone, and the syndicate becomes an enemy in Chapter 13;
      - the key stays yours, and every ending stays open.
45. **The syndicate and the Shadow Coalition are one full faction: the Syndicate Shadow Coalition.** In battle and in
    skirmish, the syndicate's prototypes, exoskeleton troops and stealth drones fight alongside the insurgent cells.
    This fits G8's "insurgent cells plus a PMC patron", with the patron now being the syndicate.
46. **The bunkers come in two kinds, plus one last bunker:**
    - **Archive vaults:** pre-war time capsules with clean corridors, working lights, sleeping board members in cryo,
      and archives that hold pieces of the founder's and the chairman's shared past. You take them in deep underground
      squad operations, boarding-style.
    - **Fortress factories:** huge underground arms plants still running, defended by automated pre-war turrets and
      prototype guards.
    - **The chairman's bunker** is the last and the worst.
47. **When the makers arrive, the syndicate splits:**
    - **The core becomes the cult's army on Earth.** When the cult reveals itself inside the makers' fleet, the
      syndicate turns out to be its prepared ground force. Whether that helps you depends on whether you accepted the
      chairman's offer or burned his bunkers.
    - **Defecting executives break away.** Some kneel to the makers, and some sell to the highest bidder.
48. **The soldier companion is the loyal hard man.** A pre-war sergeant, older than the founder and utterly loyal, he
    carries out the worst of the cover-ups. His line becomes your army's backbone and the keeper of the darkest secrets,
    which makes it the most dangerous if it turns.
49. **The engineer companion is the one who suspects.** She's a brilliant self-taught mechanic who recognises pre-war
    nanite tech in the dead zones and slowly realises the founder knows more than they say. Her line drives your
    industry and keeps digging, and it's her descendant who finds the founder's files in Chapter 9.
50. **The medic companion heals everyone.** She treats friend, enemy and civilian alike and refuses to pick sides. Her
    line runs your hospitals and the black sites' medical wards, and clashes with you over conduct. They're the voice
    the Healer listens to most.
51. **The scavenger companion is the survivor who sells.** He's a quick, funny, unreliable kid who knows every ruin
    and trades with everyone. His line becomes your scouts and smugglers, and the first to do business with the
    syndicate. That makes them your best link to it, and your likeliest leak.
52. **The two possible fifth bloodlines:**
    - **The preacher** leads a faith that grows up around the dead zones. That faith later splits, and its
      Machine-worshipping wing feeds the Coalition's cult wing.
    - **The merchant** builds your first economy and quietly works for the syndicate from day one.
53. **Signature set-pieces:**
    - **The dam (Chapter 4):** retake the dam and power plant in a flood and a storm. The first nanite flare-up hits
      the turbines, and the first cover-up follows straight after.
    - **The city that falls (Chapters 10–11):** a huge urban last stand as the Machine takes one of your growing
      cities. It ends with an evacuation by river and rail.
    - **The broadcast night (Chapter 12):** the night the truth comes out. Your capital riots, your own units split
      live in battle, and the Coalition strikes at the same time.
    - Not chosen: a set-piece return to the founder's old trench lines in Chapter 7.

### The Syndicate Shadow Coalition in depth (6 questions)
54. **Doctrine: three layers working together.**
    - **Cells bleed you:** cheap insurgent cells pin and wear you down with IEDs, ambushes, hit-and-run raids,
      sabotage and civilian cover.
    - **The elite strike:** once you're pinned, small syndicate elite units hit the weak point:
      - exoskeleton squads;
      - stealth drones;
      - smart munitions;
      - pre-war prototypes.
      They're few and deadly, and every elite loss really hurts them.
    - **Mercenaries fill the gaps:** units hired per battle from many eras and sources, so their army is never the
      same twice. Money buys whatever the battle needs.
    - **In play:** cells are the screen and the bait, mercenaries are the flexible middle, and the elite are the
      knife. Kill the money or the elite, and the rest falls apart.
55. **Tech: buy, steal, unseal.** There is no normal research tree. Tech comes from three sources:
    - **Buy:** units bought with money from war profits.
    - **Steal:** enemy tech taken through raids, captured gear and bribed engineers.
    - **Unseal:** pre-war vaults opened to release prototypes.
56. **Buildings (all four kinds):**
    - **Hidden and disguised:** cells build safehouses inside civilian buildings and workshops in ruins, linked by
      tunnels. A base looks like ordinary ruins until it's scouted.
    - **Bunker hatches:** syndicate structures sit underground, with only hardened hatches, lifts and vents on the
      surface. Destroying the surface doesn't kill what's below.
    - **Black markets:** market and broker buildings where mercenaries are hired and stolen tech is traded. They're the
      faction's economic heart.
    - **Vault cores:** a rare, unsealed pre-war vault that unlocks prototypes. It's their most valuable and most
      defended structure.
57. **Bunkers are fought level by level.** Each major bunker has floors you take one at a time:
    1. surface hatches;
    2. barracks and factory floor;
    3. labs;
    4. the cryo and archive vault at the bottom.

    Each level is a squad operation, and alarms wake the defences further down.
58. **Territory is held in the shadows.** The Coalition has no clean borders. Instead it infests regions that others
    own, spreading influence through towns, black markets and cells. On the map it shows as a creeping stain. Rooting
    it out takes patrols, policing and winning the locals over.
59. **Signature units.**
    - **Chosen:**
      - **Ghost exo squad:** pre-war exoskeleton troops with active camouflage. Their elite infantry, rare and
        terrifying.
      - **Backdoor hacker:** seizes enemy units or turrets that were bought from the syndicate, using the backdoors it
        sold.
      - **Hybrid nanite weapon:** an unstable vehicle or weapon built from Machine samples. It's devastating, but it can
        turn on its own side.
      - Not chosen: a swarm of armed technicals as the cells' cavalry.
    - **The owner asked for more.** These are candidates to react to, not yet chosen:
      - **Mercenary ace:** a hired named commander with their own veteran unit and a price that rises every battle.
      - **Sleeper cell:** units that sit disguised as civilians inside your towns until activated.
      - **Prototype walker:** a pre-war heavy walker from a vault core, one per army, and the faction's centrepiece.
      - **Broker:** a support unit that buys off enemy squads mid-battle, turning them neutral or mercenary.
      - **Silent rotor:** a stealth helicopter for inserting the ghost exos behind your lines.

#### The ghost exo squad in depth (owner's answers, 2026-10-28)
60. **Role is chosen by loadout before deploying:**
    - **Strike:** deep strike and decapitation. Commanders, artillery, radar, depots, and heirs on the field.
    - **Assault:** breaking fortified positions head-on.
    - **Recon:** unseen scouting, spotting and sabotage.
61. **Size, rarity and how the suits last:**
    - **Three formations:**
      - the standard 4-operator squad (the per-army cap grows over the campaign; see item 70);
      - a larger 6-operator squad, limited by cost;
      - named solo operators, used alone or in pairs, hero-style.
    - **Suits are pre-war prototypes,** so losses hurt. A damaged or recovered suit can be:
      - refurbished;
      - reverse-engineered;
      - then upgraded.
    - **Operators can be retrained** into another loadout or formation.
62. **How the camouflage works (all four rules):**
    - **Moving breaks it:** operators are near-invisible while still or walking. Sprinting, firing or taking hits makes
      the camo flicker, so speed costs concealment.
    - **Limited power:** the camo drains a battery that recharges slowly.
    - **It can be countered by:**
      - thermal sights;
      - sensor towers;
      - dogs;
      - recon drones;
      - rain and smoke, which show their outlines;
      - the Machine's nanite sense.
    - **Upgradable:** refurbished or reverse-engineered suits get better camo.
63. **Armour depends on loadout:**
    - **Recon:** light and fragile.
    - **Strike:** medium. It stops rifle fire and shrapnel, but heavy guns cut through.
    - **Assault:** heavy plating that shrugs off most small arms and light cannon. Only dedicated anti-armour weapons
      kill it.
64. **Weapons:**
    - **Suppressed smart rifles:** integrally suppressed, with smart optics and target tracking. There are no
      guided rounds that curve around corners; the rounds fly straight.
    - **Breaching and demolition:** shaped charges, thermite and EMP charges for doors, armour and bunker hatches.
    - **Close-quarters blades:** powered blades or hydraulic fists for silent kills and boarding actions.
    - Not chosen: arm-mounted heavy weapons.
65. **Vehicles (all four chosen, and the owner asked for more):**
    - **Silent rotor:** a stealth helicopter that inserts and extracts squads behind the lines. It's quiet and flies
      low, with no heavy guns.
    - **Ghost runner:** a light, camo-coated fast-attack buggy for four operators, with a quiet electric drive.
    - **The Mole:** a pre-war tunnelling pod that brings a squad up underneath a base or bunker. Renamed from
      "Burrower" so it doesn't clash with the G7 Machine burrower.
    - **Stealth APC:** an armoured carrier with a reduced signature, carrying a 6-operator squad and its gear.
    - **Drop pod:** a high-altitude drop capsule fired from the stealth transport plane, for the deepest strikes.
      Late eras only.
    - **River ghost:** a low-profile stealth boat for river and coastal insertions.
    - **Exo mule:** an unmanned walker that carries ammo, power cells and spare suit parts, so squads can stay out
      longer.
    - **Stealth transport plane:** a high-altitude, low-signature plane for long-range drops and extractions.
    - **Mini-sub:** a swimmer-delivery sub for harbour raids on blue-water navies and ports.
    - **Ghost drone carrier:** a ground vehicle that launches a swarm of small stealth drones to act as the squad's
      eyes and decoys.
    - **Exo recovery truck:** a disguised civilian truck that recovers downed suits and operators from the field.
    - Not chosen: a disguised rail crawler.
66. **The operators are a mix:**
    - **Cryo veterans lead:** pre-war operators woken from bunker cryo, who know little of the world above.
    - **Mercenaries fill out the ranks:** the syndicate's best, contracted for life.
    - **Vengeful recruits** from the victims' cells are trained up over time.
67. **Capturing their suits:**
    - **Recovering downed suits:** any side can grab a downed suit from the field, and the exo recovery truck races
      your teams for it. Captured suits feed the "captured tech" research layer.
    - **A remote kill switch:** syndicate suits carry one. A captured suit may shut down or self-destruct unless your
      engineers strip the switch out first.
    - **Your own exos:** late on, Human A can field its own reverse-engineered ghost-exo variant, weaker and less
      stealthy than the originals.
    - Not chosen: a dedicated counter-exo unit for every faction. The camo counters from item 62 cover that role.
68. **Upgrades: suit generations by era, each with module slots.**
    - **Mk I (Stages 6–8):** crude camo and a short battery.
    - **Mk II (Stages 9–10):** better camo and a neural link.
    - **Mk III (Stages 11–13):** near-perfect camo and hybrid parts made from Machine samples, which carry a risk.

    Each Mk comes from refurbishing, reverse-engineering or a vault unsealing. Every suit also has module slots
    (camo, armour, power, sensors) that can be swapped and upgraded.
69. **In the story, the ghosts are a rumour first and a named hunter later.**
    - **Early chapters:** rumours of "ghosts" killing officers. Nobody sees one clearly.
    - **From Chapter 9:** once the syndicate shows its hand, one named ghost-exo commander stalks your dynasty through
      Chapters 9–13:
      - assassination attempts on your heirs;
      - a raid to steal an heir;
      - a final duel.
      This commander is the syndicate's face in the field.
70. **The ghost-exo force grows from a handful to an army (owner's rule, 2026-10-28):**
    - **When the Coalition goes public in Chapter 9,** the syndicate fields only 4–6 exo squads in total. Every one is
      precious, and losing one matters. Before that, it works in secret from Chapter 1: agents, the merchant, quiet
      deals and rumoured ghosts (Part 0, resolution 7).
    - **Over the middle chapters it builds up** by refurbishing, reverse-engineering, unsealing vaults and training
      recruits (items 61, 66 and 68).
    - **By Chapters 12–13 it has 100+ squads** across every specialization and formation, maxed out: Mk III suits,
      full module slots, veteran operators.
    - **This makes the syndicate a real threat in the finale.** It lands at the same moment as the broadcast night and
      the chairman's offer (items 43–44).
    - **The war director tracks the build-up.** Cracking bunkers, killing the money and recovering suits (items 42, 54
      and 67) slows it, so a dynasty that fought the syndicate early faces a smaller army at the end.
    - **This replaces the earlier per-army cap of 2–3 squads.** The cap now scales with the campaign.

#### Exo operations in depth (owner's answers, 2026-10-28)
71. **Specialist squads.** These sit on top of the strike, assault and recon loadouts (item 60), and the late-game
    100+ force draws on all of them:
    - **Sniper/overwatch:** long-range marksman pairs with spotters, holding high ground and covering other squads'
      approaches and escapes.
    - **Electronic warfare:** jam radios, blind sensors and drones, spoof radar, and cut command links across an area.
    - **Snatch team:** captures heirs, officers, engineers or suits alive, and gets them out.
    - **Combat engineer / sapper:** mines, booby traps, demolishing bridges and depots, and breaching bunkers.
    - **Combat medic team:** field-repairs suits and stabilises downed operators, so a wounded squad can keep going or
      be extracted.
    - **Drone controllers:** run swarms of small attack and recon drones from cover while the operators stay hidden.
    - **Anti-armour hunters:** carry portable guided anti-tank weapons and mines, and stalk tanks and vehicles.
    - **Infiltrator / deep cover:** disguised, with no visible suit. They blend in with civilians or enemy troops and
      plant bugs and charges before a strike.
72. **Inside a squad: fire-team roles that can split into pairs.**
    - **The four roles:**
      - **Leader:** holds the command link and calls in support.
      - **Point:** leads the way and breaches.
      - **Gunner:** keeps up sustained fire.
      - **Specialist:** carries whatever the squad type needs (EW kit, medic kit, anti-tank launcher).
    - **Losing the leader** cuts off call-ins until another operator takes over.
    - **Splitting:** on command, the squad splits into two buddy pairs that act as separate micro-teams.
73. **Every operation runs insertion, approach, action, exfiltration:**
    1. **Insertion:** by vehicle, Mole, drop or on foot.
    2. **Approach:** under camo, watching the battery.
    3. **Action:** the strike, sabotage or snatch.
    4. **Exfiltration:** out to a pickup point.

    A squad that can't get out is trapped behind your lines and hunted down.
74. **Suit sensors:**
    - **Thermal and night vision:** exos see in the dark and through smoke, so they own the night (ties to item 4).
    - **Acoustic sensing:** they hear footsteps and engines through walls, and locate shooters by sound.
    - Not chosen: a shared squad picture, and tapping enemy comms. Squads see only what each operator sees.
75. **What limits time in the field (all four):**
    - **Suit power:** the camo battery (item 62) plus overall suit power. An operator who runs dry is slow, visible and
      heavy. Power cells are swapped from the exo mule or from caches.
    - **Ammo and charges:** squads carry a limited number of rounds, breaching charges and drones. Resupply comes from
      the mule, air drops or caches.
    - **Operator fatigue:** long missions tire operators, so aim, camo discipline and reactions all degrade until they
      rest. This is physical fatigue only; it doesn't add the combat-stress layer turned down in item 3.
    - **Suit wear:** every mission wears down joints and camo panels, so suits need workshop time between operations.
76. **A badly hit operator is downed, not dead.**
    - The suit locks up and protects a badly wounded operator for a short time.
    - During that time, the squad or a medic team can drag them out, or the enemy can capture both operator and suit.
    - If the operator is left too long, the kill switch fires to protect the syndicate's secrets.
77. **How exos fight alongside the rest of the faction (all four patterns):**
    - **Cells as the distraction:** a cell attack or riot pulls your forces one way while the exos strike somewhere
      else. This is the faction's signature combined move.
    - **Exos call in fire:** recon and sniper squads paint targets for syndicate artillery, drones or mercenary
      strikes.
    - **Exos open the door:** exos take out gates, radar and AA first, and then mercenaries and cells pour through.
    - **Covering the escape:** cells and mercenaries hold an exit corridor so the exos can get out.
78. **Exo AI: the smartest enemy in the game.**
    - **Patient hunters:** they wait for gaps such as shift changes, night, storms or your army moving out. They pick
      isolated targets and break off if they're detected, rather than fighting fair.
    - **They read your defences:** recon probes first, learning where your sensors and dogs are, then routing around
      them.
    - **They adapt across battles:** if you keep beating one tactic (say, thermal towers everywhere), they switch to
      another (EW squads to blind them, Moles under them).
    - **They pick priority targets:** whatever hurts you most, such as heirs, named officers, artillery, supply and
      command posts.
    - **Even more brains and memory (owner's addition):** they keep a long memory of your dynasty, carried across
      chapters and generations:
      - your favourite base layouts, patrol habits and reaction times;
      - which heirs and officers are careless;
      - which tricks have already failed against you.
      They also coordinate several squads on one plan, use feints to test your responses, and set traps for the
      rescue teams you send.
79. **On the regional map (all four):**
    - **No marker until detected:** exo squads don't appear on your map unless detected. You see their effects
      instead: a depot blown, an officer dead, a bridge down.
    - **Raids as mini-ops:** some raids trigger a short defensive squad operation for you to fight; others resolve as
      events.
    - **Counter-hunts:** you can send hunt operations into regions with signs of exo activity, to find and kill a squad
      before it strikes.
    - **Hidden lairs:** exos work from hidden forward caches and safehouses. Finding one ends their reach in that
      area.
80. **What keeps them grounded: a maintenance bottleneck.** Suits need specialist techs and parts. A broken workshop
    or a dead tech grounds squads, which makes syndicate workshops and techs high-value targets.
    - Not chosen: weight and noise limits, heat signature, or the human-inside limits. Exos are not slowed by mud,
      noise or heat beyond the camo rules in item 62.
81. **How they look and sound on the battlefield:**
    - **A heat-shimmer silhouette:** camouflaged exos show as a faint shimmer, easy to miss but readable to a careful
      eye. It flickers visibly when they move fast or fire.
    - **Their own audio cues:** a quiet servo whine and suppressed shots, so sharp-eared players hear them before they
      see them.
    - **A reveal moment:** when the camo drops, there's a sharp "decloak" effect and a sting in the score.
    - Not chosen: a distinct look for each Mk.
82. **Human A's exos follow a different doctrine.** Human A fields its reverse-engineered suits (item 67) as elite
    bodyguards for heirs and officers: counter-assassination teams that hunt syndicate ghosts. That keeps the
    syndicate's offensive stealth unique.
83. **How operators grow (all three):**
    - **Ranks:** missions raise rank, improving camo discipline, aim and endurance.
    - **Specialist certifications:** operators earn certifications that let them switch specialization (the
      retraining in item 61).
    - **Named legends:** long-surviving operators become named, with personal traits and a reputation your soldiers
      fear. Top-rank operators become squad leaders or solo operators.
84. **The hunter commander is a cover-up orphan.** They are the child of a witness your founder silenced in Chapters
    4–6, raised by the syndicate and given a suit. The hunt is personal, and it pulls on the cover-up threads. Like the
    chairman, the hunter sleeps in bunker cryo between hunts and wakes for each generation of your heirs, so they last
    from Chapter 9 to 13 (Part 0, resolution 6).
85. **How the hunter's story ends depends on conduct, and the hunter can win.**
    - **Kill them** in the final duel.
    - **Capture them** for the black site.
    - **Turn them:** if your dynasty has been merciful and confessed in Chapter 12, they can stand down, or even turn
      against the syndicate.
    - **They can win:** in Dynasty mode, the hunter can really kill an heir, which changes your succession for good.
86. **Where exos come from: one central complex, plus forward outposts.**
    - **The exo complex:** one huge hidden bunker, with its parts on different levels:
      - **workshop:** refurbishing, module refits and repairs, the bottleneck from item 80;
      - **training range:** where recruits train and operators earn certifications;
      - **cryo wake hall:** where cryo veterans are woken and reconditioned;
      - **reverse-engineering lab:** studies captured or wrecked suits and Machine samples to build new Mks.
    - **Forward workshops:** small workshops in the field that handle repairs.
    - **A campaign-scale target:** finding and cracking the complex cripples the whole exo programme and slows the
      build-up in item 70.
87. **Comms depend on the Mk:**
    - **Mk I: burst radio.** Squads keep radio silence and send short, encrypted bursts. Each burst risks being picked
      up by your EW or signal towers. Cut their relay (a hidden mast or the silent rotor) and the squads keep acting on
      their last orders (item 6).
    - **Mk II and III: a neural link** to command. The squads are never cut off, but the link can be hijacked by a
      backdoor hacker, and that works in both directions.
88. **What a hacker can do through the neural link:**
    - **Available once the link exists:**
      - **Blind the squad:** cut its sensors or camo for a short window, so your troops can strike.
      - **Track them:** ride the link to see where the squad is and where it's heading.
    - **Unlocked only very late:**
      - **Fire the kill switch:** set off a suit's kill switch remotely.
      - **Turn an operator:** briefly seize a suit and make it attack its own squad.
89. **Exos against the Machine and the makers:**
    - **Against the Machine: fairly effective, with known weaknesses.** Exos can fight it, but they have known
      vulnerabilities, chief among them the nanite sense that sees through camo (item 62).
    - **Against the makers: capable, but not enough on their own.** Exos are useful in the arrival war, but they can't
      beat the makers alone. They need the rest of humanity, or the cult, alongside them.
90. **Controlling exos as the player (skirmish):**
    - **Direct control:** you select and order exos like any other unit, with extra tools:
      - a camo on/off toggle;
      - a battery gauge;
      - a route planner that shows the enemy sensor ranges you know about;
      - one-click exfil to the nearest pickup.
    - **An optional mission planner** for multi-squad operations. You set insertion, route, target and exfil before
      launch, then watch it run, stepping in when needed.

#### The exo support corps (owner's answers, 2026-10-28)
91. **Exo engineers work at two levels:**
    - **Senior techs at the complex** are rare pre-war suit techs woken from cryo, who train apprentices over the
      campaign. Each tech raises how many suits can be maintained, so killing or capturing techs is the surest way to
      choke the build-up in item 70.
    - **Field techs** go out with squads to do quick repairs. They're soft targets for snipers.
92. **Training officers, at two levels:**
    - **Cryo instructors:** a few named pre-war instructors run the training range. Their quality sets how fast
      recruits rank up and how many certifications are possible. Losing one slows the whole pipeline.
    - **Veterans rotating in:** named-legend operators (item 83) can leave the field to train recruits. That boosts
      training at the cost of field strength, so the syndicate has to choose between strength now and growth later.
93. **Backdoor hackers:**
    - **Line of sight or a relay:** a hacker has to be near the target, or patched through a relay or an EW squad.
      Hacks take time, and you can interrupt one by killing or jamming the hacker.
    - **Hackers grow:** they rank up, getting faster and able to hold more units at once, and the best become named.
    - **Their targets** are still the backdoors in syndicate-sold gear (item 59) and the neural link (item 88).
    - Not chosen: a counter-hacking system for stripping backdoors.
94. **Hybrid nanite weapons: what they are.**
    - **Nanite grenade or charge:** releases a short-lived nanite cloud that eats armour and electronics in an area,
      then burns out. It can drift onto your own side.
    - **Hybrid tank:** a tank with a nanite-grown armour skin that slowly repairs itself, but grows more unstable the
      more damage it heals.
    - **Nanite launcher:** artillery that fires seeded shells, creating temporary creep zones that block movement and
      corrode units.
    - **Small arms and crewed weapons (owner's addition):**
      - assault rifles and other guns that fire nanite-laced rounds;
      - crewed mobile turrets;
      - other infantry weapons.
      See item 95.
    - Not chosen: hybrid exo modules as their own category. The Mk III hybrid parts in item 68 still stand.
95. **Hybrid small arms and crewed weapons (all four):**
    - **Corroding rifle rounds:** assault rifles whose nanite-laced rounds keep eating into armour after impact. They're
      strong against vehicles and suits, but magazines degrade and jam if stored too long.
    - **Nanite LMG:** a squad machine gun whose rounds leave corroding residue on cover, wearing walls and sandbags
      away.
    - **Crewed mobile turret:** a wheeled turret with a crew of two, firing nanite-laced autocannon rounds. It's
      devastating, but its barrels slowly grow out of shape and need constant tending.
    - **Nanite shotgun / breacher:** a close-range weapon that dissolves doors, hatches and armour plates, for bunker
      and boarding fights.
96. **The cost of hybrid weapons:**
    - **Handlers get sick:** crews exposed for long periods develop slow nanite sickness, tracked through the wound
      system.
    - **Conduct and civilians:** using them near civilians counts against your conduct and against how civilians
      remember you (item 12).
    - Not chosen: an instability meter, or drawing the Machine's attention. The weapon-specific quirks in items 94–95
      (drift, jamming, barrel growth, unstable self-repair) still apply.

#### The cells and the mercenaries (owner's answers, 2026-10-28)
97. **How insurgent cells operate (all four):**
    - **They hide among civilians:** cell fighters look like civilians until they act. Attacking them risks civilian
      casualties and your conduct, and that is their main shield.
    - **They recruit from grievance:** cells grow fastest in regions you brutalised or neglected (ties to item 12).
    - **They're cheap and expendable:** light weapons, IEDs and technicals, all low-cost. Losing cells barely hurts
      the syndicate.
    - **Each cell has a named local leader.** Killing the leader scatters the cell; capturing them gives you intel.
98. **The cell toolkit:**
    - **IEDs and ambushes:** roadside bombs, command-wire triggers and ambushes on convoys, which make supply routes
      dangerous.
    - **Suicide drones:** cheap, commercial-style drones rigged with explosives. Cells build them and use them in swarms
      in later eras.
    - Not chosen: technicals and shoot-and-scoot mortar or rocket teams.
99. **Mercenaries (all four):**
    - **Hired per battle:** before or during a battle, the black market offers a rotating selection of mercenary units
      for money. They leave when the contract ends.
    - **Mixed eras and origins:** ex-Human B tank crews, deserters, foreign companies, even ex-Human A veterans, each
      with their own gear.
    - **Loyalty is for sale:** they can be outbid. If their employer runs out of money or loses badly, they may switch
      sides or walk off mid-battle.
    - **Named companies:** a few mercenary companies have names, reputations, leaders and grudges. They remember who
      paid them and who betrayed them.
100. **Your dynasty can hire only the independent named companies,** never the mercenaries the syndicate controls.

## To do (not yet designed)
- Nothing open. (The space ship rosters were settled 2026-10-27; see "Space ship rosters" above.)

---

## Research consulted (2026-10-26)
- Company of Heroes 3: [NPR](https://www.npr.org/2023/02/20/1158011960/company-of-heroes-3-review),
  [Vice](https://www.vice.com/en/article/company-of-heroes-3-review/),
  [Prima Games](https://primagames.com/reviews/company-of-heroes-3-review)
- Broken Arrow: [Notebookcheck](https://www.notebookcheck.net/The-best-Real-Time-Strategy-RTS-of-2025-New-modern-wargame-breaks-into-Steam-s-top-charts-with-v1-0-launch.1040192.0.html),
  [Round Table Co-op](https://roundtablecoop.com/?p=10998)
- WARNO: [Wikipedia](https://en.wikipedia.org/wiki/Warno_(video_game))
- Terminator: Dark Fate – Defiance: [Slitherine dev diary](https://www6.slitherine.com/news/terminator-dark-fate-defiance-we-are-legion-dev-diary-2),
  [Steam discussion](https://steamcommunity.com/app/1839950/discussions/0/4344355079688064655)
- Tempest Rising: [AOL/IGN review](https://www.aol.com/tempest-rising-review-single-player-140000130.html),
  [PC Games](https://www.pcgames.de/Tempest-Rising-Spiel-73832/Tests/Echtzeit-Strategie-auf-den-Spuren-von-Command-und-Conquer-1470766/4/)
- Regiments: [ModDB](https://www.moddb.com/games/regiments),
  [CyberPowerPC review](https://www.cyberpowerpc.com/blog/regiments-game-review/)
- Dust Front: [PCGamesN](https://www.pcgamesn.com/dust-front/steam-rts-game)
- Men of War II: [CGMagazine](https://www.cgmagonline.com/review/game/men-of-war-ii-pc-review/)
- StarCraft II, Kenshi, Mount & Blade, X4, Crusader Kings and RimWorld were referenced from general knowledge, not
  researched in this session.
