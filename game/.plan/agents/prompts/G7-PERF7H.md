# G7-PERF7H: finish the 2k sim gate with margin (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board; status DIRECTLY every 5 tool calls, never 10 min silent: heartbeat .plan/hb.sh around
long runs; no git, no D:). Successor to PERF7G: read .plan/handoff/PERF7G.json and board fact perf7g.done. Gate (frozen,
PROGRESS G7 Done-when 3): 2k-unit sim ms/tick <= 1.2x G6.1 (55b4e04), same session. PERF7G: median of 6 alternating
pairs 1.214x (pairs 1.05-1.42 on a semi-idle PC). Target: median <= 1.15x so the final idle-PC run clears with margin.
Bench + tools: .plan/sim_ab7.gd, .plan/perf7g_pairs.sh, .plan/perf7g_prof.gd (per-system, both trees), G6.1 tree
C:/CODING/g7_regress2_wt/game (read-only except its .plan/).
## Candidates (G7-only costs, from PERF7G): shrapnel ~1.26 ms/tick (about 100 us per fragment wound hit + 0.25 ms
per-candidate overhead); Senses7 inside fog +1.0 ms; movement path-queue drain +0.58 ms; Wounds visibility / bleed passes
walk every entry every tick (~0.4 ms: cadence / dirty lists); Formations7 polish still ~140 ms per 1000-unit command
(tick-1 spike; native or an exact pre-filter). Pick by measured payoff.
## Rules: hash-preserving first (prove: the gate scene's 600-tick hash f8e094305be0e45b on and off, plus test_det7);
a behaviour-changing optimisation needs a stated reason and stays faithful to the feature (wounds / shrapnel / senses
are owner features: same results, cheaper). Never weaken a feature, test or threshold. Final: 6 alternating pairs
(raw table, median ratio, CPU load), per-system before/after, test_squad7 / test_wound7 / test_det7 / test_perf_g6 /
test_senses7 (or the owner test of each system you touch) green.
Files: shrapnel.gd, senses7.gd, movement.gd (path queue), wounds.gd, formations7.gd, combat.gd / damage.gd (hot paths)
- post a claim fact first; LPRES7 (lp_reserve7 / sentinels7 / lp_setup / world.gd COMMANDS lines) and CIWS7-5 are live.
