# G7-ART7B: roll the approved rev3 art out to the rest of G7 (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first. Then docs/G7_REFERENCE.md "Look checkpoint rev3 decision" (the owner approved the rev3
direction and scale), the earlier look decisions, and the board facts art.scale (seq 762), art.detail_level DL7-3
(seq 963). Study the approved samples: tools/art/g7_cn_lib.gd, g7_cn_mesh.gd (a small 3D-to-pixel renderer that models
in metres), g7_cn_soldiers.gd, and .plan/shots/ARTCN7/compare_today_vs_g7_rev3.png. ARTCN7-5 (live) owns those files and
is polishing the APCs/dropships; you USE its lib and renderer, you don't edit them (ask on the board if you need an API).

## The job: every G7 def that has no art (or placeholder / old-scale art) gets art at the rev3 scale and quality
Run `bash tests/run.sh --only=test_art` first; its failures are your list. Known today:
- TURRET7's 8 turrets (a_t7_*): sheets at the rev3 scale (the old g7_turrets2.gd output predates it), build stages,
  damaged, traverse, recoil/beam, muzzle and impact frames, menu icons. Their gunners use the approved soldier figure.
- THREAT7's Machine threat units: g7_m_burrower, spitter, mimic, leech (missing walk / fire frames and sheets), packhunter,
  weaver (rev3 samples exist; check they sit right at the new scale). The Machine keeps its CURRENT art style (look at
  today's m_walker / m_colossus) but must be scaled consistently with the new humans.
- Drones: g7_a/b_strike_drone, g7_a/b_fpv, cn_gun_drone, g7_cn_interceptor_drone (sheets + icons).
- Counter-nanite kit and buildings: g7_cn_sentry, g7_cn_barrier (+ icons), a_cn_facility / b_cn_facility, cn_tower,
  cn_checkpoint, cn_blast_wall, cn_popup (these are the blue boxes in the Last Protocol base). For the buildings that
  ARTCN7 already draws in g7_cn_facility.gd, coordinate on the board: ARTCN7-5 owns that file; write new buildings in
  your own generator and ask ARTCN7-5 to hand over or include anything that must share it.
- FISSURE7's big growths g7_growth_spire / g7_growth_heart: build states the test wants (g7_growths.gd is yours now).
- Human B variants wherever a def exists for faction human_b.
All at one scale (art.scale), with team masks, every facing, the frames the catalog needs, icons, within the memory
budgets. Generators you own: tools/art/g7_turrets2.gd, g7_threats2.gd, g7_drones.gd, g7_growths.gd, plus a new
tools/art/g7_rollout.gd (or similar) for the CN kit/buildings; their assets/art/ folders; art catalog groups by
change_request to ORCH.

## Done when
test_art passes (or every remaining failure is named with why it can't be fixed by you); a contact sheet per group and
an in-game shot of a mixed G7 scene (turret line, threats, drones, the facility compound) at zoom 1/2/3 that you have
looked at yourself and that matches the approved samples' quality and scale. Report fps-relevant memory per sheet.
