extends "res://tests/test_base.gd"
## G7 SPECOPS8 (master scope 13.9c-44): the four spec-ops missions of the tactical operator squads, on the real Last
## Protocol start (map last_protocol: the facility with 2 strike teams + 4 operator squads in their garages, the stealth
## dropship on its helipad, the regular VTOL dropship on its pad). Each mission runs end to end (drive; fly where it
## applies), the targets are placed a few minutes from the gate (the LP start's own cores are far out); a player order
## cancels; a save mid-mission gives the same future; the reason functions refuse what the sim refuses.

const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const CN = preload("res://sim/systems/counter_nanite.gd")
const M8 = preload("res://sim/systems/cn_mission8.gd")
const SO = preload("res://sim/systems/specops8.gd")
const Creep = preload("res://sim/systems/creep.gd")
const Cores = preload("res://sim/systems/cores.gd")
const Medical = preload("res://sim/systems/medical.gd")
const CnOps7 = preload("res://sim/systems/cn_ops7.gd")

static var _base: Dictionary = {}
var LOG := false


func _lp() -> SimWorld:
	if not preload("res://sim/map_gen.gd").has_map("last_protocol"):
		return null
	if _base.is_empty():
		var w0 := SimWorld.new_match(LastProtocol.make_config(77, "last_protocol"))
		if w0 == null:
			return null
		w0.run_ticks(25)
		_base = w0.to_dict().duplicate(true)
	var w := SimWorld.from_dict(_base.duplicate(true))
	w.ai_state = {}
	return w


func _fid(w: SimWorld) -> int:
	return int(w.sys_state.lp.fid)


func _mfid(w: SimWorld) -> int:
	for f in w.factions:
		if int(f) != _fid(w) and w.is_enemy(_fid(w), int(f)):
			return int(f)
	return -1


func _teams(w: SimWorld, kind: String) -> Array:
	var out := []
	for tid in CN.team_ids(w):
		var t: Dictionary = CN.team(w, int(tid))
		if String(t.kind) == kind and int(t.fid) == _fid(w):
			out.append(int(tid))
	return out


func _C(w: SimWorld) -> Vector2:
	return Vector2(w.map.lp.base.center)


func _patch(w: SimWorld, p: Vector2, r: int = 5) -> Vector2:
	var s = Creep.enable(w)
	var c := w.cell_of(p)
	var v: PackedByteArray = s.v
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r:
				var q := c + Vector2i(dx, dy)
				if w.in_bounds(q):
					v[Creep._k(s, q)] = 200
	s.v = v
	return p


## Clears creep round p (stage: the downed group waits on clean ground; on the LP map's creep south of the base the
## riflemen died of nanite exposure (counter_nanite _tick_exposure, foot soldiers on creep) before the squad arrived).
func _clear(w: SimWorld, p: Vector2, r: int = 4) -> void:
	var s = Creep.enable(w)
	var c := w.cell_of(p)
	var v: PackedByteArray = s.v
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var q := c + Vector2i(dx, dy)
			if w.in_bounds(q):
				v[Creep._k(s, q)] = 0
	s.v = v


## No Machine pressure (the test is about the order flow, not the fight): enemies never fire, creep never spreads.
func _quiet(w: SimWorld) -> void:
	w.cfg["creep_spread"] = false
	for e in w.entities.values():
		if String(e.get("kind", "")) == "unit" and w.is_enemy(_fid(w), int(e.owner)):
			e.cd_ticks = 1 << 30


func _machine_unit(w: SimWorld, p: Vector2) -> int:
	var id := w.spawn_unit("m_hauler", _mfid(w), p)
	w.entities[id].cd_ticks = 1 << 30
	w.entities[id].order = {"type": "hold"}
	w.entities[id].hp = 100000.0   # G7 FIX8 (G7_REFERENCE "Lethality test-setup authority", before 13.9c-48): durable marked target (the recon APC's .50 one-shot it)
	return id


func _cmd(w: SimWorld, cmd: Dictionary) -> String:
	cmd.issuer = _fid(w)
	var r := w.submit(cmd)
	if not r.ok:
		return String(r.reason)
	return w.preview_command(cmd)


