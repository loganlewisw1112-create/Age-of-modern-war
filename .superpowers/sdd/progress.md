# Pre-G10 SDD Progress Ledger

Branch: g71
Plan: docs/superpowers/plans/2026-11-23-pre-g10.md
Scope: game/docs/PRE_G10_SCOPE.md
Started: 2026-11-23


Task 0: complete (commits dd4fe7d0..b8ca436d, review approved; Important seam fix in flight)

Task 0 seam fix: 6e75a381 (machine_ew7 exclusive COMBAT9+)

Task 1: complete (commits 6e75a381..e61e20fc, review clean after Content-backed ≥60 fix)

Task 2: review blockers fixed (production command routes for all 13, causal power sabotage, command-only decapitation, soft coalition restore)
    Focused verification: test_count9 14/0
    Addendum frozen: Hive network + Warmind + PACE71 in scope/plan/board

Addendum scaffold checkpoint:
    PACE71: implemented shared movement multiplier; skirmish+LP focused test 1/0
    Warmind: doctrine/budget/counter-memory/readable intent; test_warmind71 3/0
    Hive network: quality/topology/shared senses/creep cable/dead-zone cuts; test_hive9 6/0
    Movement gold regression suite: historical gold/hash expectations fail because global pace intentionally changes hashes; parity subtests observed passing; overlong run stopped at 232s during native_on_off parity

Tasks 3-4 complete:
    COMBAT9+: forts, EW, crew bail/recrew, wear/breakdown/recovery, multi-class ballistics; test_combat9 10/0
    SKIRM9+: setup toggle + capped siege attack-move; test_skirm9 5/0

Tasks 6-10 complete:
    AI9 adaptation, five named generals, diplomacy, intelligence-only difficulty and phased operations; test_ai9 5/0
    Warmind remains green; test_warmind71 3/0

Tasks 11-15 complete:
    rare_metals gathering, location-mix trade, territory/civilian support, tiered research and black market; test_econ9 5/0

Tasks 16-17 complete:
    coalition soak formed/broke truce deterministically
    PACE71 GOLD/GOLD_FLAT refreshed from two identical independent captures
    test_hot_state 17/0; expanded smoke 33 suites green when the interrupted wrapper was completed in isolated/remainder runs
    peak remasure p10 116.8; README/PLAY_ME/PRE_G10_SCOPE synchronized

Lock: CLOSED (`pre_g10.lock`). Package/push recorded in the ORCH report and board.
