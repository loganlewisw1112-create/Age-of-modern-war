extends Node2D
## G7 ATMO7 (13.9c-7): facility atmosphere, wear, signage and damage, plus the display-only time of day. Display only:
## it never writes the sim (state hash identical with it on / off: tests/test_atmo7.gd). The facility is read through
## CnFacility.render_entries (a throttled read, never while a sim step is in flight), the render snapshot (statics hp)
## and events (CnLockdown, CnFacilityLost); never mv.world per frame.
##  1. Alarm (lockdown / breached ONLY, owner 13.9c-17; amber when contested, under fire or on a launch_alert): red rotating beacons on
##     every tower and gate, flashing wall lamps chasing round the ring, tower searchlights sweeping the approaches,
##     blast-door shutters sliding down over the visible garage / building doors, blast shields rising round the
##     helipad, the decon zone flooding with counter-nanite mist.
##  2. Time of day (Settings "Time of day": day / dusk / night; default day, Last Protocol dusk): a multiply tint over
##     the world under the fx, then additive lights above it: tower floodlight pools, lamp pools, door lamps, light
##     spilling from garage doors (LIFE7 door_open when present), pad edge lights blinking, base building lights.
##  3. Generator exhaust, roof / ground vent steam, drifting decon mist, a windsock and flags moving with the wind.
##  4. Ground wear: tyre tracks and wet asphalt after the APC wash, oil stains on pads / bays, hazard stripes round the
##     wash and pads, garage bay numbers and the unit crest on the aprons.
##  5. Signage: building name boards, gate numbers, STOP / SLOW stencils, lane arrows, warning boards.
##  6. Damage: cracks / smoke / fire on towers, walls, checkpoint and core by their snapshot hp, the zone buildings by
##     the core's hp, rubble where a part was destroyed, the whole compound a smouldering ruin after CnFacilityLost.
## Wiring (ORCH change_request): add after baseprops_layer, z_index 0, setup(self); refresh(snap) every frame next to
## baseprops_layer.refresh; on_events(evs) in _on_step_events. Unwired (auto = true) it pulls mv.snap itself.
## A match without a facility at day draws nothing and costs one cheap call per frame.

const ViewUtil = preload("res://presentation/view/view_util.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const ArtCat = preload("res://presentation/art/art_catalog.gd")
const SettingsMenu = preload("res://presentation/menu/settings.gd")

const ART_DIR := "res://assets/art/g7_atmo7/"
const TODS := ["day", "dusk", "night"]
const TOD_AMT := {"day": 0.0, "dusk": 0.5, "night": 1.0}
const DUSK := Color(0.86, 0.70, 0.64)
const NIGHT := Color(0.27, 0.31, 0.50)
## Heights in screen px at zoom 1 above the ground point (calibrated on the ART7F sprites, see pt7_atmo7 shots).
const WALL_Z := 44.0
const TOWER_Z := 110.0   # ATMO7-2: FACB7-2 tower cupola top 11.44 m x 9.8 px/m (was 132: beacons floated ~22 px above)
## POLISH7-2 (13.9c-14, owner: "fix the floating RED LIGHT warning lights ... not hovering at all"): every alarm light
## stands on a real fixture at FACB7's own heights (tools/art/g7_fac7f.gd + fact facb7.zone_heights, 9.8 px per m).
const PX_M := 9.8
const TOWER_ROOF_Z := 10.84 * PX_M   # tower roof slab top (tower_piece: slab z 10.72 + 0.12, half width 2.15 m)
const BEACON_OFF := Vector2(0.475, -0.475)   # on that slab's right (+x, -y, screen-right) corner, clear of the cupola ring
const SEARCH_OFF := Vector2(0.44, 0.36)   # the tower searchlight head (1.75, 1.45, 11.05) m
const SEARCH_Z := 11.05 * PX_M
const WALL_CAP_Z := 3.78 * PX_M      # blast wall capping beam top (_wall_kit: 3.68 + 0.1), on the segment's centre line
const GATE_CAP_Z := 5.85 * PX_M      # gate bastion cap top (gate_layer: 5.7 + 0.15), bastion centre ey - 1.3 m across
const CP_PARAPET_Z := 5.6 * PX_M     # checkpoint roof parapet top (gatehouse: 5.42 + 0.18)
const CP_BEACON := Vector2(0.9625, -0.5)   # on the checkpoint's east parapet, (3.85, -2.0) m from its centre
const LAMP_HOUSING := Color(0.16, 0.16, 0.17)
const MAST_COL := Color(0.22, 0.22, 0.24)
const DOOR_Z := 30.0
const BLD_Z := {"planning": 70.0, "lab": 60.0, "workshop": 74.0, "drone_bay": 56.0, "decon_hall": 50.0, "core": 70.0,
	"magazine": 38.0, "armory": 41.0, "aid_station": 37.0, "ready_room": 71.0, "barracks": 71.0}   # ATMO7-2: FACB7-2 facb7.zone_heights x 9.8 px/m
const PART_FOOT := {"cn_tower": 2, "cn_blast_wall": 2, "cn_checkpoint": 2, "a_cn_facility": 4}
const PART_Z := {"cn_tower": 100.0, "cn_blast_wall": 40.0, "cn_checkpoint": 51.0, "a_cn_facility": 70.0}
const FIRE_COL := Color(1.0, 0.55, 0.18)
const MIST_COL := Color(0.78, 0.96, 0.92)

var mv = null
var map: Dictionary = {}
var hm: Dictionary = {}
var off := OS.get_environment("ATMO7_OFF") == "1"
var auto := false                 # true: _process pulls mv.snap / snap.events itself (no match_view wiring yet)
var t := 0.0                      # display clock (s)
var night := 0.0                  # eased 0..1 (0 day, 0.5 dusk, 1 night)
var wind := Vector2(1, 0)         # world-space wind direction (display only, from the map)
var facs: Array = []              # last CnFacility.render_entries
var geo: Array = []               # per facility: derived drawing geometry (see _geom)
var counts: Dictionary = {}       # last frame's draw counters (tests / playtest probes)
var on_screen := false            # some facility (or ruin) is in view this frame

var props: Node2D                 # z 2, under the entities: windsock, flags, back blast shields
var over: Node2D                  # z 3, over the entities: smoke, steam, mist, fire, cracks, beacons, shutters
var dark: Node2D                  # z 3, multiply: the time-of-day tint
var glow: Node2D                  # z 3, additive: every light
var _spr: Dictionary = {}         # sprite id -> {tex, pivot, fw, fh, frames}
var _fac_key := ""
var _frame := 0
var _fac_frame := -999
var _tod_override := ""
var _night_drawn := -1.0
var _alarm: Dictionary = {}       # fid -> {lvl, red, t_on, lock_t, lock}
var _alert: Dictionary = {}       # fid -> display time a launch alert ends
var _ruins: Array = []            # [{g (geometry), t0}]
var _parts: Dictionary = {}       # static id -> [def, cell Vector2, size, fid]
var _gone: Array = []             # [{cell, size, def, t0}]
var _dmg: Array = []              # [{p (ground screen), z, size, h, def, seed}]
var _zone_dmg: Dictionary = {}    # fid -> core hp 0..1
var _stat_tick := -1
var _blds: Array = []             # base building lights: [tile pos, size]
var _blds_n := -1
var _ev_tick := -1
var _wired_ev := false
var _snap: Dictionary = {}
var _vr := Rect2()


func setup(view) -> void:
	mv = view
	map = view.world.map if view != null and view.get("world") != null else {}
	hm = ViewUtil.height_map_of(map) if not map.is_empty() else {}
	var hs := absi(hash(Vector3i(int(map.get("w", 64)), int(map.get("h", 64)), int(map.get("seed", 7)))))
	wind = Vector2.RIGHT.rotated(float(hs % 6283) / 1000.0)
	_load_art()
	props = _child("Atmo7Props", 2, -1)
	over = _child("Atmo7Over", 3, -1)
	dark = _child("Atmo7Dark", 3, CanvasItemMaterial.BLEND_MODE_MUL)
	glow = _child("Atmo7Glow", 3, CanvasItemMaterial.BLEND_MODE_ADD)
	props.draw.connect(func(): _timed("props", _draw_props))
	over.draw.connect(func(): _timed("over", _draw_over))
	dark.draw.connect(_draw_dark)
	glow.draw.connect(func(): _timed("glow", _draw_glow))
	set_process(auto)
	visible = not off


## CPU cost of each redrawn canvas (smoothed us; playtest / profiling only, no effect on what is drawn).
var prof: Dictionary = {}
func _timed(nm: String, f: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	f.call()
	prof[nm] = float(prof.get(nm, 0.0)) * 0.9 + float(Time.get_ticks_usec() - t0) * 0.1


func _child(nm: String, z: int, blend: int) -> Node2D:
	var n := Node2D.new()
	n.name = nm
	n.z_index = z
	if blend >= 0:
		var m := CanvasItemMaterial.new()
		m.blend_mode = blend
		n.material = m
	add_child(n)
	return n


func _load_art() -> void:
	var p := ART_DIR + "manifest.json"
	if not FileAccess.file_exists(p):
		return
	var man = JSON.parse_string(FileAccess.get_file_as_string(p))
	if not (man is Dictionary):
		return
	var a: Dictionary = (man as Dictionary).get("atmo7", {})
	for k in a:
		var e: Dictionary = a[k]
		var tx := ArtCat._texture(ART_DIR + String(e.file))
		if tx == null:
			continue
		var fw := int(e.get("fw", e.get("w", 1)))
		var fh := int(e.get("fh", e.get("h", 1)))
		_spr[k] = {"tex": tx, "pivot": Vector2(float(e.pivot[0]), float(e.pivot[1])), "fw": fw, "fh": fh, "frames": int(e.get("frames", 1))}


# =============================================================== public API
## Settings "Time of day" (graphics / time_of_day): day | dusk | night. Unset: day, Last Protocol dusk.
func time_of_day() -> String:
	if _tod_override != "":
		return _tod_override
	var v = null
	if (SettingsMenu.DEFAULTS.graphics as Dictionary).has("time_of_day") or SettingsMenu._c().has_section_key("graphics", "time_of_day"):
		v = SettingsMenu.get_value("graphics", "time_of_day")
	if v != null and TODS.has(String(v)):
		return String(v)
	return "dusk" if map.has("lp") else "day"


func set_time_of_day(s: String) -> void:
	_tod_override = s if TODS.has(s) else ""


func night_amount() -> float:
	return night


## 0 none, 0.5 amber (contested / under fire / launch alert), 1 red (lockdown / breached only: owner 13.9c-17).
func alarm_level(fac_id: int) -> float:
	var a: Dictionary = _alarm.get(fac_id, {})
	return float(a.get("lvl", 0.0))


## SEQ7: amber beacons on fac_id for secs (a launch). Display only.
func launch_alert(fac_id: int, secs: float) -> void:
	_alert[fac_id] = maxf(float(_alert.get(fac_id, 0.0)), t + secs)


# =============================================================== frame
func _process(dt: float) -> void:
	if auto and mv != null:
		var sn = mv.get("snap")
		if sn is Dictionary:
			if not _wired_ev and int((sn as Dictionary).get("tick", -1)) != _ev_tick:
				_ev_tick = int(sn.get("tick", -1))
				on_events(sn.get("events", []), true)
			refresh(sn)


func on_events(evs: Array, from_snap := false) -> void:
	if not from_snap:
		_wired_ev = true
	for ev in evs:
		var ty := String(ev.get("type", ""))
		if ty == "CnLockdown":
			var fid := int(ev.get("fac", -1))
			var a: Dictionary = _alarm.get(fid, {})
			a["lock"] = bool(ev.get("on", false))
			a["ev_t"] = t
			_alarm[fid] = a
			_fac_frame = -999   # re-read the entries next frame
		elif ty == "CnFacilityLost":
			_lose(int(ev.get("id", -1)))
		elif ty == "CnFacilityRaised":
			_fac_frame = -999


func refresh(snap: Dictionary) -> void:
	if mv == null or off:
		return
	var t0 := Time.get_ticks_usec()
	_refresh(snap)
	prof["refresh"] = float(prof.get("refresh", 0.0)) * 0.9 + float(Time.get_ticks_usec() - t0) * 0.1


func _refresh(snap: Dictionary) -> void:
	var dt := clampf(get_process_delta_time(), 0.0, 0.1) if is_inside_tree() else 1.0 / 60.0
	t += dt
	_frame += 1
	_snap = snap
	# facility entries: re-read every 15 frames (a facility changes slowly), never while a sim step is in flight
	if _frame - _fac_frame >= 15 and not (mv.has_method("sim_busy") and mv.sim_busy()):
		_fac_frame = _frame
		var w = mv.get("world")
		var fe: Array = CnFacility.render_entries(w) if w != null and CnFacility.active(w) else []
		var key := str(fe.size())
		for F in fe:
			key += "|%d,%s,%s,%d,%s" % [int(F.id), str(F.lock), str(F.state), int(F.heli), str(F.compound)]
		if key != _fac_key:
			_fac_key = key
			for F0 in facs:   # a facility that vanished without its event (loaded mid-way, events unwired): ruin it
				var still := false
				for F1 in fe:
					still = still or int(F1.id) == int(F0.id)
				if not still:
					_lose(int(F0.id))
			facs = fe
			_rebuild()
	_alarms()
	var st_tick := int(snap.get("tick", -1))
	if (not geo.is_empty() or not _ruins.is_empty()) and st_tick != _stat_tick and (_frame % 6 == 0 or _stat_tick < 0):
		_stat_tick = st_tick
		_statics(snap.get("statics", {}))
	# time of day
	var target: float = TOD_AMT.get(time_of_day(), 0.0)
	night = move_toward(night, target, dt * 0.5)
	var vp := get_viewport()
	_vr = vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect() if vp != null else Rect2()
	if night > 0.004 and int(snap.get("tick", 0)) % 30 == 0:
		_base_lights(snap.get("statics", {}))
	on_screen = false
	for g in geo:
		on_screen = on_screen or _vr.intersects(g.bbox)
	for r in _ruins:
		on_screen = on_screen or _vr.intersects(r.g.bbox)
	var nchg := absf(night - _night_drawn) > 0.01
	if nchg:
		_night_drawn = night
		dark.queue_redraw()
	dark.visible = night > 0.004
	if on_screen:   # ATMO7-2: animated canvases at 30 Hz, staggered (props + over on even frames, glow on odd)
		if _frame % 2 == 0:
			props.queue_redraw()
			over.queue_redraw()
		else:
			glow.queue_redraw()
	elif nchg or (night > 0.004 and _frame % 30 == 0):
		glow.queue_redraw()


func _alarms() -> void:
	for g in geo:
		var fid := int(g.id)
		var a: Dictionary = _alarm.get(fid, {})
		var st := String(g.F.state)
		var lock := bool(a.get("lock", g.F.lock)) if t - float(a.get("ev_t", -99.0)) < 1.0 else bool(g.F.lock)
		var red := lock or st == "breached"   # POLISH7-2 (13.9c-17): full lockdown look only on lock / breach
		var amber := st == "contested" or st == "under_fire" or float(_alert.get(fid, 0.0)) > t
		var lvl := 1.0 if red else (0.5 if amber else 0.0)
		if lvl > 0.0 and float(a.get("lvl", 0.0)) <= 0.0:
			a["t_on"] = t
		if lock != bool(a.get("lock_on", false)):
			a["lock_on"] = lock
			a["lock_t"] = t
		a["lvl"] = lvl
		a["red"] = red
		_alarm[fid] = a


# =============================================================== geometry
## ATMO7-2: memoised (the ground-lift lookup was most of the per-frame draw cost; nearly every point drawn is static).
var _isoc: Dictionary = {}
func _iso(p: Vector2) -> Vector2:
	if hm.is_empty():
		return ViewUtil.iso(p)
	var c = _isoc.get(p)
	if c != null:
		return c
	var s := ViewUtil.iso(p)
	s.y -= ViewUtil.ground_lift(hm, p)
	if _isoc.size() >= 8192:
		_isoc.clear()
	_isoc[p] = s
	return s


func _rect(a) -> Rect2:
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3])) if a is Array and (a as Array).size() == 4 else Rect2()


