# G71-FIRES71: fire support, kill zones, observers and the CONDUCTOR (B4, D5, B1 thermobaric + incendiary, B6, G1 FO, G2 MLRS)

> **ORCH 2026-11-09:** every roster question is answered in `.plan/orch71/wave2_roster.md` section 5A. Read it before your first step; it overrides any "if" in this brief. Q1: Last Protocol only.


You are FIRES71. Read `G71_COMMON.md` first (and through it G7_COMMON.md) and follow it. Budget: MAX_TOKENS 750000,
MAX_TOOL_CALLS 140 (hand off at 70%: `max(est + 90k, 312k + 2.3k x calls) >= 525k` or calls >= 98). Scope:
`docs/G71_SCOPE.md` parts **B4, D5, B6**, the **thermobaric + incendiary** bullet of B1, the **forward observers /
JTAC** bullet of G1 and the **MLRS** bullet of G2, the Pre-start decisions (incl. the 2026-11-09 sim-gate amendment;
our gunship is named **CONDUCTOR**, the hive's commander is the Hollow King) and Done-when 1, 2, 3, 4, 7, in full.
Roster: `.plan/orch71/wave2_roster.md`.

## The owner's words
- B4: "hold a key for a radial menu (HE, smoke, illumination, thermobaric, incendiary, precision, gunship) then shape
  the strike: point, line (barrage along a lane), box (saturate), or creeping barrage that walks toward the enemy."
  "Final protective fire (FPF), manual only: each wall face gets a pre-planned strip 30-60 m out where artillery,
  mortars and the wall's MGs are already laid. One press = every assigned weapon fires its max rate into the strip for
  ~30-60 s. Heavy ammo cost, cooldown, danger-close to anything of ours in the strip. The player can repaint lines."
  "Counter-battery: radar tracks siege-walker shells back to their source; our guns auto-answer." [PROPOSED, approved]
  "observers / drones / radar must see the target for precise rounds; unobserved fire scatters wider."
- D5: "Beautiful, easy, never 'step 16': select any turret / unit / squad / platoon / team / company / army and drag a
  fire sector. Anything left unset gets a sensible zone automatically (turrets cover their wall face and overlap
  neighbours; squads cover their sector). FPF strips (B4) are drawn in the same view."
- B1: "fuel-air rockets for packed lanes; incendiary belts pre-laid in kill zones and ignited on command; fire also
  stops nanite self-repair (B2) and reanimation."
- B6: "A sleek, heavily armed command gunship orbiting the facility, flying with 4-6 autonomous loyal-wingman drones in
  a rotating formation. It passes targets to the wingmen; they peel off to strike, screen it, and sacrifice themselves
  to block drone dives or missiles." Weapons "(owner: required): rotary railgun chin turret, side-mounted heavy cannon
  for orbit fire, laser CIWS vs drone swarms, missile cells, flares / decoys. Wingmen: light guns, missiles, kamikaze
  option." "Orbit placed by the player (radius, side, altitude); returns to its own pad through A1's registry; hot-pit
  serviced." Numbers PROVISIONAL.
- G1: "Forward observers / JTAC teams: spotters that make fire support precise (B4's observed-fire rule) and call the
  heavy strike UCAV (F1) and the Conductor gunship (B6)." G2: "Rocket artillery (MLRS): thermobaric / cluster / smart
  rounds that sweep whole wave lanes; ties into B4's radial menu, line and box strikes."

## Before you start (ORCH fills these in)
- **ANSWERED, see roster section 5A (Q1)** (fire support / kill zones in every mode or LP only? Off-LP sector
  filtering of units also needs the Q2 answer: native find / act mirror target choice off LP).
- **ANSWERED, see roster section 5A (Q6)** (illumination entry now?), **Q19** (radial "gunship" = CONDUCTOR orbit?), **Q12** (MLRS:
  new rounds for the existing a_mlrs or a new def?), **Q4** (snapshot fields), **Q15** (Conductor / FO teams / counter-
  battery radar in the LP starting base, how many).
- The UCAV (F1) is wave 3: FO "call the UCAV" is an API slot with a test stub. The siege walker (C3) is wave 3:
  counter-battery is built and tested against today's enemy indirect shooter (find one in Step 1; else a test-only def).
- Art: functional at the G7 detail level (`fact art.detail_level`); the Conductor is a wave-5 look-checkpoint sample,
  so no full art roll-out now (roster Q16).

## Step 1: survey and measure before building (mandatory)
1. Read how fire support works today: `Strikes` (loiter / mlrs / mass_driver kinds, `strike` command), `Callins`
   (`designate`, JTAC accuracy / delay mults through G6Hooks), Combat indirect fire (`Tiers.long_indirect`), CnOps7 fire
   support, Supply8 airdrop, the CN facility wall faces (`WallTurret7` mount sides) that FPF strips and auto zones hang
   on, and Air's public orders + Pads71 (pads, hot-pit) for the Conductor.
2. Count clicks today for: a barrage along one wall lane, a smoke screen, and giving one turret / one squad a sector.
   That is the "before" for "never step 16".
3. Post `fact fires71.survey` and compiling stubs `fact killzone71.api` (`KillZone71.allow(w, shooter, target_pos) ->
   bool`, `sector_of(w, eid)`, `fpf_strip(w, face)`) and `fact fires71.api` (`Fires71.fpf_aim(w, shooter) -> Variant`
   (strip point or null), `observed(w, fid, pos) -> bool`) within your first 15 tool calls. BASTION71 (turrets) and
   ARMY71 (squads, MG crews) call them from their own files through guards. Send ORCH your commands + SYSTEM_ORDER slots.

## Step 2: build
1. **Radial menu + strike shapes** (new presentation/ui71/fire_radial.gd, strike_shape.gd; sim new fires71.gd):
   hold-key radial (key by change_request to ORCH: hotkeys.gd), kinds HE / smoke / illumination (per Q6) /
   thermobaric / incendiary / precision / gunship (per Q19); shapes point / line / box / creeping (walks toward the
   enemy at a PROVISIONAL rate). One `fire_mission` command assigns in-range friendly artillery / mortars / MLRS
   deterministically (ids ascending). **Observed fire**: precise only if an observer / drone / radar of the side sees
   the target (FO teams, Callins designation, Senses7 / fog); unobserved scatters wider (PROVISIONAL mults).
2. **FPF**: per wall face a strip 30-60 m out (PROVISIONAL default in that range), assigned artillery / mortars / wall
   MGs (BASTION71 turrets + ARMY71 MG crews read `fpf_aim`), one press = max rate into the strip for 30-60 s
   (PROVISIONAL), heavy ammo cost, cooldown, danger-close warning + effect on our own units in the strip, repaintable.
   Manual only: no AI ever fires FPF.
3. **Counter-battery**: a radar (existing Airdef radar or a new def, per Step 1) tracks enemy indirect shells back to
   their source; assigned guns auto-answer. Exposes the hook the wave-3 siege walker uses (shell = indirect projectile).
4. **D5 kill zones** (new killzone71.gd + presentation/ui71/killzone_paint.gd): select anything (turret ... army) and
   drag a sector (arc + min / max range); groups split the sector across members by a deterministic rule (PROVISIONAL);
   auto zones for everything unset (turrets: their wall face + overlap with neighbours; squads: their sector).
   FPF strips in the same view. Sectors restrict target choice through `KillZone71.allow` (callers own the call).
   Measure: clicks for the Step-1 tasks after the change (target <= 3, like A3).
5. **Thermobaric + incendiary**: fuel-air rockets (radial kind + MLRS round): blast on packed lanes via Blast8 /
   Shrapnel profiles (DAMAGE71's files: ask for profile hooks by change_request); incendiary belts (`belt_lay` by
   engineers or drag-to-lay in the kill-zone view, `belt_ignite` on command) burning cells for N s; everything burning
   calls `Parts71.ignite` (DAMAGE71 API: stops nanite self-repair).
6. **G1 FO / JTAC teams** (defs in defs_g71_fires.json): spotter teams that make observed fire precise, extend Callins
   designation, and call the Conductor orbit / a UCAV stub. **G2 MLRS**: thermobaric / cluster / smart rounds through
   Strikes' mlrs kind; line + box shapes from the radial.
7. **B6 CONDUCTOR** (new conductor71.gd, defs, tools/art/g71_fires.gd): a gunship that orbits a player-placed orbit
   (radius, side, altitude; presentation/ui71/conductor_orbit.gd) with 4-6 wingmen (PROVISIONAL 4) in a rotating
   formation; target hand-off to wingmen, peel-off strikes, screening, sacrifice-blocks against drone dives / missiles,
   kamikaze option; weapons rotary rail chin turret, heavy side cannon for orbit fire, laser CIWS, missile cells, flares
   / decoys. Flight through Air's public orders (air.gd is unowned: any edit is a change_request to ORCH); home pad via
   `Pads71` (register a pad kind by API), hot-pit service from A2. Run tests/test_airfix71.gd + test_airops71.gd after
   air work (Done-when 2 must stay green).

## Files (write; everything else by change_request to its owner, see the roster)
sim/systems/strikes.gd, callins.gd; new fires71.gd, killzone71.gd, conductor71.gd; new presentation/ui71/fire_radial.gd,
strike_shape.gd, killzone_paint.gd, conductor_orbit.gd; new presentation/view/fires71_view.gd (markers, strips, sectors;
effects through the public fx61 API); new content/g71/defs_g71_fires.json, rules_g71_fires.json; new tools/art/g71_fires.gd
(+ assets/art/g71_fires/); tests/test_fires71.gd, test_killzone71.gd, test_conductor71.gd; tools/pt71_fires71.gd,
pt71_killzone71.gd, pt71_conductor71.gd. New panels attach as their own nodes with their own input (CR to ORCH for the
attach line, as PatrolDraw71: CR 161) and pass tools/ui_fit_test.gd at all resolutions.

## Rules
- **Sim cost** (final build <= 1.7x G6 on 2k; every later wave ~0): with your code in, 2k fight / 2k mixed / 10k 200t
  hashes equal `fact w2.bench_ref` and your systems' profiled share there is <= 0.05 ms/tick (PROVISIONAL, roster Q18).
  Kill-zone checks cost nothing for units without a sector (precomputed flag); FPF and fire missions are event-driven;
  measure an FPF press on all faces at bench.lp_peak and report the ms/tick burst. tiers.gd budgets used cost. Timing
  runs follow `orch.timing_lock` (seq 440).
- **Determinism**: two-run hash identical in your tests; save / load mid fire mission, mid FPF, mid orbit keeps the
  same future (all new state saved + hashed).
- **Player control first**: no AI fires FPF; auto zones never override a painted sector; AI never overrides a fresh order.
- **Perf**: fps p10 on bench.lp_peak and 2k before / after your presentation work; no visible quality trades.
- **Screenshots** as each visible thing lands (radial, each strike shape, FPF strip + press, kill-zone view, the
  Conductor + wingmen in orbit): look at them, then post `fact shots.best`.
- Tests: tests/test_fires71.gd (shapes, observed vs unobserved scatter, FPF assignment / cost / cooldown / danger-close,
  counter-battery answer, thermobaric / belts burn + ignite calls), tests/test_killzone71.gd (sector maths, group split,
  auto zones, overlap, `allow`), tests/test_conductor71.gd (orbit, wingmen hand-off / sacrifice, pad return, hot-pit).
  Flows (ORCH registers): `tools/pt71_fires71.gd`, `pt71_killzone71.gd` (click counts logged), `pt71_conductor71.gd`.
- Report: AGENT_RULES final report format. No commits. No GENESIS/postflight offer.