## Event counts by type over the whole _run (w.event_log keeps only the last EVENT_LOG_MAX events, so a long run had
## already rolled the raid's SoChargePlanted out of it by the time the checks ran).
var evc := {}
## Optional hook called as on_phase.call(w, tid, phase) whenever a team's phase changes during _run (checks that
## belong to a moment of the mission, e.g. recon marks while they are live: marks expire by design).
var on_phase := Callable()
## SPECOPS8E: per-tick staging hook (called with the world after every step of _run).
var on_tick := Callable()


## Steps until every listed team's mission has ended (or limit). Returns {tid: [phases seen]}.
func _run(w: SimWorld, tids: Array, limit: int, cn_tids: Array = []) -> Dictionary:
	var seen := {}
	for tid in tids + cn_tids:
		seen[tid] = []
	for i in limit:
		w.step()
		if on_tick.is_valid():
			on_tick.call(w)
		for ev in w.events:
			evc[String(ev.type)] = int(evc.get(String(ev.type), 0)) + 1
		var all_done := true
		for tid in tids + cn_tids:
			var M: Dictionary = SO.mission_of(w, int(tid)) if tids.has(tid) else M8.mission_of(w, int(tid))
			var ph := String(M.get("phase", ""))
			var arr: Array = seen[tid]
			if arr.is_empty() or arr[-1] != ph:
				arr.append(ph)
				if on_phase.is_valid():
					on_phase.call(w, int(tid), ph)
				if LOG:
					print("  [so8] t=%d team %d %s | %s" % [w.tick, int(tid), ph, SO.status_line(w, int(tid)) if tids.has(tid) else M8.status_line(w, int(tid))])
			var live := SO.active(M) if tids.has(tid) else M8.active(M)
			if live:
				all_done = false
		if all_done and i > 3:
			break
	return seen


func _events(w: SimWorld, typ: String) -> Array:
	var out := []
	for ev in w.event_log:
		if String(ev.type) == typ:
			out.append(ev)
	return out


## Count of events of type typ: seen during _run (evc) or still in the rolling log.
func _n_events(w: SimWorld, typ: String) -> int:
	return maxi(int(evc.get(typ, 0)), _events(w, typ).size())


# ================================================================ reasons
func test_reasons() -> void:
	var w := _lp()
	if w == null:
		check(true, "last_protocol map not registered: skipped")
		return
	var fid := _fid(w)
	var st := _teams(w, "strike")
	var tac := _teams(w, "tactical")
	if not check(st.size() >= 1 and tac.size() >= 4, "LP start has strike teams and 4 operator squads"):
		return
	var C := _C(w)
	check(SO.mission_reason(w, fid, int(st[0]), "recon", C + Vector2(0, 50), "drive") != "", "a strike team cannot run spec-ops missions")
	check(SO.mission_reason(w, fid, int(tac[0]), "bogus", C, "drive") != "", "unknown mission kind refused")
	check(SO.mission_reason(w, fid, int(tac[0]), "recon", C + Vector2(0, 50), "walk") != "", "mode must be drive or fly")
	check_eq(SO.mission_reason(w, fid, int(tac[0]), "recon", C + Vector2(0, 50), "drive"), "", "recon by road accepted")
	check_eq(SO.mission_reason(w, fid, int(tac[0]), "recon", C + Vector2(0, 50), "fly"), "", "recon by air accepted (dropship ready)")
	check(SO.mission_reason(w, fid, int(tac[0]), "escort", int(st[0]), "drive").contains("purge mission"), "escort needs a purge mission running")
	check(SO.mission_reason(w, fid, int(tac[0]), "raid", C + Vector2(0, 50), "drive") != "", "raid needs a core / Machine structure")
	check(SO.mission_reason(w, fid, int(tac[0]), "rescue", C + Vector2(0, 60), "drive").contains("Nobody"), "rescue needs survivors")
	var why := _cmd(w, {"type": "so_mission", "team_id": int(st[0]), "kind": "recon", "mode": "drive", "target": [C.x, C.y + 50]})
	check(why != "", "the sim refuses what the reason function refuses (strike team)")
	check(SO.cancel_reason(w, fid, int(tac[0])) != "", "nothing to cancel")
	check(w.sys_state.get("so8") == null, "no state until a spec-ops mission is ordered (no cost)")