func _rebuild() -> void:
	geo = []
	var C: Dictionary = CnFacility.conf()
	for F in facs:
		geo.append(_geom(F, C))
	queue_redraw()
	props.queue_redraw()
	over.queue_redraw()
	glow.queue_redraw()


## Everything that stays put while the facility stands, in tile space.
func _geom(F: Dictionary, C: Dictionary) -> Dictionary:
	var cr := _rect(F.compound)
	var O := cr.position
	var cs := cr.size.x
	var Z: Dictionary = {}
	for zn in F.zones:
		Z[zn] = _rect(F.zones[zn])
	var ctr := cr.get_center()
	var g := {"id": int(F.id), "F": F, "O": O, "cs": cs, "ctr": ctr, "zones": Z, "owner": int(F.owner)}
	var top := _iso(Vector2(cr.position.x, cr.position.y))
	var bb := Rect2(top, Vector2.ZERO)
	for q in [Vector2(cr.end.x, cr.position.y), cr.end, Vector2(cr.position.x, cr.end.y)]:
		bb = bb.expand(_iso(q))
	g.bbox = bb.grow_individual(80, 200, 80, 60)
	# towers (2x2) and the wall ring lamps (every 2-tile wall section, gates excluded)
	var towers := []
	for tw in C.get("towers", []):
		towers.append(O + Vector2(float(tw[0]) + 1.0, float(tw[1]) + 1.0))
	g.towers = towers
	var lamps := []
	var icsz := int(cs)
	var reserved := [_rect(C.get("gate_outer", [0, 0, 0, 0]))]
	for tw in C.get("towers", []):
		reserved.append(Rect2(float(tw[0]), float(tw[1]), 2, 2))
	var cp: Array = C.get("checkpoint", [0, 0])
	reserved.append(Rect2(float(cp[0]), float(cp[1]), 2, 2))
	var ring := []
	for x in range(0, icsz, 2):
		ring.append(Vector2(x, 0))
	for y in range(2, icsz - 2, 2):
		ring.append(Vector2(icsz - 2, y))
	for x in range(icsz - 2, -1, -2):
		ring.append(Vector2(x, icsz - 2))
	for y in range(icsz - 4, 1, -2):
		ring.append(Vector2(0, y))
	for i in ring.size():
		var r := Rect2(ring[i], Vector2(2, 2))
		var clash := false
		for rs in reserved:
			clash = clash or r.grow(-0.1).intersects(rs)
		if not clash:
			lamps.append([O + r.get_center(), i])
	g.lamps = lamps
	g.checkpoint = O + Vector2(float(cp[0]) + 1.0, float(cp[1]) + 1.0)
	# garages: [rect, door face (+x 0 / -x 2), index]
	var gar := []
	var grs: Array = F.get("garage_rects", [])
	for i in grs.size():
		var r := _rect(grs[i])
		gar.append([r, 0 if r.get_center().x < ctr.x else 2, i])
	g.garages = gar
	# doors of the zone buildings on a visible face (+x / +y): [zone, face 0 / 1, centre along the face, face line]
	var doors := []
	var dc: Dictionary = C.get("doors", {})
	var fcs: Dictionary = F.get("faces", {})
	for zn in dc:
		if not Z.has(zn) and zn != "core":
			continue
		if zn in ["planning", "lab"] and Z.has(zn):   # POLISH7: shutters on FACB7's own door geometry
			var zf := int(fcs[zn]) if fcs.has(zn) else -1
			if zf < 0:   # no faces entry: the conf door's face (the side FACB7 draws the door on, like entity_layer)
				for d in dc[zn]:
					var dq := O + Vector2(float(d[0]), float(d[1]))
					if absf(dq.x - (Z[zn] as Rect2).end.x) < 0.01:
						zf = 0
					elif absf(dq.y - (Z[zn] as Rect2).end.y) < 0.01:
						zf = 1
			for fd in _facb7_doors(zn, Z[zn], zf):
				doors.append(fd)
			continue
		var zr: Rect2 = Z.get(zn, Rect2(O + Vector2(float(C.core_offset[0]), float(C.core_offset[1])), Vector2(4, 4)))
		for d in dc[zn]:
			var dp := O + Vector2(float(d[0]), float(d[1]))
			if absf(dp.x - zr.end.x) < 0.01:
				doors.append([zn, 0, dp.y + 0.5, zr.end.x])
			elif absf(dp.y - zr.end.y) < 0.01:
				doors.append([zn, 1, dp.x + 0.5, zr.end.y])
	g.doors = doors
	# smoke / steam emitters: [tile pos, z, kind]
	var em := []
	if Z.has("planning"):
		var r: Rect2 = Z.planning
		em.append([Vector2(r.end.x - 0.6, r.position.y + 0.7), BLD_Z.planning * 0.55, "exhaust"])   # TOC generator
	if Z.has("workshop"):
		var r: Rect2 = Z.workshop
		em.append([Vector2(r.position.x + 1.0, r.position.y + 1.0), BLD_Z.workshop + 4.0, "exhaust"])
		em.append([Vector2(r.position.x + 1.6, r.position.y + 0.9), BLD_Z.workshop + 4.0, "exhaust"])
	if Z.has("lab"):
		var r: Rect2 = Z.lab
		em.append([Vector2(r.position.x + 1.2, r.position.y + 0.8), BLD_Z.lab + 8.0, "steam"])
	if Z.has("decon_hall"):
		var r: Rect2 = Z.decon_hall
		em.append([Vector2(r.get_center().x, r.position.y + 0.8), BLD_Z.decon_hall + 2.0, "steam"])
	var vents := []
	for zn in ["decon_hall", "lab", "apc_wash"]:   # ground vent grates beside the wet buildings
		if Z.has(zn):
			var r: Rect2 = Z[zn]
			var vp := Vector2(r.end.x + 0.35, r.end.y - 0.5) if zn != "apc_wash" else Vector2(r.position.x - 0.35, r.get_center().y)
			vents.append(vp)
			em.append([vp, 2.0, "vent"])
	g.vents = vents
	for zn2 in ["magazine", "fuel_point", "fuel", "ready_room"]:   # FACB7's new buildings: backup generator exhaust
		if Z.has(zn2):
			var r: Rect2 = Z[zn2]
			em.append([Vector2(r.end.x - 0.5, r.position.y + 0.5), 34.0, "exhaust"])
			break
	g.emit = em
	# decon mist areas
	var mist := []
	for zn in ["apc_wash", "decon_hall"]:
		if Z.has(zn):
			mist.append(Z[zn])
	g.mist = mist
	g.flood = [Z.get("apc_wash", Rect2()), Z.get("decon_hall", Rect2()), Z.get("staging", Rect2()), Z.get("gate_inner", Rect2())]
	# windsock and flags
	var hp: Rect2 = Z.get("helipad", Z.get("pad", Rect2(ctr, Vector2(1, 1))))
	g.windsock = Vector2(hp.end.x - 0.3, hp.position.y + 0.35)   # helipad's far corner: nothing stands in front of it
	var core := Rect2(O + Vector2(float(C.core_offset[0]), float(C.core_offset[1])), Vector2(4, 4))   # flags in front of the HQ
	g.core_r = core
	# POLISH7: two poles on the open lane in front of the HQ entrance (door cell core_offset + (1, 4) on the +y face),
	# 0.75 tile out, beside the walkway: clear of LIFE7's ops inset (east) and of the comms mast in the lane; drawn on
	# the over layer (_draw_flags) so the HQ canopy behind them never covers the poles.
	g.flags = [Vector2(core.position.x + 0.9, core.end.y + 0.75), Vector2(core.position.x + 1.45, core.end.y + 0.75)]
	# lights: [pos, kind]: flood pools in front of the towers, door lamps, pad edge lights
	var lt := []
	for tc in towers:
		var inn: Vector2 = (ctr - tc).normalized()
		lt.append([tc + inn * 2.6, "flood"])
	for d in doors:
		var dp := Vector2(float(d[3]) + 0.25, float(d[2])) if int(d[1]) == 0 else Vector2(float(d[2]), float(d[3]) + 0.25)
		lt.append([dp, "door"])
	var edge := []
	for zn in ["pad", "helipad"]:
		if not Z.has(zn):
			continue
		var r: Rect2 = Z[zn]
		var k := 0
		for x in range(0, int(r.size.x) + 1):
			edge.append([Vector2(r.position.x + x, r.position.y), zn, k]); k += 1
		for y in range(1, int(r.size.y) + 1):
			edge.append([Vector2(r.end.x, r.position.y + y), zn, k]); k += 1
		for x in range(int(r.size.x) - 1, -1, -1):
			edge.append([Vector2(r.position.x + x, r.end.y), zn, k]); k += 1
		for y in range(int(r.size.y) - 1, 0, -1):
			edge.append([Vector2(r.position.x, r.position.y + y), zn, k]); k += 1
	g.lights = lt
	g.edge = edge
	return g


