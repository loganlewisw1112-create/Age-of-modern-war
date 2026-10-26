# G61-BEARER61: infantry ammo bearer (MAX_TOKENS 450000, MAX_TOOL_CALLS 110)
Read G61_COMMON.md first. Flow name: bearer61.

The owner: "add new infantry unit that can be used within the squad, group it with, and that unit's job is to carry extra
ammo enough for multiple units to fully restock (3 units per this unit)".

1. **Content** (new content/g6/defs_g61_bearer.json; check how content/g6 fragments load and follow that): one bearer per
   faction (human_a "Ammo Bearer", human_b "Supply Carrier", machine "Munitions Drone", a small foot/hover unit), light or
   no weapon, pop 1, cheap, producible at each faction's barracks equivalent (if the loader can't add to a building's
   produces list from your fragment, post a change_request to ORCH with the exact lines). Post `fact bearer.defs` so ORCH
   adds a bearer slot to infantry company presets.
2. **Load:** 3.0 "restocks" = enough to fully restock 3 units; restocking a unit from a% ammo uses (1 - a) of a restock.
   The bearer refills at any existing supply source (depot / HQ / supply truck; follow Supply's rules, sim/systems/supply.gd
   is ORCH's: read it, ask for any change).
3. **In the squad:** `join_squad {issuer, unit_ids (bearers), squad_unit_id}` puts the bearer into that unit's squad (and
   platoon/company if any); it follows the squad a few tiles behind the centre, out of the front line, and restocks squad
   members below a threshold (e.g. 50%) within 2 tiles, lowest first, over a short time; then any friendly unit nearby if
   its squad is full. `leave_squad` detaches. Input: select bearer(s) + right-click a friendly squad member, or a
   "Join squad" button on the bearer's card (ask SQUAD61 for the button/hotkey by change_request; your input handling may
   live in a new file of yours).
4. **UI:** inspector shows "Ammo load 2.4 / 3" (expose a function returning the line; ORCH wires it if the inspector isn't
   yours), and a small ammo marker on the unit.
5. **Art:** sprite + production icon per faction through the existing G6 art pipeline (tools/gen_art.gd, assets/art/g6_*;
   follow how the 89 G6 assets were added, and keep test_art_machine / test_art_g3b green).
6. **AI:** the enemy AI builds bearers and attaches one per ~3 infantry squads (OFF61 owns ai_army.gd: change_request with
   the exact hook; GEN61 for generals).

## Tests (tests/test_bearer61.gd)
One bearer fully restocks exactly 3 empty units then is empty; partial restocks use fractional load; refill at a depot;
join_squad follows the squad; leave_squad; validation (not a bearer, enemy squad, dead unit); save/load + determinism.
Keep test_supply / test_units* / test_art* / test_content* green.
Playtest flow tools/pt61_bearer61.gd: train a bearer, join it to a squad from the UI, fight until ammo drops, watch the
restock; shots.
