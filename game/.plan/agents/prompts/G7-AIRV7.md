# G7-AIRV7: the CN Vanta rotorless stealth gunship (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board, heartbeat via `bash .plan/hb.sh AIRV7 <calls> <tokens> "<label>" -- <cmd>`, status every 5
tool calls with calls_used / tokens_used_est / next_action, no git, no D:). Spec: docs/G7_REFERENCE.md **13.9c-14** (the
owner's note; read every word), 13.9c-13 (realism, no gimmicks), section 6 (counter-nanite line), the existing air units
and their systems (sim/systems/air.gd, airfield.gd, airdef.gd, counterdrone.gd, drone systems, Loadouts in
sim/systems/loadouts.gd if present), the dropship / helicopter art generators (ARTCN7, ART7D) and the art detail level.
FACB7-4 (live) builds the 3-storey Sentinel barracks with the rooftop pad: agree the pad position / size on the board.

## Build
1. The unit (content/g7/defs_g7_vanta.json; Human A and Human B variants), counter-nanite teams only, trained / based at
   the facility (the barracks rooftop pad: launch, land, rearm, refuel there; one per pad, PROVISIONAL cost / time).
2. **Hardpoints (owner 13.9c-15):** front nose (main), left side, right side and rear. Each hardpoint takes one weapon or
   attachment, each visible on the art at its mount and firing from it (nose: forward arc; sides: their side arcs; rear:
   tail cover: flares / deterrents / anti-drone / rear gun). Mission-adaptable loadouts chosen before a sortie (and changeable when landed on its pad): drone launcher (deploys
   the existing G7 drones), missiles (anti-armour / anti-walker), gun (machine gun / cannon), anti-drone suite (uses the
   counterdrone mechanics), advanced flares and deterrents (decoys against AA / SAMs). Use the existing loadout / weapon
   systems; a player command to pick the loadout (rebindable hotkey: change_request to ORCH for hotkeys.gd if needed).
3. Flight model consistent with the other air units (hover, strafe, attack runs), stealth (harder to spot / lock:
   Senses7 / airdef hooks), deterministic, saved and hashed; the AI commander can use it to defend the facility.
4. Art: a new generator tools/art/g7_vanta.gd: a futuristic ROTORLESS stealth attack craft (faceted hull, ducted /
   vectored fans or thrusters, no rotor), each loadout visible on the pylons, 16 facings, hover / flight / landing gear
   down, firing frames per weapon, flare / decoy fx, damaged and wreck; same scale and detail bar as the approved
   dropships; display on the barracks roof pad at the right height.
5. Tests tests/test_vanta7.gd (each loadout works, rearm/refuel on the pad, stealth effect, hash twice-same, no facility
   = no cost) and playtest tools/pt7_vanta7.gd (ORCH registered "vanta7"): take-off from the roof pad, each loadout in
   action, flares vs a SAM, landing; shots at zoom 1 / 1.75 / 2.5; Read every PNG; list the best (the owner wants them).
Files you own: content/g7/defs_g7_vanta.json, a new sim/systems/vanta7.gd (SYSTEM_ORDER slot via change_request),
tools/art/g7_vanta.gd + assets/art/g7_vanta/, tests/test_vanta7.gd, tools/pt7_vanta7.gd, art_catalog.gd (register only).
Anything else: change_request (exact lines).
