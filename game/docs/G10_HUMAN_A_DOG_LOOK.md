# G10 Human A Robot Dog — complete redesign (owner request)

**Owner request (2026-11-23):** Faction A (`human_a`) robot dogs currently read like Machine walkers (blocky chassis, cyan spine glow, industrial). Replace with a **complete new design**: smaller, sleeker, distinctly Human A military companion—not a Machine unit with a dog gait.

Authority for G10 art agents; does not replace Machine hounds (`g71_m_ember_hound` etc.). Def id remains `g71_robot_dog` (and any skirmish variants); art group regenerates under a new Human A companion sheet.

## Problem with current art

Current `g71_fleet` dog sheets: rectangular torso, cyan spine rack, blunt dual-lamp “face,” spindly stick legs—reads as **small Machine**. That breaks faction silhouette language (Human A = military industrial realism; Machine = nanite/hive glow).

## Design pillars

1. **Smaller** — lower body mass and footprint vs current; packs of 3–4 must read as scouts, not mini-tanks.
2. **Sleeker** — continuous curved flanks, recessed seams, no brick torso.
3. **Human A** — olive/slate armor, subdued IR tabs, optional armband team colour; **no cyan Machine glow**, no nanite veins.
4. **Dog-legible** — clear head, chest, haunch, paw pads; gallop must sell “hound,” not “table walker.”
5. **Multifunction but quiet** — sensor ear dishes, under-chin camera, optional soft muzzle mount; gear stays flush.

## Silhouette (target)

- **Scale:** ~60–70% of current visual mass; radius/pop stay sim-compatible unless balance pass says otherwise.
- **Head:** tapered sensor snout, dual recessed optics (white/amber when active, not cyan), articulated “ears” as planar arrays.
- **Body:** low-slung teardrop / greyhound chassis; single dorsal rail for soft packs (antenna folded flat).
- **Legs:** four digitigrade limbs with visible knee/ankle; rubberized paw pads (readable contact with ground).
- **Finish:** matte ceramic-composite plates, subtle wear; team colour on collar ring / shoulder tab only.

## Palette

| Element | Colour |
|---------|--------|
| Armor | Slate / olive-drab / cold grey |
| Trim | Soft bone / sand |
| Active sensors | Warm amber or white (brief) |
| Forbidden | Machine cyan, hive purple, nanite shimmer |

## Animation / presentation notes

- Gallop: snappier, lighter weight cue than Machine walkers (`Motion.WT_DOG` stays; tune amplitude down for sleeker mass).
- Idle: micro head scan; ears tick toward gunfire.
- Wreck: collapsed hound pose, not brick chunk—still recoverable by fleet mule rules.
- Icons: side silhouette with ear arrays; must not match ember-hound / Machine quadruped icons.

## Variants (optional G10 depth, same silhouette family)

- **Scout dog** — stock `g71_robot_dog` (sensors, light MG or none).
- **Tracker dog** — Counter-Ghost cue package (thermal sniff / camo shimmer detect assist)—Human A only.
- **Silent dog** — suppressed soft-kill / net for urban (no heavy gun).

Do not invent Machine-looking variants.

## Generator / pipeline

- New or rewritten drawer under `game/tools/art/` (e.g. `g71_dog_human.gd` or extend fleet art) producing 4-facing loco sheets + mask + icon + wreck.
- Look checkpoint strip before bulk replace: old vs new side-by-side forbidden—ship only new.
- Catalog override must beat any Machine-adjacent sheet still in `g71_fleet`.

## Acceptance

1. Owner lookcheck: “not a Machine” at a glance beside `g71_m_ember_hound`.
2. Smaller/sleeker readable at LP zoom and skirmish.
3. Team colour via collar/tab only; no cyan spine rack.
4. Tests/art harness still resolve `g71_robot_dog`; fleet71 recover/wipe paths unchanged unless art paths update.
5. Contact sheet in package look checkpoint.

## Plan hook

`docs/superpowers/plans/2026-11-23-g10-shadow-coalition.md` — Task **DOG10** (Human A fleet art redesign), parallel with ART10 / CG10.
