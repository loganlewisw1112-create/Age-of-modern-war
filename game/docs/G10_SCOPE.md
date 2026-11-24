# G10 "Shadow Coalition" — master scope (UP71 Stage E)

**OPEN — owner-review draft.** Follows `pre_g10.lock`. Approval of
`docs/superpowers/plans/2026-11-23-g10-shadow-coalition.md` freezes this Done-when and opens Task 0; until then, do not
start G10 game code.

## Headline

Ship the Shadow Coalition as the fourth full faction: Coalition-only forms across **Stages 1–13**, a full-parity
**Stage 7–10** core (target **about 60 gameplay definitions**), early raider bands, late syndicate/Mk III forms, the
AI-first Ghost Exo Programme, and Human A's full Counter-Ghost Corps.

## Owner decision carried forward (2026-11-23)

`CAMPAIGN_VISION.md` Part 0 resolution 4 originally deferred Coalition Stages 1–6 and 11–13 to G14. For the
**Shadow Coalition only**, that split is inverted: its early and late forms ship in **G10**. Other factions retain
their current Stage 7–10 availability and wait for G14.

## Scope

1. **Identity and doctrine:** cells bleed and distract; mercenaries flex around the opponent; scarce Syndicate elites
   strike the weak point. The Coalition is fictional and uses no real-world group names or symbols.
2. **Faction mechanics:** civilian disguise and sleeper activation; tunnels/caches; IEDs, traps, sabotage and shock
   raids; scavenge/capture/refit; weld-shop vehicle packages; black-market contracts, patron favour and mercenary
   loyalty. Civilian harm uses the shipped support consequences.
3. **Technology:** pure **buy / steal / unseal** progression. Coalition has no normal research tree and can never own,
   build, buy, capture into use, or inherit counter-nanites.
4. **Buildings:** disguised safehouses/workshops, tunnel entrances/caches, underground production, black markets and
   broker/patron sites, Ghost complex/forward repair shops, and rare vault cores. These are faction structures, not
   UNDERSTRIKE floors or Human A bunkers.
5. **Stage bands:**
   - **1–6 Raiders:** survivor smugglers → organized cells → warlord camps → reclaimed workshops → confederated
     raiders → industrial criminal armies. Low-tech capture, salvage, tunnels and patron access replace normal
     research. No Mk II/III exos.
   - **7–10 Core Syndicate:** full combined roster and building parity, target about 60 core definitions; cells,
     technicals, captured armour, drones, boats, companies/officers, patron air support, Death/Shadow/Anchor and Stage
     10 prototypes.
   - **11–13 Late Syndicate:** Mk III hybrid exos, distributed cells, apex vault/patron assets and 100+ squad-scale
     **capacity in stress/soak scenarios**. Ordinary skirmish still respects its selected cap; G12 owns uncapped
     skirmish.
6. **Ghost Exo Programme:** implement the G10 rows of
   `docs/superpowers/specs/2026-11-23-ghost-exo-programme-design.md`: AI-first Conductor, Death combat echelon,
   Shadow Corps, Anchor, mission cards/ROE, camo/power/counters, operator/suit wounds, cohesion, intel gates, lifecycle,
   adaptations, workshop bottleneck, vehicles and recovery. Hunter campaign memory/build-up remains G15.
7. **Human A Counter-Ghost Corps:** a full but weaker reverse-exo operational corps at Stage 10: intercept/recon/breach
   teams, thermal/sensor support, APC/recovery support, kill-switch stripping and suit-race counterplay. It is not the
   post-G10 skirmish CN/Blackglass branch and grants no Coalition tech.
8. **AI hooks:** extend shipped Adapt9/generals/intelligence/CoC systems with a Coalition doctrine adapter and
   Conductor. Do not rewrite Pre-G10 AI. Difficulty is patience, scouting, feints, target choice, contracts and
   adaptation—never free resources, HP or damage.
9. **Modes:** all thirteen stages appear in skirmish **only when Shadow Coalition is selected**; other factions'
   deferred stages remain unavailable. Last Protocol keeps its canonical Human A-vs-Machine entry and gains a separate
   Stage 10 **Coalition defender profile** using the same mode/map contract with Coalition base/roster/objectives.
   G10 does not add LP co-op.
10. **Owner-review dark/G7.1 picks proposed for this lock:** **Blackout** (coordinated EW/power raid), **Hollow
    Ground** (readable tunnel-collapse/ambush play), **Mirror Fortress** (decoy hatches/false complex), and **Dead
    Radio** (mimicked radio/AAR deception with explicit tells). All other ROADMAP dark options remain unselected.
11. **Presentation/art:** four-facing readable art and icons for the complete Coalition set, team-colour readability,
    hidden/revealed states, stage-band silhouettes, exo shimmer/battery tells, and owner look checkpoints before bulk
    rollout.

