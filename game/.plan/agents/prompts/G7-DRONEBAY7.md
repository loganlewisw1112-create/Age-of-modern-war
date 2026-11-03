# G7-DRONEBAY7: drone bay defence drone garrison (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board, heartbeat via `bash .plan/hb.sh DRONEBAY7 <calls> <tokens> "<label>" -- <cmd>`, status every 5
tool calls with calls_used / tokens_used_est / next_action, also during long runs; post `fact shots.best` as soon as
something is visible; no git, no D:). Spec: docs/G7_REFERENCE.md **13.9c-27** (read every word), 13.9c-18 (drone bay on the workshop),
13.9c-13. What exists: cn_ops7.gd overwatch recon drone launched from the drone_bay zone; Airfield / G5 launched drones
(G5Mech) and the counterdrone systems; LIFE7's display drone on the workshop launch deck (fac_life7.gd).
## Build
1. Sim (new sim/systems/drone_bay7.gd): the facility drone bay garrisons up to 12 defence drones (interceptor, gun,
   kamikaze: reuse existing drone defs where they fit), auto-releases what the threat needs when the base is threatened
   (BaseState7 contested / under_fire / breached), recovers to the launch deck, rearms, rebuilds losses slowly (cost /
   time PROVISIONAL); player launch / recall command, and an auto-release toggle that defaults ON (owner: "launchable either maually or automatically as a default"); keeps the recon overwatch job; deterministic, saved, hashed; no
   facility = no cost (SYSTEM_ORDER slot via change_request to ORCH).
2. UI: the drone bay / workshop panel shows "Drones 9/12" and Launch / Recall buttons.
3. Tests tests/test_dronebay7.gd and a windowed playtest tools/pt7_dronebay7.gd (ORCH registers "dronebay7"): drones
   launching from the deck at an attack, fighting, landing back; shots; Read every PNG; post fact shots.best.
Files you own: the new files above; anything else change_request.