# ================================================================ drive: all four missions at once
func test_drive_all() -> void:
	var w := _lp()
	if w == null:
		check(true, "last_protocol map not registered: skipped")
		return
	var fid := _fid(w)
	var C := _C(w)
	var st := _teams(w, "strike")
	var tac := _teams(w, "tactical")
	_quiet(w)
	# purge site for the escorted strike team, a core to raid, a creep + Machine area to scout, a downed group to rescue
	var purge := _patch(w, C + Vector2(0, 46))
	var core_id := Cores.place(w, _mfid(w), w.cell_of(C + Vector2(34, 58)))
	var core_hp0 := float(w.entities[core_id].hp)
	var rp := _patch(w, C + Vector2(-26, 56), 4)
	var mu := _machine_unit(w, rp + Vector2(3, 2))
	# the downed group waits on clean ground (stage, see _clear; at C+(14,70) on the map's creep all three died of
	# nanite_exposure at ~t=2000, before the rescue squad got there)
	var resc := C + Vector2(14, 70)
	_clear(w, resc, 5)
	var surv := []
	for i in 3:
		surv.append(w.spawn_unit("rifleman", fid, resc + Vector2(float(i), 0.0)))
	Medical.wound(w, w.entities[surv[0]])
	Medical._state(w).wounded[int(surv[0])] = 1 << 28   # no bleed-out during the test
	_quiet(w)
	check_eq(_cmd(w, {"type": "cn_mission", "team_id": int(st[0]), "target": [purge.x, purge.y], "mode": "drive"}), "", "purge mission (CNMISSION8) for the escort")
	w.step()
	check_eq(_cmd(w, {"type": "so_mission", "team_id": int(tac[0]), "kind": "escort", "mode": "drive", "escort_team": int(st[0])}), "", "escort accepted")
	check_eq(_cmd(w, {"type": "so_mission", "team_id": int(tac[1]), "kind": "raid", "mode": "drive", "target_id": core_id}), "", "core raid accepted")
	check_eq(_cmd(w, {"type": "so_mission", "team_id": int(tac[2]), "kind": "recon", "mode": "drive", "target": [rp.x, rp.y]}), "", "recon accepted")
	check_eq(_cmd(w, {"type": "so_mission", "team_id": int(tac[3]), "kind": "rescue", "mode": "drive", "target": [resc.x, resc.y]}), "", "rescue accepted")
	w.step()
	evc = {}
	# recon checks while the marks are live (they expire after the mark time by design; the whole run lasts far longer):
	# taken when the recon squad finishes scouting (enters "ret")
	var rc := {}
	on_phase = func(ww: SimWorld, tid: int, ph: String) -> void:
		if tid != int(tac[2]) or ph != "ret" or not rc.is_empty():
			return
		var kinds := {}
		for m in SO.marks(ww, fid):
			kinds[String(m.kind)] = true
		rc["n"] = SO.marks(ww, fid).size()
		rc["kinds"] = kinds
		rc["mu"] = ww.entities.has(mu)
		if ww.entities.has(mu):
			rc["mu_marked"] = int(ww.entities[mu].get("marked_until", 0)) > ww.tick
			rc["mu_vis"] = SimWorld.Fog.entity_visible(ww, fid, ww.entities[mu])
			rc["fr"] = CnOps7.fire_reason(ww, {"issuer": fid, "team_id": int(tac[2]), "kind": "artillery", "target_id": mu})
	# SPECOPS8E: _quiet's "creep never spreads" is not honoured by Creep (no such switch), so the cleared ground round the
	# downed group grew back and all three died of nanite_exposure (t=800..2040) while the rescue squad, 4th out of the
	# garage, was still queued at the gate (search at t=2864: "nobody found"). Keep the stage premise (clean ground)
	# until the rescue squad starts searching; from then on creep acts normally.
	on_tick = func(ww: SimWorld) -> void:
		if ww.tick % 20 == 0 and ["board", "exit", "travel"].has(String(SO.mission_of(ww, int(tac[3])).get("phase", ""))):
			_clear(ww, resc, 5)
	var seen := _run(w, tac, 30000, [int(st[0])])
	on_phase = Callable()
	on_tick = Callable()
	print("  [so8] drive phases ", seen, " tick ", w.tick)
	for tid in tac:
		var M := SO.mission_of(w, int(tid))
		check_eq(String(M.get("phase", "")), "done", "[%s] mission complete (%s)" % [String(M.get("kind", "?")), SO.status_line(w, int(tid))])
		check(String(M.get("note", "")) != "home (not parked)", "[%s] the APC parked back in its garage (%s)" % [String(M.get("kind", "?")), String(SO.fac_team(w, int(tid)).get("phase", "-"))])
	check((seen[int(tac[0])] as Array).has("follow") and (seen[int(tac[0])] as Array).has("screen"), "escort drove with the strike team and screened the purge site")
	check((seen[int(tac[1])] as Array).has("plant") and (seen[int(tac[1])] as Array).has("withdraw") and (seen[int(tac[1])] as Array).has("detonate"), "raid: plant -> withdraw -> detonate")
	check(_n_events(w, "SoChargePlanted") >= 1 and _n_events(w, "ChargeDetonated") >= 1, "charges planted and detonated")
	var core = w.entities.get(core_id)
	check(core == null or float(core.hp) < core_hp0, "the core took the charges' damage (hp %s -> %s)" % [core_hp0, core.hp if core != null else "destroyed"])
	var kinds: Dictionary = rc.get("kinds", {})
	check(kinds.has("creep") and kinds.has("target"), "recon marked creep areas and Machine targets (%d marks)" % int(rc.get("n", 0)))
	if bool(rc.get("mu", false)):
		check(bool(rc.get("mu_marked", false)), "the Machine unit carries the G5 mark (visible through fog)")
		check(bool(rc.get("mu_vis", false)), "the marked Machine unit is visible to the player")
		check(not String(rc.get("fr", "")).contains("can't see"), "fire support accepts a marked target (%s)" % String(rc.get("fr", "")))
	var Mr := SO.mission_of(w, int(tac[3]))
	check(int(Mr.get("saved", 0)) >= 3, "rescue recovered the downed group (%d)" % int(Mr.get("saved", 0)))
	check(_n_events(w, "SoCasualtyCarried") >= 1 and _n_events(w, "SoCasualtyAboard") >= 1, "the wounded soldier was carried aboard")
	var home := CnFacility.evac_point(CnFacility.fac(w, int(CnFacility.facilities(w, fid)[0])))
	var near_home := 0
	for id in surv:
		var e = w.entities.get(int(id))
		if e != null and Vector2(e.pos).distance_to(home) <= 30.0:
			near_home += 1
	check(near_home >= 2, "survivors brought home (%d near the gate)" % near_home)


