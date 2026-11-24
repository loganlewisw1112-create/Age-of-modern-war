# G10 Shadow Coalition — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Owner gate:** This is a review/approval plan. Do **not** implement G10 game code until the owner replies
> **APPROVE**. The approval freezes the draft Done-when in `game/docs/G10_SCOPE.md`.

**Goal:** Ship the Shadow Coalition as the fourth full faction across Coalition Stages 1–13, with a ~60-definition
Stage 7–10 core, asymmetric faction mechanics, AI-first Ghost Exos, Human A Counter-Ghost counterplay, skirmish and LP
parity, and an evidenced `g10.lock`.

**Architecture:** **Approach C — parallel pillars, one lock.** First land a small shared foundation (content loader,
faction registry, Coalition-only stage gating and a roster manifest). Then run non-overlapping roster/art, mechanics,
tech/building, Ghost/Counter-Ghost, AI, and mode pillars in parallel. Integrate only through public APIs into the
existing deterministic `SimWorld`; extend shipped Pre-G10 AI/economy rather than cloning or replacing it.

**Tech Stack:** Godot **4.7.2** + deterministic GDScript simulation; JSON content fragments under `game/content/g10/`;
existing presentation/art generators and four-facing art catalog; Rust `rts_core` only after a measured native/perf
case; permanent upgrade board at `game/.plan/upgrade_board/`; package script `game/.plan/package_g71.ps1`.

## Global Constraints

- Branch: `g71`. Plan authority: `game/docs/G10_SCOPE.md`.
- No game-code work before owner **APPROVE**. Scope remains OPEN until that approval is recorded.
- Shadow Coalition only: other factions' Stages 1–6 and 11–13 remain unavailable until G14.
- Stage 11–13 “100+ squads” is a deterministic capacity/stress path; G12 still owns uncapped skirmish population.
- Coalition tech is **buy / steal / unseal** only. It never uses normal `Research9` progression.
- Coalition can never obtain counter-nanites through production, market, theft, capture, editor/load, patron or
  difficulty override.
- Ghost Exo authority is
  `docs/superpowers/specs/2026-11-23-ghost-exo-programme-design.md`. G10 implements skirmish/Conductor rows only;
  campaign Hunter/build-up waits for G15.
- Human A Counter-Ghost is a full G10 corps but stays weaker than Coalition exos. It is not the post-G10 CN/Blackglass
  skirmish branch.
- Pre-G10 AI/economy is shipped: call `Adapt9`, `Generals9`, `Dipl9`, `AiCommand`, `Territory9`, `Market`, `Trade9`,
  `Research9` and their public state; do not re-plan or rewrite them.
- Difficulty by intelligence only: no Coalition resource income, starting stock, HP, damage, accuracy or production
  multipliers by difficulty.
- Fictional identity only: no real-world extremist names, insignia or direct analogues.
- Numbers remain **PROVISIONAL** until owner playtesting; interfaces, exclusions and acceptance gates are not
  provisional.
- Determinism: sorted entity/definition iteration, integer ticks, `w.rng` only, plain save/hash state, and lazy state
  creation where a match does not use a G10 system.
- Existing perf gates remain: 2k on-screen p10 ≥ 60 and 10k zoomed-out p10 ≥ 30; measure, do not assume.
- Upgrade-board protocol: read recent rows → `CLAIM` exclusive paths → work/STATUS → test FACT → `HANDOFF` +
  `RELEASE`. ORCH alone commits, packages, updates README/PLAY_ME and pushes.
- This execution does **not** push unless the owner/controller separately authorizes a push.
- Godot console:
  `C:\Users\logan\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe`
- Focused test form:
  `& $G --headless --path game -s res://tests/run_tests.gd -- "--only=test_g10_content"`
- Every task ends in a board HANDOFF and an ORCH-owned focused commit during execution.

---

## Frozen interpretation for owner approval

- **Skirmish stages:** the faction row controls valid stages. `shadow_coalition` exposes 1–13; Human A/B/Machine keep
  the stages currently shipped. Do not flip `playable_now` globally for stages 1–6 or 11–13.
- **LP parity:** keep the canonical Human A-vs-Machine button/config unchanged. Add a separate Coalition defender
  profile under the Last Protocol entry, Stage 10 only, with Coalition base/army/role closure and the same Machine
  threat objective contract.
- **Selected dark/G7.1 depth:** only Blackout, Hollow Ground, Mirror Fortress and Dead Radio ship in G10.
- **Core parity count:** at least 60 Stage 7–10 Coalition gameplay definitions, counted as Coalition-owned units and
  buildings. Production rows, company templates, art aliases and rules do not inflate the count.
- **Owner look gates:** approve a six-subject sample before bulk art, then approve the complete catalog before lock.

## Owner-frozen Ghost Wing expansion

This section is additive to the Ghost Exo spec and is required by `game/docs/G10_SCOPE.md`. Art agents must also read
`game/docs/G10_GHOST_LOOK.md`. These capabilities are package choices with costs, incompatibilities and tells—not a
flat stack of buffs.

- **Batch A:** **3** modular black-budget suits; **4** bounded no-witness comms/camera suppression and false IFF;
  **5** blood-debt recovery/economic loss; **7** hardened, redundant Conductor with EMP → breach → execute takedown;
  **9** door-kick micro-drones; **10** wiretap drones; **13** Silent Rotor quiet-to-gunship flip; **14** Mole
  multipath/alternate exit/collapse; **15** tethered remote Ghost Runner; **17** fighting Guardian Mule; **20**
  soft/hard/collapse breach charges; **21** Machine-focused EMP scalpel; **22** backdoor ammunition/spikes against
  compromised Syndicate-sold hardware; **24** hatch-only Ghost wing/vault bay; **25** adaptive kill-house; **26**
  doctrine-locking briefing crypt; **27** stolen-tech suit reliquary; **28** Recon/Surgical/Atrocity contracts;
  **29** escalating alert heat; **30** evidence-bearing false flag; **32** Counter-Ghost corps plus spider/Reaper
  depth.
- **Batch B:** **37** wall/ceiling/hatch spider drones; **38** rotorless Reaper stealth manta; **40** pad-only
  Reaper magazines (recon / EMP / backdoor / thermite); **41** honeycomb Nest repair rack; **44** telegraphed
  Guardian Mule denial overcharge; **47** Surgical-success contract escalation before Atrocity/False Flag; **49**
  bright Human A flechette/foam/ultrasonic spider-killers.
- **Batch C:** **52** hardened joints; **53** redundant battery with swap shimmer; **56** Judge; **57** Warden;
  **58** Shade; **59** Sergeant-led Pack hierarchy; **60** HVT/officer Execution stance trading intel for heat;
  **63** Mk I→III stage progression; **64** named aces as **3 early → +6 along the way → final campaign unlock**.
  G10 owns skirmish-era gating and content/art hooks; G15 owns campaign chapter mapping and final campaign unlock.

**Required constraints:** Conductor packages are gated by intel, workshop, suits, contract tier, heat and recovery
state; hardpoints/toolkits conflict; blood debt punishes suit abandonment; hardened systems degrade rather than grant
immunity; executions are non-gory and consequential; false flags carry discoverable evidence. Explicitly unpicked
ideas **1, 2, 6, 8, 11, 12, 16, 18, 19, 23, 31, 33–36, 39, 42, 43, 45, 46, 48, 50, 51, 54, 55, 61, 62 and 65**
are not required G10 work and may not enter implementation except through a later owner-approved scope revision.

## Authoritative Stage 7–10 roster manifest (61 core definitions)

The roster task may tune names shown to players, but these IDs and roles are the cross-pillar contract.

**Infantry/cells/mercenaries (14):**
`x_cell_rifle`, `x_cell_at`, `x_cell_sapper`, `x_cell_medic`, `x_ambush_cell`, `x_sleeper_cell`,
`x_backdoor_hacker`, `x_broker`, `x_pmc_rifle`, `x_pmc_assault`, `x_pmc_sniper`, `x_pmc_ew`, `x_officer`,
`x_ghost_infiltrator`.

**Ground vehicles (14):**
`x_technical_mg`, `x_technical_rocket`, `x_technical_aa`, `x_technical_mortar`, `x_technical_recoilless`,
`x_captured_tank`, `x_refit_ifv`, `x_shock_truck`, `x_stealth_apc`, `x_ghost_runner`, `x_exo_mule`,
`x_recovery_truck`, `x_ghost_drone_carrier`, `x_prototype_walker`.

**Air/naval/drones (10):**
`x_stealth_drone`, `x_shock_drone`, `x_recon_drone`, `x_silent_rotor`, `x_stealth_transport`, `x_patron_cas`,
`x_river_ghost`, `x_mini_sub`, `x_smuggler_boat`, `x_patrol_boat`.

