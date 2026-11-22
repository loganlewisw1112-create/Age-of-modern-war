extends RefCounted
## G7.1 CNOPS71 B7 VANTA2 playtest (windowed, Last Protocol seed 77): a Vanta from the barracks roof pad, flown by
## orders only (w.submit, the same path as a right-click):
##   vanta71_1_cruise.png   lifted and sent 30 tiles south: at cruise, the motion trail behind it
##   vanta71_2_bank.png     a hard turn mid-flight: banked (wing line tilted), the trail curving
##   vanta71_3_strafe.png   attack order on a Machine (its fire held): a strafing pass, the twin front MGs firing
##   vanta71_4_coast.png    a stop order at cruise: it coasts on (momentum) before the hover
## Logged checks: cruise reached, bank seen in the turn, strafing passes through the target, front MG shots (ml / mr),
## still moving 0.2 s after the stop. Forced by the flow: explored fog, the Machine target's fire held.
const MapGen = preload("res://sim/map_gen.gd")
const V7 = preload("res://sim/systems/vanta7.gd")

var pt
var fid := 0
var vid := -1


func _w() -> SimWorld:
	return pt._w()


func _e() -> Dictionary:
	var e = _w().entities.get(vid)
	return e if e != null else {}


func _spd() -> float:
	var fv = V7.rec(_w(), vid).get("fv", [0.0, 0.0])
	return Vector2(float(fv[0]), float(fv[1])).length()


func _shot_on(name: String) -> void:
	var e := _e()
	if e.is_empty():
		pt._log(name, false, "the Vanta is gone")
		return
	pt._mv().center_camera_on(Vector2(e.pos))
	var sp: float = pt._mv().speed
	pt._mv().speed = 0.0
	await pt._wait(0.35)
	await pt._shot(name)
	pt._mv().speed = sp


func _order(cmd: Dictionary) -> void:
	cmd.issuer = fid
	cmd.unit_ids = [vid]
	_w().submit(cmd)


func run(p_) -> void:
	pt = p_
	if not MapGen.has_map("last_protocol"):
		pt._log("vanta71_map", false, "last_protocol map not registered")
		return
	var started: bool = pt.main.start_match(SimWorld.LastProtocol.make_config(77, "last_protocol"))
	pt._log("vanta71_match_started", started, "Last Protocol, seed 77")
	if not started:
		return
	var ok: bool = await pt._wait_until(func(): return _w().sys_state.has("lp") and bool(_w().sys_state.lp.get("filled", false)), 60.0)
	pt._log("vanta71_facility_filled", ok, "facility filled at tick %d" % _w().tick)
	if not ok:
		return
	pt._mv().join_sim()
	var w := _w()
	var s: Dictionary = w.sys_state.lp
	fid = int(s.fid)
	var ex: PackedByteArray = w.fog[fid].explored
	ex.fill(1)
	w.fog[fid].explored = ex
	var C := Vector2(s.base.center)
	pt._log("vanta71_rules", not V7.V2().is_empty(), "rules.g71_cn.vanta2 %s" % str(V7.V2().keys().size()))
	vid = w.spawn_unit("cn_vanta_a", fid, C + Vector2(0, 8))
	await pt._wait(0.5)
	pt._log("vanta71_registered", not V7.rec(_w(), vid).is_empty(), "Vanta %d on pad %s" % [vid, str(V7.rec(_w(), vid).get("fac", 0))])
	var cruise := float(Content.unit("cn_vanta_a").speed) * V7.v2f("cruise_mult", 1.0)
	_order({"type": "move", "target": C + Vector2(0, 38)})
	var top := 0.0
	ok = await pt._wait_until(func():
		top = maxf(top, _spd())
		return _spd() >= 0.95 * cruise, 30.0)
	pt._log("vanta71_cruise", ok, "speed %.2f of cruise %.2f (G7 speed %.2f)" % [_spd(), cruise, float(Content.unit("cn_vanta_a").speed)])
	await pt._wait(0.6)
	await _shot_on("vanta71_1_cruise")
	# a hard right turn
	var p := Vector2(_e().pos)
	_order({"type": "move", "target": p + Vector2(-14, 6)})
	var bank := 0.0
	ok = await pt._wait_until(func():
		bank = maxf(bank, absf(float(_e().get("vt_bank", 0.0))))
		return bank >= 15.0, 6.0)
	pt._log("vanta71_bank", ok, "max bank %.1f deg in the turn" % bank)
	await _shot_on("vanta71_2_bank")
	# strafing run on a Machine
	var mf := int(s.get("mfid", -1))
	var mdef := ""
	for e in _w().entities.values():
		if String(e.get("kind", "")) == "unit" and int(e.owner) == mf:
			mdef = String(e.def)
			break
	if mdef == "":
		pt._log("vanta71_target", false, "no Machine unit def")
		return
	var tid := _w().spawn_unit(mdef, mf, C + Vector2(10, 44))
	var tg: Dictionary = _w().entities[tid]
	tg.cd_ticks = 1 << 30
	tg.hp = 1e9
	_order({"type": "attack", "target_id": tid})
	var passes := 0
	var close := false
	var mg := {}
	var t0 := _w().tick
	var shot_done := false
	while _w().tick - t0 < 20 * 40:
		await pt.get_tree().process_frame
		for ev in _w().events:
			if String(ev.get("type", "")) == "ShotFired" and int(ev.get("shooter", -1)) == vid and ["ml", "mr"].has(String(ev.get("vt", ""))):
				mg[String(ev.vt)] = true
		var d := Vector2(_e().get("pos", Vector2.ZERO)).distance_to(Vector2(tg.pos))
		if d <= 3.0 and not close:
			close = true
			passes += 1
			if passes == 2 and not shot_done:
				shot_done = true
				await _shot_on("vanta71_3_strafe")
		elif d >= 6.0:
			close = false
		if passes >= 3 and mg.size() == 2:
			break
	pt._log("vanta71_strafe", passes >= 2, "%d passes through the target in %.1f s" % [passes, float(_w().tick - t0) / 20.0])
	pt._log("vanta71_twin_mg", mg.has("ml") and mg.has("mr"), "front MG mounts firing %s" % str(mg.keys()))
	if not shot_done:
		await _shot_on("vanta71_3_strafe")
	# momentum: stop at cruise
	_order({"type": "move", "target": C + Vector2(-20, 30)})
	await pt._wait_until(func(): return _spd() >= 0.9 * cruise, 10.0)
	var s0 := _spd()
	_order({"type": "stop"})
	await pt._wait(0.2)
	pt._log("vanta71_momentum", _spd() > 0.4 * s0, "speed %.2f -> %.2f 0.2 s after stop" % [s0, _spd()])
	await _shot_on("vanta71_4_coast")
