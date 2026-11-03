# G7-WALLFIRE7: no direct fire through walls (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board; status DIRECTLY every 5 tool calls, never 10 min silent: heartbeat .plan/hb.sh around
long runs; no git, no D:). Spec: docs/G7_REFERENCE.md **13.9c-35** (every word, with the owner's "Realistic exemptions"
answer), plus 13.9c-23 (wall-walk), 13.9c-30 (traverse), 13.9c-33 (fortress balance), 13.9c-34 (LP reserve QRF / surge).
Owner verbatim: "NO unit can shoot from inside outside the walls UNLESS they are on the wall walkways our outside the
wall(s)".
## Build
1. Find today's rule: how Damage.line_clear / combat target picking / Fog treat wall segments, facility walls, LP ring
   walls, gates (open / closed) and the wall-walk (WallWalk7.on_wall). Say plainly whether units inside fire out through
   walls today and why (with a probe).
2. Rule (sim, deterministic, cheap: no per-shot full scans; reuse existing grids / line walks): direct fire whose line
   crosses a wall cell is blocked both ways, unless the shooter is on the wall-walk / outside, or the target is up on
   the wall-walk (exposed to fire from outside), or the line passes through an OPEN gate cell. Exempt: indirect fire
   (mortars, howitzers, artillery, arcing shells), raised mounts (towers, roof CIWS, rooftop / wall turrets whose mount
   height clears the wall), anything airborne (drones, helicopters, dropships) shooting or being shot. Blocked units do
   not "shoot the wall": they pick another target or move (the QRF / surge drills already climb to the wall-walk: check
   they still do, and that target picking stops choosing blocked targets so nobody stands inside firing at a wall).
3. Balance check: the facility fortress (13.9c-33: full facility holds CA x2.5 5/5, breaks in at ~4x; Sentinels alone
   lose at x2.5) must still hold after the rule; run the BAL7 probe (.plan/bal7_probe.gd, 5 seeds x 2.5/3/3.5/4/4.5 +
   bay-off). If the targets move, retune only PROVISIONAL numbers (report every change) or report and ask ORCH.
4. Tests: new tests/test_wallfire7.gd (inside rifleman cannot hit an outside target through a wall; on the wall-walk
   it can; outside attacker cannot hit an inside unit through the wall but can hit one on the wall-walk; open gate gap
   allows, closed gate blocks; mortar / tower / CIWS / drone / helicopter exempt; same inputs -> same hash; deep save /
   load same future). Keep test_wallwalk7, test_wallturret7, test_sent7 (12/0), test_cnfac7, test_dronebay7,
   test_ciws7, test_lpreserve7, test_det7, test_squad7 green; report any test_hot_state golden moves (do NOT edit
   goldens).
5. Windowed: a flow wallfire7 (G7_FLOWS + tools/pt7_wallfire7.gd): Sentinels inside a wall NOT firing out while the
   ones on the wall-walk do; post fact shots.best (read them first; plain caption).
Files: damage.gd / combat.gd (line-of-fire path; PERF7I may profile combat: post a claim, keep edits small), fog.gd only
if needed, wallwalk7.gd, new test + flow. Live: PERF7I (formations7 / senses7 / shrapnel), CIWS7-6 (ciws7), LPRES7-2
(lp_reserve7), LPSHRINK7 (lp_setup / LP layout), FACINT7 (flows). Check claims first.
