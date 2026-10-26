# G61-SQUAD61: squads that fight as one unit, smart soldiers, classic controls (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G61_COMMON.md first. Flow name: squad61.

Units today act like loose pieces. Make every squad (e.squad) and platoon (e.platoon) act as one unit, for the player
AND the AI, and give the player much better team management and controls (the classic RTS layer; PLAN61 does the
map-drawing layer).

## Sim (sim/systems/squad_ai.gd: stub already registered after Orders; commands set_stance, regroup)
1. **Shared fight:** members share targets (focus fire, sensible split to avoid overkill); the whole squad returns fire
   when any member is hit; idle members move to support an engaged squadmate; the squad leader picks targets.
2. **Cohesion:** formation spacing around the squad leader (leash), stragglers catch up, a squad on attack-move moves at
   its slowest member's pace and stops together.
3. **Smart soldiers:** take cover/height when engaged (short local reposition), spread out against splash/artillery,
   role-aware targeting (AT on vehicles, MG on infantry, snipers on officers/crews), low-HP units fall back behind the
   squad toward a medic, suppressed units go prone (REAL61 owns suppression values; you read them), low-ammo units pull
   back toward a bearer/supply, vehicles reverse out of AT range when outmatched instead of dying in place, kiting where
   range allows, retreat paths avoid crossing the enemy's fire.
4. **Stances** (set_stance): aggressive (pursue, engage at max range), defensive (hold the area, return fire, limited
   chase), hold fire (only self-defence), hold position (never moves). Shown in the inspector and the Teams panel.
5. **regroup:** selected squads/platoons reform on their leader.
6. **Orders from the chain:** when CHAIN61 delivers an order to a squad leader (its API), the squad executes it; AI
   doctrine (OFF61) sets squad stance/formation through your API: `SquadAI.set_stance_internal(w, ids, stance)`,
   `SquadAI.squad_state(w, squad_id)`. Post `fact squad.api` as a stub within 15 calls.

Rules: never override a direct player order (20 s window / DIRECT_ORDERS), never move units on Hold Position; staggered
thinking. Measure 2k-unit ms/tick before/after with tools/scale_bench (report CPU load); test_perf_g6 must stay green.

## Formations (formation_slots in movement.gd + orders.gd)
Add **box, echelon left/right, file, spread (skirmish)** to line/wedge/column; formations face the move direction;
mixed selections put armour in front and infantry behind; **move as a group at the slowest speed** toggle.

## Team management + controls (presentation)
- Command card buttons for every formation and stance + regroup (presentation/hud/g2_commands.gd), with rebindable
  hotkeys (presentation/ui5/panels/hotkeys.gd; other agents send you their hotkey requests).
- **Teams panel** (new presentation/ui6/teams_panel.gd, opened from the HUD with a hotkey, e.g. T): lists control groups,
  squads, platoons and companies with unit count, health, ammo, stance, current order and comms state (CHAIN61 API when
  it lands); click selects, double-click centres the camera; set stance/formation for a whole group; rename a group.
- Control groups: Ctrl+1..9 assign, 1..9 select, double-tap centres, Shift+number adds (fix whatever is missing).
- Double-click a unit selects its squad; Ctrl+double-click selects its platoon.

## Tests (tests/test_squad61.gd)
Focus fire; return fire within 2 s; leash (no member > N tiles from its leader after a move); hold-position never
moves; hold-fire doesn't shoot unprovoked; AT prefers vehicles; low-HP fallback; each new formation gives distinct
non-overlapping slots; a player order is not overridden; determinism + save/load.
Keep test_orders* / test_movement* / test_combat* / test_g2* / test_hud / test_ui* green.
Playtest flow tools/pt61_squad61.gd: select squads, set formations and stances from the card and the Teams panel, fight;
shots of each formation and the panel.