## Ruin a facility that is gone (its event, or it vanished from the entries).
func _lose(fid: int) -> void:
	for i in range(geo.size() - 1, -1, -1):
		if int(geo[i].id) == fid:
			_ruins.append({"g": geo[i], "t0": t})
			geo.remove_at(i)
	queue_redraw()


## Facility parts' hp from the snapshot statics (towers, walls, checkpoint, core); a part that disappears while its
## facility stands leaves rubble. Throttled (every 6 frames, new ticks only).
func _statics(stats: Dictionary) -> void:
	var seen := {}
	_dmg = []
	_zone_dmg = {}
	for id in stats:
		var s: Dictionary = stats[id]
		var def := String(s.get("def", ""))
		var sz: int = PART_FOOT.get(def, 0)
		if sz == 0:
			continue
		var cell := Vector2(s.get("cell", Vector2i.ZERO))
		var fid := -1
		for g in geo:
			if Rect2(g.O - Vector2(1, 1), Vector2(g.cs + 2.0, g.cs + 2.0)).has_point(cell):
				fid = int(g.id)
				if def == "a_cn_facility":
					_zone_dmg[fid] = float(s.get("hp", 1.0))
		if fid < 0:
			continue
		seen[int(id)] = true
		_parts[int(id)] = [def, cell, sz, fid]
		var h := float(s.get("hp", 1.0))
		if h < 0.72:
			_dmg.append({"c": cell + Vector2(sz, sz) * 0.5, "z": float(PART_Z.get(def, 40.0)), "size": sz, "h": h, "def": def, "seed": int(id)})
	var changed := false
	for pid in _parts.keys():
		if not seen.has(pid):
			var pr: Array = _parts[pid]
			var alive := false
			for g in geo:
				alive = alive or int(g.id) == int(pr[3])
			if alive:
				_gone.append({"cell": pr[1], "size": pr[2], "def": pr[0], "t0": t})
				changed = true
			_parts.erase(pid)
	if changed:
		queue_redraw()


func _base_lights(stats: Dictionary) -> void:
	if stats.size() == _blds_n:
		return
	_blds_n = stats.size()
	_blds = []
	for id in stats:
		var s: Dictionary = stats[id]
		if String(s.get("kind", "")) != "building" or not bool(s.get("built", true)) or PART_FOOT.has(String(s.get("def", ""))):
			continue
		var def := String(s.get("def", ""))
		if def.begins_with("cn_") or def.contains("wall") or def.contains("mine"):
			continue
		_blds.append([Vector2(s.get("cell", Vector2i.ZERO)), int(s.get("size", 1))])
		if _blds.size() >= 400:
			break


# =============================================================== sprites
func _sp(id: String, at: Vector2, frame := 0, row := 0, mod := Color.WHITE, sc := 1.0, node: CanvasItem = null) -> bool:
	var e: Dictionary = _spr.get(id, {})
	if e.is_empty():
		return false
	var fw := float(e.fw)
	var fh := float(e.fh)
	var src := Rect2(float(frame % maxi(1, int(e.frames))) * fw, float(row) * fh, fw, fh)
	var dst := Rect2(at - Vector2(e.pivot) * sc, Vector2(fw, fh) * sc)
	(node if node != null else self).draw_texture_rect_region(e.tex, dst, src, mod)
	return true


