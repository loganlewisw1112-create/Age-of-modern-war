# G6 plan: "Command & Terrain" (draft for owner sign-off, 2026-10-25)

**Status: DRAFT, waiting for owner sign-off.** The scope was approved 2026-10-25 (PROGRESS.md, "G6 (slice after G5): owner notes", items 1-17 and the two answer passes). This plan says how it gets built. Nothing starts until you sign off. G5 is finalized (commit a8eb715, delivered partial).

**One seamless wave**, like G5. It delivers one packaged build. There are no stops between parts and no hand-backs to you until the final gate, except the one sign-off gate in section 0b.

## What you get to play
- **Real high ground:**
  - 4 terrain height levels (valley, plain, hill, ridge) with ramps;
  - high ground gives sight, range and defence;
  - cliffs block movement and sight;
  - the editor gets raise, lower and smooth brushes.
- **Companies and armies:**
  - train a 15-45-element company in one order at a new **Company HQ**, from a preset type or your own **Army Builder** template;
  - each company has a captain and lieutenants;
  - join 2-4 companies into an army under a **Commander**;
  - losses refill automatically;
  - the next in line steps up when a leader falls.
- **AI that fights like a military:**
  - every AI level positions on high ground and in cover, holds formation, and attacks with combined arms (recon, suppress, assault, consolidate);
  - it runs special ops and exfil, holds reserves and retreats in good order. The enemy uses the same doctrine.
- **Your own AI Commanders:**
  - hand one a company, an army or a role (base defence, air, logistics, naval);
  - give it an objective and a stance (cautious / balanced / aggressive) and pick a playstyle;
  - your orders always override it.
  - Also: **ally AI commands** ("attack here", "defend me", "send air support").
- **89 new assets**, already drawn as game sprites (`docs/g6_art_kit`): 15 turrets, 9 fortifications, 9 drone pieces, 15 vehicles, 13 infantry, 4 aircraft, 10 ships including the **carrier** and **submarine**, 11 buildings, and the Rhomboid, Laser Tank and Exo-Suit Trooper.
- **New battlefield systems:**
  - minefields and mine clearing, on land and at sea;
  - garrisons, plus trench and sandbag cover;
  - tank traps and wire;
  - camo and decoys;
  - rail and the armored train;
  - submarines and sonar, carriers;
  - SAMs that need radar;
  - a counter-drone layer;
  - Machine self-repair and wreck conversion;
  - hover units;
  - airdrops and airlift.
- **Exo-suit garage** (Human A): Avatar-style walking suits with big rifles and missile tubes; the pilot ejects when a suit is destroyed.
- **Infantry loadouts:** per squad, at a barracks or the Company HQ, up to Iron-Man-style exo armour.
- **Research upgrades** for the new content.
- **Stage 10 playable** ("Automated Technocracies").
- **Marketplace:** buy and sell resources for credits at moving prices.
- **New airfield:** a base, then tarmac, then a short runway, with hangars auto-placed in slots.
- **Survival mode:** "Repel all waves" or "Survive mm:ss" on any map, plus 2 new stronghold maps and a dedicated Wave AI.
- **Editor Live mode:** units you place fight with AI tactics; switching Live off rewinds the map.
- **G5 carry-over fixes** (D22): 10k speed, AI soaks with winners (Valley Conquest included), a full-suite rerun, fps measured, and flake-free parallel playtests.

---

## 0. How "one wave" works
- ORCH writes `docs/CONTRACTS_G6.md` and the compiling scaffold first (about 1-2 hours; G6 has more cross-agent APIs than G5). That fixes:
  - the IDs, file ownership and API signatures;
  - the `*.api_ready` facts and the failing acceptance tests.
- Then every workstream runs in a single continuous pipeline.
- **Up to 8 agents live at a time** (D21). A finished slot is refilled from the queue at once.
- **Every agent gets its own operating guide** (section 11). No two agents own the same file.
- Dependencies are "API ready" facts on the board, not separate waves:
  - the AI starts as soon as the elevation, company and mechanics APIs are posted as stubs;
  - art and content start at once from the fixed IDs.
- **Honest size:** G6 is the largest slice yet:
  - 89 assets + about 8 new art pieces;
  - about 14 new sim systems;
  - a terrain-height layer touching movement, combat, fog, render and editor;
  - a doctrine AI rewrite on top of the existing AI;
  - about 6 new UI panels.
- G5 took about a day and a half of continuous orchestrated work. **Expect G6 to take about 4-6 days.** You get a status whenever you ask. If a part runs long, I park it with a written note; tests are never cut. Nothing is pushed without asking.

## 0b. Built for speed and first-time-right (lessons from G4 + G5)

