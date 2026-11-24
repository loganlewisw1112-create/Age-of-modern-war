# Pre-G10 "Depth Bridge" — master scope (UP71 Stage D)

Frozen for UP71 from owner approval of Approach C (parallel pillars → one `pre_g10.lock`).
Follows `g9.lock`. Does **not** open Shadow Coalition (that remains **G10**).

## Headline
Close every G9 depth gap left after thin verticals, then ship non-campaign **AI** and **strategy/economy** upgrades that ROADMAP parked under G10 — so G10 can be Coalition-only.

## Scope (three pillars)

### Pillar 1 — G9 leftovers (depth)
1. **HIVE9+:** blended Machine art **≥60 defs**; silhouettes readable at 4 facings; modular merge/split + nanite eat/evolve visible in soak; hardest-but-fair tune pass (rules, not cheats).
2. **COUNT9+:** all 13 counters usable in play (not harness-only), including **coalitions** (feeds Pillar 2 diplomacy).
3. **COMBAT9+:** dig-in + field forts persist; EW/drones/cyber beyond G7 min in skirmish+LP; vehicle **crews** (bail/recrew) + wear/breakdown/recovery; ballistics facing/weak spots on more than one class.
4. **SKIRM9+:** `director_adapt` as a real skirmish setup toggle; Tide siege units under fair caps with **attack-move** / sensible orders.
5. **Hive network:** link quality degrades with distance, terrain, and EW; mesh and spine topologies behave differently; linked nodes share last-seen contacts while severed nodes become peer-fog-blind; creep provides a weak nanite-ground signal that firebreaks and dead zones can cut.
6. **PACE71:** all skirmish and Last Protocol vehicles move at about **1.7×** current open-ground speed; roads/cleared ground add about **20%**; creep/rubble/mud subtract about **30%**; acceleration, turning, and deployment friction remain meaningful.

### Pillar 2 — AI upgrades
1. Adapts to the player (composition / opener / kill-mix → mid-match shifts).
2. Named rival generals (3–5 personas, distinct doctrine, UI + AAR readable).
3. Diplomacy / multi-faction (temporary truce / joint push vs over-strong Machine; break when threat drops).
4. Difficulty by intelligence (scouting, priority, retreat/regroup, terrain) — **no** resource/HP cheats.
5. AI chain of command runs its own multi-phase operations (player-side commanders + enemy generals).
6. **Warmind:** keeps a readable doctrine (`hold`, `counter_swarm`, or `decap`) until evidence justifies a pivot; budgets threats before committing; remembers what killed nodes and retunes counters (ties adapt); exposes its current priority through radio/UI/board telemetry.

### Pillar 3 — Strategy & economy
1. Deeper matches via meaningful mid/late upgrade/evolution choices.
2. Richer evolutions/upgrades for Human A/B + Machine.
3. Research tree overhaul (clear tiers/prereqs; Machine path stays distinct).
4. Civilians + territory (holding matters; civilian harm costs support).
5. AoE3-style trade routes (capture posts → income + location resource mix).
6. Black-market marketplace tier (smuggled gear; merc loyalty hooks where applicable).
7. **2–3 new gathered resources** (e.g. fuel already exists in market — add **rare_metals** + widen fuel/ammo economy so every match gathers 2–3 that matter).

## Out of scope
- Shadow Coalition faction (roster, art, tunnels-as-faction, buy/steal/unseal tech) → **G10**
- Campaign / Inheritance / Living World / Orbit → **G15+**
- UNDERSTRIKE bunkers → **G11+**
- G12 human training/bunk/security depth, biomes, procedural maps, full AAR productization
- Co-op LP → **G19**; uncapped skirmish pop → **G12**; leftover dark/G7.1 ideas → **G10** (owner 2026-11-23)
- Tactical pause+queue (still parked)

## Done-when (frozen)
1. Full suite + expanded smoke **0 FAIL / 0 SCRIPT ERROR**; two-run hash OK on touched sim paths.
2. Machine blended catalog **≥60** defs with look-checkpoint samples in package.
3. All 13 counters have **play path + harness**; coalitions fire in a 3-faction soak FACT.
4. Forts / crews / EW depth exercised in tests beyond G9 thin cases.
5. Skirmish: director_adapt toggle in setup UI; siege attack-move works under caps.
6. AI: named general selectable/spawned; adapt evidence in soak log; Hard has **no** cheat multipliers.
7. Economy: 2–3 resources gathered meaningfully; ≥1 trade route pays location mix; black-market tier purchasable; research tiers gated.
8. Packaged build; root README + PLAY_ME show Pre-G10 CLOSED; peak remasure FACT posted; G10 still named Coalition-only.
9. Hive-network tests prove quality loss, topology behavior, shared-sense severing, and creep-cable cuts; Warmind tests prove doctrine persistence/pivot, threat budget, counter-memory, and readable priority.
10. PACE71 tests prove faster open-ground vehicle travel in skirmish + LP and slower travel on creep/rubble/mud while retaining acceleration/turn/deploy friction.

## Build order (Approach C)
```
D0 freeze + board roster
D1 G9 depth   (HIVE9+ / COUNT9+ / COMBAT9+ / SKIRM9+ parallel)
D1a addendum  (PACE71 early · Hive network through HIVE9+/COUNT9 seam)
D2 AI9        (adapt · generals · diplomacy · intel-diff · CoC ops)
D2a addendum  (Warmind doctrine · threat budget · counter-memory · readable intent)
D3 ECON9      (resources · trade · territory/civ · research · black market · upgrades)
   — serialize D2↔D3 on diplomacy + Machine-coalition seam
D4 integ      smoke · soak · peak · README/PLAY_ME · package → pre_g10.lock
```

## Execution plan
Full task plan (Approach C): `docs/superpowers/plans/2026-11-23-pre-g10.md`

## Lock status
**CLOSED (`pre_g10.lock`)** — Tasks 0–17, verification, package, and GitHub push are complete.