**Ghost Regiment (9):**
`x_death_strike`, `x_death_assault`, `x_death_recon`, `x_shadow_pathfinder`, `x_shadow_ew`,
`x_shadow_signal`, `x_shadow_decoy`, `x_anchor_tech`, `x_anchor_medic`.

**Buildings (14):**
`x_safehouse`, `x_tunnel_entrance`, `x_cache`, `x_weld_shop`, `x_black_market`, `x_broker_exchange`,
`x_patron_office`, `x_disguised_workshop`, `x_bunker_hatch`, `x_underground_barracks`,
`x_underground_factory`, `x_ghost_complex`, `x_forward_repair`, `x_vault_core`.

Stage-band additions live in separate files and do not weaken the 61-core-definition minimum.

## File map

**Scope, content and registration**
- Modify: `game/docs/G10_SCOPE.md` at Task 0 (review draft → frozen) and final lock (frozen → closed).
- Authority: `game/docs/G10_GHOST_LOOK.md` — owner-frozen Ghost Wing visual language; art agents do not rewrite it.
- Modify: `game/sim/content.gd` — add sorted `res://content/g10` fragment directory.
- Modify: `game/content/factions.json` — add `shadow_coalition` identity, role map, start units and stage roles.
- Modify: `game/content/stages.json` only for metadata; never set deferred stages globally playable.
- Create: `game/content/g10/defs_g10_core.json` — 61 core definitions and production closure.
- Create: `game/content/g10/defs_g10_raiders.json` — Stage 1–6 forms.
- Create: `game/content/g10/defs_g10_late.json` — Stage 11–13 forms.
- Create: `game/content/g10/rules_g10_coalition.json` — doctrine, mechanics and difficulty-neutral rules.
- Create: `game/tests/test_g10_content.gd`, `game/tests/test_g10_stage.gd`.

**Faction mechanics, tech and buildings**
- Create: `game/sim/systems/coalition10.gd` — faction state/query facade and doctrine telemetry.
- Create: `game/sim/systems/tunnels10.gd`, `civilian_cells10.gd`, `ieds10.gd`, `patron10.gd`,
  `weld_shop10.gd`, `coalition_tech10.gd`, `coalition_buildings10.gd`.
- Modify: `game/sim/world.gd` — preload/tick/command registration only.
- Extend public seams: `capture71.gd`, `market.gd`, `territory9.gd`, `construction.gd`, `production.gd`.
- Create: `game/content/g10/rules_g10_mechanics.json`, `rules_g10_tech.json`, `rules_g10_buildings.json`.
- Create: `game/tests/test_g10_mechanics.gd`, `test_g10_tech.gd`, `test_g10_buildings.gd`.

**Ghost and Counter-Ghost**
- Create: `game/sim/systems/ghost_exo10.gd`, `ghost_conductor10.gd`, `ghost_mission10.gd`,
  `counter_ghost10.gd`.
- Extend: `game/sim/systems/exo.gd`, `loadouts.gd`, `wounds.gd`, `transport.gd`, `fog.gd`, `supply.gd`.
- Create: `game/content/g10/defs_g10_counterghost.json`, `rules_g10_ghost.json`,
  `rules_g10_counterghost.json`.
- Create: `game/tests/test_g10_ghost.gd`, `test_g10_counterghost.gd`.

**AI, modes and presentation**
- Create: `game/sim/ai/coalition_ai10.gd`, `game/sim/ai/coalition_doctrine10.gd`.
- Extend: `game/sim/ai/ai_controller.gd`, `general_ai.gd`, `game/sim/systems/ai_command.gd`.
- Modify: `game/presentation/hud/g3b_data.gd`, `game/presentation/menu/skirmish_setup.gd`.
- Modify: `game/sim/systems/last_protocol.gd`, `lp_setup.gd`, `game/presentation/ui7/lp_menu.gd`.
- Create: `game/content/g10/lp_profile_coalition.json`.
- Create: `game/presentation/ui10/coalition_command.gd`, `ghost_command.gd`,
  `game/presentation/view/ghost_exo_layer.gd`.
- Create: `game/tests/test_g10_ai.gd`, `test_g10_modes.gd`, `test_g10_dark.gd`.

**Art and integration**
- Create: `game/tools/art/g10_coalition_samples.gd`, `g10_coalition.gd`,
  `game/tools/g10_roster_audit.gd`, `g10_stage_soak.gd`, `g10_doctrine_soak.gd`,
  `g10_100_squad_soak.gd`, `g10_donewhen_smoke.ps1`.
- Extend: `game/presentation/art/art_catalog.gd`, `game/presentation/view/entity_layer.gd`,
  `game/sim/render_snap.gd`.
- Final modify: root `README.md`, current `game/docs/PLAY_ME_*`, `game/docs/ROADMAP.md`,
  `game/.plan/upgrade_board/README.md`, append-only `board.jsonl`.

## Agent roster and path ownership

- **ORCH:** approval record, claims, shared seams, integration, commits, docs/package; never delegates `world.gd`
  integration or final lock.
- **FOUND10:** content loader, faction registry, Coalition-only stage API and audit tests.
- **IDENT10:** `coalition10.gd`, doctrine state/telemetry and intent-first UI contracts.
- **ROSTER10:** all G10 definition fragments; subclaims `RAID10`, `CORE10`, `LATE10` by file after manifest freeze.
- **ART10:** sample gate, complete four-facing catalog, icons and hidden/revealed states.
- **MECH10:** tunnels, civilians, IEDs, patron and weld/capture mechanics; one owner coordinates public seams.
- **TECH10:** buy/steal/unseal and all denial gates.
- **BLD10:** Coalition structures, hidden/revealed/damage behavior and build closure.
- **GHOST10:** Ghost anatomy, mission lifecycle, Conductor and Ghost vehicles.
- **ARMORY10:** Exo Armory building, unlock/outfit UX, bay caps (`G10_EXO_ARMORY.md`).
- **CG10:** Human A Counter-Ghost definitions and counterplay only.
- **DOG10:** Human A `g71_robot_dog` complete art redesign (`G10_HUMAN_A_DOG_LOOK.md`).
- **AI10:** Coalition doctrine adapter over shipped Pre-G10 AI.
- **MODE10:** skirmish stage filtering and Coalition LP profile.
- **DARK10:** four selected extras, telemetry/radio/AAR; no other dark option.
- **VERIFY10:** independent smoke/hash/soak/perf verification; no feature edits without ORCH NEED/CLAIM.

Maximum six live agents. Serialize shared seams: `world.gd` (ORCH), `factions.json` (FOUND10),
`capture71.gd` (MECH10), `exo.gd` (GHOST10, then CG10), and LP files (MODE10).

---

## Wave E0 — approval and board freeze

### Task 0: Freeze G10 scope and Stage E board

**Files:**
- Modify: `game/docs/G10_SCOPE.md`
- Modify: `game/.plan/upgrade_board/README.md`
- Append: `game/.plan/upgrade_board/board.jsonl`

**Interfaces:**
- Consumes: owner reply `APPROVE` plus execution choice.
- Produces: board FACT `g10.scope.frozen`, Stage E roster and non-overlapping CLAIM map.

- [ ] **Step 1:** Confirm the owner approved this exact plan path and record the approval text in a FACT; if approval
  changes a scope item, revise the scope/plan and request approval again instead of silently interpreting it.
- [ ] **Step 2:** Change G10_SCOPE status from “OPEN — OWNER REVIEW” to “FROZEN — implementation open”; do not mark
  Done-when complete.
- [ ] **Step 3:** Replace the upgrade-board active roster with Stage E IDs while preserving historical rosters.
- [ ] **Step 4:** Append `g10.claim.map` with the ownership listed above and explicit serialized seams.
- [ ] **Step 5:** Validate docs links:
  `rg -n "G10_SCOPE|g10-shadow-coalition|ghost-exo-programme-design" game/docs docs/superpowers`.
  Expected: every referenced authority resolves and G10_SCOPE points to this full plan.
- [ ] **Step 6:** ORCH commit: `docs: freeze G10 Shadow Coalition scope and board`.

**Acceptance:** no feature CLAIM begins before `g10.scope.frozen`; board roster and path owners are unambiguous.

---

## Wave E1 — shared foundation

### Task 1: Register G10 content and the fourth faction

**Files:**
- Modify: `game/sim/content.gd`
- Modify: `game/content/factions.json`
- Create: `game/content/g10/defs_g10_core.json`
- Create: `game/tests/test_g10_content.gd`