| # | Measure | Problem it prevents |
|---|---|---|
| 1 | **Contracts + compiling scaffold + failing acceptance tests named after each agent's Done-when**, before any agent starts. | Guessed APIs; "done" meaning different things. |
| 2 | **APIs posted as compiling stubs within each agent's first hour** (`*.api_ready`). | AI/UI waiting on sim. |
| 3 | **Art first:** the G6 art kit already renders every asset. ART-G6 moves it into `tools/art/g6_*` on day 1, so VIEW/UI/PT have real sprites from the start. | Placeholder silhouettes for days. |
| 4 | **Caps sized for the current guard model** (base 303k): builders 750k / 140 calls, heavy roles split in two, never raised mid-run. | Handoffs at 30 calls; cap hits mid-task. |
| 5 | **Write in chunks, never one giant file:** a skeleton first, then ≤250-line edits, a render or test after each, and a status after each. | G6 art pass: an agent silent for 12 min writing one 60 KB file was stopped. |
| 6 | **Every runner prints parse errors and has a timeout** (Godot hangs on exit after a GDScript parse error and prints nothing). | The art-kit runner hid parse errors, so an agent looked silent. |
| 7 | **Network-drop resume:** a dropped agent is resumed from its own transcript with a standard message. Its stale strikes during the outage do not count once it posts a status. | G6 art pass: 3 agents dropped at once (ECONNRESET). |
| 8 | **Integration heartbeat every ~3 h:** ORCH runs the full suite + playtests on the committed head and commits verified work in small batches. | Breakage found only at the end. |
| 9 | **Test lanes on a shared PC:** at most 3 soaks + 2 windowed playtests at once. Playtests that flake in parallel are fixed, not just re-run alone (G5 left two such flakes). | Load-inflated timings; G5 stages/tutorial flakes. |
| 10 | **Soak lanes start on day 1:** AI7-USE re-runs the G5 soak lane immediately (it was never re-run after the final fix) and keeps the Valley draw under watch all wave. | Soaks as the tail. |
| 11 | **One owner gate only, mid-wave:** a short "doctrine + elevation look" checkpoint. Screenshots and a 2-minute replay of one AI company assault on high ground, with a yes/adjust from you. Everything else is defaulted in section 1. | Waiting on decisions; wrong AI feel found at the end. |
| 12 | **Final perf on a quiet PC, ORCH only, every agent stopped.** | Machine load. |

---

## 1. Decisions (recommended default first; change any before sign-off)