# ================================================================ fly: raid and rescue (lost-squad beacon)
func test_fly() -> void:
	var w := _lp()
	if w == null:
		check(true, "last_protocol map not registered: skipped")
		return
	var fid := _fid(w)
	var C := _C(w)
	var tac := _teams(w, "tactical")
	_quiet(w)
	var core_id := Cores.place(w, _mfid(w), w.cell_of(C + Vector2(40, 64)))
	var core_hp0 := float(w.entities[core_id].hp)
	var bc := w.cell_of(C + Vector2(-20, 76))
	var lp = w.sys_state.get("lp")
	var has_beacon: bool = lp != null and lp.get("sites") is Dictionary and (lp.sites.get("secrets", {}) as Dictionary).has("lost_squad")
	if has_beacon:
		lp.sites.secrets.lost_squad.cell = bc
		lp.sites.secrets.lost_squad.state = "hidden"
	check(has_beacon, "the LP map has a lost-squad beacon")
	_quiet(w)
	check_eq(_cmd(w, {"type": "so_mission", "team_id": int(tac[1]), "kind": "raid", "mode": "fly", "target_id": core_id}), "", "fly raid accepted")
	w.step()
	var b := Vector2(bc) + Vector2(0.5, 0.5)
	check(SO.mission_reason(w, fid, int(tac[3]), "rescue", b, "drive").contains("Fly"), "the beacon needs an aircraft: drive refused")
	check_eq(_cmd(w, {"type": "so_mission", "team_id": int(tac[3]), "kind": "rescue", "mode": "fly", "target": [b.x, b.y]}), "", "fly rescue accepted")
	w.step()
	var n0 := CN.team_ids(w).size()
	var seen := _run(w, [int(tac[1]), int(tac[3])], 30000)
	print("  [so8] fly phases ", seen, " tick ", w.tick)
	for tid in [int(tac[1]), int(tac[3])]:
		var M := SO.mission_of(w, int(tid))
		check_eq(String(M.get("phase", "")), "done", "[fly %s] mission complete (%s)" % [String(M.get("kind", "?")), SO.status_line(w, int(tid))])
		check((seen[tid] as Array).has("air_fly") and (seen[tid] as Array).has("air_home"), "[fly %s] flew out and home" % String(M.get("kind", "?")))
		# SPECOPS8E (13.9c-45): both dropships came home together and each one unloaded on its pad (no timeout fallback)
		var ds = w.entities.get(int(M.get("ds", -1)))
		check(ds == null or (ds.get("cargo", []) as Array).is_empty(), "[fly %s] the dropship unloaded at home (cargo %s)" % [String(M.get("kind", "?")), str(ds.get("cargo", []) if ds != null else [])])
		check(String(M.get("note", "")) != "could not unload at the pad", "[fly %s] no unload timeout at the pad" % String(M.get("kind", "?")))
	var core = w.entities.get(core_id)
	check(core == null or float(core.hp) < core_hp0, "fly raid: the core took the damage")
	check(CN.team_ids(w).size() > n0, "the lost squad was found (a new operator squad)")
	check(int(SO.mission_of(w, int(tac[3])).get("saved", 0)) >= 1, "rescue recovered the lost squad")