func _quad(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([_iso(r.position), _iso(Vector2(r.end.x, r.position.y)), _iso(r.end), _iso(Vector2(r.position.x, r.end.y))])


func _cnt(k: String, n := 1) -> void:
	counts[k] = int(counts.get(k, 0)) + n


# =============================================================== ground (z 0, under everything; redrawn on change)
func _draw() -> void:
	for k in ["tracks", "wet", "stripes", "oil", "stencils", "arrows", "signs", "vents", "rubble", "scorch"]:
		counts[k] = 0
	for g in geo:
		_draw_wear(g)
		_draw_marks(g)
		_draw_signs(g)
	for gn in _gone:
		var c: Vector2 = gn.cell + Vector2(gn.size, gn.size) * 0.5
		_sp("scorch", _iso(c), 0, 0, Color(1, 1, 1, 0.8), float(gn.size) * 0.5)
		_sp("rubble%d" % (absi(hash(gn.cell)) % 3), _iso(c) + Vector2(0, -8.0 * float(gn.size) * 0.5), 0, 0, Color.WHITE, float(gn.size) * 0.5)
		_cnt("rubble")
	for r in _ruins:
		_draw_ruin(r.g)


const TRACK := Color(0.06, 0.06, 0.06, 0.40)
const WET := Color(0.05, 0.07, 0.09, 0.42)
const SHEEN := Color(0.62, 0.72, 0.80, 0.55)
const HAZ_Y := Color(0.93, 0.74, 0.12, 0.92)
const HAZ_K := Color(0.08, 0.08, 0.08, 0.92)


func _line_t(a: Vector2, b: Vector2, c: Color, w := 1.0) -> void:
	draw_line(_iso(a), _iso(b), c, w)


func _draw_wear(g: Dictionary) -> void:
	var Z: Dictionary = g.zones
	var go0: Rect2 = Z.get("gate_outer", Rect2())
	if go0.size.x > 0.0:   # the paved approach outside the gate, under the tyre tracks (ATMO7-2: was drawn over them)
		var go := go0
		var ap := Rect2(go.position.x, go.end.y, go.size.x, 3.2)
		draw_colored_polygon(_quad(ap), Color(0.21, 0.22, 0.23, 0.95))
		_line_t(Vector2(ap.position.x + 0.1, ap.position.y), Vector2(ap.position.x + 0.1, ap.end.y), Color(0.9, 0.9, 0.85, 0.7))
		_line_t(Vector2(ap.end.x - 0.1, ap.position.y), Vector2(ap.end.x - 0.1, ap.end.y), Color(0.9, 0.9, 0.85, 0.7))
	var wash: Rect2 = Z.get("apc_wash", Rect2())
	var gin: Rect2 = Z.get("gate_inner", Rect2())
	var gout: Rect2 = Z.get("gate_outer", Rect2())
	var stg: Rect2 = Z.get("staging", Rect2())
	if wash.size.x > 0.0:
		var x0 := wash.position.x
		var xw := wash.size.x
		# wet asphalt: the wash floor, the inner gate and a drying apron into the staging yard (fading strips)
		draw_colored_polygon(_quad(wash), WET)
		if gin.size.x > 0.0:
			draw_colored_polygon(_quad(gin), Color(WET, WET.a * 0.85))
		var y_top := gin.position.y if gin.size.x > 0.0 else wash.position.y
		for k in 5:
			var a := WET.a * (0.75 - 0.14 * float(k))
			draw_colored_polygon(_quad(Rect2(x0 + 0.3 + 0.1 * k, y_top - 0.6 * float(k + 1), xw - 0.6 - 0.2 * k, 0.6)), Color(WET, a))
		_cnt("wet", 7)
		for i in 18:   # sheen streaks on the wet floor
			var hs := absi(hash(Vector2i(int(g.id), i)))
			var p := Vector2(x0 + 0.3 + float(hs % 97) / 97.0 * (xw - 0.6), wash.position.y - 2.5 + float((hs / 97) % 89) / 89.0 * (wash.size.y + 4.0))
			_line_t(p, p + Vector2(0.0, 0.35), Color(SHEEN, SHEEN.a * (0.5 + 0.5 * float((hs / 9973) % 2))))
		# tyre tracks: two lanes (in / out) of paired wheel lines from outside the gate to the staging yard; wet and
		# dark through the wash, fading out on the yard
		var y_end := stg.position.y - 3.0 if stg.size.x > 0.0 else y_top - 5.0   # across the yard into the lane (the inner gate hides the first tiles)
		var y_mud := gout.position.y if gout.size.x > 0.0 else wash.end.y   # outside the outer gate: muddy, not yet washed
		var y_start := (gout.end.y + 1.5) if gout.size.x > 0.0 else wash.end.y + 1.0
		for lane in [-0.62, 0.62]:
			for wheel in [-0.27, 0.27]:
				var x: float = x0 + xw * 0.5 + lane + wheel
				var y := y_start
				var seg := 0
				while y > y_end:
					var y2 := maxf(y - 0.5, y_end)
					var dry := clampf((y_top - y2) / 7.0, 0.0, 1.0)
					var col := Color(TRACK, TRACK.a * (1.0 - dry * 0.7)) if y2 < y_top else Color(0.02, 0.03, 0.04, 0.62)
					if y2 >= y_mud:
						col = Color(0.40, 0.33, 0.23, 0.60)   # ATMO7-2: dark-on-dark was invisible on the apron
					var wob := sin(float(seg) * 0.9 + lane * 3.0) * 0.04
					_line_t(Vector2(x + wob, y), Vector2(x - wob, y2), col, 2.0)   # ATMO7-2: 2 px, read at zoom 1-2.5
					y = y2
					seg += 1
				_cnt("tracks")
		# hazard stripes round the wash bay
		_haz_rect(wash.grow(-0.08))
	for zn in ["pad", "helipad", "fuel_point"]:
		if Z.has(zn):
			_haz_rect(Z[zn].grow(0.22 if zn != "fuel_point" else -0.05), 0.16)
	# oil stains: pads, the staging bays, garage aprons (deterministic per facility)
	var spots := []
	for zn in ["pad", "helipad", "staging"]:
		if Z.has(zn):
			var r: Rect2 = Z[zn]
			for i in int(r.size.x * r.size.y / 5.0):
				var hs := absi(hash(Vector3i(int(g.id), i, zn.length())))
				spots.append(r.position + Vector2(0.5 + float(hs % 101) / 101.0 * (r.size.x - 1.0), 0.5 + float((hs / 101) % 103) / 103.0 * (r.size.y - 1.0)))
	for ga in g.garages:
		var r: Rect2 = ga[0]
		var ap := Vector2(r.end.x + 0.7, r.get_center().y) if int(ga[1]) == 0 else Vector2(r.position.x - 0.7, r.get_center().y)
		spots.append(ap + Vector2(0.15, -0.3))
	for i in spots.size():
		_sp("oil%d" % (i % 3), _iso(spots[i]), 0, 0, Color(1, 1, 1, 0.85), 1.0 + 0.3 * float(i % 2))
	_cnt("oil", spots.size())


## Yellow / black hazard stripes on a band just inside r's edge (diagonal blocks, 0.5 tile each).
func _haz_rect(r: Rect2, band := 0.2) -> void:
	var edges := [[r.position, Vector2(1, 0), r.size.x, Vector2(0, 1)], [Vector2(r.end.x, r.position.y), Vector2(0, 1), r.size.y, Vector2(-1, 0)],
		[r.end, Vector2(-1, 0), r.size.x, Vector2(0, -1)], [Vector2(r.position.x, r.end.y), Vector2(0, -1), r.size.y, Vector2(1, 0)]]
	for e in edges:
		var p0: Vector2 = e[0]
		var d: Vector2 = e[1]
		var n: Vector2 = e[3]
		var L := float(e[2])
		var k := 0
		var s := 0.0
		while s < L - 0.01:
			var s2 := minf(s + 0.35, L)
			var a := p0 + d * s
			var b := p0 + d * s2
			var col := HAZ_Y if k % 2 == 0 else HAZ_K
			draw_colored_polygon(PackedVector2Array([_iso(a), _iso(b), _iso(b + n * band + d * 0.12), _iso(a + n * band + d * 0.12)]), col)
			s = s2
			k += 1
		_cnt("stripes")


func _draw_marks(g: Dictionary) -> void:
	var Z: Dictionary = g.zones
	# garage bay numbers + the unit crest on each apron, reading from the door outward
	for ga in g.garages:
		var r: Rect2 = ga[0]
		var i := int(ga[2])
		var ap := Vector2(r.end.x + 0.75, r.get_center().y) if int(ga[1]) == 0 else Vector2(r.position.x - 0.75, r.get_center().y)
		if _sp("st_n%02d" % (i + 1), _iso(ap + Vector2(0, 0.55)), 0, 0, Color(1, 1, 1, 0.9)):
			_cnt("stencils")
		_sp("crest", _iso(ap + Vector2(0, -0.6)), 0, 0, Color(1, 1, 1, 0.85), 0.75)
	# gates: STOP + gate number outside the outer gate, SLOW + G2 on the yard side of the inner gate, CP at the checkpoint
	var go: Rect2 = Z.get("gate_outer", Rect2())
	if go.size.x > 0.0:   # the paved approach outside the gate (gate width: the serpentine baffles start right of it)
		# ATMO7-2: no footpath / jersey barriers here any more: FACB7's fortified foot entry (13.9c-8) draws the
		# blast-walled serpentine (cn_ecp_baffle) on that ground.
		var c := Vector2(go.get_center().x, go.end.y)
		_sp("st_stop", _iso(c + Vector2(0, 0.9)))
		_sp("st_g1", _iso(c + Vector2(0, 1.9)))
		_line_t(Vector2(go.position.x + 0.2, go.end.y + 0.35), Vector2(go.end.x - 0.2, go.end.y + 0.35), Color(0.92, 0.92, 0.86, 0.85), 2.0)
		_cnt("stencils", 2)
	var gi: Rect2 = Z.get("gate_inner", Rect2())
	if gi.size.x > 0.0:
		var c := Vector2(gi.get_center().x, gi.position.y)
		_sp("st_g2", _iso(c + Vector2(0, -0.8)))
		_sp("st_slow", _iso(c + Vector2(0, -1.8)))
		_cnt("stencils", 2)
	_sp("st_cp", _iso(Vector2(g.checkpoint) + Vector2(0, -1.6)))
	# lane arrows: two-way roads, one arrow per lane every ~5 tiles (keep right)
	for l in (g.F.get("lanes", []) as Array):
		var r := _rect(l)
		var horiz := r.size.x >= r.size.y
		var L := maxf(r.size.x, r.size.y)
		var W := minf(r.size.x, r.size.y)
		if L < 5.0 or W < 2.0:
			continue
		var n := int(L / 5.0)
		for k in n:
			var s := (float(k) + 0.5) * L / float(n)
			for side in [-1, 1]:
				var p := r.position + (Vector2(s, r.size.y * 0.5 + float(side) * W * 0.25) if horiz else Vector2(r.size.x * 0.5 + float(side) * W * 0.25, s))
				var rot := (0 if side > 0 else 2) if horiz else (3 if side > 0 else 1)
				if _sp("arrow%d" % rot, _iso(p), 0, 0, Color(1, 1, 1, 0.8), 0.55):
					_cnt("arrows")
	for v in g.vents:
		_sp("vent", _iso(v))
		_cnt("vents")


## Free-standing boards on posts (drawn before the entities): gate / approach warnings outside the walls, the pad and
## helipad boards at their road-side corners. Building names hang on the facades as plaques (_draw_plaques, over).
func _draw_signs(g: Dictionary) -> void:
	var Z: Dictionary = g.zones
	var items := []
	var go: Rect2 = Z.get("gate_outer", Rect2())
	if go.size.x > 0.0:   # outside the walls: the approach warnings and the gate number
		items.append(["board_gate_outer", Vector2(go.position.x - 0.9, go.end.y + 0.6)])
		items.append(["w_nanite", Vector2(go.position.x - 1.1, go.end.y + 2.5)])
		items.append(["w_force", Vector2(go.position.x - 3.0, go.end.y + 1.4)])
		items.append(["w_speed", Vector2(go.position.x - 0.8, go.end.y + 4.6)])   # vehicles' side, clear of the serpentine
	# ATMO7-2: the foot entry's boards stand clear of FACB7's serpentine (baffles at y + 2 / + 3 from the gatehouse,
	# walk-in leg along the wall from the gate side): ID board east of the gatehouse, STOP SHOW ID at the leg's mouth.
	var cp: Vector2 = g.checkpoint
	items.append(["board_checkpoint", cp + Vector2(-3.0, 4.6)])   # before the walk-in leg's mouth, clear of the baffles
	# (the STOP SHOW ID board went: in the open it stood on the gate apron, and the ECP board says the same)
	if Z.has("pad"):
		var r: Rect2 = Z.pad
		items.append(["board_pad", Vector2(r.end.x - 0.9, r.end.y - 0.3)])   # on the pad's front corner band
		items.append(["w_jet", Vector2(r.position.x + 1.2, r.end.y - 0.3)])
	if Z.has("helipad"):
		var r: Rect2 = Z.helipad
		items.append(["board_helipad", Vector2(r.end.x - 0.9, r.end.y - 0.3)])
		items.append(["w_rotor", Vector2(r.position.x + 1.2, r.end.y - 0.3)])
	if Z.has("fuel_point"):   # FACB7 13.9c-6: hot refuel / rearm marking at the pads
		var r: Rect2 = Z.fuel_point
		items.append(["board_fuel_point", Vector2(r.position.x + 0.2, r.end.y + 0.3)])
		items.append(["w_nosmoke", Vector2(r.end.x - 0.3, r.end.y + 0.3)])
	items.sort_custom(func(a, b): return (a[1] as Vector2).x + (a[1] as Vector2).y < (b[1] as Vector2).x + (b[1] as Vector2).y)
	for it in items:
		if _sp(String(it[0]), _iso(it[1])):
			_cnt("signs")


## Plaque spots on the visible facades: [sprite id, face 0 (+x) / 1 (+y), face line, centre along the face, z].
## A zone's name plaque goes over its door when the door is on a visible face, else in the middle of the +y face;
## its hazard plaque (if any) beside it.
const PLAQUE_WARN := {"range": "w_livefire", "magazine": "w_explosive", "fuel_point": "w_nosmoke", "fuel": "w_nosmoke", "decon_hall": "w_suits", "armory": "w_suits"}
const OPEN_ZONES := ["pad", "helipad", "staging", "apc_wash", "gate_outer", "gate_inner", "fuel_point"]
const INSET := 0.42


func _plaques(g: Dictionary) -> Array:
	if g.has("plaques"):
		return g.plaques
	var out := []
	var Z: Dictionary = g.zones
	var dc: Dictionary = CnFacility.conf().get("doors", {})
	for zn in Z:
		if OPEN_ZONES.has(zn) or not _spr.has("board_" + zn) or not _has_art(zn):
			continue
		var zr: Rect2 = Z[zn]
		var face := 1
		var along := zr.get_center().x
		var z := 26.0
		for d in dc.get(zn, []):
			var dp: Vector2 = g.O + Vector2(float(d[0]), float(d[1]))
			if absf(dp.x - zr.end.x) < 0.01:
				face = 0
				along = dp.y + 0.5
				z = DOOR_Z * 0.8 + 9.0
				break
			if absf(dp.y - zr.end.y) < 0.01:
				face = 1
				along = dp.x + 0.5
				z = DOOR_Z * 0.8 + 9.0
				break
		var line := (zr.end.x if face == 0 else zr.end.y) - INSET
		var lo := (zr.position.y if face == 0 else zr.position.x) + INSET + 0.5
		var hi := (zr.end.y if face == 0 else zr.end.x) - INSET - 0.5
		along = clampf(along, lo, hi)
		var pat := Vector2(line, along) if face == 0 else Vector2(along, line)
		if _plaque_hidden(g, pat, z, float(_spr["board_" + zn].fw), float(_spr["board_" + zn].fh) - 8.0):
			continue   # POLISH7: a tower / the outer wall stands in front of this face (e.g. the magazine's south end)
		out.append(["board_" + zn, face, line, along, z])
		if PLAQUE_WARN.has(zn) and _spr.has(PLAQUE_WARN[zn]):   # beside the name plaque, never overlapping it
			var gap := (float(_spr["board_" + zn].fw) + float(_spr[PLAQUE_WARN[zn]].fw)) * 0.5 / 32.0 + 0.15
			var lo2 := (zr.position.y if face == 0 else zr.position.x) + INSET + float(_spr[PLAQUE_WARN[zn]].fw) / 64.0
			var hi2 := (zr.end.y if face == 0 else zr.end.x) - INSET - float(_spr[PLAQUE_WARN[zn]].fw) / 64.0
			if along + gap <= hi2:
				out.append([PLAQUE_WARN[zn], face, line, along + gap, z])
			elif along - gap >= lo2:
				out.append([PLAQUE_WARN[zn], face, line, along - gap, z])
	g["plaques"] = out
	return out


## POLISH7: true when a tower (2x2, TOWER_Z) or the compound's front (+x / +y) wall strip stands in front of the
## plaque at world point at (z px up, fw x fh px) and covers its middle or either end on screen: the plaques draw on
## the over layer (above the entities), so a covered one would hang over the tower / wall in front of it.
func _plaque_hidden(g: Dictionary, at: Vector2, z: float, fw: float, fh: float) -> bool:
	var s := _iso(at) - Vector2(0, z + fh * 0.5)
	var pts := [s, s + Vector2(-fw * 0.5, 0), s + Vector2(fw * 0.5, 0)]
	var O: Vector2 = g.O
	var cs := float(g.cs)
	var occ := [[Rect2(O + Vector2(cs - 2.0, 0), Vector2(2, cs)), WALL_Z], [Rect2(O + Vector2(0, cs - 2.0), Vector2(cs, 2)), WALL_Z]]
	for tc in g.towers:
		occ.append([Rect2((tc as Vector2) - Vector2(1, 1), Vector2(2, 2)), TOWER_Z])
	for o in occ:
		var r: Rect2 = o[0]
		if at.x >= r.end.x or at.y >= r.end.y or r.has_point(at):
			continue   # in front of it (or on it)
		var q := [_iso(r.position), _iso(Vector2(r.end.x, r.position.y)), _iso(r.end), _iso(Vector2(r.position.x, r.end.y))]
		var up := Vector2(0, -float(o[1]))
		var poly := PackedVector2Array([q[3], q[3] + up, q[0] + up, q[1] + up, q[1], q[2]])
		for pt in pts:
			if Geometry2D.is_point_in_polygon(pt, poly):
				return true
	return false


func _draw_plaques(g: Dictionary) -> void:
	for p in _plaques(g):
		var e: Dictionary = _spr.get(String(p[0]), {})
		if e.is_empty():
			continue
		var face := int(p[1])
		var at := Vector2(float(p[2]), float(p[3])) if face == 0 else Vector2(float(p[3]), float(p[2]))
		var o := _iso(at) - Vector2(0, float(p[4]))
		var fw := float(e.fw)
		var fh := float(e.fh) - 8.0   # the board without its posts
		over.draw_set_transform_matrix(Transform2D(Vector2(1.0, -0.5 if face == 0 else 0.5), Vector2(0, 1), o))
		over.draw_texture_rect_region(e.tex, Rect2(-fw * 0.5, -fh, fw, fh), Rect2(0, 0, fw, fh))
		_cnt("plaques")
	over.draw_set_transform_matrix(Transform2D.IDENTITY)


## True when the zone's building is drawn (FACB7 art present), so plaques / window light never float over a bare slab.
const ZONE_ART := {"planning": "g7_fac_planning", "drone_bay": "g7_fac_dronebay", "workshop": "g7_fac_workshop", "range": "g7_fac_range",
	"lab": "g7_fac_lab", "decon_hall": "g7_fac_deconhall"}
func _has_art(zn: String) -> bool:
	if zn == "core":
		return true
	var b: Dictionary = ArtCat.manifest().get("buildings", {})
	return b.has(ZONE_ART.get(zn, "")) or b.has("g7_fac_" + zn) or b.has("g7_fac_" + zn.replace("_", ""))


## Interior light through the windows at dusk / night: a warm wash up the lower half of each visible facade.
func _facade_light(g: Dictionary, n: float) -> void:
	for zn in g.zones:
		if OPEN_ZONES.has(zn) or zn == "range" or not _has_art(zn):
			continue
		var zr: Rect2 = (g.zones[zn] as Rect2).grow(-INSET)
		var hz := float(BLD_Z.get(zn, 46.0)) * 0.55
		var cw := Color(1.0, 0.80, 0.50, 0.20 * n)
		for face in [0, 1]:
			var a := _iso(Vector2(zr.end.x, zr.position.y) if face == 0 else Vector2(zr.position.x, zr.end.y))
			var b := _iso(zr.end)
			glow.draw_polygon(PackedVector2Array([a, b, b - Vector2(0, hz), a - Vector2(0, hz)]), PackedColorArray([cw, cw, Color(cw, 0.0), Color(cw, 0.0)]))
		_pool(_iso(zr.end + Vector2(0.4, 0.4)), 30.0 + 10.0 * zr.size.x, Color(1.0, 0.8, 0.5, 0.22 * n))


func _draw_ruin(g: Dictionary) -> void:
	# what is left of the roads and pads: cracked, soot-stained asphalt and concrete
	for l in (g.F.get("lanes", []) as Array):
		draw_colored_polygon(_quad(_rect(l)), Color(0.15, 0.15, 0.15, 0.9))
	for zn in ["pad", "helipad", "staging", "apc_wash"]:
		if (g.zones as Dictionary).has(zn):
			var r: Rect2 = g.zones[zn]
			draw_colored_polygon(_quad(r), Color(0.33, 0.32, 0.30, 0.95))
			for k in int(r.size.x * 2.0):   # cracks across the slab
				var hs := absi(hash(Vector3i(int(g.id), k, zn.length())))
				var p := r.position + Vector2(float(hs % 97) / 97.0 * r.size.x, float((hs / 97) % 89) / 89.0 * r.size.y)
				var q := p + Vector2(float((hs / 8633) % 7) / 7.0 - 0.5, float((hs / 60431) % 5) / 5.0) * 0.9
				draw_line(_iso(p), _iso(q), Color(0.1, 0.1, 0.1, 0.8), 1.0)
	var areas := []
	for zn in g.zones:
		if not OPEN_ZONES.has(zn):
			areas.append(g.zones[zn])
	for ga in g.garages:
		areas.append(ga[0])
	areas.append(Rect2(g.O + Vector2(3, 3), Vector2(4, 4)))
	var ai := 0
	for r in areas:
		var rr: Rect2 = (r as Rect2).grow(-0.2)
		draw_colored_polygon(_quad(rr), Color(0.22, 0.21, 0.20, 0.95))   # burnt foundation slab
		_sp("scorch", _iso(rr.get_center()), 0, 0, Color(1, 1, 1, 0.9), maxf(rr.size.x, rr.size.y) * 0.45)
		_cnt("scorch")
		# standing stubs of the walls along the back edges, jagged tops
		for side in [0, 1]:
			var a := rr.position
			var b := Vector2(rr.end.x, rr.position.y) if side == 0 else Vector2(rr.position.x, rr.end.y)
			var segs := int(maxf(rr.size.x, rr.size.y) * 2.0)
			for k in segs:
				var hs := absi(hash(Vector3i(ai, side, k)))
				var hz := float(hs % 18) + 2.0
				if hs % 5 == 0:
					continue
				var p0 := _iso(a.lerp(b, float(k) / float(segs)))
				var p1 := _iso(a.lerp(b, float(k + 1) / float(segs)))
				draw_colored_polygon(PackedVector2Array([p0, p1, p1 - Vector2(0, hz * 0.8), p0 - Vector2(0, hz)]), Color(0.40, 0.39, 0.37) if side == 0 else Color(0.33, 0.32, 0.30))
				draw_line(p0 - Vector2(0, hz), p1 - Vector2(0, hz * 0.8), Color(0.12, 0.11, 0.1), 1.0)
		var nx := maxi(1, int(round(rr.size.x / 1.6)))
		var ny := maxi(1, int(round(rr.size.y / 1.6)))
		for iy in ny:
			for ix in nx:
				var c := rr.position + Vector2((float(ix) + 0.5) * rr.size.x / float(nx), (float(iy) + 0.5) * rr.size.y / float(ny))
				_sp("rubble%d" % ((ix * 7 + iy * 3 + ai) % 3), _iso(c) + Vector2(0, -4), 0, 0, Color.WHITE, 0.95)
				_cnt("rubble")
		ai += 1


# =============================================================== props (z 2, under the entities, animated)
func _wind_strength() -> float:
	return 0.65 + 0.25 * sin(t * 0.37) + 0.1 * sin(t * 1.9)


## POLISH7: the two HQ flag poles stand in front of the HQ (nothing in front of them but the open lane), so they draw
## on the over layer: under props the HQ's own canopy / facade (drawn after props) covered the poles and flags.
func _draw_flags(g: Dictionary) -> void:
	var left := ViewUtil.iso(wind).x < 0.0
	for i in (g.flags as Array).size():
		var fp := _iso(g.flags[i])
		over.draw_line(fp, fp + Vector2(0, -34), Color(0.62, 0.63, 0.65), 1.0)
		over.draw_line(fp + Vector2(1, 0), fp + Vector2(1, -34), Color(0.32, 0.33, 0.35), 1.0)
		over.draw_rect(Rect2(fp + Vector2(-1, -1), Vector2(4, 2)), Color(0.30, 0.31, 0.32))   # footing
		var col: Color = mv.team_color(int(g.owner)) if i == 0 and mv != null and mv.has_method("team_color") else Color.WHITE
		var fr := int(t * (6.0 + 6.0 * _wind_strength()) + float(i) * 2.0) % 6
		over.draw_set_transform(fp + Vector2(1, -34), 0.0, Vector2(-1.0 if left else 1.0, 1.0))
		_sp("flag", Vector2.ZERO, fr, 0 if i == 0 else 1, col, 1.0, over)
		over.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		counts["flags"] += 1


func _draw_props() -> void:
	for g in geo:
		if not _vr.intersects(g.bbox):
			continue
		var ws := _iso(g.windsock)
		var sd := ViewUtil.iso(wind)   # screen direction of the wind
		var d8 := int(round(fposmod(atan2(sd.y / 0.6, sd.x), TAU) / TAU * 8.0)) % 8
		_sp("windsock", ws, int(t * (4.0 + 6.0 * _wind_strength())) % 4, d8, Color.WHITE, 1.0, props)
		# (POLISH7: the HQ flags moved to _draw_flags on the over layer)
		# helipad blast shields, back edges (north / west) rise behind the craft
		var sh := _shield_h(g)
		if sh > 0.5 and g.zones.has("helipad"):
			var r: Rect2 = g.zones.helipad
			_shield(props, Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), sh)
			_shield(props, Vector2(r.position.x, r.position.y), Vector2(r.position.x, r.end.y), sh)