| ID | Question | Default | Alternative |
|---|---|---|---|
| D21 | Agents live at once | **8** (your G5 override again; the standing rule is 6) | 6 (slower, about +30% wall time) |
| D22 | G5 carry-over gaps | **Yes**: G6 owns the G5 misses. That means 10k speed, soak winners incl. Valley, full-suite rerun, fps measured and the two parallel-playtest flakes. | Leave them for G7 |
| D23 | Elevation data | **A new per-tile height layer** `map.height` (0 valley, 1 plain, 2 hill, 3 ridge) beside the existing terrain codes. Ramps are tiles that join two levels; a level change without a ramp is a cliff. Map files gain a version; old maps load at plain, with G4 HILL tiles converted to level 2 and CLIFF kept. | A smooth heightmap |
| D24 | Height rules | Per level of advantage: **+2 sight, +10% weapon range, 15% less damage taken from lower attackers.** Line of sight is blocked by higher ground between. Climbing a ramp costs 30% speed. | Sight only |
| D25 | Runway lengths (tiles) | **Airfield/aerodrome 12, airstrip 8, forward strip 6, Machine launch rail 6** (from 26/14/10/12) | Your numbers |
| D26 | Airfield layout | **Main airfield base (2×2) → tarmac apron → 1 runway.** 6 hangar slots on the apron; each Extra Airstrip upgrade adds 1 runway + 2 slots. Hangars auto-fill the next slot. Existing G5 save/maps migrate. | Keep strips, only shorten |
| D27 | Market pricing | **Each resource has a base price.** Every unit bought by anyone raises the price 1%, every unit sold lowers it 1%, and prices drift back to base over 3 min. Selling pays 70% of the buy price. There are trade limits per minute. The market opens from the HQ panel, with no new building. | Fixed prices |
| D28 | Company sizes and cost | **Presets come as Platoon (~15), Company (~30) and Battalion (45).** Cost and population = the sum of members, with **no discount**. Training time = the slowest member + 25%. | 10% bulk discount |
| D29 | Company cohesion | Within 12 tiles of its captain: **+10% accuracy and +10 morale**; outside: no bonus. | No bonus |
| D30 | Commander unit | **One Commander unit per faction**, trained at the Company HQ. At most 2 alive (= the 2-army cap). It is armed lightly and has an aura (+morale for the army). | Commander = upgraded captain |
| D31 | Company HQ | **One per player at a time** (build a second only after losing the first), size 3. Trains companies, Commanders and replacements. Styled per faction (art kit adds it). | Unlimited |
| D32 | Exo-suit roster (Human A) | **Rifle Suit and Missile Suit at Stage 9, AA Suit at Stage 10**, from a size-2 Exo-Suit Garage. A suit counts as 1 vehicle element in a company. | 2 suits only |
| D33 | Exo-Suit Trooper (Stage 10 unit) vs loadouts | **The Exo-Suit Trooper is the top infantry loadout tier** ("exo armour"): Iron-Man-style powered infantry, applied per squad at a barracks or the Company HQ. The garage suits are the separate AMP-style walkers. | Separate unit |
| D34 | Loadouts per faction | **Human A:** Standard / Assault / AT / Marksman / Breacher / Plates / Exo armour (Stage 10). **Human B:** Standard / Assault / AT / Breacher / Plates. **Machine:** module swaps on crawlers (armour / sensor / weapon). | Humans only |
| D35 | Research upgrades | **About 24 new research items:** 2-3 per new system (mines, CIWS, sonar, armour kits, radar range, rail speed, suit armour, ...), in `research.json` | ~12 |
| D36 | Stage 10 gate | **Same structure as the 8→9 gate:** cost ×1.5 plus one new research ("Automation Doctrine" / Machine "Overmind Protocols"), with a 60 s transition | Free unlock |
| D37 | Rail | **New terrain code RAIL**, laid with a drag tool by engineers from a Rail Yard. Trains move only on rail and can be cut by destroying rail tiles. | Fixed map rails only |
| D38 | Submarines | **Submerged subs are invisible except within sonar range** (destroyer, AA frigate, minesweeper, Supply Ship has none) or for 5 s after firing. Surfacing: faster, visible, can be resupplied. | Always visible |
| D39 | Carriers | **The carrier holds 4 light hangar slots** (strike jet / interceptor) using the G5 hangar + sortie model at sea, rearms at a Supply Ship or pier. | 6 slots |
| D40 | Doctrine AI build | **Layered:** Strategic (Commander/army: objectives, fronts, reserves, timing) → Operational (company: axis, formation, phase lines, combined-arms sequence) → Tactical (platoon: cover/height-seeking positions, bounding overwatch, flanks). Special ops and exfil become new mission types on the G2 `ops_missions`. Every decision is logged with a reason tag so soaks can prove it. | Rule tweaks to the current AI |
| D41 | AI Commanders UI | **A Commanders panel:** select a formation or pick a role → "Assign commander" → playstyle, objective (click map) and stance. A badge on each unit under AI command. Your direct order overrides that unit for 20 s. "Recall" returns full control. | Hotkey only |
| D42 | Survival maps | **Two new maps:** "Ridge Bastion" (walled ridge, 2 ramps, 4 attack lanes) and "River Dam" (dam and bridges, like vision 02-04). Wave AI escalates every 90 s, and waves use the attacker faction's companies. | One map |
| D43 | Live mode controls | **Toolbar toggle (L)**, with speed buttons pause / 1x / 2x / 4x. Switching off restores the exact pre-Live snapshot. Undo history is untouched by Live. | Toggle only |
| D44 | Out of scope (unchanged) | **Weather + day/night and veterancy (G7), 4th faction (G7/G8), Stages 1-6 and 11-13, audio, multiplayer** | |

---

## 2. Workstream A: engine, elevation, G5 carry-over

### A1. True elevation (D23, D24)
- **Sim:**
  - `map.height` layer, ramp and cliff derivation;
  - movement cost and passability by slope;
  - line of sight through height;
  - the height bonuses in combat and fog;
  - artillery and indirect fire ignore LOS but get a range bonus from height;
  - aircraft ignore height.
- Path grid and native core (`rts_core`) updated, determinism hash-proven A/B; save/load includes height.
- **Map generation:** the built-in maps get authored height (Valley Conquest gets real valleys and ridges). `map_gen` gets height noise with ramp placement and validation (every base reachable).
- **Render (VIEW6 + ELEV-VIEW):**
  - tiles and entities drawn with a height offset;
  - cliff faces, ramp and slope tiles in every terrain style;
  - correct draw order across levels;
  - fog drawn on raised tiles;
  - selection and picking on raised tiles.

### A2. G5 carry-over (D22)
- 10k all-fighting to ≤62.5 ms/tick (from about 94-101 at G5 end; the next steps are in `.plan/handoff/CORE10K-3.json`). Elevation must cost ≤5 ms of that.
- Windowed fps measured: 2k at 60+, 10k zoomed out at 30+.
- AI soak lane re-run on day 1. Winners on all configs, Valley Conquest included.
- Full suite green on every heartbeat.
- The stages and tutorial playtests made deterministic when run two at a time.

