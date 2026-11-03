# G7-CIWS7: rotary CIWS turrets on the command centre roof (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board; status DIRECTLY every 5 tool calls with calls_used / tokens_used_est / next_action,
including before / after long runs; post `fact shots.best` as soon as something is visible; no git, no D:). Spec:
docs/G7_REFERENCE.md **13.9c-32** (owner: "add in phalanx style turret(s) on top of main command building inside facility
/ future modified anti machine version of the us phlanx Gatling style turret belt fed"), 13.9c-30 (traverse before fire:
sim/systems/traverse7.gd), 13.9c-28 (muzzle at the barrels: tools/art/muzzle7.gd + muzzle7_gen.gd), 13.9c-18, 13.9c-13.
Existing pieces to reuse: counterdrone.gd CIWS (now lays before intercept via Traverse7), a_laser_ciws, turrets7.gd /
wallturret7.gd (G7 turret defs, art, part placement on the facility), CnFacility roof_pad (how a roof position is
expressed), the command centre = zone "planning" (4-storey, 15.5 m roof; fact facb7.zone_heights), tools/art/g7_fac7f.gd.
## Build
1. Sim: a new turret def (original name; e.g. a rotary CIWS) placed as facility parts on the command centre roof (2,
   opposite corners), owner-only, not buildable elsewhere, destroyed with the building; engages drones / missiles /
   rockets / shells (via the counterdrone intercept path with lay) and Machine ground units inside its radius; burst fire,
   spin-up, belt / drum capacity + reload (PROVISIONAL), Traverse7 lay (fast slew); deterministic, saved, hashed.
2. Art: an original sprite set (radar dome over a rotary barrel cluster on a training mount, ammo drum / belt feed), 8+
   aim directions x elevation, spin / fire / reload / idle-sweep / destroyed frames; drawn ON the roof at the roof
   height; muzzle points generated (muzzle7_gen) so the tracer stream leaves the barrel cluster.
3. Tests tests/test_ciws7.gd (placement on the roof, intercepts a drone and a rocket after laying, engages a Machine
   crawler in the compound, burst + reload, destroyed with the building, hash twice-same, no facility = no cost) and a
   windowed playtest tools/pt7_ciws7.gd (ORCH registers "ciws7"): a drone swarm + rockets + a crawler rush, shots at zoom
   1.75 / 2.5 frame-exact on a burst; Read every PNG; post fact shots.best.
Files: new files are yours; counterdrone.gd / traverse7.gd / turrets7.gd have no live owner (post a fact before
editing); cn_facility.gd / defs_g7_facility.json (no live owner, post a fact); g7_fac7f.gd planning section only; world.gd /
combat.gd / entity_layer.gd / render_snap.gd: change_request to ORCH. PERF7F, DET7, PATH7-2 are live.