**Interfaces:**
- Produces: faction ID `shadow_coalition`; `Content.faction("shadow_coalition")`; all generic roles return non-empty
  valid defs; `Coalition10.CORE_IDS` audits exactly the 61 manifest IDs.

- [ ] **Step 1:** Write failing tests `test_shadow_coalition_registered`,
  `test_shadow_roles_and_start_units_resolve`, `test_g10_fragments_load_after_g71`, and
  `test_core_manifest_has_at_least_60_gameplay_defs`.
- [ ] **Step 2:** Run focused suite; expected FAIL because `shadow_coalition` and `res://content/g10` do not exist.
- [ ] **Step 3:** Add `res://content/g10` after `g71` in `Content.FRAGMENT_DIRS`; preserve sorted no-override fragment
  semantics.
- [ ] **Step 4:** Add faction metadata and role IDs: HQ=`x_safehouse`, power=`x_cache`, depot=`x_black_market`,
  barracks=`x_underground_barracks`, factory=`x_underground_factory`, refinery=`x_weld_shop`,
  defense=`x_tunnel_entrance`, builder/gatherer=`x_cell_sapper`, infantry=`x_cell_rifle`,
  antitank=`x_cell_at`, recon=`x_ambush_cell`, light=`x_technical_mg`, heavy=`x_captured_tank`,
  artillery=`x_technical_mortar`, officer=`x_officer`, supply=`x_recovery_truck`, air=`x_silent_rotor`.
- [ ] **Step 5:** Seed `defs_g10_core.json` with valid minimal rows for all 61 manifest IDs and complete producer links;
  later tasks deepen values without renaming IDs.
- [ ] **Step 6:** Run `test_g10_content`; expected `RESULT ... 4 passed, 0 failed` and no `Content:` errors.
- [ ] **Step 7:** HANDOFF with manifest count by units/buildings and role-closure evidence.

**Acceptance:** a headless world can construct a Coalition side without missing faction, role, start or content data.

### Task 2: Coalition-only Stage 1–13 selection

**Files:**
- Modify: `game/presentation/hud/g3b_data.gd`
- Modify: `game/presentation/menu/skirmish_setup.gd`
- Create: `game/content/g10/defs_g10_raiders.json`
- Create: `game/content/g10/defs_g10_late.json`
- Create: `game/tests/test_g10_stage.gd`

**Interfaces:**
- Produces:
  `G3bData.playable_stages_for(faction_id: String) -> Array[int]`;
  `Coalition10.validate_stage_opener(stage: int) -> Dictionary`.

- [ ] **Step 1:** Add failing tests proving Coalition returns `[1..13]`, Human A/B/Machine retain `[7,8,9,10]`,
  changing a slot faction refreshes only that row's stage options, and config round-trip preserves Coalition Stage 3/12.
- [ ] **Step 2:** Run suite; expected FAIL on missing `playable_stages_for`.
- [ ] **Step 3:** Add a faction-specific stage availability map to Coalition rules; do not change deferred stages'
  global `playable_now`.
- [ ] **Step 4:** Refresh each stage OptionButton when its faction changes, preserving the selected stage when still
  valid and choosing Stage 8 otherwise.
- [ ] **Step 5:** Add legal minimal openers for each stage to raider/late fragments; every opener must include a base,
  builder/gatherer and combat unit.
- [ ] **Step 6:** Run suite; expected all PASS and tests explicitly assert other factions cannot select Stage 1 or 13.

**Acceptance:** G10 unlocks thirteen stages for Coalition without accidentally delivering G14 for other factions.

### Task 3: Identity/doctrine facade and telemetry

**Files:**
- Create: `game/sim/systems/coalition10.gd`
- Create: `game/content/g10/rules_g10_coalition.json`
- Create: `game/presentation/ui10/coalition_command.gd`
- Modify: `game/sim/render_snap.gd`
- Extend: `game/tests/test_g10_content.gd`

**Interfaces:**
```gdscript
static func active(w: SimWorld, fid: int) -> bool
static func layer(w: SimWorld, fid: int) -> String # cells|mercs|elite
static func set_intent(w: SimWorld, fid: int, intent: String) -> void
static func board(w: SimWorld, fid: int) -> Dictionary
```

- [ ] **Step 1:** Tests assert default intent `harry`, doctrine transitions only from evidence/resources, and board
  includes `cells`, `contracts`, `patron_favour`, `intel_grade`, `ghost_ready`, `tech_sources`.
- [ ] **Step 2:** Implement lazy `sys_state.coalition10` with sorted faction keys and no tick work for matches without
  Coalition.
- [ ] **Step 3:** Build EaW-simple command surface: build bar + intent cards; Advanced drawer is optional and closed by
  default.
- [ ] **Step 4:** Run content suite and a non-Coalition two-run hash; expected Coalition tests PASS and legacy hash
  unchanged where G10 state is never created.

**Acceptance:** all pillars consume one faction facade and one readable board schema.

---

## Wave E2A — roster, art and buildings

### Task 4: Stage 7–10 core roster and production closure

**Files:**
- Modify: `game/content/g10/defs_g10_core.json`
- Create: `game/tools/g10_roster_audit.gd`
- Extend: `game/tests/test_g10_content.gd`

**Interfaces:**
- Consumes: exact 61-ID manifest in this plan.
- Produces: `g10_roster_audit` JSON summary `{units, buildings, production, orphan_defs, orphan_art, role_gaps}`.

- [ ] **Step 1:** Add failing tests for unique IDs, faction ownership, stage_min/max, producer closure, weapon/loadout
  references, movement classes, population/cost fields and all role mappings at Stages 7–10.
- [ ] **Step 2:** Fill core definitions by category. Stage progression: Stage 7 cells/technicals/tunnels; Stage 8
  contracts/naval and Mk I; Stage 9 network/EW, Mk II and advanced patron; Stage 10 prototypes/Death apex.
- [ ] **Step 3:** Define company templates in Coalition rules for Cell Screen, Technical Troop, Mercenary Company,
  Ghost Regiment and Anchor Train; templates do not count toward 61.
- [ ] **Step 4:** Run `test_g10_content`; expected zero orphan or cross-faction production rows.
- [ ] **Step 5:** Run audit:
  `& $G --headless --path game -s res://tools/g10_roster_audit.gd`.
  Expected: `CORE_GAMEPLAY_DEFS >= 60`, `ORPHANS 0`, `ROLE_GAPS 0`.

**Acceptance:** the Stage 7–10 Coalition can play build/economy/combat end-to-end with ≥60 real gameplay defs.

### Task 5: Stage 1–6 raider forms

**Files:**
- Modify: `game/content/g10/defs_g10_raiders.json`
- Modify: `game/content/g10/rules_g10_coalition.json`
- Extend: `game/tests/test_g10_stage.gd`

**Interfaces:**
- Produces six opener profiles:
  `scattered`, `camp`, `frontier_cell`, `reclamation_gang`, `warlord_confederacy`, `industrial_syndicate`.

- [ ] **Step 1:** Tests assert each stage has valid start/build/production closure and cannot produce a def above its
  stage.
- [ ] **Step 2:** Implement stage identities: 1 scavenger band; 2 hidden camp/cache; 3 ambush/tunnel; 4 captured
  workshop; 5 weld-shop warlord confederacy; 6 industrial cell network + Mk I prototype access.
- [ ] **Step 3:** Gate patron strength and exos by stage: local hires at 3–5, limited patron at 6, no Mk II/III.
- [ ] **Step 4:** Run suite; expected all six openers survive 1,200 deterministic ticks without invalid production.

**Acceptance:** early Coalition is a low-tech growth faction, not a reskinned Stage 7 army.

### Task 6: Stage 11–13 late syndicate forms

**Files:**
- Modify: `game/content/g10/defs_g10_late.json`
- Modify: `game/content/g10/rules_g10_coalition.json`
- Extend: `game/tests/test_g10_stage.gd`

**Interfaces:**
- Produces stage profiles `synthetic_syndicate`, `distributed_syndicate`, `apex_syndicate`.

- [ ] **Step 1:** Tests assert Mk III starts at 11, distributed remote caches at 12, apex vault/patron assets at 13,
  and no late def leaks into Stage 10.
- [ ] **Step 2:** Add Mk III hybrid variants through modules on existing Death IDs, plus late distributed-node and apex
  production/building additions; avoid duplicate parallel units where modules suffice.
- [ ] **Step 3:** Add stress-only `g10_100_squad` config with enough stock/cap for 100+ Death squads; keep normal
  skirmish caps unchanged.
- [ ] **Step 4:** Run stage suite; expected PASS and explicit cap assertion for ordinary skirmish.

**Acceptance:** late forms express Mk III/distributed/apex play and expose a bounded 100+ stress path.

