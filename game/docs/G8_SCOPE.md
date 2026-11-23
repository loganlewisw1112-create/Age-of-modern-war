# G8 "Four Sides" — master scope (UP71 Stage B)

Frozen for UP71 from `docs/ROADMAP.md` G8 + `docs/G7_REFERENCE.md` G8 HEADLINE. Owner slice order approved 2026-10-31; Done-when contracted here for no-stop execution. Follows G7.1 lock (`g71.lock`).

## Headline
Full 4-side view rotation: every building, prop, terrain edge and effect drawable from 4 sides (no mirroring). 90° steps on Q / E + middle-mouse drag (rebindable). Camera keeps focus. Selection, orders, minimap, fog, every display layer and depth sort follow the view. Facing hints in the UI.

## Scope
1. **View rotation core (ROT8):** facing index 0..3; input; camera focus preserved; world↔screen maps; order click mapping; depth sort.
2. **Four-side art (ART8):** generators emit 4 sides for buildings, props, terrain edges, FX; detail upgrade for playable factions + full human redraw in the same pass; catalog / masks / wrecks / icons.
3. **Animation overhaul (ANIM8):** locomotion / fire / death for rotated views; wire `k8_*` ANIM8 paths.
4. **Presentation (PRES8):** director-cam PiP; end-of-run highlight reel; end-of-run creep timelapse; LP after-action heat map (high-leverage polish).

## Out of scope (later slices)
Shadow Coalition (G10), Machine full overhaul (G9), UNDERSTRIKE, campaign, co-op LP, tactical pause queue.

## Done-when (frozen for UP71 G8)
1. Full suite 0 FAIL / 0 SCRIPT ERROR after G8 integ; two-run hash identical.
2. Q / E and MMB rotate view through all 4 facings; camera focus holds; selection and right-click orders land on the correct world cell for every facing (headless + packaged).
3. Minimap, fog, FX, and depth sort follow facing; UI shows facing hint.
4. Art: sample strip of buildings + units + edges for all 4 sides with 0 mirrored cheats on lookcheck.
5. Director PiP, highlight reel, and creep timelapse each fire once in a headless end-of-run harness.
6. Packaged build in Downloads; root README + PLAY_ME current (`g8.lock`); peak remasure FACT posted (chase continues; amended G7.1 peak gate still held).

## Build order
B1 ROT8 → B2 ART8 → B3 ANIM8 → B4 PRES8 → B5 integ + package.