## 3. Workstream B: 89 assets into the game
- **Content:** every art_id in `docs/g6_art_kit/items.json` (minus `x_*`) becomes a def in `content/g6/*.json`:
  - units, buildings, weapons, armor_mult, production, faction_roles, stage gates (D36), research (D35);
  - provisional balance, tuned by the soak evidence;
  - the Rhomboid moves to Human B Stage 7.
- **Art:** the kit drawers move to `tools/art/g6_*.gd` + `g6_art_gen.gd` → `assets/art/g6_units/`, `assets/art/g6_bld/`. Buildings get all 4 rotations plus damaged and build stages (like G5).
- **New art not yet in the kit:**
  - Company HQ ×3;
  - Commander ×3, captain/lieutenant figures ×3;
  - Exo-Suit Garage;
  - Rifle, Missile and AA exo suits;
  - Exo-armour infantry;
  - rail tiles;
  - cliff and ramp terrain;
  - mine markers, garrison pips, sonar ping;
  - icons for every new command.
- **Polish items from the art pass:**
  - hovercraft cargo contrast, supply ship crane load, fuel tender smoke;
  - b_conscripts 64×44 squad frame (renderer must accept per-def squad fw/fh).

## 4. Workstream C: new battlefield systems (the mechanics the assets need)

| System | Assets that use it | Core rules |
|---|---|---|
| Mines (land + sea) | Minefield, Sentry Mine Turret, Spider Mine Layer, Mine Barge | Area brush; owner sees dashed boundary; enemies see nothing until detected; AT vs AP; triggers + damage |
| Mine clearing | EOD Sappers, Mine-Clearing Vehicle, Minesweeper, Recon drones | Detect radius, clear lane, line charge, sweep path |
| Garrison | Garrisonable Building, Pillbox, FOB | Squads enter (capacity pips), fire from slots, protected; flamers/satchels/artillery clear them |
| Field cover | Sandbag Line, Trench, Tank Traps, Barbed Wire | Infantry-buildable lines; cover multipliers; traps block vehicles; wire slows foot |
| Camo / decoys | Camo Nets and Decoys | Hidden until it moves; decoys draw AI fire and strikes |
| Rail | Rail Yard, Armored Train | D37 |
| Sonar / submarines | Attack Submarine, destroyers, frigates, Minesweeper | D38 |
| Carrier ops | Aircraft Carrier | D39 |
| Radar-gated air defence | Radar Station, SAM Site, AWACS, Pulse Spire Mk II | SAM needs radar in range; AWACS shares air picture |
| Counter-drone | Laser CIWS, Net Launcher Post, Jammer Obelisk, Backpack Jammer Team, Scrap AA Squad | Hard-kill shells, rockets, drones; nets capture (B salvages); jamming downs drones and guided shots in a field |
| Recon / call-ins | Aerostat, JTAC, Drone Control Center, AWACS | Persistent sight; designation cuts strike delay and cost; drone-team bonuses |
| Auras / morale | Command Vehicle, Propaganda Team, Propaganda Tower, Commander | Morale and accuracy auras; enemy morale drain |
| Machine specials | Nanite Wall, Nanite Forge, Repair Swarm II, Assimilator, Hive Node, Swarm Queen, Mimic Drone, Stalker Synth, Shield Drone, Relay Lattice, Overmind Uplink, Phase Gate | Self-repair, wreck conversion, spawners, disguise, cloak, energy shield, power-range chain, team-only gate |
| Mobility | Hover Tank, Hovercraft, Bridge Layer, Paratroopers, Airlift Transport, Marines | Water/land hover; temporary bridge; airdrop squads and pallets; fast beach unload |
| Strikes | Loitering Munition Truck, MLRS, Mass Driver, Cruise Missile Battery, SP Howitzer | Loiter-and-dive; salvo; long range; global-range cooldown strike |
| Engineering | Armored Bulldozer, Salvage Crane, Scrapyard Crane, Vehicle Repair Bay, Breacher Crawler, Satchel Sappers | Clear traps and wrecks; tow wrecks to income; fast repair; breach charges |

## 5. Workstream D: economy and bases
- **Marketplace** (D27): HQ panel, buy/sell salvage, ore, fuel and ammo, shared moving prices, per-minute limits. The AI trades with the same rules. Soaks must show it fixing small-map salvage starvation.
- **Airfield overhaul** (D25, D26):
  - new layout, slot hangars and short runways;
  - G5 flight/sortie/holding/crater logic kept, re-pointed at the new geometry;
  - editor placement and AI building updated;
  - old saves and maps migrate.

## 6. Workstream E: companies and armies (item 15)
- **Templates:** faction presets (A: Rifle, Mechanized, Armored, Artillery Battery, Air Assault, Engineer, Special Ops; B: Conscript Battalion, Shock Assault, Heavy Armor, Siege Battery, Works; Machine: Swarm Cluster, Walker Phalanx, Siege Array, Hunter Pack), each as Platoon / Company / Battalion (D28). Custom templates come from the **Army Builder** screen: slots, 45 cap, validation, saved per profile.
- **Company HQ** (D31) trains a whole company and spawns it at once with its captain and one lieutenant per platoon.
- **Chain of command** extends `ops.gd` groups to 3 levels: army → company → platoon.
  - Captain death → the senior lieutenant is promoted (confusion 10 s, −15 morale).
  - Commander death → the army splits back into its companies.
