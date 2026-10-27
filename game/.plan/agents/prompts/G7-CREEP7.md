# G7-CREEP7: Machine creep, seeds, cores, escalation, learned reactions (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first. Flow name: creep7. Spec: G7_REFERENCE master scope sections 0, 8 (all of it except the threat
units, which THREAT7 builds later), 6.3 (what counter-nanites do to creep), 10 (how Last Protocol uses creep, cores and
phases). The Machine keeps its CURRENT art; anything you draw follows that style.

Pre-registered stubs (ORCH): `sim/systems/creep.gd` (after MachineG6), `sim/systems/cores.gd` (after Creep).

## Deliver
1. **Creep layer** (`creep.gd`): a per-cell creep field (budget-friendly: coarse grid or sparse chunks; must hold on
   512×512+ maps) that spreads from Machine structures over time, powers and repairs Machine units/buildings standing on
   it, and can't cross water, burnt, salted or cratered ground (firebreaks). Purged cells are permanently sterile.
   APIs (post `fact creep.api` stub early): `Creep.at(w, cell) -> float`, `Creep.coverage(w) -> float` (share of the map,
   for Last Protocol's creep meter), `Creep.purge(w, center, radius, kind)` (kinds: standard / seed_hunter / barrier line),
   `Creep.burn(w, center, radius)` (thermite), `Creep.is_sterile(w, cell)`.
2. **Dormant seeds and burrowed cores:** hidden regrowth points that survive a base wipe and regrow creep and structures
   unless found (scanner reveal API: `Creep.reveal(w, center, radius, side)`) and purged. Seed nests (dense clusters) for
   LPMAP7 to place.
3. **Minimum hacking and EMP:** Machine EW can jam or briefly take over normal human vehicles and drones in range
   (never units flagged `unhackable`, which CNSIM7 sets); EMP stuns Machine units (`Creep`-side API or a small helper
   `sim/systems/machine_ew7.gd` called from MachineG6). Post `fact machine.ew_api`: `stun(w, center, radius, secs)`,
   `can_hack(e)`.
4. **Doomsday + living cores** (`cores.gd`): core structures that pulse, grow armour plating over time, emit a
   `CoreHit` event with intensity (AUDIO7 screams later) and drive a countdown modifier API for Last Protocol:
   `Cores.list(w)`, `Cores.countdown_rate(w)`, and the **last core's second phase**: at low health it tears out of the
   ground and walks (a mobile boss; it can be slowed by EMP, leg damage and barrier lines; core-breaker packages finish
   it). Post `fact cores.api`.
5. **Escalation phases + learned reactions:** an escalation API LPMODE7 drives (`Cores.set_phase(w, n)`: unit tiers,
   creep speed, assault waves) and the four learned reactions, learned in order and triggered by what strike teams do
   (1 after the first successful deployment: defend deployment sites; 2 after losing a set amount of creep: hunt strike
   teams with hunter packs and ambushes; 3 after a core or major structure falls: raid the facility; 4 late: adapt to
   routes and habits), each emitting `NetworkAdapted` (HUD alert "THE NETWORK HAS ADAPTED"). The Machine AI acts on them
   (new `sim/ai/machine_react7.gd`; ask ORCH by change_request for the AI hook line).
6. **View:** `presentation/view/creep_layer.gd`: creep drawn on the ground (pulsing network in the Machine style), purged
   ground recovering slowly, sterile ground visible; cheap at 512×512 zoomed out.

## Tests (tests/test_creep7.gd)
spread over time and blocked by water/burnt/cratered ground; purge kinds (standard area, seed-hunter wider and
underground, barrier line that creep can't cross); sterile ground never regrows; seeds regrow after a wipe unless purged;
EMP stun and hack rules (unhackable immune); core plating grows; last core enters phase 2 and walks; reactions learned in
order on their triggers; same seed twice = same hash; a match with no creep is hash-identical to before; cost at
512×512 with full creep reported.
Playtest flow tools/pt7_creep7.gd: creep spreading from a Machine base, a purge clearing it for good, a seed regrowing,
a core pulsing and the walking phase; shots of each.
