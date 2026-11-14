extends RefCounted
## G7.1 AIRFIX71 playtest (windowed, Done-when 2 packaged flow): a real skirmish match; a helipad, a VTOL dropship pad, a
## FARP and a CN facility (stealth dropship helipad + Vanta roof pad) beside the HQ. Each of the 4 craft types is sent
## off its pad with low fuel and must come back and land centred on its own pad (screenshot of each landed craft); a
## second helicopter homed on the taken helipad must hold beside it with the AirPadBusy alert (screenshot); a helicopter
## homed on the FARP lands there and is hot-pit serviced with rotors turning (air_hot, screenshot).
## Screenshots: airfix71_*.png.
const Air = preload("res://sim/systems/air.gd")
const Pads71 = preload("res://sim/systems/pads71.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Vanta7 = preload("res://sim/systems/vanta7.gd")
const Movement = preload("res://sim/systems/movement.gd")


func _near_open(w: SimWorld, c: Vector2i, size: int) -> Vector2i:
	for r in range(0, 30):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var o := c + Vector2i(dx, dy)
				var ok := true
				for yy in range(-1, size + 1):
					for xx in range(-1, size + 1):
						var q := o + Vector2i(xx, yy)
						if not w.in_bounds(q) or not Terrain.buildable(w.terrain_at(q)) or preload("res://sim/systems/construction.gd").building_at_cell(w, q):
							ok = false
				if ok:
					return o
	return c


## Sends craft id off its pad with low fuel (Vanta: vanta_rtb) and waits until it lands; true + its pad distance.
func _return(pt, w: SimWorld, mv, id: int, label: String, max_s: float = 50.0) -> Array:
	mv.join_sim()
	var e: Dictionary = w.entities[id]
	var f: Dictionary = Air._ensure(w, e)
	Air.sync71(w)
	var hk := Air.home71(w, e)
	if bool(e.get("air_landed", false)):
		Air._lift(w, e, f)
	e.pos = Vector2(clampf(e.pos.x + 12.0, 3.0, w.map.w - 4.0), clampf(e.pos.y - 9.0, 3.0, w.map.h - 4.0))
	Movement.stop_path(e)
	e.order = {"type": "idle"}
	var d := Air.adef(e)
	if bool(d.get("cn_vanta", false)):
		w.submit({"type": "vanta_rtb", "unit_ids": [id], "issuer": int(e.owner)})
	else:
		e.fuel = 0.15 * float(d.get("fuel_max", 100.0))
	var t := 0.0
	while t < max_s:
		await pt._wait(0.5)
		t += 0.5
		if not w.entities.has(id) or bool(w.entities[id].get("air_landed", false)):
			break
	var landed: bool = w.entities.has(id) and bool(w.entities[id].get("air_landed", false))
	var dd := Vector2(w.entities[id].pos).distance_to(Pads71.pos_of(w, hk)) if w.entities.has(id) and hk != "" else -1.0
	var tol := maxf(0.75, float(Pads71.pad(w, hk).get("s", 1.5)) * 0.5) if String(Pads71.pad(w, hk).get("k", "")) == "farp" else 0.75
	pt._log("airfix71_%s_lands_on_pad" % label, landed and dd >= 0.0 and dd <= tol, "landed=%s pad=%s d=%.2f t=%.1fs" % [str(landed), hk, dd, t])
	if w.entities.has(id):
		mv.center_camera_on(Vector2(w.entities[id].pos))
	await pt._wait(0.6)
	await pt._shot("airfix71_%s_landed" % label)
	return [landed, dd, hk]


func run(pt) -> void:
	var cfg := SimWorld.default_config()
	cfg.sides[1].ai = false
	if not pt.main.start_match(cfg):
		pt._log("airfix71_start", false, "start_match failed")
		return
	await pt._wait(2.0)
	var mv = pt._mv()
	var w: SimWorld = pt._w()
	mv.join_sim()
	var hq = mv._player_hq()
	var base: Vector2i = Vector2i(hq.cell) if hq != null else w.cell_of(Vector2(w.factions[0].spawn))
	w.factions[0].credits = 200000
	for k in ["salvage", "ore", "fuel", "ammo"]:
		w.factions[0].stock[k] = 200000
	var hp := w.spawn_building("a_helipad", 0, _near_open(w, base + Vector2i(9, 4), 3), true)
	var vp := w.spawn_building("a_g7_vtol_pad", 0, _near_open(w, base + Vector2i(9, 11), 4), true)
	var fp := w.spawn_building("a_g71_farp", 0, _near_open(w, base + Vector2i(16, 4), 4), true)
	var off: Array = CnFacility.conf().core_offset
	var fac_o := _near_open(w, base + Vector2i(-26, 6), 18)
	w.spawn_building("a_cn_facility", 0, fac_o + Vector2i(int(off[0]), int(off[1])), true)
	await pt._wait((CnFacility.DISCOVER_EVERY + 4) / 20.0 + 0.5)
	mv.join_sim()
	var ids := {}
	ids.heli = w.spawn_unit("a_attack_heli", 0, Vector2(w.entities[hp].pos))
	ids.vtol = w.spawn_unit("a_vtol_dropship", 0, Vector2(w.entities[vp].pos))
	var fs: Array = CnFacility.facilities(w, 0)
	if not fs.is_empty():
		var F := CnFacility.fac(w, int(fs[0]))
		CnFacility._finish_train(w, F, "stealth_dropship")
		ids.cn = int(F.get("heli", -1))
		var rp := Vanta7.pad_of(w, int(fs[0]))
		if not rp.is_empty():
			ids.vanta = w.spawn_unit("cn_vanta_a", 0, Vector2(rp.centre) + Vector2(3, 3))
	pt._log("airfix71_setup_four_craft", ids.size() == 4 and int(ids.get("cn", -1)) > 0, "ids=%s" % str(ids))
	await pt._wait(1.0)
	mv.join_sim()
	if w.entities.has(int(ids.vtol)):
		Air.land_now(w, w.entities[int(ids.vtol)])
	Air.sync71(w)
	mv.center_camera_on(Vector2(base) + Vector2(8, 6))
	mv.camera.set_zoom_level(1.4)
	await pt._wait(0.6)
	await pt._shot("airfix71_pads_overview")
	for ty in ["heli", "vtol", "cn", "vanta"]:
		if ids.has(ty) and w.entities.has(int(ids[ty])):
			await _return(pt, w, mv, int(ids[ty]), ty)
		else:
			pt._log("airfix71_%s_lands_on_pad" % ty, false, "no %s in the match" % ty)
	# ---- taken pad: a second helicopter homed on the (occupied) helipad holds beside it with an alert
	mv.join_sim()
	var h2 := w.spawn_unit("a_attack_heli", 0, Vector2(w.entities[hp].pos) + Vector2(-10, -8))
	await pt._wait(0.3)
	mv.join_sim()
	var hk := "af:%d" % hp
	var cap := int(Pads71.pad(w, hk).get("cap", 1))
	for i in cap - 1:   # fill every other slot of the helipad (the first heli sits on one)
		var fx := w.spawn_unit("a_attack_heli", 0, Pads71.pos_of(w, hk))
		var ex: Dictionary = w.entities[fx]
		var ff: Dictionary = Air._ensure(w, ex)
		if not bool(ex.get("air_landed", false)):
			ex.pos = Pads71.pos_of(w, hk)
			Air._lift(w, ex, ff)
			Air.land71(w, ex, ff, hk)
	pt._log("airfix71_taken_pad_full", not Pads71.is_free(w, hk, Air._sorted(Air.flights(w)), h2), "cap=%d" % cap)
	Pads71.set_home(w, h2, hk)
	var e2: Dictionary = w.entities[h2]
	var f2: Dictionary = Air._ensure(w, e2)
	if bool(e2.get("air_landed", false)):
		Air._lift(w, e2, f2)
	e2.fuel = 0.15 * float(Air.adef(e2).get("fuel_max", 100.0))
	var busy := false
	var t := 0.0
	while t < 30.0:
		await pt._wait(0.5)
		t += 0.5
		if Air.flight(w, h2).has("hold71") and Vector2(e2.pos).distance_to(Air.flight(w, h2).hold71) <= 3.0:
			busy = true
			break
	var hold_d := Vector2(e2.pos).distance_to(Vector2(w.entities[hp].pos))
	pt._log("airfix71_taken_pad_holds_beside", busy and hold_d > 1.5 and not bool(e2.get("air_landed", false)), "holding=%s d_pad=%.2f" % [str(busy), hold_d])
	mv.center_camera_on(Vector2(w.entities[hp].pos))
	await pt._wait(1.0)
	await pt._shot("airfix71_taken_pad_holding")
	# ---- FARP hot-pit: a helicopter homed on the FARP lands there, rotors turning while serviced
	mv.join_sim()
	var h3 := w.spawn_unit("a_attack_heli", 0, Vector2(w.entities[fp].pos))
	await pt._wait(0.3)
	mv.join_sim()
	Pads71.set_home(w, h3, "farp:%d" % fp)
	var e3: Dictionary = w.entities[h3]
	if Air.adef(e3).has("ammo_max"):
		e3.ammo = 0
	var r3: Array = await _return(pt, w, mv, h3, "farp")
	var hot := false
	t = 0.0
	while t < 4.0 and bool(r3[0]):
		if bool(e3.get("air_hot", false)):
			hot = true
			break
		await pt._wait(0.1)
		t += 0.1
	pt._log("airfix71_farp_hot_pit", hot, "air_hot=%s" % str(hot))
	await pt._shot("airfix71_farp_hot_pit")