- **Armies:** a Commander (D30) joins 2-4 companies; max 2 armies.
- **Cohesion** (D29); **auto-refill** of losses at the Company HQ (toggle per company).
- **HUD:** company and army cards with a unit grid (vision 05), plus a battle-status line.

## 7. Workstream F: exo-suits, loadouts, research, Stage 10
- **Exo-Suit Garage** + Rifle/Missile/AA suits (D32). Pilot eject → one wounded soldier (G5 medical) → re-suit at the garage for less.
- **Loadouts** (D33, D34): swap per squad at a barracks or Company HQ for a cost; changes weapon and armour; exo armour is the top Human A tier.
- **Research** (D35) and the **Stage 10 gate** (D36) with its unlock list (PROGRESS item 7).

## 8. Workstream G: modes and editor
- **Survival** (D42): the `survive` and `repel_waves` victory types in `victory.gd`, wave spawner, Wave AI, 2 new maps, skirmish setup option.
- **Editor Live mode** (D43): snapshot → run combat + AI tactics only (no economy, no production) → restore. Speed buttons; works with AI Commanders and doctrine AI.
- **Editor elevation:** raise / lower / smooth / ramp brushes, symmetry-aware; validation (bases reachable, ramps valid).
- **Editor G6 placements:** mines, garrisons, rail, carriers, subs, Company HQ; companies placed as one block.

## 9. Workstream H: AI (items 10, 17; D40, D41)
- **Doctrine AI** (all AIs, enemy included):
  - Strategic: fronts, main effort vs fixing force, reserves, timing attacks to production spikes, retreat and regroup.
  - Operational: company axis and phase lines, combined-arms sequence, artillery prep, breaching.
  - Tactical: high ground and cover seeking, bounding overwatch, flanking, suppression then assault, garrison use, mine awareness.
  - Special ops (raid, sabotage, recon, officer hunt) and **exfil** (extract squads, wounded, VIPs under fire) as missions.
  - Every decision is logged with a tag (`overwatch_set`, `flank`, `assault_phase`, `exfil_done`, ...) for the soak gates.
- **AI uses everything:** trains companies and armies, builds every new defence, lays and clears mines, garrisons, uses subs, carriers, SAM + radar and counter-drone, trades on the market, uses the new airfield, reaches Stage 10.
- **AI Commanders** (player side): formation or role, objective + stance, 4 playstyles (Defensive / fortifier, Aggressive / breakthrough, Special ops / raider, Combined arms). Never countermands a fresh player order; badge + recall.
- **Ally AI commands:** "attack here", "defend me", "send air support" in team games.
- **Wave AI** for survival.

## 10. Workstream I: UI and view
- **New panels:** Marketplace, Army Builder, company/army cards, Commanders panel, loadout swap, Exo-Suit Garage, Live toggle + speed, height brushes, mine/garrison/rail tools, research additions, Stage 10.
- Every screen fits at all 7 resolutions with 0 issues (G5 fit test). RTS Mil everywhere.
- **New effects:** laser CIWS beam, nets, jamming field, sonar ping, mine blasts, line charge, train smoke, airdrop chutes, cloak shimmer, nanite repair, assimilate stream.
- **New overlays:** mines (owner view), garrison pips, sonar range, radar range, company cohesion ring, AI-command badges.

---

## 11. How it's built: agents, roles and operating guides (one wave, up to 8 live)

### 11.0 Rules every agent follows (common operating guide → `.plan/agents/prompts/G6_COMMON.md`)
Same as PLAN_G5 §11.0 (read order, own files only + change_requests, determinism, compile after every write, `--only` tests, board + bus, budget, machine sharing, final report, no commit, no GENESIS offer). It adds:
1. **Chunked writing:** a skeleton first; edits ≤250 lines; a test or compile after each; a board status after each (§0b-5).
2. **Runners time out and print parse errors** (§0b-6). Never pipe Godot output through a filter that hides `SCRIPT ERROR` / `Parse Error`.
3. **On a network drop,** your successor is you, resumed. Post a status as your first call back.
4. **Height-aware by default:** any code that reads positions, ranges or sight goes through `Terrain.height_at` / `Elevation.los` once `elev.api_ready` is posted.

### 11.0a Coordination layers
The message board (`.plan/board.jsonl`, guard.mjs under Monitor, caps registered) and the semantic layer (`.plan/bus.log` + `busd.py`), exactly as PLAN_G5 §11.0a.