### Task 7: Coalition buildings and hidden-state contract

**Files:**
- Create: `game/sim/systems/coalition_buildings10.gd`
- Create: `game/content/g10/rules_g10_buildings.json`
- Modify: `game/sim/world.gd` via ORCH
- Extend: `game/sim/systems/construction.gd`, `game/sim/systems/fog.gd`
- Create: `game/tests/test_g10_buildings.gd`

**Interfaces:**
```gdscript
static func reveal(w: SimWorld, building_id: int, observer_fid: int, cause: String) -> void
static func underground_alive(w: SimWorld, building_id: int) -> bool
static func production_reason(w: SimWorld, building_id: int) -> String
```

- [ ] **Step 1:** Failing tests cover 14 buildings, disguised-until-scouted state, surface hatch destruction versus
  underground health, power/producer closure, vault uniqueness and no UNDERSTRIKE floor state.
- [ ] **Step 2:** Implement hidden/revealed render flags and explicit detector/recent-action reveals.
- [ ] **Step 3:** Implement hatch damage as access/production penalty; destroying the underground entity still requires
  direct damage/capture, not an imported UNDERSTRIKE floor simulation.
- [ ] **Step 4:** Run building suite; expected all PASS and save/load preserves revealed observers and underground HP.
- [ ] **Step 5:** Deepen the Ghost complex with approved **24–27** as bounded modules: hatch-only Wing/vault suit bay;
  adaptive kill-house keyed to the last failed-op record; briefing crypt with one committed match doctrine; suit
  reliquary that consumes recovered tagged technology for an allow-listed non-stacking exo upgrade.
- [ ] **Step 6:** Add attack/readability tests for hatch/vent discovery, changed kill-house layout, committed doctrine
  lock, displayed/consumed reliquary parts and the neon-under-tarp black-market versus dark Ghost-site contrast.
- [ ] **Step 7:** Wire **Exo Armory** building shell into Ghost campus (full sim in Task 7B / ARMORY10): stage band
  locker→full→black, hatch-only surface, bay occupancy flags. Authority: `game/docs/G10_EXO_ARMORY.md`.

**Acceptance:** Coalition base identity is hidden/underground without stealing Human A's bunker system. Ghost modules
have distinct strategic jobs and counterplay; no module creates an UNDERSTRIKE floor, hidden free research or an
unbounded permanent upgrade path. Armory appears as a campus module with correct stage bay caps.

### Task 7B: Exo Armory (ARMORY10)

**Files:**
- Create: `game/sim/systems/exo_armory10.gd`
- Create: `game/content/g10/defs_g10_exo_armory.json`, `game/content/g10/rules_g10_exo_armory.json`
- Create: `game/tests/test_g10_exo_armory.gd`
- Authority: `game/docs/G10_EXO_ARMORY.md`, look `G10_GHOST_LOOK.md`

**Interfaces:**
```gdscript
static func bay_count(w, building_id) -> int
static func outfit_preset(w, bay, squad_ids, preset_id) -> String  # err or ""
static func field_kit(w, carrier_id, exo_id, kit_id) -> String
static func on_armory_destroyed(w, building_id) -> void  # harsh in-bay loss
```

- [ ] **Step 1:** Failing tests for Coalition-only build, stage bay caps (1 / 2–3 / ≤6), 4-op per bay, field-kit
  limits, harsh destroy, unlock gates (preset → mix → per-op), CN denial.
- [ ] **Step 2:** Implement bay upgrade path and parallel squad outfit queues.
- [ ] **Step 3:** Implement unlock economy (starters cheap; elite = contracts + steal/unseal/reliquary).
- [ ] **Step 4:** Field kits from mule/APC only; scale by mission-importance score; never full refit.
- [ ] **Step 5:** Destroyed Armory captures/destroys in-bay suits; field kits persist; outfit commands fail.
- [ ] **Step 6:** Enemy raid yields intel/parts events only—no outfit rights.
- [ ] **Step 7:** `--only=test_g10_exo_armory` PASS; art bay lights/racks on look sheet.

**Acceptance:** All `G10_EXO_ARMORY.md` Acceptance rows green; no Human A/Machine outfit path.

### Task 7C: Human A robot dog redesign (DOG10)

**Files:**
- Create/extend: `game/tools/art/g71_dog_human.gd` (or fleet art rewrite)
- Modify: `game/assets/art/g71_fleet/` dog sheets + manifest + catalog override
- Authority: `game/docs/G10_HUMAN_A_DOG_LOOK.md`
- Tests: art harness / look checkpoint; `test_fleet71` still green

- [ ] **Step 1:** Owner look sample strip: new dog beside `g71_m_ember_hound` — must not read as Machine.
- [ ] **Step 2:** Generate smaller/sleeker 4-facing loco + mask + icon + wreck (slate/olive, amber sensors, digitigrade
  paws, collar/tab team colour; **no cyan spine**).
- [ ] **Step 3:** Replace catalog entries for `g71_robot_dog`; keep sim def id and fleet71 recover/wipe contracts.
- [ ] **Step 4:** Tune presentation weight if needed so gallop reads lighter; run fleet71 + anim smoke PASS.

**Acceptance:** Packaged look checkpoint includes new dog; owner can tell Human A hound from Machine hound at a glance.

### Task 8: Six-subject look checkpoint, then complete art

**Files:**
- Create: `game/tools/art/g10_coalition_samples.gd`
- Create: `game/tools/art/g10_coalition.gd`
- Modify: `game/presentation/art/art_catalog.gd`
- Modify: `game/presentation/view/entity_layer.gd`
- Extend: `game/tests/test_g10_content.gd`

**Interfaces:**
- Sample IDs: `x_cell_rifle`, `x_technical_rocket`, `x_safehouse`, `x_death_strike`, `x_patron_cas`,
  `x_prototype_walker`.
- Produces art group `g10_coalition` with four facings and hidden/revealed variants where applicable.

- [ ] **Step 1:** Generate only the six samples and package/contact-sheet them at the existing G71 look-checkpoint
  path.
- [ ] **Step 2:** Board NEED `g10.look.samples`; pause ART10 until owner records approve/revise.
- [ ] **Step 3:** After approval, generate all 61 core IDs plus early/late additions, wrecks and icons.
- [ ] **Step 4:** Add tests for catalog coverage, four facings, non-empty dimensions, team-colour masks and distinct
  hidden/revealed assets.
- [ ] **Step 5:** Run content/art audit; expected `orphan_art=0`. Record final owner look approval before Task 20.
- [ ] **Step 6:** Generate the owner-frozen Ghost set: Base/Judge/Warden/Shade/Sergeant, Mk I/II/III bands and nine
  progressive ace identities; preserve the shared no-face/oversized-shoulder grammar while making role, Mk and ace
  readable without UI labels.
- [ ] **Step 7:** Generate state sheets for oil-slick camo at rest/walk/sprint/fire/hit, redundant-battery swap,
  hardened joints, execution stance and Warden shield deployment. Camo is never chrome.
- [ ] **Step 8:** Generate vehicle/drone/building state sheets: Silent Rotor → ugly gunship; Mole coffin; Runner wedge;
  Guardian Mule normal/guardian/overcharge; Stealth APC civilian lie; spider crawl/hatch/limpet; rotorless Reaper and
  four magazine modes; Nest occupancy/damage; hatch-only wing; adaptive kill-house; briefing crypt; reliquary.
- [ ] **Step 9:** Contact sheets place too-clean Ghosts beside ragged cells and bright Counter-Ghost foam bots. Audit
  enforces debt-stripe/armband-only team colour and rejects full-body team paint.

**Acceptance:** readable silhouettes by stage/role and no placeholder/missing Coalition art in the final package.
The complete catalog independently identifies Judge/Warden/Shade/Sergeant, all Mk bands, ace debt numerals, each
transform/magazine/camo state and every fair-counter tell under `G10_GHOST_LOOK.md`.

---

## Wave E2B — asymmetric mechanics and technology

### Task 9: Tunnels, caches and Hollow Ground

**Files:**
- Create: `game/sim/systems/tunnels10.gd`
- Create: `game/content/g10/rules_g10_mechanics.json`
- Modify: `game/sim/world.gd` via ORCH
- Create: `game/tests/test_g10_mechanics.gd`

**Interfaces:**
```gdscript
static func link(w: SimWorld, entrance_a: int, entrance_b: int) -> bool
static func transit(w: SimWorld, fid: int, unit_ids: Array, entrance_id: int, exit_id: int) -> String
static func collapse(w: SimWorld, entrance_id: int, cause: String) -> void
static func cache_resupply(w: SimWorld, cache_id: int, unit_ids: Array) -> Dictionary
```

