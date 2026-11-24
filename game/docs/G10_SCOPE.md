# G10 "Shadow Coalition" — master scope (UP71 Stage E)

OPEN for UP71 from `docs/ROADMAP.md` G10. Follows `pre_g10.lock`.

## Headline
Shadow Coalition full faction — Stages **1–13** forms as applicable: **1–6** early raider bands, **7–10** core Syndicate parity, **11–13** late syndicate (Mk III exos, 100+ squads).

## Owner decision (2026-11-23)
`CAMPAIGN_VISION.md` Part 0 **resolution 4** originally deferred Coalition Stages 1–6 and 11–13 to the “every faction” stage pass (**G14**). For **Shadow Coalition only**, that split is **inverted**: early and late forms ship in **G10** with the core roster, not G14.

## Scope
1. **Shadow Coalition (Syndicate) identity + mechanics:** full playable 4th faction; **no counter-nanites**; pure buy / steal / unseal tech UX.
2. **Stage bands (this faction):**
   - **1–6:** raider and warlord bands (early-growth / low-tech Coalition fantasy).
   - **7–10:** full-parity core roster (~22 hulls), art, tunnels-as-faction where designed; matches campaign “Syndicate Shadow Coalition” battle identity.
   - **11–13:** late syndicate — Mk III exos, large squad counts (100+ where specified), apex-band units and buildings as applicable.
3. **Ghost Exo Programme (owner-approved 2026-11-23):** seamless AI-first **Conductor**; tip echelon = **Death** squads (+ Shadow Corps + Anchor); packages in `docs/superpowers/specs/2026-11-23-ghost-exo-programme-design.md`; slice plan `docs/superpowers/plans/2026-11-23-ghost-exo-programme.md`. G10 ships skirmish/Conductor core + Human A **Counter-Ghost full corps** (faction-depth Q5=D). Campaign Hunter / build-up waits for **G15**.
4. **Difficulty bar:** whole Coalition = **super-difficult**, **super intelligent / strategic** foe — difficulty by intelligence and strategy, not cheats; beatable with counters, crushing if ignored. Vs Machine: Machine = snowball king; Coalition = cunning king; skirmish slider; campaign Coalition always vicious. **UX:** Conductor runs Death ops by default (Advanced override).
5. **G10 extras:** expanded roster / buildings / features; **leftover dark + G7.1 ideas** folded where they fit the bar (owner pick in G10 Q&A; not all must ship). See `docs/superpowers/plans/2026-11-23-faction-depth-decisions.md` and ROADMAP G10 dark/G7.1 lists.
6. **Pre-G10 already shipped (not reopened here):** non-campaign **AI** (adapt, generals, diplomacy, intel-difficulty, CoC, Warmind) and **strategy/economy** (research tiers, trade routes, territory/civ, black market, gathered resources, coalitions). G10 is **faction-focused**.

## Out of scope
- **UNDERSTRIKE** bunkers and borer fleet → **G11+** (Human A only).
- **Inheritance** campaign, Living World, Orbit → **G15+**.
- **Other factions’** Stages **1–6** and **11–13** (Human A/B, Machine, Vhessar, Unbound) → still **G14**.
- **Space** combat and orbit slice → **G18+**.
- Tactical pause+queue (parked); co-op LP → **G19**; uncapped skirmish pop → **G12**.

## Done-when (draft — owner will freeze later)
1. Shadow Coalition selectable in skirmish and LP with stage-appropriate forms for **1–6**, **7–10**, and **11–13** where setup allows; core **7–10** parity roster playable end-to-end.
2. Early raider band identity readable in soak (composition, economy, Conductor behavior distinct from core).
3. Late syndicate band (11–13) exercises Mk III / large-squad fantasies in harness + one packaged soak path.
4. Ghost Exo Conductor + Death / Shadow / Anchor echelons; Human A Counter-Ghost full corps counterplay path in tests.
5. No Coalition counter-nanites; buy/steal/unseal tech path documented in setup UX.
6. Super-intelligent AI doctrine (no resource/HP cheats on Hard) for Coalition persona; evidence in soak log.
7. Expanded smoke + full suite **0 FAIL / 0 SCRIPT ERROR** on touched paths; two-run hash OK where sim applies.
8. Packaged build; root README + PLAY_ME name G10 status; `g10.lock` when owner freezes Done-when.

## Build order (provisional)
```
E0 freeze scope + board roster + owner G10 Q&A (dark/G7.1 picks)
E1 COAL10 core (Stages 7–10 roster, art, faction sim, tunnels)
E2 STAGE10 bands (Stages 1–6 raiders + 11–13 late syndicate)
E3 GHOST10 (Conductor, Death packages, Counter-Ghost corps)
E4 DARK10 (selected leftover dark / G7.1 depth)
E5 integ · smoke · soak · peak · package → g10.lock
```

## Execution plan
Ghost Exo + integration: `docs/superpowers/plans/2026-11-23-ghost-exo-programme.md` · faction depth: `docs/superpowers/plans/2026-11-23-faction-depth-decisions.md`. Broader G10 task plan TBD after Q&A.

## Lock status
**OPEN** — scope recorded; Done-when not frozen; no `g10.lock`.