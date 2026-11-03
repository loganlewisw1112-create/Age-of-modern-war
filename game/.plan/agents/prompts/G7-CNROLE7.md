# G7-CNROLE7: CN strike teams / spec ops never on base defence (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board; status DIRECTLY every 5 tool calls with calls_used / tokens_used_est / next_action,
including before / after long runs; no git, no D:). Spec: docs/G7_REFERENCE.md **13.9c-29** (owner: "counternanite strike
team and spec ops team(s) are NEVER to be on base defense -- strictly to go run their missions") and B16 (section on the
main army's role), 6.x (how strike teams / tactical squads operate: facility launch flow, planning room, missions).
## Build
1. Audit: every path that can give a unit a defence job or pull it into a fight at home: lp_defence.gd (already skips
   cn_team), lp_garrison7.gd, last_protocol.gd, sim/ai/ai_controller.gd + AI commanders (ai_command*, any side incl. an
   enemy AI that owns a facility), sentinels7.gd job board / QRF / stand-to, wallwalk7 manning, garrison.gd, turret crews,
   base_state7 lockdown reactions, squad_ai / combat idle chase for units standing at the facility, command_net. How a
   CN unit is recognised: e.cn_team, defs g7_cn_* / g7_op_* (and B builds), their APCs (threats7.gd:790 has a predicate;
   reuse or centralise one helper). Post the audit on the board.
2. Fix each path so no automatic system assigns them defence; at the facility between missions they hold (no chase /
   sally; return fire only where they stand). Player direct orders still work (B16 override). Deterministic; no facility /
   no CN units = no cost.
3. Tests tests/test_cnrole7.gd: base attacked while teams are home -> no CN unit gets a defence / garrison / QRF / wall
   job and none leaves its post to chase; LP defence commander + garrison + Sentinels ignore them; a launched mission
   still runs; player order still obeyed; hash twice-same. Keep test_cnfac7, test_lpmode7, test_sent7, test_apcmov7,
   test_ai*, test_wallwalk7 green (never weaken).
Files: the systems you need to touch, but FACB7-7 owns cn_facility.gd, APCMOV7-4 owns fac_drive7.gd / movement.gd gates:
change_request those. world.gd / combat.gd / entity_layer.gd: change_request to ORCH. Others are free (no live owner):
post a fact on the board naming each file before you edit it.