- [ ] **Step 1:** Tests cover hidden link creation, deterministic travel time/capacity, blocked/collapsed exit, cache
  resupply, dead-zone interaction and visible Hollow Ground tell before collapse.
- [ ] **Step 2:** Implement transit as saved mission state, not teleport; units are unavailable during transit and
  emerge in sorted order at free cells.
- [ ] **Step 3:** Collapse from terrain/charges damages or delays transiting units using fixed rules and reveals the
  network endpoint.
- [ ] **Step 4:** Run mechanics suite twice with same seed; expected matching state hash.

**Acceptance:** tunnels are powerful logistics with scout/demolition/dead-zone counters and readable collapse risk.

### Task 10: Civilian disguise, sleeper cells, IEDs and shock raids

**Files:**
- Create: `game/sim/systems/civilian_cells10.gd`
- Create: `game/sim/systems/ieds10.gd`
- Extend: `game/sim/systems/territory9.gd`
- Modify: `game/sim/world.gd` via ORCH
- Extend: `game/tests/test_g10_mechanics.gd`

**Interfaces:**
```gdscript
static func disguise(w: SimWorld, unit_id: int) -> bool
static func activate(w: SimWorld, unit_ids: Array, intent: String) -> void
static func plant(w: SimWorld, fid: int, kind: String, cell: Vector2i, trigger: String) -> int
static func disarm(w: SimWorld, fid: int, trap_id: int) -> bool
```

- [ ] **Step 1:** Tests prove disguise breaks on sprint/fire/hostile action or detector contact; civilian harm lowers
  support; sleepers cannot capture while disguised.
- [ ] **Step 2:** Tests cover roadside, building and drone-borne charge triggers, friendly/civilian consequences,
  engineer/recon disarm and save/load.
- [ ] **Step 3:** Implement shock-raid intent as a combined command using existing movement/damage systems; do not add
  gore or campaign conduct systems.
- [ ] **Step 4:** Run mechanics + econ9 suites; expected both PASS and Territory9 behavior unchanged for other factions.

**Acceptance:** disguise and traps have real play paths, costs and counters, not harness-only markers.

### Task 11: Patron contracts, favour and mercenary loyalty

**Files:**
- Create: `game/sim/systems/patron10.gd`
- Extend: `game/sim/systems/market.gd`
- Extend: `game/content/g10/rules_g10_mechanics.json`
- Extend: `game/tests/test_g10_mechanics.gd`

**Interfaces:**
```gdscript
static func offer(w: SimWorld, fid: int, contract_id: String) -> Dictionary
static func accept(w: SimWorld, fid: int, contract_id: String) -> String
static func loyalty(w: SimWorld, unit_id: int) -> int
static func settle_pay(w: SimWorld, fid: int) -> void
```

- [ ] **Step 1:** Tests cover favour from territory/loot, timed unit/support contracts, late pay lowering loyalty,
  deterministic desert/switch outcome, and fanatic home-ground immunity.
- [ ] **Step 2:** Use shipped black-market ledger/currency APIs; add Coalition contract catalog without changing
  ordinary market pricing.
- [ ] **Step 3:** Patron air/drone/adviser support must expire or renew on contract timer; no permanent free call-in.
- [ ] **Step 4:** Run mechanics and `test_econ9`; expected all PASS.
- [ ] **Step 5:** Implement approved contract chain **28/47**: Recon → Surgical → Atrocity; Atrocity and False Flag
  remain unavailable until the configured number of successful Surgical contracts. Failures, late pay and exposure
  can regress access.
- [ ] **Step 6:** Implement approved heat/false-flag depth **29/30**: Ghost overuse, Execution and Atrocity increase
  alert readiness (dogs/AA/thermal coverage, never free HP/damage); false flags create attributable evidence,
  exposure risk and a deterministic diplomacy/grudge result.

**Acceptance:** money/favour buys flexibility, and failure to pay is a strategic liability. Contract escalation is
earned, high heat changes defender preparedness without cheats, and every false flag can be uncovered and attributed.

### Task 12: Capture, refit and weld-shop packages

**Files:**
- Create: `game/sim/systems/weld_shop10.gd`
- Extend: `game/sim/systems/capture71.gd`
- Extend: `game/content/g10/rules_g10_mechanics.json`
- Extend: `game/tests/test_g10_mechanics.gd`

**Interfaces:**
```gdscript
static func claim_vehicle(w: SimWorld, fid: int, vehicle_id: int) -> String
static func packages_for(w: SimWorld, vehicle_id: int) -> Array
static func install(w: SimWorld, shop_id: int, vehicle_id: int, package_id: String) -> String
```

- [ ] **Step 1:** Tests cover empty crew/captured vehicle claim, wreck salvage race, valid packages `mg`, `rocket`,
  `aa`, `recoilless`, `slat`, `mortar`, and mutually exclusive mount slots.
- [ ] **Step 2:** Implement packages as deterministic entity modifiers with cost/time and art alias, preserving the
  original base def for save compatibility.
- [ ] **Step 3:** Deny Coalition use of captured counter-nanite and UNDERSTRIKE builders; convert forbidden captures to
  salvage/intel only.
- [ ] **Step 4:** Run mechanics, count9 capture and vehicle-crew suites; expected all PASS.

**Acceptance:** captured hardware becomes configurable Coalition kit without bypassing faction exclusions.

### Task 13: Buy / steal / unseal technology

**Files:**
- Create: `game/sim/systems/coalition_tech10.gd`
- Create: `game/content/g10/rules_g10_tech.json`
- Extend: `game/sim/systems/production.gd`, `market.gd`
- Modify: `game/sim/world.gd` via ORCH
- Create: `game/tests/test_g10_tech.gd`

**Interfaces:**
```gdscript
static func acquire(w: SimWorld, fid: int, source: String, tech_id: String, evidence: Dictionary) -> String
static func unlocked(w: SimWorld, fid: int, tech_id: String) -> bool
static func source_log(w: SimWorld, fid: int) -> Array
static func forbidden_reason(def_id: String) -> String
```

- [ ] **Step 1:** Tests prove Buy spends money/favour, Steal requires captured gear/raid evidence, Unseal requires a
  controlled vault core and alarm/heat cost.
- [ ] **Step 2:** Tests prove Coalition `research` command is rejected with “Coalition technology is bought, stolen or
  unsealed,” while Human/Machine Research9 remains unchanged.
- [ ] **Step 3:** Add a deny matrix for all defs tagged `counter_nanite`, `understrike_builder`, `mb_borer` and
  `human_a_only`; exercise build, queue, market, capture, editor/load and difficulty paths.
- [ ] **Step 4:** Implement source log and expose it in Coalition Command; no hidden unlock.
- [ ] **Step 5:** Run tech, econ9, research71 and production/faction suites; expected all PASS.

**Acceptance:** every Coalition unlock has one of three auditable sources and forbidden tech cannot leak.

---

## Wave E2C — Ghost Exo and Counter-Ghost

### Task 14: Ghost suit anatomy, camo, wounds and echelons

**Files:**
- Create: `game/sim/systems/ghost_exo10.gd`
- Create: `game/content/g10/rules_g10_ghost.json`
- Extend: `game/sim/systems/exo.gd`, `loadouts.gd`, `wounds.gd`, `fog.gd`, `supply.gd`
- Create: `game/tests/test_g10_ghost.gd`

**Interfaces:**
```gdscript
static func squad_state(w: SimWorld, squad_id: int) -> Dictionary
static func visibility(w: SimWorld, operator_id: int, observer_fid: int) -> float
static func assign_package(w: SimWorld, squad_id: int, package: Dictionary) -> String
static func hot_wash(w: SimWorld, squad_id: int) -> Dictionary
```

- [ ] **Step 1:** Tests cover 4-op, 6-op and solo/pair formations; Strike/Assault/Recon armour; Death/Shadow/Anchor
  attachment rules; role cards and certifications.
- [ ] **Step 2:** Tests cover camo still/walk/sprint/fire/hit, battery drain/recharge, thermal/sensor/dog/drone/rain/
  smoke/nanite-sense counters.
- [ ] **Step 3:** Implement operator attributes/skills/mastery as AI-read state; default UI exposes Fresh/Worn/Grounded
  and Legend name only.
- [ ] **Step 4:** Implement dual wounds and kill-switch timing; downed suits support rescue, enemy capture and recovery
  races.