func _shield_h(g: Dictionary) -> float:
	var a: Dictionary = _alarm.get(int(g.id), {})
	if not bool(a.get("lock_on", false)):
		var since := t - float(a.get("lock_t", -99.0))
		return maxf(0.0, 10.0 * (1.0 - since / 1.2)) if since < 1.2 else 0.0
	return 10.0 * clampf((t - float(a.get("lock_t", t - 9.0))) / 1.6, 0.0, 1.0)


func _shield(n: CanvasItem, a: Vector2, b: Vector2, h: float) -> void:
	var L := a.distance_to(b)
	var d := (b - a) / L
	var k := 0
	var s := 0.0
	while s < L - 0.01:
		var s2 := minf(s + 1.0, L)
		var p0 := _iso(a + d * s)
		var p1 := _iso(a + d * s2)
		var up := Vector2(0, -h)
		n.draw_colored_polygon(PackedVector2Array([p0, p1, p1 + up, p0 + up]), Color(0.36, 0.38, 0.40) if k % 2 == 0 else Color(0.31, 0.33, 0.35))
		n.draw_line(p0 + up, p1 + up, Color(0.55, 0.57, 0.58), 1.0)
		n.draw_line(p0 + up * 0.35, p1 + up * 0.35, HAZ_Y, 1.0)
		s = s2
		k += 1