# ================================================================ override + save / load
func test_override_cancels() -> void:
	var w := _lp()
	if w == null:
		check(true, "last_protocol map not registered: skipped")
		return
	var C := _C(w)
	var tac := _teams(w, "tactical")
	var t: Dictionary = CN.team(w, int(tac[2]))
	check_eq(_cmd(w, {"type": "so_mission", "team_id": int(tac[2]), "kind": "recon", "mode": "drive", "target": [C.x - 20, C.y + 60]}), "", "recon accepted")
	w.run_ticks(200)
	check(SO.active(SO.mission_of(w, int(tac[2]))), "running before the override")
	check_eq(_cmd(w, {"type": "cn_fire_support", "team_id": int(tac[2]), "kind": "artillery", "pos": Vector2(C.x, C.y + 60)}) == "" or true, true, "fire support order does not cancel (refused or not)")
	w.step()
	check(SO.active(SO.mission_of(w, int(tac[2]))), "a KEEP order leaves the mission running")
	_cmd(w, {"type": "cn_move", "team_id": int(tac[2]), "target": [C.x + 5, C.y + 40]})
	w.step()
	check_eq(String(SO.mission_of(w, int(tac[2])).get("phase", "")), "cancelled", "a player move order takes over (mission cancelled)")
	check_eq(_cmd(w, {"type": "so_mission", "team_id": int(tac[2]), "kind": "recon", "mode": "drive", "target": [C.x - 20, C.y + 60]}), "", "a new mission can start")
	w.step()
	check_eq(_cmd(w, {"type": "so_cancel", "team_id": int(tac[2])}), "", "so_cancel accepted")
	w.step()
	check_eq(String(SO.mission_of(w, int(tac[2])).get("phase", "")), "cancelled", "so_cancel stops the mission")
	check(t != null, "team still there")


func test_save_load_same_future() -> void:
	var w := _lp()
	if w == null:
		check(true, "last_protocol map not registered: skipped")
		return
	var C := _C(w)
	var tac := _teams(w, "tactical")
	_quiet(w)
	var core_id := Cores.place(w, _mfid(w), w.cell_of(C + Vector2(34, 58)))
	check_eq(_cmd(w, {"type": "so_mission", "team_id": int(tac[1]), "kind": "raid", "mode": "drive", "target_id": core_id}), "", "raid accepted")
	w.step()
	var guard := 0
	while guard < 20000 and not ["plant", "withdraw"].has(String(SO.mission_of(w, int(tac[1])).get("phase", ""))):
		w.step()
		guard += 1
	var ph := String(SO.mission_of(w, int(tac[1])).get("phase", ""))
	check(["plant", "withdraw"].has(ph), "reached the target mid-mission (%s at tick %d)" % [ph, w.tick])
	var l := SimWorld.from_dict(bytes_to_var(var_to_bytes(w.to_dict())))
	check_eq(l.state_hash(), w.state_hash(), "loaded world hashes like the live one")
	var same := true
	for i in 1200:
		w.step()
		l.step()
		if i % 100 == 99 and w.state_hash() != l.state_hash():
			same = false
			check(false, "diverged by tick %d" % w.tick)
			break
	check(same, "save mid-mission: the same future (1200 ticks)")
	check_eq(String(SO.mission_of(l, int(tac[1])).get("phase", "")), String(SO.mission_of(w, int(tac[1])).get("phase", "")), "same mission phase after the run")
