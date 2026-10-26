# G7-LOOK7: battlefield look + the ports' animations (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first. Flow name: look7. Spec: G7_REFERENCE master scope sections 0, 4 (all of it), 5 (all of it),
and the parts of 2 and 3 you draw (wounds, panic, gait, backing off, clearing, herringbone).

Today: G6.1 (ANIMA61/ANIMB61/ANIMC61) built motion.gd, frame sets (walk/run ≥6, prone, crawl, fire poses, reload,
throw, die, wounded, idle), vehicle frames, packing + mirrored facings for memory; fog_layer draws dark fog.

## Deliver (display only: never write the sim; view on/off hash identical)
1. **Grey fog of war:** outside current sight the map turns grey (desaturated, slightly darkened) showing what your
   units last saw, instead of dark; last-known enemy markers from the intel data fade with age and confidence
   (buildings already ghost this way).
2. **Ground marks** (`decal_layer.gd`): blood, scorch, craters, debris linger up to a cap (oldest fade first); bodies
   stay longer than now, also capped.
3. **Explosions:** layered brown dust columns that drift and fade slowly, debris arcs, haze (replacing bright fireballs
   for ground blasts).
4. **Armbands:** shrink the team-colour mask area on existing human soldier sprites to an armband or helmet band (the
   rest realistic camo); vehicles and zoomed-out LOD icons keep the full team colour. Regenerate through the pipeline.
5. **New poses + frame selection** (section 5): crouch-walk, duck-run, backwards walk while firing; hit reactions by zone
   (stumble, limp, knock-back, blast knock-down), unconscious, crawling; buddy aid, medic treatment, dragging,
   stretcher carry; grenade wind-up and throw, room entry, lean/peek, window fire, cower/flee/drop weapon; smooth
   formation movement and reforming, vehicles angling into the herringbone; drone take-off/bank/release/dive (with
   DRONE7). Frames for every foot unit that needs them, in the existing pixel style and facings.
6. **Render snapshot** (you own sim/render_snap.gd): add the fields WOUND7 and SQUAD7 request (wound zones,
   unconscious, being treated/dragged/carried, panic, gait, sector facing, backing off, stacking, herringbone angle,
   building roof_open) and draw from them; **roof cut-away** on buildings with roof_open.
7. **Memory and fps:** check atlas pages/MB before and after (mirror/pack like ANIMC61); 2k on screen p10 ≥ 60 and
   10k zoomed out p10 ≥ 30 must still pass; report numbers with CPU load.

## Tests (tests/test_look7.gd)
frame-name checks for every new pose on every unit that needs it; armband masks smaller than before on soldiers and
unchanged on vehicles/LOD icons; decal and body caps hold; last-known markers fade with age; view on/off hash identical.
Playtest flow tools/pt7_look7.gd: fogged area grey with fading markers, a firefight with dust explosions and lingering
marks, wounded crawling and a drag, a building cut-away, a herringbone halt; shots plus a 10-shot 0.3 s strip for the
owner (the look checkpoint uses these: grey fog, wound/crawl, armbands, staggered column, herringbone).