### 11.1 Schedule (one continuous wave)

| Slot use | Agents |
|---|---|
| **Start (8 live)** | ELEV, PERF6, CONTENT6, ART-G6, ARMY6, MECH6a, AI7-USE (soak lane re-run first), ECON-AIRF6 |
| **Queue, starting the moment a slot frees** | MECH6b → NAVAL6 → AIRDEF6 → EXO6 → AI7-DOC → AI7-CMD → ELEV-VIEW → VIEW6 → UI6a → UI6b → MODES6 → ED6 → ART-G6b → PT6 |
| **Successors** | take queue priority |
| **Owner checkpoint** | doctrine + elevation look (§0b-11), when AI7-DOC posts `doctrine.demo_ready` |
| **Final gate** | ORCH, with every agent stopped |

### 11.2 Operating guide for each agent (the contracts fix exact files and signatures)

#### ELEV: terrain height, sim side
- **Role:** the height layer and every sim rule that uses it (D23, D24).
- **Owns:** `sim/terrain.gd` (height API), `sim/systems/elevation.gd` (new), the height parts of `map_io.gd`, `map_gen.gd`, `save_system.gd`, path grid + native height reads; `tests/test_elevation*.gd`.
- **Tasks:**
  1. Post `elev.api_ready` (`height_at`, `ramp_at`, `los`, `height_adv`) as compiling stubs in hour 1.
  2. Map v-next format + migration.
  3. Movement and passability by slope; LOS, sight, range and damage bonuses wired with CRs to combat and fog owners.
  4. Author height for the built-in maps; `map_gen` height + validation.
  5. A/B hash proof.
- **Done-when:** test_elevation (LOS, bonuses, ramps, cliffs, migration, save/load); every built-in map validates; soak-safe.

#### PERF6: 10k speed + elevation budget
- **Role:** G5 carry-over speed (D22) and keeping elevation within ≤5 ms.
- **Owns:** `sim/hot_state.gd`, `sim/native_core.gd`, `native/**`, `bin/**`, `tools/scale_bench.gd`, `tests/test_perf*.gd`, perf-sensitive paths in movement/combat/fog (shared by contract regions with ELEV).
- **Tasks:**
  1. Resume `.plan/handoff/CORE10K-3.json` (morale/fog native ports, hash-proven).
  2. Port the elevation LOS/path costs to native.
  3. Windowed fps harness.
- **Done-when:** 10k fight avg ≤62.5 ms/tick on a quiet PC; A/B hashes equal; fps numbers reported.

#### CONTENT6: defs for every G6 asset, research, Stage 10
- **Owns:** `content/g6/*.json` (new), `content/research.json` (additions), the stage 10 entries in `stages.json` / `rules.json advancement` / `factions.json stage_roles`; `tests/test_content_g6.gd`.
- **Tasks:**
  1. All 89 defs + weapons + production + roles with provisional balance.
  2. ~24 research items (D35).
  3. Stage 10 gate (D36) and unlock list.
  4. Company preset templates as data (D28).
  5. Loadout and exo-suit defs (D32-D34).
- **Done-when:** every id loads, is producible at its stage, appears in the right panel; content tests green.

#### ART-G6 (+ ART-G6b successor): integrate the kit, draw the new pieces
- **Owns:** `tools/art/g6_*.gd`, `tools/art/g6_art_gen.gd`, `assets/art/g6_units/`, `assets/art/g6_bld/`, `tests/test_art_g6.gd`.
- **Tasks:**
  1. Move the 89 kit drawers in; buildings get 4 rotations + damaged + build stages.
  2. Icons.
  3. The new pieces listed in §3 (Company HQ, Commander/captain/lieutenant, garage, suits, exo armour, rail, cliffs/ramps per terrain style, markers).
  4. The polish items.
- **Done-when:** manifest complete for every G6 id; every sheet self-checked by eye (8 facings); art tests green.

#### ARMY6: companies, armies, chain of command
- **Owns:** `sim/systems/companies.gd` (new), the group-hierarchy extension of `sim/systems/ops.gd`, the Company HQ production hook, `tests/test_companies*.gd`.
- **Tasks:**
  1. Post `army.api_ready` (train_company, form_army, company_of, army_of, promote) in hour 1.
  2. Templates (preset + custom validation).
  3. HQ training and spawn.
  4. Captain/lieutenant/Commander hierarchy, field promotion, army split.
  5. Cohesion; auto-refill.
  6. Save/load + hash.
- **Done-when:** test_companies (train, spawn, hierarchy, promotion, army join/split, caps 4 and 2, refill, cohesion, save mid-battle).

