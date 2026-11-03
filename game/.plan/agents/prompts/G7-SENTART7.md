# G7-SENTART7: Sentinel art and animation (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board, heartbeat via `bash .plan/hb.sh SENTART7 <calls> <tokens> "<label>" -- <cmd>`, status every 5
tool calls with calls_used / tokens_used_est / next_action, no git, no D:). Spec: docs/G7_REFERENCE.md 13.9c-10 (Sentinels),
13.9c-13 (realism, no gimmicks), every "Look checkpoint" decision (the owner approved the infantry, CN operators and
counter-nanite strike team as "fucking solid": match that bar), and the board facts `sent7.art_needs` (seq 4150: the 7
types' silhouettes, kit, A vs B) and `sent7.anim_needs` (seq 4151: reload, stationary crouch, sidearm pose). Read how the
CN operator / strike-team sheets are generated (ARTCN7 commits, tools/art/g7_cn*.gd, assets/art/g7_cn) and the
ART7 detail level (fact art.detail_level).

## Build
1. A generator tools/art/g7_sentinels.gd writing assets/art/g7_sentinels/: the 7 Sentinel types (Warden, Marksman,
   Gunner, Bulwark, Lancer, Arc, Mender) + the Sentinel Ammo Bearer, Human A and Human B, on the same figure rig and
   scale as the CN operators (8 facings, team-colour *_mask.png), states: idle, walk, crouch-walk / duck-run, sprint,
   crouch (stationary), aim, fire (primary), fire (sidearm machine pistol), reload (short mag change), drag (casualty),
   down / dead. Slim sealed nanotech armour, no glowing super-effects (13.9c-13); each type readable by silhouette.
2. Point the Sentinel defs' art at the new sheets (content/g7/defs_g7_sentinels.json: art field only; tell SENT7-3, who
   owns the file, on the board, or post a change_request if it objects) and register the group in art_catalog.gd.
3. The animation hooks from sent7.anim_needs: the render snapshot must expose reload (e.s7_rl) and sidearm (e.s7_sa) as
   UNHASHED display keys and the view must pick crouch when gait 1 and still. render_snap / entity_layer unit drawing are
   ORCH's files: send ORCH a change_request with the exact, cheapest lines (render_snap is the hot path: no per-unit cost
   for non-Sentinels; e.g. only inside the existing g7u per-unit block that Sentinels already populate).
4. Tests tests/test_sentart7.gd (sheets present for every type/state/facing, defs point at them, hash unchanged with the
   art on). Playtest tools/pt7_sentart7.gd (ORCH registers "sentart7"): each type idle / aim / fire / reload / sidearm /
   crouch / drag at zoom 1 / 1.75 / 2.5, A and B, on the wall top and in the open; Read every PNG; fix what falls short;
   list the best for the owner.
Files you own: tools/art/g7_sentinels.gd + assets/art/g7_sentinels/, tests/test_sentart7.gd, tools/pt7_sentart7.gd,
presentation/art/art_catalog.gd (register only).
