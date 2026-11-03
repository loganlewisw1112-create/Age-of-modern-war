# G71-AIRFIX71: aircraft come home to their own pad (A1), then air ops (A2)

You are AIRFIX71. Read `G71_COMMON.md` first (and through it G7_COMMON.md) and follow it. Budget: MAX_TOKENS 750000,
MAX_TOOL_CALLS 140. Scope: `docs/G71_SCOPE.md` parts A1 and A2, and Done-when 2, in full.

## The owner's problem
"Titanium cement": aircraft that should return to their pad instead hang in the air, often over the middle of the
facility. All 4 craft types do it: helicopters, the regular VTOL dropship, the CN stealth dropship, the Vanta.

## Step 1: reproduce before fixing (mandatory)
Build a headless repro (`tests/test_airfix71.gd` + a tools/ probe) that puts each of the 4 craft types through
low fuel / return-to-base / mission-complete / manual "return" on (a) a skirmish map and (b) the Last Protocol map,
and logs, every N ticks, position vs its home pad slot and the building centre. Record which cases hang and why. The
scope's 5 suspected causes are UNVERIFIED and its line numbers are stale (air.gd has changed since). A G7 attempt
exists in `.plan/airfix7/` (logs, an `air.new.gd`): read it for leads, trust nothing in it until reproduced.
Post `fact airfix71.repro` with the confirmed causes before writing the fix.

## Step 2: the fix (A1)
- One shared **home-pad registry** (`sim/systems/pads71.gd`): helipads, VTOL pads, the CN facility helipad, the Vanta
  roof pad, Blackglass / hospital pads later, FARPs, drone docks later. Kinds + sizes; each craft has a home pad; saved
  and hashed. Post `fact pads71.register` (the API other systems call to register a pad) as a compiling stub within
  your first 15 tool calls; then add the registration calls in cn_facility.gd / drone_bay7.gd yourself (those lines only).
- Fly to the **exact pad slot**, never `b.pos`. Busy pad -> holding orbit beside it + alert. Destroyed pad -> nearest
  pad of its kind, else land on open ground beside the base + alert. No pad at all -> same. Stale occupancy records
  are cleaned (the Vanta wait-forever case). Never hover over a building centre.
- **Matrix (Done-when 2):** 4 craft types x {own pad free, taken, destroyed, none} = 16 cases, each ends "landed centred
  on a correct pad" or "holding with an alert", 0 hovering over a building centre. Headless test + the packaged-style
  flow `tools/pt71_airfix71.gd` (windowed, screenshots of landed craft; post `fact shots.best`).

## Step 3: A2 air ops (after the matrix is green)
- Much longer fuel; near-zero burn while hovering / loitering inside own airspace (define own airspace in rules).
- **Hot-pit service:** land, refuel + rearm in seconds with rotors / fans turning (render state for the view), then
  auto-return to the last task.
- **FARP:** a buildable forward arming and refuelling point (content/g71/defs_g71_air.json; Human A; placeable outside
  the walls); its pads join the registry. Tag it so the wave-3 hive AI can target it (`farp: true`).
- **Auto patrol routes:** command `air_patrol` (draw a loop of waypoints); aircraft fly it and cycle service between
  runs, keeping a minimum on station. Drawing UI in new presentation/ui71/patrol_draw.gd + a hotkey via change_request
  to ORCH (hotkeys.gd).
- Tests `tests/test_airops71.gd`, flow `tools/pt71_airops71.gd`.

## Rules
- Determinism: two identical runs give the same hash; save/load mid-flight keeps the same future.
- Hashes will move (landing behaviour changes): report which, with two identical runs; ORCH re-baselines.
- The registry must cost ~nothing per tick (event-driven, no per-tick scans of all buildings).
- New commands need registering in sim/world.gd: change_request to ORCH with exact names and system position.
