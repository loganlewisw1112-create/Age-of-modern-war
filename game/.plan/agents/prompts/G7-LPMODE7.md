# G7-LPMODE7: Last Protocol mode rules (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first. Flow name: lpmode7. Spec: G7_REFERENCE master scope section 10 (all of it, exactly), 13.3 (set
pieces), 13.5 (endings: logic only; CINE7 makes the cinematics later), 13.8 (secrets: logic), plus brainstorm B6, B7, B10,
B11, B16, B17 entries. LPMAP7 builds the map in parallel: agree the placement interface (cores, nests, FOBs, relays,
dam, bridges, power grid, secrets, ring layout) on the board early.

Pre-registered stub (ORCH): `sim/systems/last_protocol.gd` (before Victory).

## Deliver
1. **Mode**: `cfg.mode == "last_protocol"`: strictly 1v1, you (Human A only) vs the Machine at maximum difficulty; a main
   menu entry from day one (presentation/menu: change_request to ORCH with the exact lines, or own a new
   presentation/ui7/lp_menu.gd), with best-time and score records saved locally.
2. **Start state**: everything researched (Stage 10 included); the 3-ring pre-built base from LPMAP7's layout, base
   starts secure; the facility full (2 strike teams + 4 tactical squads, 8 APCs, normal caps lifted via
   `CounterNanite.set_tac_cap`), 2 regular VTOL dropships at the airfield + the stealth dropship on its helipad; the
   8 new turrets in the outer ring (TURRET7 defs; placeholders if not ready).
3. **Main army rules**: strict defence run by a defence AI Commander (existing AI Commanders system, role "base defence":
   mans walls/towers/turrets/vehicles, shifts reserves, rotates crews, sets repair priorities), owner override; leaving
   the walls allowed but punished (exposure, no repairs, packhunters); air force defends base airspace and flies out
   only as fire support on call.
4. **Breaches**: defenders fall back to the next ring and the gates seal; income drops while Machine forces are in the
   economy ring; engineers rebuild walls/towers; creep follows a breach unless purged/burned/sealed.
5. **Lose**: creep meter critical (`Creep.coverage`), countdown zero (`Cores.countdown_rate`, creep speeds it up), or the
   facility falls with no teams in the field. **Win**: all 3 cores destroyed (incl. the walking last core) AND creep
   below the threshold. Each core destroyed slows the countdown.
6. **Run shape**: early entrenched; middle escalation phases (`Cores.set_phase`), learned reactions unlocking; Weavers
   from 60–75% (THREAT7's gate API); finale **THE TIDE** (last core phase 2 or countdown final stage): the creep surges
   toward the base with every Machine unit left, defence AI Commander to maximum posture, hold all 3 rings while strike
   teams chase the walking core. Length target 60–90 minutes.
7. **Set pieces and secrets (logic)**: blow the dam (flood valley → permanent firebreak, costs a convoy route), bridge
   demolitions, reconnect the old power grid (faster training/lab output while held); 4 secrets (prototype weapon cache,
   lost squad rescue, Machine origin site → capture-a-core story, dormant human mech).
8. **Endings (logic + events for CINE7)**: total purge, pyrrhic victory, secret capture-a-core (EMP-lock + barrier
   containment of the last core), and a defeat ending per loss rule. End-of-run data: time, creep purged, cores
   destroyed, teams lost, extractions, medals (bronze/silver/gold), personal bests, the "Remembered" list.
9. HUD meters: creep meter + countdown + phase (a small panel `presentation/ui7/lp_hud.gd`, ORCH hooks it).

## Tests (tests/test_lpmode7.gd)
start state; lose rules; win rule; countdown math; phase progression; Weaver gate; Tide trigger; breach fallback; endings
selection; records saved; same seed twice = same hash; normal matches untouched.
Soak hook for INTEG7: a headless AI-vs-AI run on LPMAP7's map (or lp_test512 until then) that reaches the Tide and prints a
result line. Playtest flow tools/pt7_lpmode7.gd: start a run, a breach + fallback, the Tide, an ending screen; shots.
