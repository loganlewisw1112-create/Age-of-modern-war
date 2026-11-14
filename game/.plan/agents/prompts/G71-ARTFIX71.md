# G71-ARTFIX71: FARP art + icons, air_patrol command icon (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)

You are ARTFIX71 (generation 1). Read `G71-FIX71_COMMON.md` first and follow it.

## Your 3 red files (wave-1 regressions: HEAD fda25f9 passes all three)
- `test_art` 4/3: "placeholder/null art: icon a_g71_farp"; "building a_g71_farp at least footprint wide";
  "3 distinct construction looks for a_g71_farp (got 1, expected 3)"; plus test_faction_coverage (read its log line).
- `test_icons7` 0/1: "buildings with placeholder icon: ["a_g71_farp"]".
- `test_art_g5_bld` 1/1: "32x32 icon for command air_patrol" (the log also shows image load_from_file errors: find out
  which file it tries to load).

## What to build
- `a_g71_farp` (content/g71/defs_g71_air.json; size 4, Human A, "forward arming and refuelling point": 2 rotorcraft pads,
  fuel bladders, ammo pallets, a small ops tent / container, camo netting): a real building sprite at least footprint
  wide, its 3 construction looks, its icon, and every faction-coverage entry test_art expects, in the same procedural
  pipeline the other Human A buildings use (`tools/gen_art.gd`, `tools/art/buildings.gd`, `bdress.gd`, `bdetail.gd`, the
  art manifests under `assets/art/`). Match the Human A look of the G6 / G7 buildings. No placeholder.
- A 32x32 icon for command `air_patrol` (SHIFT+Y, CR 149), wherever the other G5+ command icons live.
- Update the FARP def's `_note` "Art: placeholder until the look checkpoint" so it no longer claims a placeholder.
  The look checkpoint polish (wave 5) is not needed now.

## Check
The 3 files green in the live tree, plus `test_airops71` and `test_airfix71` (they place a FARP). Post `fact shots.best`
with a frame of the FARP in a match (G7_COMMON screenshot rule) and give its path in your report.