## Explicitly out

- Inheritance campaign, Hunter chapter memory/build-up, Living World and Orbit/space roster.
- UNDERSTRIKE buildings, floors and borer fleet; those remain Human A-only in G11+.
- Other factions' Stage 1–6 and 11–13 forms; those remain G14.
- Rebuilding Pre-G10 Adapt9, generals, diplomacy, Warmind, research tiers, trade routes, territory/civilians,
  gathered resources, black market or coalition systems. G10 may call or faction-specialize their public interfaces.
- Human A skirmish CN/Blackglass branch, co-op LP, uncapped skirmish population, tactical pause/queue.
- ROADMAP dark options not named in Scope item 10.

## Done-when (draft ready for owner approval)

1. `shadow_coalition` is the fourth registered faction, has valid role/start data, and can start, build, gather,
   produce, fight, save and load without missing definitions.
2. Coalition-only skirmish selection supports Stages **1–13**; selecting another faction still exposes only that
   faction's shipped stages. Every stage has a legal opener and at least one advancement/progression path.
3. Stage 1–6 raider soak proves a low-tech opener, capture/salvage growth, tunnels and patron escalation without a
   normal research queue or Mk II/III exos.
4. Stage 7–10 core contains **at least 60 Coalition gameplay definitions** across infantry/exos, vehicles,
   air/naval/drones and buildings; role/build/production closure has no orphan definitions.
5. Stage 11–13 soak proves Mk III risk, distributed-cell/apex assets and a deterministic 100+ Death-squad stress
   capacity path while normal skirmish caps remain enforced.
6. Tunnels/caches, civilian disguise, IED/shock raids, contracts/patron loyalty, capture/refit and weld-shop packages
   each have a real command/play path, deterministic test and readable counter.
7. Buy/steal/unseal are the only Coalition tech acquisition paths. Automated denial tests cover normal research and
   counter-nanites through build, market, capture, editor/load and difficulty overrides.
8. Ghost Exo G10 packages run end-to-end: mission card → intel/workshop gate → package → insertion/approach/action/
   exfil → hot wash/echo. Death, Shadow and Anchor all participate; camo counters and suit recovery work.
9. Human A Counter-Ghost Corps can detect, intercept, disable, strip and recover a Coalition suit in a focused
   counterplay scenario; it remains weaker than equivalent Coalition exos.
10. Coalition AI completes one cell-feint/merc-screen/elite-strike operation and one retreat/exfil under pressure.
    Easy/Normal/Hard change decision quality and pressure only; tests prove no Coalition resource/HP/damage multiplier.
11. Coalition starts and completes a skirmish at Stages 3, 8 and 12, and the separate Stage 10 Coalition LP defender
    profile reaches playable state with valid objectives. Canonical Human A-vs-Machine LP remains green.
12. Blackout, Hollow Ground, Mirror Fortress and Dead Radio have explicit tells/counters and appear in one packaged
    doctrine soak; no unselected dark option ships.
13. Owner look checkpoints approve: (a) raider + technical + hidden structure, (b) Death + patron vehicle + late
    prototype, then the complete four-facing catalog.
14. Expanded G10 smoke and full suite report **0 FAIL / 0 SCRIPT ERROR**; two-run hashes match on touched deterministic
    scenarios; AI-vs-AI and 100+ squad soaks have no invariant failure.
15. Package launches from a clean folder; root `README.md` and `PLAY_ME` describe G10; upgrade_board records claims,
    look approvals, test/soak/hash/package facts; only then close as `g10.lock`.

## Build order (Approach C)

```text
E0 owner APPROVE → freeze scope + Stage E board roster/claims
E1 foundation: registry/stage gating + identity/doctrine + authoritative roster manifest
E2 parallel pillars:
   ROSTER10 (1–6 / 7–10 / 11–13) · ART10 · MECH10 · TECH10 · BLD10
   GHOST10 · COUNTERGHOST10 · AI10 · MODE10 · DARK10
E3 seam integration: content closure · Conductor/AI · stage/mode · presentation
E4 smoke · hashes · AI/100+ soaks · look approval · package/docs → g10.lock
```

## Execution plan

`docs/superpowers/plans/2026-11-23-g10-shadow-coalition.md`

Supporting authorities:
`docs/superpowers/specs/2026-11-23-ghost-exo-programme-design.md`,
`docs/superpowers/plans/2026-11-23-ghost-exo-programme.md`, and
`docs/superpowers/plans/2026-11-23-faction-depth-decisions.md`.

## Lock status

**OPEN — OWNER REVIEW.** No `g10.lock`; no implementation starts before **APPROVE**.