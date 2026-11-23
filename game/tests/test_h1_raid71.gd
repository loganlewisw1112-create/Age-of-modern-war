extends "res://tests/test_base.gd"
## Done-when 8: multi-phase core raid ends in purge success OR a reported failed phase.

const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const Director71 = preload("res://sim/systems/director71.gd")
const Cores = preload("res://sim/systems/cores.gd")


func test_core_raid_reaches_failed_or_done() -> void:
	var c := LastProtocol.make_config(119, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 25:
		w.step()
	var s: Dictionary = w.sys_state.lp
	s.dread = 0.95
	s.core_raid = {}
	LastProtocol._core_raid_tick(w, s)
	check_eq(String(s.core_raid.get("phase", "")), "recon", "raid opens at recon")
	var every := int(ceil(float(Director71.rules().get("core_raid_phase_s", 45.0)) * float(SimWorld.TICK_RATE)))
	# Advance through recon -> soften -> breach -> purge -> failed (no core kill).
	for expect in ["soften", "breach", "purge", "failed"]:
		s.core_raid.t0 = w.tick - every - 1
		LastProtocol._core_raid_tick(w, s)
		check_eq(String(s.core_raid.get("phase", "")), expect, "raid phase -> %s" % expect)
	check_eq(String(s.core_raid.get("failed", "")), "purge", "failed phase reported as purge")
	var saw_fail := false
	for o in LastProtocol.hud(w).objectives:
		if String(o.get("kind", "")) == "core_raid_fail":
			saw_fail = true
	check(saw_fail, "failed raid opens a regroup objective")


func test_core_raid_done_when_core_dies() -> void:
	var c := LastProtocol.make_config(120, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 20:
		w.step()
	var s: Dictionary = w.sys_state.lp
	s.dread = 0.95
	s.core_raid = {}
	LastProtocol._core_raid_tick(w, s)
	var core_id := int(s.core_raid.get("core", -1))
	check(core_id >= 0 and w.entities.has(core_id), "raid locked a live core")
	for core in Cores.list(w):
		Cores.finish(w, int(core.ix), int(s.fid))
	check_eq(Cores.alive_count(w), 0, "all cores finished")
	LastProtocol._core_raid_tick(w, s)
	check_eq(String(s.core_raid.get("phase", "")), "done", "raid ends done after core wipe")
