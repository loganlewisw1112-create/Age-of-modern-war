# AUTONOMOUS SPACE COMMAND

Owner-approved direction, 2026-11-27. PLANNED / NOT IMPLEMENTED. All examples are non-executable documentation guidance. No runtime changes or gate changes authorized.

Player personally establishes foothold/base, appoints commander, sets directive and authority; observes growth, takes over, resumes. Reuse existing officer/institution systems. Competence, experience, doctrine, personality, memory and limited intelligence affect decisions; mistakes and losses possible. No free assets. Scope: installation, colony, planetary, fleet, regional, civilization high command; industry/science/logistics/defense functional roles without mandatory staffing.

| Directive | Priority |
|---|---|
| Balanced | diversified development |
| Expansionist | authorized settlement/territory |
| Industrial | extraction/manufacturing |
| Military | force generation |
| Offensive | authorized campaigns |
| Defensive | protection |
| Scientific | discoveries/research |
| Economic | commerce |
| Custom | explicit objective |
Delegation: current operations, development, full authorized strategy. Player override within existing campaign battle restrictions. Cargo/crew/supplies travel with actual mass, fuel, route, duration and capacity; automated freight, escorts, reroute, repairs, rescue and salvage. Shortages affect industry and combat. Shared persistent warfare: interplanetary, orbital, atmospheric, surface, naval/aquatic, subterranean and supported interior/boarding; same casualty, damage and territory ledger.

## Illustrative pseudocode (not executable)
```text
for commander in stable_order(due_commanders):
    knowledge = observed_state(commander.faction, commander.scope)
    candidates = bounded_plan(knowledge, directive, competence, doctrine)
    for intent in prioritize(candidates):
        if manual_control_conflict(intent): continue
        if authorized(intent) and reserve_actual_resources(intent):
            submit_to_authoritative_validator(intent)
```
CommandIntent {id,issuer,scope,target,objective,knowledge_tick,budget,priority,expected_state_version}. Validate authority, resource, tech, target and ownership; release reservations on rejection/cancel; deterministic conflict resolution. Takeover invalidates conflicting pending intents, preserves completed work and reconciles reservations; resume current state, never stale snapshot. UI directive, authority preset, takeover and actionable alerts. Test restricted scope, limited knowledge, shortages, conflicting orders, handoff, save/load and camera independence.