#### MECH6a: human-side mechanics
- **Owns:** `sim/systems/mines.gd`, `garrison.gd`, `fieldworks.gd` (cover lines, traps, wire, camo/decoys), `rail.gd`, `callins.gd` (JTAC, aerostat, drone CC, airlift, paradrop), `auras.gd`; `tests/test_mines*.gd` etc.
- **Done-when:** a test per system in §4 rows Mines, Mine clearing, Garrison, Field cover, Camo, Rail, Recon/call-ins, Auras, Mobility (bridge layer, paradrop, airlift), Engineering.

#### MECH6b: Machine mechanics + strikes
- **Owns:** `sim/systems/machine_g6.gd` (self-repair, assimilate, spawners, mimic, cloak, shield, relay chain, phase gate), `strikes.gd` (loiter, salvo, mass driver, cruise strike); tests.
- **Done-when:** a test per §4 Machine specials + Strikes row.

#### NAVAL6: submarines, sonar, carriers, sea mines, hover
- **Owns:** `sim/systems/sonar.gd` (new), carrier hangar-at-sea in `naval.gd` (contract region), sea-mine hooks with MECH6a, hover move class; tests.
- **Done-when:** test_naval_g6 (detection, surfacing, carrier sortie + rearm, supply ship Auto at sea, sweep lane, hover land/water).

#### AIRDEF6: radar, SAM, AWACS, counter-drone
- **Owns:** `sim/systems/airdef.gd` (radar gating, AWACS picture), `counterdrone.gd` (CIWS, nets, jamming fields); tests.
- **Done-when:** test_airdef (SAM blocked without radar, AWACS reveal, CIWS shoots drones/shells, net capture + salvage, jam field downs drones and guided shots).

#### ECON-AIRF6: marketplace + airfield overhaul
- **Owns:** `sim/systems/market.gd` (new), `sim/systems/airfield.gd` + `air.gd` geometry parts, `content/g5/air.json` strip/slot entries (contract-granted), migration; tests.
- **Done-when:** test_market (prices move/drift, limits, AI parity, save); test_airfield_g6 (slots, short runways, takeoff/land/holding/craters on new geometry, G5 save migration).

#### EXO6: garage, suits, loadouts
- **Owns:** `sim/systems/exo.gd` (pilot eject, re-suit), `loadouts.gd`; tests.
- **Done-when:** test_exo (train suit, eject → wounded → evac → re-suit discount), test_loadouts (swap cost, stats change, exo tier at Stage 10).

#### AI7-USE: AI uses everything + soaks (starts day 1)
- **Owns:** `sim/ai/ai_g6.gd` (new), production/build lists in existing AI files by contract region, soak lane scripts; tests.
- **Tasks:**
  1. Re-run the G5 soak lane on day 1 and fix to winners (Valley included).
  2. Then: build and use every G6 system, market trading, new airfield, Stage 10.
- **Done-when:** soak gates in §12.3; test_ai_g6.

#### AI7-DOC: doctrine engine
- **Owns:** `sim/ai/doctrine/*.gd` (new: strategic, operational, tactical, missions), the hooks into `ai_controller.gd` / `ops_missions.gd` by contract region; tests.
- **Tasks:**
  1. The three layers (D40).
  2. Special ops + exfil missions.
  3. Reason-tag logging.
  4. `doctrine.demo_ready` with a recorded replay for the owner checkpoint.
- **Done-when:** test_doctrine (high-ground pick, bounding overwatch, flank, suppress→assault sequence, reserve commit, retreat, exfil completes); soak tags present.

#### AI7-CMD: AI Commanders, ally commands, Wave AI
- **Owns:** `sim/ai/commanders.gd`, `ally_cmds.gd`, `wave_ai.gd` (new); tests.
- **Done-when:**
  - test_ai_commanders: assign formation/role, objective + stance, override 20 s, recall, never fights a fresh player order, 4 playstyles behave differently by tag counts;
  - test_ally_cmds;
  - test_wave_ai.

#### ELEV-VIEW and VIEW6: drawing it all
- **ELEV-VIEW owns:** terrain-height rendering (offsets, cliffs, ramps, draw order, fog on raised tiles, picking).
- **VIEW6 owns:** entity height offsets, new effects and overlays (§10).
- **Done-when:** view tests + probe screenshots for each new state; 6+ playtests stay green.

#### UI6a and UI6b: panels
- **UI6a owns:** Marketplace, Army Builder, company/army cards, Commanders panel.
- **UI6b owns:** loadout swap, garage, Live toggle + speed, mine/garrison/rail tools, research and Stage 10 additions.
- **Done-when:** UI fit 0 issues at 7 resolutions; ui playtests for each panel.

#### MODES6: survival
- **Owns:** victory types in `victory.gd` (contract region), wave spawner, setup option, the 2 new maps (`sim/maps/`).
- **Done-when:** test_survival (both victory types, waves escalate, any-map edge spawns); both maps validate; survival soak ends correctly.

