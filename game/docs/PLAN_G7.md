# PLAN_G7: "Last Protocol"

Scope authority: **G7 MASTER SCOPE** in `docs/G7_REFERENCE.md` (sections 0–13; section numbers below refer to it).
Goal and frozen Done-when: `PROGRESS.md` "Active goal (G7 ...)". Branch `g7` (cut from `g6` at 55b4e04). **Working copy on C:** `C:/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare` (owner order 2026-10-26 after D: drive hardware errors; push back to D: only when G7 is complete).

## 1. How the wave runs
- One continuous wave, **6 agents live at most** (owner), queued agents start as slots free.
- Every agent has a brief `.plan/agents/prompts/G7-<ID>.md` and follows `G7_COMMON.md`.
- Board `.plan/board_g7.jsonl`, guard armed by ORCH, budget per brief (default MAX_TOKENS 750000, MAX_TOOL_CALLS 140).
- ORCH owns `sim/world.gd` (SYSTEM_ORDER, COMMANDS, preloads), `tools/ui_playtest.gd`, content registries, README /
  PROGRESS / PLAY_ME, commits and packaging. New systems are pre-registered as compiling stubs (done for Wounds,
  DronePilot, Convoy); others ask by `change_request`.
- **Look checkpoint (Done-when 6):** ARTCN7 produces sample strips first; ORCH sends them to the owner; **no full art
  roll-out (ART7B/ART7C) starts before the owner approves.**

## 2. Agent roster

| ID | Workstream (master scope section) | Wave |
|---|---|---|
| SCALE7 | 512×512+ map support: map size cap, terrain/minimap/camera at 512+, pathing and spatial index at 512, fog grid at 512 (sim), a blank 512 test map, bench at 512 | 1 |
| WOUND7 | Soldier realism (2): hit zones, out-of-action timers, bleeding, shrapnel, full casualty-care chain, visible panic | 1 |
| SQUAD7 | Squad tactics + formations (3) + convoy/moving-cover framework (6.7): bounding, suppressive fire, hold/ambush, assault/break contact, building clearing + roof cut, grenade decisions, gait under fire, backing off, rebuilt formations, movement techniques, herringbone/coil | 1 |
| DRONE7 | Drone piloting + drone cam (1): commands, strike drone, FPV, feed view + shader, link loss | 1 |
| LOOK7 | Battlefield look (4) + port animations (5): grey fog + last-known markers, ground marks, dust explosions, armbands, all new poses and their frame selection | 1 |
| ARTCN7 | Look-checkpoint samples at the new detail level: strike team + operators, both APCs, facility sample, both dropships, 2 turrets, packhunter, Weaver, living core | 1 |
| SENSE7 | Realistic senses (2) + per-squad knowledge (3): view cones, noise, hearing, optics; intel per squad | 2 |
| CREEP7 | Machine systems (8): creep, seeds, regrowth, minimum hacking/EMP, doomsday + living cores, escalation phases, learned reactions; creep render layer | 2 |
| CNSIM7 | Counter-nanite units (6.3–6.6, 6.8): unlock, strike team, operators, both APCs and their defences, packages, deployment, site hold, hero detonation, suits/exposure | 2 |
| CNFAC7 | Facility + dropships + base (6.2, 6.9 dropships, 9): the fortified compound and its areas/flows, lockdown, both dropships with internal cargo bays, base secure state | 2 |
| CNOPS7 | Operation support + progression (6.9 support, 6.10): overwatch drone, fire support on call, relief convoys, named operators, personalities, bonds, signature skills, team XP, upgrades | 3 |
| TURRET7 | 8 new Human A turrets (7) | 3 |
| THREAT7 | Machine threat units (8): burrowers, spitters, mimics, packhunters, leeches, Weavers, walking last core | 3 |
| LPMODE7 | Last Protocol rules (10, 13.5): mode, 3-ring base, defence AI posture, breaches, air rules, lose/win, run shape, the Tide, endings, set pieces, secrets, score/medals/records | 3 |
| LPMAP7 | Last Protocol map (10, 13.3, 13.8, 13.9): the 512×512+ hand-built map and world reaction (creep-warped terrain, sky/light, wildlife/civilian traces) | 3 |
| OPSUI7 | Operations UI (6.11, 13.6, 13.7): ops panel, deployment tracker, team cam, strategic map, tablet style, holographic war table, PROTOCOL advisor, lore codex UI | 4 |
| AUDIO7 | Sound (13.2, 13.4, 10): adaptive music, operator voice barks, command voice, core screams | 4 |
| CINE7 | Cinematics (13.1, 13.5): opening cinematic, endings, end-of-run screen with medals and "Remembered" | 4 |
| ART7B / ART7C | Full art roll-out after owner approval: all counter-nanite units, facility, dropships, 8 turrets, threat units, living cores | after checkpoint |
| PERF7 | Perf at 512+ and overall sim cost (Done-when 3) | 4 |
| INTEG7 | Integration, Last Protocol soak (Done-when 4), packaged playtests, package (Done-when 5) | last |

Waves are an order of start, not hard phases: a later agent starts as soon as a slot frees and its inputs exist.

## 3. Wave 1 (launched 2026-10-26)
SCALE7, WOUND7, SQUAD7, DRONE7, LOOK7, ARTCN7. File ownership is in `G7_COMMON.md`.

## 4. Order of risk
1. **512×512+ map** (SCALE7 first): if pathing, fog or render can't hold the fps/sim gates at 512, stop and ask the owner.
2. **Formation/convoy AI** (SQUAD7): the quality bar for both soldiers and the counter-nanite group.
3. **Sprite memory** (ARTCN7 sizes the new detail level against the atlas budget before the roll-out).
4. **Last Protocol load** (LPMODE7/LPMAP7 + PERF7): full base + 8 APCs + Tide on the 512 map.

## 5. Done-when mapping
| Done-when | Who proves it |
|---|---|
| 1 full suite | every agent (own suites) + ORCH full runs |
| 2 determinism | every sim agent (two-run hash), DRONE7 (recorded flight), INTEG7 |
| 3 perf | SCALE7 (512 early), PERF7 (final, idle PC) |
| 4 LP soak | LPMODE7 + INTEG7 |
| 5 package | INTEG7 + ORCH |
| 6 look checkpoint | ARTCN7 strips → ORCH → owner |