# =============================================================== over (z 3, over the entities)
func _puffs(base: Vector2, n: int, life: float, rise: float, drift: float, size: float, col: Color, seed: int, alpha := 1.0) -> void:
	var sd := ViewUtil.iso(wind).normalized()
	var ws := _wind_strength()
	for i in n:
		var ph := fposmod(t / life + float(i) / float(n) + float(seed % 97) * 0.013, 1.0)
		var jit := float(absi(hash(Vector2i(seed, i))) % 100) / 100.0 - 0.5
		var p := base + sd * drift * ws * ph + Vector2(jit * 6.0 * ph, -rise * ph)
		var a := col.a * alpha * (1.0 - ph) * minf(1.0, ph * 6.0)
		_sp("puff%d" % (i % 3), p, 0, 0, Color(col, a), size * (0.45 + 1.3 * ph), over)
	_cnt("puffs", n)


func _draw_over() -> void:
	for k in ["puffs", "fires", "cracks", "beacons", "shutters", "mist", "plaques", "flags"]:
		counts[k] = 0
	for g in geo:
		if not _vr.intersects(g.bbox):
			continue
		_draw_flags(g)
		# POLISH7-2 (13.9c-14): the masts under FACB7's red obstruction lamps (tower (-1.2, -1.2) m to 12.8 m, checkpoint
		# (3.4, -3.3) m to 7.2 m): the art's 3-6 cm masts vanish at every zoom and the lamp hung in the air
		for k in (g.towers as Array).size():
			if not _hid(g, "t%d" % k):
				var mb := _iso(g.towers[k] + Vector2(-0.3, -0.3))
				over.draw_line(mb - Vector2(0, TOWER_ROOF_Z), mb - Vector2(0, 12.7 * PX_M), MAST_COL, 1.0)
		var cm := _iso(Vector2(g.checkpoint) + Vector2(0.85, -0.825))
		over.draw_line(cm - Vector2(0, 5.24 * PX_M), cm - Vector2(0, 7.1 * PX_M), MAST_COL, 1.0)
		var a: Dictionary = _alarm.get(int(g.id), {})
		var lvl := float(a.get("lvl", 0.0))
		var lock := bool(a.get("lock_on", false))
		# smoke and steam
		var i := 0
		for e in g.emit:
			var gp := _iso(e[0]) - Vector2(0, float(e[1]))
			match String(e[2]):
				"exhaust":
					_puffs(gp, 6, 3.4, 34.0, 26.0, 0.8, Color(0.30, 0.30, 0.31, 0.55), int(g.id) * 31 + i)
				"steam":
					_puffs(gp, 6, 2.6, 30.0, 16.0, 0.9, Color(0.96, 0.97, 0.98, 0.55), int(g.id) * 31 + i)
				"vent":
					_puffs(gp, 4, 2.2, 16.0, 10.0, 0.6, Color(0.95, 0.96, 0.97, 0.40), int(g.id) * 31 + i)
			i += 1
		# decon mist: drifting low banks over the wash / decon hall; on lockdown the decon zone floods
		var areas: Array = g.flood if lock else g.mist
		var dens := 0.55 if lock else 0.22
		var ai := 0
		for r in areas:
			var rr: Rect2 = r
			if rr.size.x <= 0.0:
				continue
			var nb := int(clampf(rr.size.x * rr.size.y * 0.6, 4.0, 22.0))
			for k in nb:
				var hs := absi(hash(Vector3i(int(g.id), ai, k)))
				var u := fposmod(float(hs % 101) / 101.0 + wind.x * t * 0.018, 1.0)
				var v := fposmod(float((hs / 101) % 103) / 103.0 + wind.y * t * 0.018, 1.0)
				var p := rr.position + Vector2(u * rr.size.x, v * rr.size.y)
				var breathe := 0.75 + 0.25 * sin(t * 0.7 + float(k))
				var edge := minf(minf(u, 1.0 - u), minf(v, 1.0 - v)) * 4.0
				_sp("puff%d" % (k % 3), _iso(p) - Vector2(0, 4), 0, 0, Color(MIST_COL, dens * breathe * clampf(edge, 0.0, 1.0)), 2.6, over)
				counts["mist"] += 1
			ai += 1
		# blast-door shutters over the visible doors (garages on +x, building doors on +x / +y)
		var sp := clampf((t - float(a.get("lock_t", -99.0))) / 1.6, 0.0, 1.0)
		var shut := sp if lock else (1.0 - sp)
		if shut > 0.01:
			for ga in g.garages:
				if int(ga[1]) == 0:
					var r: Rect2 = ga[0]
					_shutter(0, r.end.x - INSET, r.get_center().y, 0.56, DOOR_Z, shut)   # ATMO7-2: on FACB7-2's inset facade
			for d in g.doors:
				if (d as Array).size() > 4:   # POLISH7: FACB7 door geometry (planning / lab)
					_shutter(int(d[1]), float(d[3]), float(d[2]), float(d[4]), float(d[5]), shut)
				else:
					_shutter(int(d[1]), float(d[3]) - INSET, float(d[2]), 0.42, DOOR_Z * 0.8, shut)
			# front blast shields of the helipad (south / east edges)
			if g.zones.has("helipad"):
				var r2: Rect2 = g.zones.helipad
				var sh := _shield_h(g)
				_shield(over, Vector2(r2.position.x, r2.end.y), r2.end, sh)
				_shield(over, Vector2(r2.end.x, r2.position.y), r2.end, sh)
		_draw_plaques(g)   # POLISH7-2: after the shutters, so a lockdown shutter never covers a building's name
		# POLISH7-2: the wall lamps' housings on the capping beam (always there); lit red only in a lockdown / breach
		var ph2 := int(t * 5.0)
		var lit := lvl > 0.0 and bool(a.get("red", false))
		for l in g.lamps:
			if _hid(g, "l%d" % int(l[1])):
				continue
			var hp := _iso(l[0]) - Vector2(0, WALL_CAP_Z)
			over.draw_rect(Rect2(hp + Vector2(-1.5, -2.0), Vector2(3.0, 2.0)), LAMP_HOUSING)
			if lit and (int(l[1]) + ph2) % 4 < 2:
				over.draw_rect(Rect2(hp + Vector2(-1.0, -3.0), Vector2(2.0, 1.0)), Color(1.0, 0.25, 0.15))
		# alarm beacons (sprite) on every tower and both gates
		if lvl > 0.0:
			var row := 0 if bool(a.get("red", false)) else 1
			for k in (g.towers as Array).size():
				if _hid(g, "t%d" % k):
					continue   # POLISH7-2: a taller building stands in front of this roof corner
				_sp("beacon", _iso(g.towers[k] + BEACON_OFF) - Vector2(0, TOWER_ROOF_Z), int(t * 12.0 + float(k) * 3.0) % 8, row, Color.WHITE, 1.0, over)
				counts["beacons"] += 1
			var gi := 0
			for q in _gate_posts(g):
				gi += 1
				if _hid(g, "p%d" % (gi - 1)):
					continue
				_sp("beacon", _iso(q[0]) - Vector2(0, float(q[1])), int(t * 12.0 + (q[0] as Vector2).x) % 8, row, Color.WHITE, 1.0, over)
				counts["beacons"] += 1
	# damage: cracks, smoke columns, fires
	for d in _dmg:
		var c: Vector2 = d.c
		var gp := _iso(c)
		if not _vr.has_point(gp):
			continue
		var h := float(d.h)
		var sz := float(d.size)
		var z := float(d.z)
		var sd := int(d.seed)
		_sp("cracks%d" % (sd % 3), gp + Vector2(sz * 8.0, -z * 0.45), 0, 0, Color(1, 1, 1, clampf((0.72 - h) * 3.0, 0.3, 1.0)), 0.6 + sz * 0.25, over)
		counts["cracks"] += 1
		if h < 0.25 and String(d.def) == "cn_tower":
			_sp("cracks%d" % ((sd + 1) % 3), gp + Vector2(-sz * 9.0, -z * 0.7), 0, 0, Color.WHITE, 0.8, over)
		if h < 0.48:
			_puffs(gp - Vector2(0, z * 0.85), 9, 4.5, 110.0, 60.0, 1.8, Color(0.12, 0.11, 0.11, 0.75), sd)
		if h < 0.3:
			for f in (2 if h < 0.15 else 1):
				_sp("fire", gp + Vector2(-6.0 + float(f) * 10.0, -z * (0.8 - 0.25 * float(f))), int(t * 12.0) + f * 2 + sd, 0, Color.WHITE, 1.0 + 0.2 * float(f), over)
				counts["fires"] += 1
	# zone buildings: damage follows the core's hp, each building with its own threshold
	for g in geo:
		var ch := float(_zone_dmg.get(int(g.id), 1.0))
		if ch >= 0.75 or not _vr.intersects(g.bbox):
			continue
		var zi := 0
		for zn in BLD_Z:
			if not (g.zones as Dictionary).has(zn) or not _has_art(zn):   # ATMO7-2: no fire / cracks over a bare slab
				continue
			var r: Rect2 = g.zones[zn]
			var thr := 0.75 - 0.4 * float(absi(hash(zn + str(g.id))) % 100) / 100.0
			if ch < thr:
				var gp := _iso(Vector2(r.end.x - 0.6, r.end.y - 0.6))
				var z := float(BLD_Z[zn])
				_sp("cracks%d" % (zi % 3), gp + Vector2(10, -z * 0.4), 0, 0, Color.WHITE, 1.1, over)
				counts["cracks"] += 1
				if ch < thr - 0.2:
					_puffs(_iso(r.get_center()) - Vector2(0, z), 7, 4.2, 74.0, 44.0, 1.2, Color(0.14, 0.13, 0.13, 0.65), zi * 13 + int(g.id))
					_sp("fire", _iso(r.get_center()) - Vector2(0, z * 0.9), int(t * 12.0) + zi, 0, Color.WHITE, 1.2, over)
					counts["fires"] += 1
			zi += 1
	# ruins: smouldering (fires for the first 90 s, smoke for ever)
	for r in _ruins:
		var g: Dictionary = r.g
		if not _vr.intersects(g.bbox):
			continue
		var age := t - float(r.t0)
		var k := 0
		for zn in g.zones:
			if ["pad", "helipad", "staging", "gate_outer", "gate_inner", "apc_wash"].has(zn):
				continue
			var c: Vector2 = g.zones[zn].get_center()
			_puffs(_iso(c) - Vector2(0, 10), 6, 5.0, 80.0, 50.0, 1.3, Color(0.16, 0.15, 0.15, 0.6), k * 17 + int(g.id))
			if age < 90.0 and k % 2 == 0:
				_sp("fire", _iso(c) - Vector2(0, 6), int(t * 12.0) + k, 0, Color(1, 1, 1, clampf((90.0 - age) / 20.0, 0.0, 1.0)), 1.3, over)
				counts["fires"] += 1
			k += 1


