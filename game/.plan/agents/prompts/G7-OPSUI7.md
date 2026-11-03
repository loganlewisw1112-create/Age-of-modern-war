# G7-OPSUI7: operations UI (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first. Spec: docs/G7_REFERENCE.md master scope 6.11 (operations UI), 13.6 (command screens:
in-world presentation), 13.7 (PROTOCOL advisor: logic + text; the voice itself is AUDIO7's, emit events it can use),
13.1 (lore intel files: the codex UI; LPMODE7 already places/collects the files, read lp_world.gd), 6.10 + 13.4 (the
team card data from CNOPS7). Read the handoffs of CNSIM7-*, CNFAC7-*, CNOPS7-1, LPMODE7-3 and DRONE7 (the drone feed
look), and the board change requests addressed to OPSUI7 or "ORCH/OPSUI7" (CNOPS7 seq 1209 especially). The owner
approved the G7 look direction (docs "Look checkpoint" sections); UI must match the existing UiKit style (G5 UI5a) and
pass the fit test at every resolution and scale.

## Files you own
New presentation/ui7/ files (ops_panel.gd, deploy_tracker.gd, team_cam.gd, strat_map.gd, war_table.gd,
protocol_advisor.gd (+ sim-side read-only logic or a small new sim/systems/protocol7.gd if it must be deterministic),
codex.gd, team_card.gd), tests/test_opsui7.gd, tools/pt7_opsui7.gd (flow "opsui7" is registered). hud.gd / match_view.gd
/ settings.gd / fit_screens.gd / hotkeys.gd hooks: change_request to ORCH with exact lines (hotkeys: check collisions
with Hotkeys.collisions()). Sim files belong to their owners: read their public APIs only.

## Deliver
1. Operations panel: every team's location and status, suit breaches, stock, dropship and drone status, jump-to.
2. Live deployment tracker: arming progress, dome charge, time left, incoming forces.
3. Team cam: overwatch feed (CNOPS7's overwatch drone) or helmet cam, with call signs and radio subtitles.
4. Strategic overview map: creep, seed nests, forward bases, relays, cores, countdown, routes.
5. Team card (CNOPS7 seq 1209): names, call signs, personalities, skills, records, buddies, level/XP; buttons for
   cn_fire_support (artillery|rockets|air, calls left) and cn_relief (operators|reload), plus cn_specialize.
6. Military command-tablet styling for 1-4 (scan lines, unit icons, map projections, matching the drone feed).
7. Holographic war table in the facility: a 3D-looking table you can rotate and tilt (terrain height, creep, cores,
   planned routes).
8. PROTOCOL advisor: flags opportunities and dangers in short lines ("Seed nest exposed at grid D4", "Convoy route
   crosses packhunter territory", "Core 2 plating at 60%"); suggests, never acts; can be muted / turned off (setting).
9. Lore codex: collected intel files readable in a codex screen.
10. Last Protocol HUD: show the countdown also as projected real minutes (LPMODE7 noted it shows protocol-seconds).
Register new fit screens (change_request) and pass `bash tests/run.sh --only=test_ui_fit` and test_ui_panels.

## Tests (tests/test_opsui7.gd)
each panel builds from a world with/without counter-nanite teams; jump-to; tracker values match the sim; advisor
lines fire on the right conditions and stay silent when muted; codex lists collected files only; buttons submit the
right commands; no sim mutation from the UI (hash unchanged by opening panels). Playtest flow tools/pt7_opsui7.gd:
open every panel/screen in a live match with a deployed strike team, the war table rotated, a PROTOCOL line, the codex;
shots at 1280x720 and 1920x1080 (look at every one yourself).