- [ ] **Step 5:** Implement cohesion behavior modifiers and readable movement/AAR text, with no mandatory meter.
- [ ] **Step 6:** Run ghost suite twice; expected PASS and matching hashes.
- [ ] **Step 7:** Add approved chassis state: modular black-budget hardpoints **3** with sensor/breach/net/EMP conflicts;
  blood debt **5** that raises replacement cost/unseal delay after an unrecovered loss; hardened joints **52** that
  reduce—but never cancel—foam/net/limb disable; redundant battery **53** whose cell swap produces a detection
  shimmer.
- [ ] **Step 8:** Add approved role forms: Judge **56** (backdoor rounds/spikes and turret seizure, fragile), Warden
  **57** (temporary micro-bunker/kill corridor), Shade **58** (Reaper designation and remote Mole doors, no heavy
  weapon), and Sergeant/Pack **59** (one leader, three juniors, inherited camo discipline and graceful leader-loss
  degradation).
- [ ] **Step 9:** Add Execution stance **60** as a secured-down-HVT/officer action: interruptible, non-gory, yields
  bounded intel and raises heat. It cannot target ordinary casualties or bypass capture/ROE consequences.
- [ ] **Step 10:** Gate Mk progression **63** by faction stage: Mk I scavenged/riveted at 6–8, Mk II integrated at
  9–10, Mk III dual-hardpoint/Conductor mesh at 11–13. Add nine ace records **64** in three availability cohorts
  (three early, six progressive, final campaign-hook cohort) without per-unit XP bloat; G15 supplies chapter mapping.

**Acceptance:** Packages A–D/G baseline work in sim and remain intent-thin to the player. Tests prove every approved
chassis/role has a cost, incompatibility or counter; loss/leader/battery states survive save/load; Mk/ace gates cannot
leak into earlier stages; hardened joints never make Counter-Ghost tools irrelevant.

### Task 15: Conductor, intel gate and 11-stage mission lifecycle

**Files:**
- Create: `game/sim/systems/ghost_conductor10.gd`
- Create: `game/sim/systems/ghost_mission10.gd`
- Create: `game/presentation/ui10/ghost_command.gd`
- Modify: `game/sim/world.gd` via ORCH
- Extend: `game/tests/test_g10_ghost.gd`

**Interfaces:**
```gdscript
static func submit_card(w: SimWorld, fid: int, card: Dictionary) -> Dictionary
static func plan_package(w: SimWorld, mission_id: int) -> Dictionary
static func tick(w: SimWorld) -> void
static func mission(w: SimWorld, mission_id: int) -> Dictionary
```

- [ ] **Step 1:** Tests cover Need → Rumour/Pattern/Fix/Keyhole gate → workshop/suits/cohesion → template/package →
  lifecycle → echo.
- [ ] **Step 2:** Implement exact phases `tasking`, `intel_gate`, `package`, `rehearsal`, `insertion`, `approach`,
  `action`, `complication`, `exfil`, `hot_wash`, `echo`.
- [ ] **Step 3:** Freeze G10 templates: `QuietDecap`, `SensorBlind`, `WorkshopStrike`, `FeintStorm`; omit campaign-only
  `HeirLive` and `HunterPersonal`.
- [ ] **Step 4:** Enforce Pattern minimum for Death insert, workshop/tech bottleneck, risk budget, max suit loss and
  default break-contact behavior.
- [ ] **Step 5:** Build Ghost Command flow: mission card + target + ROE + Execute; Advanced exposes stance, abort
  threshold, Legend pin and learned-habits panel.
- [ ] **Step 6:** Run one end-to-end QuietDecap test through echo and save/load at every phase.
- [ ] **Step 7:** Harden the Conductor **7** as a distributed mission asset: redundant mesh and armoured mast require
  detected target → EMP disruption → breach → execute. Loss degrades package coordination and forces local squad
  doctrine; it never turns veteran Ghosts into inert “dumb solos.”
- [ ] **Step 8:** Extend package selection across approved choices **3, 4, 5, 20–22, 28–30, 47, 52–60, 63–64**.
  Selection must explain intel grade, hardpoint/toolkit conflicts, contract tier, heat, workshop capacity, recovery
  debt and route; impossible combinations return a reason instead of silently stacking.
- [ ] **Step 9:** Implement no-witness **4** as bounded radio/camera suppression with a temporary false-IFF window,
  explicit anomaly/after-action evidence and no player-command spoofing. False Flag **30** is a strategic attribution
  layer over that evidence, not magical diplomacy.
- [ ] **Step 10:** Add doctrine/building gates **24–27**: hatch-only wing/vault bay, adaptive kill-house learning from
  the last recorded failure, briefing-crypt match doctrine commitment and reliquary conversion of recovered tech into
  allow-listed, non-stacking suit upgrades.

**Acceptance:** Packages E–G/J skirmish slice executes seamlessly under AI or Coalition intent cards. A package audit
shows why each approved component was chosen/rejected; staged Conductor takedown is fair and consequential; suppression
and false flags leave counter-evidence; building-derived upgrades cannot bypass buy/steal/unseal or exclusion tags.

### Task 16: Ghost insertion, support and recovery vehicles

**Files:**
- Modify: `game/content/g10/defs_g10_core.json`, `defs_g10_late.json`
- Extend: `game/sim/systems/ghost_mission10.gd`, `transport.gd`
- Extend: `game/tests/test_g10_ghost.gd`

**Interfaces:**
- Vehicles: Silent Rotor, Ghost Runner, Mole, Stealth APC, Drop Pod, River Ghost, Exo Mule, Stealth Transport,
  Mini-sub, Ghost Drone Carrier, Exo Recovery Truck; Package B additions Cache Beetle, False Convoy, Cryo Litter,
  Relay Mast Trailer, Wet Gate are support modules/mission assets, not extra core-count inflation.

- [ ] **Step 1:** Tests map every insertion/exfil method to legal terrain/stage and reject illegal use.
- [ ] **Step 2:** Implement shared transport contracts first; Mole uses Tunnels10 and must not collide with Machine
  burrower naming/logic.
- [ ] **Step 3:** Implement Anchor supply/recovery priority, grounded-suit workshop queue and intact-suit race.
- [ ] **Step 4:** Run lifecycle tests for ground, air, tunnel and wet insert/exfil; expected all PASS.
- [ ] **Step 5:** Implement Silent Rotor flip **13** as quiet insertion followed by a one-way, high-signature gunship
  extraction state; its open weapons and detection cost remain through the operation.
- [ ] **Step 6:** Implement Mole multipath **14** with primary/alternate exit and optional collapse-behind choice;
  implement tethered Runner **15** with remote-driver ownership, range/link loss and recovery rules.
- [ ] **Step 7:** Implement Guardian Mule **17/44** with supply, fighting posture and last-denial overcharge. Overcharge
  only arms after squad loss/abandonment, has a readable delay and destroys carried suit cores rather than becoming a
  generic area-damage bomb.
- [ ] **Step 8:** Add support-drone operations **9/10/37/38/40/41**: door-kick clear/mark, bounded relay wiretap,
  spider wall/ceiling/hatch/limpet/power actions, Reaper loiter/designation, pad-only magazines and Nest
  repair/replenishment. Magazine swaps and Nest destruction are saved deterministic states.
- [ ] **Step 9:** Add approved kit **20–22** to vehicle/drone packages: soft/hard/collapse breach charges, narrow EMP
  scalpel strong against Machine and weak against humans, and backdoor spikes/rounds that validate compromised
  Syndicate-sold provenance.

**Acceptance:** the approved vehicle/drone list has operational purpose in the Conductor rather than decorative defs.
Ground, air, tunnel and drone lifecycle tests exercise every transformed state, route choice, magazine and denial
path; all loud/armed/destructive transitions have warnings and counters; provenance prevents backdoor kit becoming a
universal disable.

### Task 17: Human A Counter-Ghost full corps

**Owner org lock (2026-11-23 ADDENDUM — board seq 171; do not stop live E2):** full corps detail in
`docs/superpowers/plans/2026-11-23-faction-depth-decisions.md` § Counter-Ghost Corps.
Loadouts **Interceptor / Bulwark / Seeker / Ward**; squads 4/6/Ward-pairs/legends; specialties as approved;
vehicles incl. **Shade Dart**; **each vehicle type requires its own garage/pad/helipad**. Extend def IDs to match;
keep weaker than Death. ORCH queues this onto **CG10** when GHOST10 releases `exo.gd`.

**Files:**
- Create: `game/sim/systems/counter_ghost10.gd`
- Create: `game/content/g10/defs_g10_counterghost.json`
- Create: `game/content/g10/rules_g10_counterghost.json`
- Extend: `game/sim/systems/exo.gd`
- Create: `game/tests/test_g10_counterghost.gd`