## POLISH7: the blast doors of FACB7's planning / lab art (tools/art/g7_fac7f.gd planning() / lab(): building-local
## metres, pivot = zone centre, local +x = the door side f, rotated by f * 90 deg, 4 m per tile, 9.8 px per m) as
## door entries [zone, face 0 / 1, centre along the face, face line, half width (tiles), height (px)]. Doors on a
## hidden face (f 2 / 3) are skipped. Keep in step with g7_fac7f.gd if FACB7 moves its doors.
static func _facb7_doors(zn: String, zr: Rect2, f: int) -> Array:
	if f != 0 and f != 1:
		return []
	var ex := (zr.size.x if f == 0 else zr.size.y) * 2.0
	var ey := (zr.size.y if f == 0 else zr.size.x) * 2.0
	var ds := []   # [local x, local y, half width, height] in metres
	if zn == "planning":
		var hx := minf((2.0 * ex - 5.0) * 0.5, 7.0)
		var xf := -ex + 1.6 + 2.0 * hx
		ds.append([xf + 2.2, 0.0, 0.9, 2.5])
	elif zn == "lab":
		var hx2 := minf((2.0 * ex - 4.2) * 0.5, 8.0)
		var hy2 := minf(ey - 2.8, 8.0)
		var xf2 := -ex + 0.8 + 2.0 * hx2
		ds.append([xf2, -1.0 - hy2 * 0.45, 1.8, 3.4])
		ds.append([xf2 + 1.8, -1.0 + hy2 * 0.45, 0.7, 2.3])
	var c := zr.get_center()
	var out := []
	for d in ds:
		var lx := float(d[0]) / 4.0
		var ly := float(d[1]) / 4.0
		if f == 0:   # local +x -> +x, local +y -> +y
			out.append([zn, 0, c.y + ly, c.x + lx + 0.03, float(d[2]) / 4.0 + 0.03, float(d[3]) * 9.8])
		else:        # local +x -> +y, local +y -> -x
			out.append([zn, 1, c.x - ly, c.y + lx + 0.03, float(d[2]) / 4.0 + 0.03, float(d[3]) * 9.8])
	return out


## A steel blast shutter on a door: face 0 = on the +x face (line x = X, centred at y = c), 1 = on the +y face.
func _shutter(face: int, X: float, c: float, hw: float, dz: float, p: float) -> void:
	var a := _iso(Vector2(X, c - hw) if face == 0 else Vector2(c - hw, X))
	var b := _iso(Vector2(X, c + hw) if face == 0 else Vector2(c + hw, X))
	var top := Vector2(0, -dz)
	var bot := Vector2(0, -dz * (1.0 - p))
	over.draw_colored_polygon(PackedVector2Array([a + top, b + top, b + bot, a + bot]), Color(0.34, 0.36, 0.38))
	var n := int(dz * p / 4.0)
	for k in n:   # slats
		var y := -dz + 4.0 * float(k + 1)
		over.draw_line(a + Vector2(0, y), b + Vector2(0, y), Color(0.24, 0.25, 0.27), 1.0)
	var hz := 3.0   # hazard bar on the leading edge
	for k in 6:
		var u0 := float(k) / 6.0
		var u1 := float(k + 1) / 6.0
		var q0 := a.lerp(b, u0) + bot
		var q1 := a.lerp(b, u1) + bot
		over.draw_colored_polygon(PackedVector2Array([q0 + Vector2(0, -hz), q1 + Vector2(0, -hz), q1, q0]), HAZ_Y if k % 2 == 0 else HAZ_K)
	over.draw_line(a + top, b + top, Color(0.55, 0.57, 0.6), 1.0)
	counts["shutters"] = int(counts.get("shutters", 0)) + 1


## POLISH7-2: alarm beacon fixtures of the entry: [world point, height px]: the cap of each gate bastion (the art's own
## lamp sits at its centre) and the checkpoint's east roof parapet.
func _gate_posts(g: Dictionary) -> Array:
	if g.has("posts"):
		return g.posts
	var out := []
	for zn in ["gate_outer", "gate_inner"]:
		if (g.zones as Dictionary).has(zn):
			var r: Rect2 = g.zones[zn]
			var c := r.get_center()
			var ax := Vector2(1, 0) if r.size.x >= r.size.y else Vector2(0, 1)   # the across axis (bastions at its ends)
			var py := (maxf(r.size.x, r.size.y) * 2.0 - 1.3) / 4.0
			out.append([c - ax * py, GATE_CAP_Z])
			out.append([c + ax * py, GATE_CAP_Z])
	out.append([Vector2(g.checkpoint) + CP_BEACON, CP_PARAPET_Z])
	g["posts"] = out
	return out


## POLISH7-2: lights behind a zone building (its prism covers the light on screen) are not drawn: the fx layers draw
## above the entities, so a covered beacon / lamp would hang in front of that building. Keys t<i> tower beacon,
## s<i> searchlight, p<i> entry beacon, l<i> wall lamp; computed once per facility.
func _hid(g: Dictionary, key: String) -> bool:
	if not g.has("hid"):
		var hid := {}
		for k in (g.towers as Array).size():
			if _behind_bld(g, g.towers[k] + BEACON_OFF, TOWER_ROOF_Z + 6.0):
				hid["t%d" % k] = true
			if _behind_bld(g, g.towers[k] + SEARCH_OFF, SEARCH_Z):
				hid["s%d" % k] = true
		var i := 0
		for q in _gate_posts(g):
			if _behind_bld(g, q[0], float(q[1]) + 6.0):
				hid["p%d" % i] = true
			i += 1
		for l in g.lamps:
			if _behind_bld(g, l[0], WALL_CAP_Z + 2.0):
				hid["l%d" % int(l[1])] = true
		g["hid"] = hid
	return (g.hid as Dictionary).has(key)


