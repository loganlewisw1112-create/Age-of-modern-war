# G61-CHAIN61: chain of command, radio and comms, intel and belief (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G61_COMMON.md first. Flow name: chain61. You are the backbone the other AI agents plug into: post your API
stubs early (within 15 calls) so GEN61, OFF61, SQUAD61 and PLAN61 can call them.

## 1. Chain of command (new sim/systems/command_net.gd)
- A per-side command tree built from what exists: General (an AI commander slot or the side's AI) > Commander unit
  (army) > Captain (company) > Lieutenant (platoon) > squad leader (first alive member of e.squad) > soldier.
  Use Companies (companies.gd), Ops groups (ops.gd) and the existing rank_role / is_officer fields; don't duplicate them.
- **Orders down:** `CommandNet.issue(w, fid, from_id, to_id_or_node, order: Dictionary)` queues an order that is
  delivered after a delay that depends on comms (below). On delivery the receiving level's owner (OFF61 doctrine for
  captains/lieutenants, SQUAD61 for squads) acts on it. Orders carry intent ("take hill 3 by t, main effort, then hold"),
  not only a target.
- **Reports up:** contact reports, casualty reports, ammo/fuel state, objective taken/failed, requests (fire support,
  reinforcement, resupply, medevac). Short readable lines, rate-limited, travel up with the same delay rules.
  `CommandNet.reports(w, fid, node_id, n)` for UI/AI.
- **Initiative:** a unit/leader without a current order (cut off, leader dead, order stale) acts on the last intent it
  received (mission command): continue to the objective, hold, or fall back by its own judgement. Succession when a
  leader dies: the next senior takes over after a short confusion delay (Companies already has promotion; integrate).

## 2. Radio and comms
- Comms range from radios: officers and command vehicles carry radios (content field, e.g. `radio_range`), HQs and
  relay buildings extend it; a unit is "in comms" if connected to its leader through radio links (cheap graph check,
  cached and rebuilt on a cadence).
- Delay = base per hop + distance; out of comms = orders not delivered (they wait or expire), reports not sent.
- **Jamming:** integrate the existing EW jammers (Progression.Status.ew_tick / jammer defs): inside jamming, delay grows
  and links can drop. Machine faction: its relay lattice / Overmind (MachineG6.relay_covers / overmind_online) is its
  network.
- UI hook data: per unit `comms` state (linked / delayed / cut off / jammed) for the inspector and a map overlay toggle
  (expose `CommandNet.comms_state(w, uid)`; ORCH or SQUAD61 shows it).

## 3. Intel and belief (new sim/systems/intel.gd)
- Each side keeps a belief map: last-known enemy contacts (pos, type guess, strength estimate, time seen, confidence
  decaying with age), built from its own fog/sight (Fog system) and from reports travelling up the chain.
- `Intel.contacts(w, fid, rect_or_center, radius)`, `Intel.strength_at(w, fid, pos, r)`, `Intel.threats_to(w, fid, pos)`.
  All AI (GEN61/OFF61, enemy AI) must be able to decide from belief instead of the truth; recon units refresh belief.
- Deception hooks: decoys/feints register as contacts until identified (use any existing decoy/mimic units, e.g.
  Machine mimic; no new art needed).

## Content and wiring
- new content/g6/rules_g61_command.json (radio ranges per role, delays, decay times, report rates); add `radio_range`
  defaults by role so no def edits are needed, or post a change_request to ORCH for def fields.
- Ask ORCH (change_request) for SYSTEM_ORDER slots for CommandNet and Intel (suggest: after Ops, before AiCommand) and any
  commands (e.g. none needed for the player, PLAN61 issues through your API).

## Tests (tests/test_chain61.gd, real checks)
Order delay grows with hops/distance; out-of-comms order not delivered until the link returns; jammer increases delay
and can cut a link; reports reach the captain with the right content; a cut-off platoon continues its last intent;
leader death -> succession after confusion; belief: a contact seen then lost keeps a last-known position whose
confidence decays; AI query from belief differs from the truth after the enemy moves unseen; determinism + save/load
mid-delivery. Measure 2k-unit ms/tick before/after your system with tools/scale_bench (report CPU load).
Playtest flow tools/pt61_chain61.gd: select an officer, show its comms state and reports in the inspector, move it out of
range, show the cut-off state; shots.