**Interfaces:**
- Definitions (baseline + org expand): `a_cg_intercept`→Interceptor, `a_cg_recon`→Seeker, `a_cg_breach`→Bulwark,
  plus Ward pair defs, specialty/support defs, Shade Dart + per-vehicle home pads per faction-depth table;
  also `a_cg_tracker`, `a_cg_sensor_drone`, `a_cg_apc`, `a_cg_recovery`, `a_cg_command`, `a_cg_workshop`.
- Commands:
  `cg_sweep`, `cg_intercept`, `cg_strip_killswitch`, `cg_recover_suit`, `cg_break_contact`
  (+ escort/hunt intents: `cg_escort_vip`, `cg_hunt_ghosts`, `cg_contest_suit` as EaW cards).

- [ ] **Step 1:** Tests assert Stage 10 Human A ownership, weaker camo/armour/power than equivalent Coalition exos,
  and no Coalition production access.
- [ ] **Step 2:** Implement thermal/sensor sweep, tracker/dog cue use, EMP/net disable and intercept operation.
- [ ] **Step 3:** Implement kill-switch strip as timed engineer action under fire; successful recovery feeds the
  Counter-Ghost track, not ordinary Research9 or Coalition tech.
- [ ] **Step 4:** Add one focused scenario: detect → intercept → disable → strip → recover; add failure cases for late
  strip and lost recovery race.
- [ ] **Step 5:** Run Counter-Ghost, Ghost and existing exo/CN suites; expected all PASS.
- [ ] **Step 6:** Implement Counter-Ghost expansion **32/49**: bright spider-killer bots carry flechette wall-clear,
  sticky foam and ultrasonic peel modes. They reveal/remove spiders and contest Nest approaches; they do not receive
  Coalition camo, Reaper or suit technology.
- [ ] **Step 7:** Test spider/Reaper depth as an action-counter loop: crawl/perch/limpet/wiretap/designate → detect →
  foam/ultrasonic/flechette clear → Ghost rescue/re-route. Hardened joints **52** shorten/mitigate foam effects on
  exos but do not protect drones or grant immunity.
- [ ] **Step 8:** Extend the focused scenario with Judge backdoor threat, Warden corridor, Shade designation,
  Sergeant-loss degradation, Guardian Mule denial and a recovered ace/Mk suit. Human A must win through coordinated
  detection and recovery, not superior raw exo stats.

**Acceptance:** Human A has a complete, comprehensible counterplay corps without inheriting Coalition superiority.
Bright counter bots make spider removal readable; every Ghost drone/exo role has at least one Human A response; the
end-to-end scenario proves disable/strip/recover remains possible against hardened joints and protected recovery.

---

## Wave E2D — AI, modes and selected dark depth

### Task 18: Coalition doctrine AI adapter

**Files:**
- Create: `game/sim/ai/coalition_ai10.gd`
- Create: `game/sim/ai/coalition_doctrine10.gd`
- Extend: `game/sim/ai/ai_controller.gd`, `general_ai.gd`
- Extend: `game/sim/systems/ai_command.gd`
- Create: `game/tests/test_g10_ai.gd`

**Interfaces:**
```gdscript
static func observe(w: SimWorld, fid: int) -> Dictionary
static func choose_operation(w: SimWorld, fid: int) -> Dictionary
static func pressure_for_difficulty(w: SimWorld, fid: int) -> Dictionary
static func board(w: SimWorld, fid: int) -> Dictionary
```

- [ ] **Step 1:** Tests prove cells probe/bleed, mercs fill a detected gap, elites strike a weak high-value target,
  and endangered elites exfil rather than trade.
- [ ] **Step 2:** Feed shipped Adapt9 pressure and general persona into doctrine selection; do not duplicate kill-mix,
  general or CoC state.
- [ ] **Step 3:** Implement combined play `cell_feint → merc_screen → Death action → Anchor exfil`.
- [ ] **Step 4:** Implement difficulty pressure only through scout interval, intel confidence, patience, operation
  concurrency and reaction delay.
- [ ] **Step 5:** Add assertions comparing Easy/Normal/Hard starting stock, income, HP, damage and production cost;
  expected exact equality.
- [ ] **Step 6:** Run AI9 + G10 AI suites; expected all PASS and board/AAR explains target, evidence and outcome.

**Acceptance:** Coalition is the cunning opponent while Machine remains the snowball opponent.

### Task 19: Skirmish and Coalition LP defender profile

**Files:**
- Modify: `game/presentation/menu/skirmish_setup.gd`
- Modify: `game/sim/systems/last_protocol.gd`, `lp_setup.gd`
- Modify: `game/presentation/ui7/lp_menu.gd`
- Create: `game/content/g10/lp_profile_coalition.json`
- Create: `game/tests/test_g10_modes.gd`

**Interfaces:**
```gdscript
static func make_config(seed: int, map_id: String = "", profile: String = "human_a") -> Dictionary
static func profile(w: SimWorld) -> String
```

- [ ] **Step 1:** Tests start Coalition skirmish at Stages 3, 8 and 12 and verify legal spawn, role closure and AI
  ownership.
- [ ] **Step 2:** Keep default LP config byte-for-byte equivalent for `profile="human_a"`; add menu choice “Coalition
  Protocol” that calls `profile="shadow_coalition"`.
- [ ] **Step 3:** Abstract LP setup through profile data: Coalition Stage 10 base uses safehouse/tunnels/Ghost complex,
  Coalition army/air/support and Coalition objective loss condition; Machine side/map/core threat remains.
- [ ] **Step 4:** Replace Human A-only facility assumptions behind profile methods; do not grant Coalition CN teams,
  facility or LP Human A cards.
- [ ] **Step 5:** Run canonical `test_lpmode7`, `test_lp_save71`, facility suites and `test_g10_modes`; expected all
  PASS.
- [ ] **Step 6:** Two-run 1,200-tick hash for both LP profiles; expected each profile stable.

**Acceptance:** Coalition is genuinely playable in LP through a separate profile and canonical LP does not regress.

### Task 20: Blackout, Hollow Ground, Mirror Fortress and Dead Radio

**Files:**
- Create or extend: `game/sim/systems/coalition_dark10.gd`
- Extend: `game/sim/systems/tunnels10.gd`, `ghost_conductor10.gd`
- Create: `game/content/g10/rules_g10_dark.json`
- Extend: `game/presentation/ui10/coalition_command.gd`
- Create: `game/tests/test_g10_dark.gd`

**Interfaces:**
```gdscript
static func blackout(w: SimWorld, fid: int, target: Rect2i) -> String
static func mirror_signature(w: SimWorld, building_id: int) -> Dictionary
static func dead_radio(w: SimWorld, fid: int, target_fid: int, line_id: String) -> String
```

- [ ] **Step 1:** Tests prove Blackout requires EW/intel, has a warning/timer, cuts power/comms temporarily and cannot
  permanently disable a base.
- [ ] **Step 2:** Hollow Ground reuses Task 9 collapse with pre-collapse sound/terrain tell and engineer/scout counter.
- [ ] **Step 3:** Mirror Fortress creates decoy hatch/signature records, not a free second base; recon/damage reveals
  the false complex.
- [ ] **Step 4:** Dead Radio emits mimicked tactical lines plus an explicit anomaly tell and AAR attribution; it never
  issues player commands or turns operators.
- [ ] **Step 5:** Test a doctrine sequence using all four and assert no ROADMAP dark option outside this set appears in
  G10 rules/commands.

**Acceptance:** selected depth is fair, bounded and readable; unselected horror/dark systems do not scope-creep in.

---

## Wave E3/E4 — integration, evidence and lock

### Task 21: Shared-seam integration and expanded smoke

**Files:**
- Modify: `game/sim/world.gd`
- Create: `game/tools/g10_donewhen_smoke.ps1`
- Create: `game/tools/g10_stage_soak.gd`, `game/tools/g10_doctrine_soak.gd`
- Modify: `game/sim/render_snap.gd`

**Interfaces:**
- Final tick order:
  economy/market/territory → production/construction → Coalition tech/buildings → AI/Conductor planning →
  orders/movement/transport → combat/wounds → tunnels/cells/IED/patron/weld → Ghost mission hot wash →
  fog/victory.

- [ ] **Step 1:** ORCH audits all HANDOFFs, releases and shared signatures before integrating `world.gd`.
- [ ] **Step 2:** Register only commands defined in Tasks 9–20 and ensure every handler validates issuer/ownership.
- [ ] **Step 3:** Add all ten G10 suites to smoke:
  `test_g10_content`, `stage`, `mechanics`, `tech`, `buildings`, `ghost`, `counterghost`, `ai`, `modes`, `dark`.