func _behind_bld(g: Dictionary, at: Vector2, z: float) -> bool:
	var s := _iso(at) - Vector2(0, z)
	var occ := []
	for zn in BLD_Z:
		if zn == "core":
			if g.has("core_r"):
				occ.append([g.core_r, BLD_Z.core])
		elif (g.zones as Dictionary).has(zn) and _has_art(zn):
			occ.append([g.zones[zn], BLD_Z[zn]])
	for o in occ:
		var r: Rect2 = o[0]
		if at.x >= r.end.x or at.y >= r.end.y or r.has_point(at):
			continue   # in front of it (or on it)
		var q := [_iso(r.position), _iso(Vector2(r.end.x, r.position.y)), _iso(r.end), _iso(Vector2(r.position.x, r.end.y))]
		var up := Vector2(0, -float(o[1]))
		if Geometry2D.is_point_in_polygon(s, PackedVector2Array([q[3], q[3] + up, q[0] + up, q[1] + up, q[1], q[2]])):
			return true
	return false


# =============================================================== dark (multiply) and glow (additive)
func _draw_dark() -> void:
	counts["dark"] = 0
	if night <= 0.004:
		return
	var col := Color.WHITE.lerp(DUSK, clampf(night * 2.0, 0.0, 1.0)) if night <= 0.5 else DUSK.lerp(NIGHT, (night - 0.5) * 2.0)
	var mw := float(map.get("w", 256))
	var mh := float(map.get("h", 256))
	var pad := 400.0
	var pts := PackedVector2Array([ViewUtil.iso(Vector2(-pad, -pad)), ViewUtil.iso(Vector2(mw + pad, -pad)), ViewUtil.iso(Vector2(mw + pad, mh + pad)), ViewUtil.iso(Vector2(-pad, mh + pad))])
	dark.draw_colored_polygon(pts, col)
	counts["dark"] = 1


func _pool(p: Vector2, rx: float, col: Color) -> void:
	var e: Dictionary = _spr.get("glow", {})
	if e.is_empty():
		return
	glow.draw_texture_rect(e.tex, Rect2(p - Vector2(rx, rx * 0.5), Vector2(rx * 2.0, rx)), false, col)
	counts["lights"] = int(counts.get("lights", 0)) + 1


func _dot(p: Vector2, r: float, col: Color) -> void:
	var e: Dictionary = _spr.get("spot", {})
	if e.is_empty():
		return
	glow.draw_texture_rect(e.tex, Rect2(p - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false, col)


func _draw_glow() -> void:
	counts["lights"] = 0
	counts["searchlights"] = 0
	var n := night
	# base building lights (any match, night / dusk): a warm pool at the front and a door lamp
	if n > 0.004:
		for b in _blds:
			var c: Vector2 = b[0] + Vector2(float(b[1]), float(b[1])) * 0.5
			var gp := _iso(c + Vector2(float(b[1]) * 0.5 + 0.3, float(b[1]) * 0.5 + 0.3))
			if not _vr.has_point(gp):
				continue
			_pool(gp, 34.0 + 14.0 * float(b[1]), Color(1.0, 0.78, 0.45, 0.30 * n))
			_dot(gp - Vector2(0, 18), 4.0, Color(1.0, 0.85, 0.6, 0.8 * n))
		var lp = map.get("lp")
		if lp is Dictionary and (lp as Dictionary).has("base"):
			var ls: Array = (lp.base as Dictionary).get("lights", [])
			for l in ls:
				var gp := _iso(Vector2(l.cell))
				if not _vr.has_point(gp):
					continue
				match String(l.get("kind", "")):
					"flood":
						_pool(gp + Vector2(0, 10), 110.0, Color(0.85, 0.92, 1.0, 0.42 * n))
					"pad":
						_dot(gp - Vector2(0, 3), 4.0, Color(0.5, 1.0, 0.6, (0.5 + 0.5 * float(int(t * 2.0) % 2)) * maxf(n, 0.35)))
					_:
						_pool(gp, 56.0, Color(1.0, 0.8, 0.5, 0.40 * n))
	for g in geo:
		if not _vr.intersects(g.bbox):
			continue
		var a: Dictionary = _alarm.get(int(g.id), {})
		var lvl := float(a.get("lvl", 0.0))
		var red := bool(a.get("red", false))
		var acol := Color(1.0, 0.12, 0.08) if red else Color(1.0, 0.6, 0.1)
		if n > 0.004:
			_facade_light(g, n)
			for l in g.lights:
				var gp := _iso(l[0])
				match String(l[1]):
					"flood":
						_pool(gp, 120.0, Color(0.86, 0.93, 1.0, 0.36 * n))
					"door":
						_pool(gp, 36.0, Color(1.0, 0.82, 0.55, 0.42 * n))
						_dot(gp - Vector2(0, DOOR_Z * 0.85), 3.5, Color(1.0, 0.9, 0.7, 0.9 * n))
			for tc in g.towers:   # floodlight heads
				_dot(_iso(tc) - Vector2(0, TOWER_Z - 10.0), 5.0, Color(0.9, 0.95, 1.0, 0.9 * n))
			# light from the garages: a spill out of the door (LIFE7 door_open when present, else a leak under the door)
			var life = mv.get("fac_life7") if mv != null else null
			for ga in g.garages:
				var r: Rect2 = ga[0]
				var op := 0.0
				if life != null and life.has_method("door_open"):
					op = clampf(float(life.door_open(int(g.id), "g%d" % int(ga[2]))), 0.0, 1.0)
				var dir := 1.0 if int(ga[1]) == 0 else -1.0
				var X := r.end.x - INSET if int(ga[1]) == 0 else r.position.x + INSET
				var yc := r.get_center().y
				var k := 0.25 + 0.75 * op
				var p0 := _iso(Vector2(X, yc - 0.7))
				var p1 := _iso(Vector2(X, yc + 0.7))
				var q1 := _iso(Vector2(X + dir * (0.6 + 1.8 * op), yc + 1.0 + 0.4 * op))
				var q0 := _iso(Vector2(X + dir * (0.6 + 1.8 * op), yc - 1.0 - 0.4 * op))
				var cw := Color(1.0, 0.86, 0.6, 0.5 * n * k)
				glow.draw_polygon(PackedVector2Array([p0, p1, q1, q0]), PackedColorArray([cw, cw, Color(cw, 0.0), Color(cw, 0.0)]))
				counts["lights"] += 1
		# pad / helipad edge lights: green edge dots blinking, a white chase running round toward the touchdown side
		var vis := maxf(n, 0.35)
		for e in g.edge:
			var gp := _iso(e[0])
			var k := int(e[2])
			var heli := String(e[1]) == "helipad"
			var base := Color(0.35, 0.65, 1.0) if heli else Color(0.35, 1.0, 0.45)
			var blink := 0.55 + 0.45 * float(int(t * 1.5) % 2)
			_dot(gp - Vector2(0, 2), 2.5 + 1.5 * n, Color(base, blink * vis))
			if (int(t * 10.0) - k) % 14 == 0:
				_dot(gp - Vector2(0, 2), 4.0 + 2.0 * n, Color(1, 1, 1, 0.95 * vis))
			counts["lights"] += 1
		# alarm: rotating beacon beams + red ground pulse, flashing wall lamps, searchlights
		if lvl > 0.0:
			var k := 0
			for tc in g.towers:
				if _hid(g, "t%d" % k):
					k += 1
					continue
				var L := _iso(tc + BEACON_OFF) - Vector2(0, TOWER_ROOF_Z + 5.0)
				_beam_rot(L, t * 6.0 + float(k) * 0.8, acol, 0.55 + 0.35 * n)
				_pool(_iso(tc), 70.0, Color(acol, (0.12 + 0.18 * n) * (0.6 + 0.4 * sin(t * 6.0 + float(k)))))
				k += 1
			var gj := 0
			for q in _gate_posts(g):
				gj += 1
				if not _hid(g, "p%d" % (gj - 1)):
					_beam_rot(_iso(q[0]) - Vector2(0, float(q[1]) + 5.0), t * 6.0 + (q[0] as Vector2).x, acol, 0.5 + 0.35 * n)
			var ph := int(t * 5.0)
			var red_on := bool(a.get("red", false))   # POLISH7-2 (13.9c-17): amber alert = beacons only
			for l in (g.lamps if red_on else []):
				var on := (int(l[1]) + ph) % 4 < 2
				if on and not _hid(g, "l%d" % int(l[1])):
					var gp := _iso(l[0]) - Vector2(0, WALL_CAP_Z + 2.5)
					_dot(gp, 3.0, Color(1.0, 0.25, 0.15, 1.0))
					_dot(gp, 9.0, Color(acol, 0.35 + 0.3 * n))
			# searchlights: one per tower, sweeping its approach outside the wall
			k = 0
			for tc in (g.towers if red_on else []):
				var outv: Vector2 = (tc - g.ctr).normalized()
				var ang := 0.75 * sin(t * 0.55 + float(k) * 1.7)
				var tgt: Vector2 = tc + outv.rotated(ang) * (5.0 + 1.5 * sin(t * 0.31 + float(k)))
				if not _hid(g, "s%d" % k):
					_searchlight(_iso(tc + SEARCH_OFF) - Vector2(0, SEARCH_Z), _iso(tgt), 0.35 + 0.65 * n)
				k += 1


func _beam_rot(L: Vector2, ang: float, col: Color, a: float) -> void:
	for s in [0.0, PI]:
		var a0: float = ang + s - 0.22
		var a1: float = ang + s + 0.22
		var R := 70.0
		var p0 := L + Vector2(cos(a0), sin(a0) * 0.5) * R
		var p1 := L + Vector2(cos(a1), sin(a1) * 0.5) * R
		glow.draw_polygon(PackedVector2Array([L, p0, p1]), PackedColorArray([Color(col, a * 0.7), Color(col, 0.0), Color(col, 0.0)]))
	_dot(L, 6.0, Color(col, a))
	_dot(L, 2.5, Color(1, 0.9, 0.85, a))
	counts["lights"] = int(counts.get("lights", 0)) + 1


func _searchlight(L: Vector2, S: Vector2, a: float) -> void:
	var d := (S - L)
	var perp := Vector2(-d.y, d.x).normalized()
	var rx := 34.0
	var c := Color(0.92, 0.96, 1.0)
	glow.draw_polygon(PackedVector2Array([L - perp * 2.0, L + perp * 2.0, S + perp * rx * 0.7, S - perp * rx * 0.7]),
		PackedColorArray([Color(c, 0.30 * a), Color(c, 0.30 * a), Color(c, 0.05 * a), Color(c, 0.05 * a)]))
	_pool(S, rx * 1.6, Color(c, 0.55 * a))
	_dot(L, 4.0, Color(c, a))
	counts["searchlights"] = int(counts.get("searchlights", 0)) + 1