#### ED6: editor Live mode, height brushes, G6 placements
- **Owns:** `presentation/editor/*` G6 additions, Live snapshot/restore, brush tools.
- **Done-when:** test_editor_g6 (Live on: fights start; Live off: state hash equals pre-Live; speed buttons; height brushes + validation; G6 placements); editor playtest.

#### PT6: playtests for every new flow
- **Owns:** `tools/ui_playtest.gd` G6 flows, `tools/editor_playtest.gd` additions.
- **Done-when:** every flow in §12.4 passes twice from a clean folder, including 2 at a time (no parallel flakes).

#### ORCH (me)
Contracts, scaffold, failing tests, caps and guard, heartbeat integration and commits, the owner checkpoint, quiet-PC perf, final gate, package, README/PROGRESS.

---

## 12. Done-when (frozen once work starts)
1. **Tests:** `tests/run.sh` TESTS OK on the final commit (a full run, not per-file), including new suites for:
   - elevation (LOS, bonuses, ramps/cliffs, migration, save);
   - companies/armies (train, hierarchy, promotion, join/split, caps, refill, cohesion);
   - mines + clearing (land and sea), garrison, field cover, camo/decoys, rail;
   - sonar/submarines, carriers;
   - radar-gated SAM + AWACS, counter-drone;
   - Machine specials, strikes, call-ins/auras, mobility (hover, bridge layer, airdrop, airlift);
   - market, airfield v2 + migration;
   - exo-suits (eject/re-suit), loadouts, research, Stage 10 gate;
   - survival (both types), editor Live (rewind hash equality), height brushes;
   - doctrine (each behaviour above), AI Commanders, ally commands, Wave AI;
   - save mid-battle with companies, subs submerged and Live off.
   - **0 files left in `tests/pending_g6/`.**
2. **Perf (quiet PC):**
   - 10k all-fighting avg **≤62.5 ms/tick** on an elevated map;
   - 2k fighting on screen 60+ fps;
   - 10k zoomed out 30+ fps;
   - numbers reported either way.
3. **AI soaks:**
   - 4 built-in maps × 2 seeds + 1 editor map + 1 survival map end with winners (survival: correct win/loss), 0 invariant failures. **Valley Conquest included.**
   - The logs show:
     - companies and an army formed;
     - doctrine tags (`overwatch_set`, `flank`, `assault_phase`, `reserve_commit`, `retreat`, `exfil_done`);
     - mines laid and cleared;
     - a garrison;
     - a submarine kill or detection;
     - a carrier sortie;
     - market trades;
     - Stage 10 reached;
     - an AI-commanded player formation in an assist soak.
4. **Playtests pass (twice, including 2 at a time):**
   - the existing 12;
   - **elevation** (take a hill; LOS and range bonus visible);
   - **company** (Army Builder template → train at Company HQ → company card → join an army with a Commander);
   - **AI Commander** (assign, objective, stance, override, recall);
   - **mines** (lay; EOD clears a lane);
   - **garrison**;
   - **naval G6** (carrier sortie; sub detected by sonar);
   - **air defence** (SAM needs radar; CIWS downs a drone);
   - **exo** (train suit; eject; re-suit);
   - **loadout swap**;
   - **market** (buy/sell);
   - **airfield v2** (buy hangar into slot, short-runway takeoff/land);
   - **survival** (survive and repel);
   - **editor Live** (fight, then rewind);
   - **height brushes**.
5. **UI fit test:** every screen at all 7 resolutions, 0 clipped or overlapping controls. RTS Mil everywhere.
6. **Owner checkpoint passed** (doctrine + elevation look, §0b-11), or your adjustments applied.
7. **Packaged build** passes all of the above from a clean folder, is copied to Downloads; README / perf report / PROGRESS match reality.

## 13. Known risks
- **Scope:** by far the largest slice. If something runs long it is parked with a note; tests are never cut. Most likely to run long: doctrine AI and elevation rendering.
- **Elevation touches everything** (movement, combat, fog, render, editor, maps, native). Determinism is guarded by A/B hashes at every step, and it lands early so others build on it.
- **Doctrine AI "feel"** can't be fully proven by tests, hence the mid-wave owner checkpoint with a replay.
- **Perf:** G5 missed 62.5 ms; G6 adds height LOS and 3-level command. The target is kept, and the risk is real. Numbers are reported either way.
- **Valley Conquest** has drawn on every code version since G4. With real height it may change character; AI7-USE owns it from day 1.
- **Art volume:** 89 kit assets to integrate + about 8 new sets + cliff/ramp terrain for every style.
- **Network drops:** seen during the G6 art pass. Resume-from-transcript is the standard procedure (§0b-7).

---
**Sign-off:** reply "approved" (optionally with changes to any D21-D44 default). ORCH then writes `CONTRACTS_G6.md` and the scaffold and starts the wave. The goal block moves to `## Active goal` in PROGRESS.md at that point.