- [ ] **Step 4:** Run focused G10 smoke. Expected: ten suites, zero fail, zero SCRIPT ERROR.
- [ ] **Step 5:** Run existing G71 done-when smoke. Expected: zero fail.
- [ ] **Step 6:** Run full suite:
  `& $G --headless --path game -s res://tests/run_tests.gd`.
  Expected: `0 failed`; save complete output as upgrade-board evidence.
- [ ] **Step 7:** Run Stage 1–13 opener soak and doctrine soak; expected no missing def, invalid command, invariant or
  script error.

**Acceptance:** all pillars coexist in one deterministic world and legacy paths remain green.

### Task 22: Hashes, AI-vs-AI, 100+ stress and performance

**Files:**
- Create: `game/tools/g10_100_squad_soak.gd`
- Extend evidence only under `game/.plan/upgrade_board/evidence/`

- [ ] **Step 1:** Run two identical Stage 3, Stage 8, Stage 12 and both LP profile scenarios; compare terminal hashes.
  Expected: pairwise identical.
- [ ] **Step 2:** Run Coalition AI vs Human A and Coalition AI vs Machine long soaks; winner is not required. Expected:
  no crash, script error, negative stock, orphan mission, stuck transit or ownership violation.
- [ ] **Step 3:** Run 100+ Death-squad Stage 13 stress with compressed visuals; expected squad count ≥100, ordinary
  skirmish cap assertion still PASS, no invariant failure.
- [ ] **Step 4:** Remeasure 2k on-screen and 10k zoomed-out p10. Expected ≥60 and ≥30 respectively; if below, post NEED
  with profile evidence before optimizing.
- [ ] **Step 5:** Board FACTs:
  `g10.hash`, `g10.ai_soak`, `g10.stage_soak`, `g10.100_squad`, `g10.peak`, each citing command/log/result.

**Acceptance:** Done-when determinism, resilience, late capacity and perf have measured evidence.

### Task 23: Final look approval, package and `g10.lock`

**Files:**
- Modify: `README.md`
- Modify: current `game/docs/PLAY_ME_*`
- Modify: `game/docs/ROADMAP.md`
- Modify: `game/docs/G10_SCOPE.md`
- Append: `game/.plan/upgrade_board/board.jsonl`
- Use: `game/.plan/package_g71.ps1`

- [ ] **Step 1:** Present complete Coalition catalog/contact sheet and record owner approval FACT. Do not lock on sample
  approval alone.
- [ ] **Step 2:** Walk all 15 G10 Done-when rows and cite at least one test/soak/look/package FACT for each.
- [ ] **Step 3:** Update README and PLAY_ME with playable faction, stages, Coalition LP profile, controls/counters,
  provisional-balance note and explicit exclusions.
- [ ] **Step 4:** Update ROADMAP G10 to CLOSED and G14 wording to retain only other factions' early/late forms.
- [ ] **Step 5:** Package:
  `powershell -NoProfile -File game/.plan/package_g71.ps1 -Note g10.lock`.
  Expected: clean-folder executable starts, package name contains commit SHA, `PLAY_ME.txt` included, no SCRIPT ERROR.
- [ ] **Step 6:** Change G10_SCOPE lock status to `CLOSED (g10.lock)` only after package verification.
- [ ] **Step 7:** ORCH commit final integration/docs, append `g10.lock`, `ship.<sha>` and `readme.synced` FACTs.
- [ ] **Step 8:** Do **not** push unless separately asked.

**Acceptance:** all scope evidence is present, the owner-approved art is packaged, and `g10.lock` is truthful.

---

## Ship cadence

1. Agent reads recent board rows, posts CLAIM and works only owned paths.
2. Agent runs focused suite and posts FACT with exact result/log.
3. Agent posts HANDOFF + RELEASE; ORCH reviews interface and scope.
4. ORCH runs the dependent seam suite, updates player docs when player-facing, then commits.
5. Package only at playable vertical checkpoints: E1 foundation, E2 core/Ghost vertical, and final E4.
6. Never overlap package runs or native DLL builds.
7. No push in this plan unless the owner/controller separately requests it.

Suggested execution commits:
- `feat: register Shadow Coalition and stage bands`
- `feat: add Coalition core roster and buildings`
- `feat: add Coalition asymmetric mechanics`
- `feat: add Coalition buy steal unseal progression`
- `feat: add Ghost Exo Conductor`
- `feat: add Human A Counter-Ghost Corps`
- `feat: add Coalition doctrine AI and mode parity`
- `feat: add G10 selected dark doctrine`
- `test: add G10 integration and soak gates`
- `docs: lock G10 Shadow Coalition`

## Risk register

- **Stage gating leaks G14:** use faction-specific API and explicit denial tests; never set deferred stages globally
  playable.
- **61 defs become shallow padding:** count only units/buildings; require role/producer/art/play-path closure and soak.
- **LP is Human A-hard-coded:** profile abstraction is MODE10-owned and canonical config must remain equivalent.
- **Conductor duplicates AI9:** AI10 consumes Adapt9/general/CoC state; Ghost mission owns only Coalition package/lifecycle.
- **Mechanics file conflicts:** MECH10 owns `capture71.gd`; ORCH alone registers world commands/ticks.
- **Ghost scope swallows campaign:** G10 excludes Hunter story, chapter memory, regional persistence and 100+ campaign
  buildup; only skirmish compression/stress ships.
- **Counter-Ghost becomes a second faction overhaul:** freeze nine defs and one operation chain; reuse Human A support.
- **Hidden units feel unfair:** every disguise, camo, trap, decoy and radio fake has a visible/audio tell and counter.
- **Dark scope creep:** automated ID/command scan permits exactly four selected extras.
- **Counter-nanite leakage:** central deny tags plus tests across build/market/capture/editor/load/difficulty.
- **Performance from 100+ squads/art:** stress profile uses existing sim tiers/LOD; measure before native work.
- **Owner art rejection late:** six-subject gate before bulk generation and final catalog gate before lock.
- **Dirty working tree:** ORCH stages only task-owned files and never absorbs pre-existing unrelated changes.

## Spec coverage checklist

- [ ] Identity/doctrine, fictional framing, EaW-simple + autonomy — Tasks 3, 18.
- [ ] Stage 1–6 raiders — Tasks 2, 5, 21–22.
- [ ] Stage 7–10 ≥60 core definitions — Tasks 1, 4, 7–8.
- [ ] Stage 11–13 Mk III/distributed/apex/100+ capacity — Tasks 2, 6, 22.
- [ ] Tunnels/caches/civilian disguise/IEDs/patron/capture/weld-shop — Tasks 9–12.
- [ ] Buy/steal/unseal and no normal research — Task 13.
- [ ] No Coalition counter-nanites through every ingress — Tasks 12–13.
- [ ] Buildings hidden/underground/market/vault/Ghost — Task 7.
- [ ] Owner-frozen Ghost IDs 3/4/5/7/9/10/13/14/15/17/20/21/22/24/25/26/27/28/29/30/32 — Tasks 7–8, 11, 14–16.
- [ ] Owner-frozen drone/counter IDs 37/38/40/41/44/47/49 — Tasks 8, 11, 16–17.
- [ ] Owner-frozen exo IDs 52/53/56/57/58/59/60/63/64 — Tasks 8, 14–17.
- [ ] Ghost Packages A–G/J skirmish rows; Death/Shadow/Anchor — Tasks 14–16.
- [ ] Human A full Counter-Ghost corps and spider-killer action/counter loop — Task 17.
- [ ] Coalition super-intelligent/no-cheat doctrine — Task 18.
- [ ] Coalition-only skirmish stages + separate LP profile — Tasks 2, 19.
- [ ] Selected Blackout/Hollow Ground/Mirror Fortress/Dead Radio only — Tasks 9, 20.
- [ ] Four-facing art and two owner look gates — Task 8, Task 23.
- [ ] Smoke/full suite/hash/soak/perf/package/README/PLAY_ME/board — Tasks 21–23.
- [ ] Explicit OUT: campaign Inheritance/Hunter build-up, UNDERSTRIKE, other factions' early/late stages,
  Pre-G10 AI/econ rewrite, space, co-op LP, uncapped skirmish — Global Constraints and G10_SCOPE.

**Self-review:** all G10_SCOPE Done-when rows map to tasks; shared function names are consistent; every implementation
step names its concrete output; the four dark picks, 61 core IDs, nine Counter-Ghost IDs, four Ghost templates and two
LP profiles are explicit.

---

## Execution choice (after owner approval)

Reply **APPROVE** + `1` or `2` to start:

**1. Subagent-Driven (recommended)** — fresh agent per task/pillar, ORCH review and verification between handoffs.

**2. Inline Execution** — execute in this session in wave order with owner checkpoints.
