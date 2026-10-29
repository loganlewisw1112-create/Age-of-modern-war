extends Node2D
## G7 SEQ7 (13.9c-7 "mission sequences on screen"): the Counter-Nanite facility's mission sequences, display only.
## Never writes the sim. Driven by the real CnFacility team phases (CnFacility.render_entries + CnFacility.team, read
## at most every 15 frames and only while no sim step is in flight, like baseprops_layer), the render snapshot (APC /
## dropship positions, facings, landed flag, g7u bay / wound / exposure keys) and the step events (CnDecon, BayRamp).
##  1. Launch: amber SCRAMBLE beacons on the launching team's garages and the loading pad; the crews run from the ready
##     room to their APC's rear door on the pad and climb in; pad floor chasers while the APCs load. Dropship sortie:
##     ramp-edge strobes + lit bay spill + a marshaller with light wands at the rear ramp while it is down; lift-fan
##     spool-up (fan glow, building dust) when the ramp closes, a dust burst and debris on take-off and touchdown.
##  2. Return + decon: spray jets from both nozzle bars of the APC wash onto a stopped team APC, contaminated runoff that
##     clears as the rinse runs, drips trailing the washed APC; the crew climb out after the rinse in field grime
##     (tools/art/g7_seq7.gd dirty sheets), walk into the infantry decon hall (blue scan pulses, mist out of the door),
##     and come out clean (green pass light) to their garage; an exposed soldier is flagged red and walks to the
##     aid-station quarantine bay instead.
##  3. Casualty flow: wounded / unconscious crew (snapshot g7u wz / unc / bleed) are carried on stretchers by medic
##     pairs from the APC to the aid station; quarantine-bay lights (rotating violet beacon + door ring) while exposed
##     team members are in.
##  4. Resupply: an ammo tug + trailer drives from the special-ammo magazine to each APC on the pad when a launch
##     starts; two loaders lift the 6-tube rocket-pod reload pack and the special-round crates aboard while it loads,
##     then the empty rig drives back.
##  5. Camera: seq_focus() = where the most recent sequence is happening (follow-the-launch hint for ORCH / CINE7).
## Every route is planned on the live facility layout (CnFacility.conf zones + doors, building footprints blocked,
## lanes preferred), so FACB7's layout changes need no edit here. Figures behind a building, an APC or a dropship are
## hidden (no figure is ever drawn through a hull). A match without a facility: one dictionary check per 15 frames.
## Wiring (ORCH change_request seq7.wire, match_view): add right after vis7_layer (z_index 2), setup(self) after
## baseprops_layer.setup, refresh(snap) every frame right after entity_layer.refresh().
const ViewUtil = preload("res://presentation/view/view_util.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const ArtCat = preload("res://presentation/art/art_catalog.gd")
const RS = preload("res://sim/render_snap.gd")

const READ_EVERY := 15
const RUN_SPD := 2.4          # tiles/s (game-paced: the sim's soldiers move at 1.5..2.5)
const RUN_MAX := 2.7          # SEQ7-3 (13.9c-13 realism): never faster than the sim's own sprinting soldiers (was 4.0)
const RUN_FPS := 16.0         # SEQ7-3: leg cadence = motion.gd's sprint / walk cadence, advanced by distance (no sliding)
const WALK_FPS := 10.0
const WALL_H := 57.0          # SEQ7-3: link-wall top 5.85 m (FACB7 fact facb7.zone_heights) x 9.8 px/m
const NOZ := 1.12             # SEQ7-3: wash nozzle bars inboard of the link walls (tiles from the hull centre line)
const HULL := 0.40            # half hull width the jets hit
## SEQ7-3: occluder heights (px) from FACB7's fact facb7.zone_heights (m x 9.8 px/m); every other zone 34 px
const ZONE_H := {"barracks": 71.0, "armory": 114.0, "aid_station": 43.0, "magazine": 38.0, "range": 14.0}
const WALK_SPD := 1.3
const CARRY_SPD := 1.1
const CART_SPD := 2.2
const HALL_S := 3.0           # inside the decon hall (CnFacility walk_time)
const MAX_CREW := 10          # figures per APC
const MAX_PUFFS := 220
const AMBER := Color(1.0, 0.62, 0.12)
const RED := Color(1.0, 0.18, 0.12)
const GREEN := Color(0.35, 1.0, 0.45)
const SCAN := Color(0.45, 0.80, 1.0)
const VIOLET := Color(0.78, 0.35, 1.0)
const WATER := Color(0.78, 0.90, 1.0)
const RUNOFF := Color(0.35, 0.58, 0.42)
const DUST := Color(0.62, 0.58, 0.50)
const DUST_LT := Color(0.86, 0.82, 0.72)   # SEQ7-2: take-off / touchdown ring (the old tone vanished on the grey helipad)
const OPEN_ZONES := ["pad", "helipad", "staging", "apc_wash", "gate_outer", "gate_inner", "fuel_point"]  # fuel_point: painted marking
const PHASE_LAUNCH := ["to_pad", "loading"]

var mv = null
var on := true                  # display toggle (tests: hash with the layer on / off)
var auto := false               # true: _process pulls mv.snap itself (playtest before ORCH wires refresh)
var hm: Dictionary = {}
var facs: Array = []            # CnFacility.render_entries (last read)
var lay: Dictionary = {}        # fac id -> layout {o, cs, zones, doors, grid, occ, keys}
var teams: Dictionary = {}      # tid -> {fac, phase, apcs [ids], crew {apc id: [[id, def]]}, owner}
var heli: Dictionary = {}       # dropship id -> fac id
var ts: Dictionary = {}         # tid -> last seen phase
var actors: Array = []
var puffs: Array = []           # {p world, h px, v world/s, vh px/s, t0, life, r0, r1, col, a}
var sprays: Dictionary = {}     # apc id -> {fac, t0, done (-1 / stime), side Vector2, fwd}
var drips: Dictionary = {}      # apc id -> until stime
var crafts: Dictionary = {}     # dropship id -> {landed, spool, burst, kind}
var scramble: Dictionary = {}   # fac id -> {until, garages [Rect2], tid}
var quarantine: Dictionary = {} # fac id -> until stime
var hall_busy: Dictionary = {}  # fac id -> until stime
var flashes: Array = []         # [world pos, color, t0, life]
var stime := 0.0
var _last_t := -1.0
var _frame := 0
var _read_frame := 0
var _lay_key := ""
var _texc: Dictionary = {}
var _sheet: Dictionary = {}
var _paths: Dictionary = {}
var _cols: Dictionary = {}
var _focus := Vector2.INF
var _focus_t := -100.0
var glow: Node2D
var _rng := RandomNumberGenerator.new()   # display-only randomness (never the global RNG)
# evidence counters (tests / playtest)
var n_launch := 0
var n_runners := 0
var n_boarded := 0
var n_carts := 0
var n_loads := 0
var n_spray := 0
var n_decon := 0
var n_clean := 0
var n_quar := 0
var n_stretcher := 0
var n_dust := 0
var n_marshal := 0
var drawn := 0
var hidden_occ := 0


func setup(view) -> void:
	mv = view
	var w = view.get("world") if view != null else null
	hm = ViewUtil.height_map_of(w.map) if w != null else {}
	glow = Node2D.new()
	glow.name = "Seq7Glow"
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = mat
	glow.draw.connect(_draw_glow)
	add_child(glow)
	if view != null and view.has_signal("world_events"):
		view.world_events.connect(on_events)
	visible = false
	set_process(auto)


func _process(_dt: float) -> void:
	if auto and mv != null:
		refresh(mv.get("snap") if mv.get("snap") != null else {})


# ================================================================ reading
func refresh(snap: Dictionary) -> void:
	if mv == null:
		return
	_frame += 1
	if _frame - _read_frame >= READ_EVERY and not (mv.has_method("sim_busy") and mv.sim_busy()):
		_read_frame = _frame
		_read(mv.get("world"))
	if facs.is_empty() and actors.is_empty() and puffs.is_empty():
		visible = false
		return
	visible = on
	var t := float(snap.get("tick", 0)) + float(mv.get("_alpha") if mv.get("_alpha") != null else 0.0)
	stime = t / float(SimWorld.TICK_RATE)
	var dt := clampf(stime - _last_t, 0.0, 0.5) if _last_t >= 0.0 else 0.0
	_last_t = stime
	_tick_crafts(snap)
	_tick_sprays(snap)
	_tick_actors(snap, dt)
	_tick_puffs(dt)
	if on:
		queue_redraw()
		glow.queue_redraw()


## Facility digest (display copy, plain data). w == null: keep the last one.
func _read(w) -> void:
	if w == null:
		return
	if not CnFacility.active(w):
		facs = []
		return
	facs = _digest(w)
	var key := ""
	for F in facs:
		key += "%d:%s|" % [int(F.id), str(F.compound)]
	if key != _lay_key:
		_lay_key = key
		lay.clear()
		_paths.clear()
		for F in facs:
			lay[int(F.id)] = _layout(F)
	var seen := {}
	heli.clear()
	for F in facs:
		if int(F.get("heli", 0)) != 0:
			heli[int(F.heli)] = int(F.id)
		if not _cols.has(int(F.owner)) and mv.has_method("team_color"):
			_cols[int(F.owner)] = mv.team_color(int(F.owner))
		for tid in F.get("garage_team", []):
			if int(tid) == 0 or seen.has(int(tid)):
				continue
			seen[int(tid)] = true
			var T: Dictionary = CnFacility.team(w, int(tid))
			if T.is_empty():
				continue
			var crew := {}
			for aid in T.get("apcs", []):
				var a = w.entities.get(int(aid))
				var list := []
				if a != null:
					for u in a.get("cargo", []):
						if u is Dictionary:
							list.append([int(u.id), String(u.get("def", ""))])
				crew[int(aid)] = list
			var D := {"fac": int(F.id), "owner": int(F.owner), "phase": String(T.get("phase", "")), "apcs": (T.get("apcs", []) as Array).duplicate(), "crew": crew}
			teams[int(tid)] = D
			_phase(int(tid), D)
	for tid in teams.keys():
		if not seen.has(tid):
			teams.erase(tid)
			ts.erase(tid)


## The facility fields this layer needs, as plain copies, built from pure reads only. Not CnFacility.render_entries:
## its mantrap display state walks every unit through SimIndex.of(w, "unit"), which can rebuild / extend the sim's
## cached entity index (w.cache.sim_index) from the view; this layer needs none of that (cheaper, no cache write).
func _digest(w) -> Array:
	var out := []
	var st = w.sys_state.get(CnFacility.KEY)
	if not (st is Dictionary):
		return out
	var conf: Dictionary = CnFacility.conf()
	var cs := float(conf.get("compound", 32))
	var gz: Array = conf.get("garage_size", [3, 3])
	var ks: Array = (st.facs as Dictionary).keys()
	ks.sort_custom(func(a, b): return int(a) < int(b))
	for k in ks:
		var F: Dictionary = st.facs[k]
		var o := Vector2(CnFacility.origin(F))
		var gr := []
		for g in CnFacility.garage_spots(F):
			gr.append([g.x - float(gz[0]) * 0.5, g.y - float(gz[1]) * 0.5, float(gz[0]), float(gz[1])])
		var ln := []
		for l in conf.get("lanes", []):
			ln.append([o.x + float(l[0]), o.y + float(l[1]), float(l[2]), float(l[3])])
		out.append({"id": int(k), "owner": int(F.get("owner", 0)), "compound": [o.x, o.y, cs, cs], "garage_rects": gr,
			"garage_team": (F.get("garages", []) as Array).duplicate(), "lanes": ln, "heli": int(F.get("heli", 0))})
	return out


## Team phase transitions -> sequences.
func _phase(tid: int, D: Dictionary) -> void:
	var old := String(ts.get(tid, ""))
	var ph := String(D.phase)
	ts[tid] = ph
	if old == ph:
		return
	if PHASE_LAUNCH.has(ph) and not PHASE_LAUNCH.has(old):
		_launch(tid, D)
	if ph == "to_gate" or ph == "out":
		for A in actors:
			if int(A.get("tid", -1)) == tid and String(A.kind) == "crew" and String(A.end) == "board":
				A.dead = true   # the last stragglers are aboard as the hatch shuts
		var S = scramble.get(int(D.fac))
		if S is Dictionary and int(S.tid) == tid:
			S.until = stime + 4.0


func on_events(evs: Array) -> void:
	for ev in evs:
		match String(ev.get("type", "")):
			"CnDecon":
				if String(ev.get("kind", "")) == "rinse":
					_rinsed(int(ev.get("id", -1)))
				else:
					flashes.append([Vector2.INF, GREEN, stime, 0.5, int(ev.get("id", -1))])
			"BayRamp":
				var cid := int(ev.get("id", -1))
				var C: Dictionary = crafts.get(cid, {})
				if not bool(ev.get("open", false)) and String(ev.get("mode", "")) == "load":
					C.spool = stime   # ramp up after loading: lift fans spool up
				crafts[cid] = C


# ================================================================ layout + routes
func _layout(F: Dictionary) -> Dictionary:
	var conf: Dictionary = CnFacility.conf()
	var o := Vector2(float(F.compound[0]), float(F.compound[1]))
	var cs := int(F.compound[2])
	var zones := {}
	var blocked := []
	for k in conf:
		var r = conf[k]
		if String(k).begins_with("_"):
			continue
		if r is Array and r.size() == 4 and (r[0] is float or r[0] is int) and String(k) != "compound":
			var R := Rect2(o + Vector2(float(r[0]), float(r[1])), Vector2(float(r[2]), float(r[3])))
			zones[String(k)] = R
			if not OPEN_ZONES.has(String(k)):
				blocked.append([R, float(ZONE_H.get(String(k), 34.0))])
	# SEQ7-2: the gate pillars (FACB7 gate art: a pillar box at each end of the gate_outer / gate_inner zone, the APC lane
	# between) stand tall: figures behind them are hidden and routes go round them
	for gk in ["gate_outer", "gate_inner"]:
		var G = zones.get(gk)
		if G is Rect2 and (G as Rect2).size.x >= 3.0:
			blocked.append([Rect2((G as Rect2).position, Vector2(1.0, (G as Rect2).size.y)), 46.0])
			blocked.append([Rect2(Vector2((G as Rect2).end.x - 1.0, (G as Rect2).position.y), Vector2(1.0, (G as Rect2).size.y)), 46.0])
	for g in F.get("garage_rects", []):
		blocked.append([Rect2(float(g[0]), float(g[1]), float(g[2]), float(g[3])), 40.0])
	var walls := []   # 13.9c-9: the walls enclosing the APC wash between the two gate layers (route blocks)
	var wocc := []    # SEQ7-3: the wall bodies + gate pillars as occluders for the wash spray / mist / figures in the wash
	var wz = zones.get("apc_wash")
	for r in conf.get("link_walls", []):
		if r is Array and r.size() == 4:
			var WR := Rect2(o + Vector2(float(r[0]), float(r[1])), Vector2(float(r[2]), float(r[3])))
			walls.append(WR)
			# FACB7-2 art: the wall body stands on the gate bastion line, 3.3 m (0.825 tile) from the cell centre toward
			# the wash, 5.85 m tall; taken as 0.5 tile thick
			var tw := 1.0 if (wz is Rect2 and (wz as Rect2).get_center().x > WR.get_center().x) else -1.0
			var bx := WR.get_center().x + 0.825 * tw
			var body := Rect2(Vector2(bx - 0.25, WR.position.y), Vector2(0.5, WR.size.y))
			walls.append(body)   # its cells are route blocks too (the body stands in the wash's edge column)
			wocc.append([body, WALL_H])
	for b in blocked:
		if (b[0] as Rect2).size.x <= 1.0 and float(b[1]) == 46.0:
			wocc.append(b)   # gate pillars
	# SEQ7-3: the foot-entry gatehouse (cn_checkpoint 2x2, parapet 5.6 m): figures in the yard behind it were drawn on
	# its roof; it is a route block too
	var cp = conf.get("checkpoint")
	if cp is Array and cp.size() == 2:
		blocked.append([Rect2(o + Vector2(float(cp[0]), float(cp[1])), Vector2(2, 2)), 5.6 * 9.8])
	var co: Array = conf.get("core_offset", [3, 3])
	blocked.append([Rect2(o + Vector2(float(co[0]), float(co[1])), Vector2(4, 4)), 48.0])
	var doors := {}
	var dc: Dictionary = conf.get("doors", {})
	for k in dc:
		var list := []
		for d in dc[k]:
			list.append(o + Vector2(float(d[0]) + 0.5, float(d[1]) + 0.5))
		doors[String(k)] = list
	var grid := PackedByteArray()
	grid.resize(cs * cs)
	for y in cs:
		for x in cs:
			var c := o + Vector2(x + 0.5, y + 0.5)
			var v := 2   # open ground
			if x == 0 or y == 0 or x == cs - 1 or y == cs - 1:
				v = 0
			else:
				for b in blocked:
					if (b[0] as Rect2).has_point(c):
						v = 0
						break
				for r in walls:
					if r.has_point(c):
						v = 0
			if v != 0:
				for l in F.get("lanes", []):
					if Rect2(float(l[0]), float(l[1]), float(l[2]), float(l[3])).has_point(c):
						v = 1
						break
			grid[y * cs + x] = v
	# personnel door: the wash wall cell nearest the decon hall's entry (crews step out of the wash into the hall line)
	var hd: Array = doors.get("decon_hall", [])
	var pdoor := Vector2.INF
	var wm: Array = doors.get("wash_man", [])   # SEQ7-3: FACB7's man-door in the link wall when the json names one
	if not wm.is_empty():
		pdoor = wm[0]
	elif not hd.is_empty():
		var best := INF
		for r in walls:
			for y in range(int(r.position.y), int(r.end.y)):
				for x in range(int(r.position.x), int(r.end.x)):
					var c := Vector2(x + 0.5, y + 0.5)
					if c.distance_to(hd[0]) < best:
						best = c.distance_to(hd[0])
						pdoor = c
	if pdoor != Vector2.INF:
		# the door row through the link cell and the wall body (open from the wash's middle columns to the yard)
		var pc := Vector2i(floori(pdoor.x - o.x), floori(pdoor.y - o.y))
		var wc := (wz as Rect2).get_center() if wz is Rect2 else pdoor
		var step := 1 if wc.x > pdoor.x else -1
		var x := pc.x
		for _k in 4:
			if x < 1 or x >= cs - 1:
				break
			grid[pc.y * cs + x] = 2
			x += step
			if wz is Rect2 and absf(o.x + float(x) + 0.5 - wc.x) < 1.0:
				break
	var occ := blocked.duplicate()
	for b in wocc:
		if float(b[1]) == WALL_H:
			occ.append(b)
	var L := {"o": o, "cs": cs, "zones": zones, "doors": doors, "grid": grid, "occ": occ, "wocc": wocc, "owner": int(F.owner), "pdoor": pdoor}
	L["keys"] = {"ready": _find(zones, ["ready", "barracks"], "staging"), "magazine": _find(zones, ["magazine", "ammo"], "workshop"),
		"aid": _find(zones, ["aid", "medic"], "decon_hall"), "quarantine": _find(zones, ["quarantine"], ""),
		"armory": _find(zones, ["armory", "suit"], "")}
	return L


func _find(zones: Dictionary, words: Array, dflt: String) -> String:
	var ks: Array = zones.keys()
	ks.sort()
	for wd in words:
		for k in ks:
			if String(k).contains(String(wd)):
				return String(k)
	return dflt if zones.has(dflt) else ""


## World point just outside a zone's door (doors from content; else the nearest walkable cell to its centre).
func _door(L: Dictionary, zone: String, idx: int = 0) -> Vector2:
	var ds: Array = (L.doors as Dictionary).get(zone, [])
	if not ds.is_empty():
		return _walkable(L, ds[mini(idx, ds.size() - 1)])
	var R = (L.zones as Dictionary).get(zone)
	if R == null:
		return _walkable(L, (L.o as Vector2) + Vector2(L.cs, L.cs) * 0.5)
	return _walkable(L, (R as Rect2).get_center())


func _cell(L: Dictionary, p: Vector2) -> Vector2i:
	var q := p - (L.o as Vector2)
	return Vector2i(clampi(floori(q.x), 0, int(L.cs) - 1), clampi(floori(q.y), 0, int(L.cs) - 1))


## Nearest walkable cell centre to p (ring search).
func _walkable(L: Dictionary, p: Vector2) -> Vector2:
	var c := _cell(L, p)
	var cs := int(L.cs)
	var g: PackedByteArray = L.grid
	for r in 8:
		var best := Vector2.INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q := c + Vector2i(dx, dy)
				if q.x < 0 or q.y < 0 or q.x >= cs or q.y >= cs or g[q.y * cs + q.x] == 0:
					continue
				var wp := (L.o as Vector2) + Vector2(q) + Vector2(0.5, 0.5)
				if best == Vector2.INF or wp.distance_to(p) < best.distance_to(p):
					best = wp
		if best != Vector2.INF:
			return best
	return p


## Grid A* (4-neighbour, lanes cost 1, open ground 1.6) between two world points; collinear points dropped.
func _route(L: Dictionary, a: Vector2, b: Vector2) -> PackedVector2Array:
	var key := "%d|%s|%s" % [int(L.o.x * 1000 + L.o.y), str(_cell(L, a)), str(_cell(L, b))]
	if _paths.has(key):
		return _paths[key]
	var cs := int(L.cs)
	var g: PackedByteArray = L.grid
	var s := _cell(L, _walkable(L, a))
	var t := _cell(L, _walkable(L, b))
	var si := s.y * cs + s.x
	var ti := t.y * cs + t.x
	var cost := {si: 0.0}
	var came := {}
	var open := [[_hd(s, t), si]]
	var done := {}
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if float(open[i][0]) < float(open[bi][0]):
				bi = i
		var cur: int = open[bi][1]
		open.remove_at(bi)
		if cur == ti:
			break
		if done.has(cur):
			continue
		done[cur] = true
		var cx := cur % cs
		var cy := cur / cs
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = cx + d.x
			var ny: int = cy + d.y
			if nx < 0 or ny < 0 or nx >= cs or ny >= cs:
				continue
			var ni := ny * cs + nx
			var gv := g[ni]
			if gv == 0 and ni != ti:
				continue
			var nc := float(cost[cur]) + (1.0 if gv == 1 else 1.6)
			if not cost.has(ni) or nc < float(cost[ni]):
				cost[ni] = nc
				came[ni] = cur
				open.append([nc + _hd(Vector2i(nx, ny), t), ni])
	var cells := []
	var k := ti
	if not came.has(ti) and ti != si:
		cells = [ti, si]   # no route: straight line (never expected inside a compound)
	else:
		while true:
			cells.push_front(k)
			if k == si or not came.has(k):
				break
			k = int(came[k])
	var pts := PackedVector2Array()
	for c in cells:
		var wp: Vector2 = (L.o as Vector2) + Vector2(int(c) % cs, int(c) / cs) + Vector2(0.5, 0.5)
		if pts.size() >= 2 and _collinear(pts[pts.size() - 2], pts[pts.size() - 1], wp):
			pts[pts.size() - 1] = wp
		else:
			pts.append(wp)
	_paths[key] = pts
	return pts


func _hd(a: Vector2i, b: Vector2i) -> float:
	return float(absi(a.x - b.x) + absi(a.y - b.y))


func _collinear(a: Vector2, b: Vector2, c: Vector2) -> bool:
	return absf((b - a).cross(c - b)) < 0.001


# ================================================================ snapshot helpers
func _upos(snap: Dictionary, id: int) -> Vector2:
	var i: int = mv.snap_index(id) if mv.has_method("snap_index") else -1
	if i < 0:
		return Vector2.INF
	var p: Vector2 = (snap.prev as PackedVector2Array)[i]
	var c: Vector2 = (snap.pos as PackedVector2Array)[i]
	var al := float(mv.get("_alpha")) if mv.get("_alpha") != null else 1.0
	return p.lerp(c, al) if p.distance_squared_to(c) < 4.0 else c


func _ufacing(snap: Dictionary, id: int) -> float:
	var i: int = mv.snap_index(id)
	return float((snap.facing as PackedFloat32Array)[i]) if i >= 0 else 0.0


func _umoving(snap: Dictionary, id: int) -> bool:
	var i: int = mv.snap_index(id)
	if i < 0:
		return false
	return (snap.prev as PackedVector2Array)[i].distance_squared_to((snap.pos as PackedVector2Array)[i]) > 0.0001


func _uflags(snap: Dictionary, id: int) -> int:
	var i: int = mv.snap_index(id)
	return int((snap.flags as PackedInt32Array)[i]) if i >= 0 and snap.has("flags") else 0


## Wound / exposure state of a (possibly carried) soldier from the snapshot's g7u table.
func _wstate(snap: Dictionary, id: int) -> Dictionary:
	var g = (snap.get("g7u", {}) as Dictionary).get(id)
	if not (g is Dictionary):
		return {"wounded": false, "exposed": false}
	var wd := bool(g.get("unc", false)) or bool(g.get("bleed", false)) or int(g.get("wz", 0)) != 0
	var ex := float(g.get("ex", 0.0)) > 0.0 or bool(g.get("sb", false))
	return {"wounded": wd, "exposed": ex}


func _team_of_apc(aid: int) -> int:
	for tid in teams:
		if (teams[tid].apcs as Array).has(aid):
			return int(tid)
	return 0


# ================================================================ 1. launch + resupply
func _launch(tid: int, D: Dictionary) -> void:
	var L: Dictionary = lay.get(int(D.fac), {})
	if L.is_empty():
		return
	n_launch += 1
	var gr := []
	for F in facs:
		if int(F.id) == int(D.fac):
			var gt: Array = F.get("garage_team", [])
			for i in gt.size():
				if int(gt[i]) == tid and i < (F.garage_rects as Array).size():
					var g: Array = F.garage_rects[i]
					gr.append(Rect2(float(g[0]), float(g[1]), float(g[2]), float(g[3])))
	scramble[int(D.fac)] = {"until": stime + 60.0, "garages": gr, "tid": tid, "t0": stime}
	var pad: Rect2 = (L.zones as Dictionary).get("pad", Rect2())
	_focus = pad.get_center()
	_focus_t = stime
	var keys: Dictionary = L.keys
	var start := _door(L, String(keys.ready)) if String(keys.ready) != "" else pad.get_center()
	var mag := _door(L, String(keys.magazine)) if String(keys.magazine) != "" else start
	# 13.9c-6: the rigs wait loaded at the rearm point beside the pads (pre-positioned from the magazine), roll to the
	# APCs when the launch is called, and drive back to the magazine empty
	var rearm := _door(L, "fuel_point") if (L.zones as Dictionary).has("fuel_point") else mag
	var n := (D.apcs as Array).size()
	for i in n:
		var aid := int(D.apcs[i])
		var slot := pad.get_center() + Vector2((float(i) - 0.5 * float(maxi(0, n - 1))) * 3.0, 0.0)   # CnFacility pad slot
		var crew: Array = (D.crew as Dictionary).get(aid, [])
		var m := mini(crew.size(), MAX_CREW)
		var path := _route(L, start, slot + Vector2(0, 1.4))
		var spd := clampf(_plen(path) / 4.5, RUN_SPD, RUN_MAX)   # SEQ7-3: never a superhuman sprint
		for j in m:
			# SEQ7-3: a staggered double file (alternate sides ~0.7 m off the route, ~1.6 m apart along it from the delay)
			# instead of a 3x3 clump
			var off := Vector2(0.18 if j % 2 == 0 else -0.18, -0.18 if j % 2 == 0 else 0.18)
			actors.append({"kind": "crew", "tid": tid, "def": String(crew[j][1]), "uid": int(crew[j][0]), "owner": int(D.owner),
				"path": _shift(path, off), "d": 0.0, "spd": spd * (0.95 + 0.02 * float(j % 3)), "delay": stime + 0.2 * float(j) + 0.1 * float(i),
				"end": "board", "apc": aid, "dirty": false, "gait": "run", "fac": int(D.fac)})
			n_runners += 1
		# resupply: one tug + trailer per APC from the magazine to the APC's flank on the pad
		var side := slot + Vector2(0.0, 2.2)
		actors.append({"kind": "cart", "tid": tid, "owner": int(D.owner), "path": _route(L, rearm, side), "d": 0.0, "spd": CART_SPD,
			"delay": stime + 0.6 * float(i), "end": "load", "apc": aid, "row": 0, "home": mag, "fac": int(D.fac), "t_load": -1.0})
		n_carts += 1


func _plen(p: PackedVector2Array) -> float:
	var n := 0.0
	for i in range(1, p.size()):
		n += p[i - 1].distance_to(p[i])
	return n


func _shift(p: PackedVector2Array, off: Vector2) -> PackedVector2Array:
	var q := PackedVector2Array()
	for i in p.size():
		q.append(p[i] + (off if i > 0 else off * 0.5))
	return q


# ================================================================ 2. return + decon, 3. casualties
func _rinsed(aid: int) -> void:
	var S = sprays.get(aid)
	if S is Dictionary:
		S.done = stime
	drips[aid] = stime + 6.0


## A team APC stopped in the wash: the crew climb out of the rear (dirty) before the hull is rinsed, step through the
## wash wall's personnel door and walk the infantry decon hall; casualties go out on stretchers.
func _dismount(aid: int) -> void:
	var tid := _team_of_apc(aid)
	if tid == 0:
		return
	var D: Dictionary = teams[tid]
	var L: Dictionary = lay.get(int(D.fac), {})
	if L.is_empty():
		return
	var snap: Dictionary = mv.snap
	var ap := _upos(snap, aid)
	if ap == Vector2.INF:
		return
	n_decon += 1
	_focus = ap
	_focus_t = stime
	var rear := ap - Vector2.from_angle(_ufacing(snap, aid)) * 1.2
	var entry := _door(L, "decon_hall", 0)
	var keys: Dictionary = L.keys
	var aid_door := _door(L, String(keys.aid), 0) if String(keys.aid) != "" else entry
	var crew: Array = (D.crew as Dictionary).get(aid, [])
	var walkers := 0
	var litters := 0
	for j in crew.size():
		var ws := _wstate(snap, int(crew[j][0]))
		if bool(ws.wounded):
			# medic pair from the aid station to the APC, then the casualty on a stretcher to the aid station
			var med := _medic_def(String(crew[j][1]))
			actors.append({"kind": "litter", "tid": tid, "def": med, "owner": int(D.owner), "path": _route(L, aid_door, rear),
				"d": 0.0, "spd": WALK_SPD * 1.5, "delay": stime + 0.8 * float(litters), "end": "pickup", "row": 1, "fac": int(D.fac),
				"exposed": bool(ws.exposed), "dest": aid_door, "gait": "run"})
			litters += 1
			n_stretcher += 1
			continue
		if walkers >= MAX_CREW:
			continue
		var off := Vector2(((walkers % 3) - 1) * 0.25, 0.0)
		actors.append({"kind": "crew", "tid": tid, "def": String(crew[j][1]), "uid": int(crew[j][0]), "owner": int(D.owner),
			"path": _shift(_route(L, rear, entry), off), "d": 0.0, "spd": WALK_SPD * (0.95 + 0.05 * float(j % 3)),
			"delay": stime + 0.45 * float(walkers), "end": "hall", "dirty": true, "exposed": bool(ws.exposed), "gait": "walk",
			"fac": int(D.fac), "apc": aid, "from": rear})
		walkers += 1


func _medic_def(crew_def: String) -> String:
	return "g7_b_cn_medic" if crew_def.contains("b_") else "g7_cn_medic"


func _tick_sprays(snap: Dictionary) -> void:
	for tid in teams:
		var D: Dictionary = teams[tid]
		if String(D.phase) != "returning":
			continue
		var L: Dictionary = lay.get(int(D.fac), {})
		var wash = (L.get("zones", {}) as Dictionary).get("apc_wash")
		if not (wash is Rect2):
			continue
		for aid in D.apcs:
			var p := _upos(snap, int(aid))
			# SEQ7-2: well inside the wash lane (grow(0.3) also caught an APC halted in the outer gate: the crews then
			# dismounted outside the wash wall and walked round the compound to the decon hall)
			if p == Vector2.INF or not (wash as Rect2).grow(-0.4).has_point(p) or _umoving(snap, int(aid)):
				continue
			if not sprays.has(int(aid)):
				var f := _ufacing(snap, int(aid))
				sprays[int(aid)] = {"fac": int(D.fac), "t0": stime, "done": -1.0, "fwd": Vector2.from_angle(f), "wash": wash}
				n_spray += 1
				_dismount(int(aid))
				_focus = p
				_focus_t = stime
	for aid in sprays.keys():
		var S: Dictionary = sprays[aid]
		var p := _upos(snap, int(aid))
		var gone: bool = p == Vector2.INF or not (S.wash as Rect2).grow(0.6).has_point(p)
		if gone or (float(S.done) > 0.0 and stime - float(S.done) > 1.2):
			sprays.erase(aid)
			if not drips.has(aid):
				drips[aid] = stime + 5.0
			continue
		if float(S.done) < 0.0 and _rng.randf() < 0.6:
			var fwd: Vector2 = S.fwd
			var sd := Vector2(-fwd.y, fwd.x) * (1.0 if _rng.randf() < 0.5 else -1.0)
			_puff(p + sd * 0.7 + fwd * _rng.randf_range(-0.9, 0.9), _rng.randf_range(6, 14), sd * 0.3, 6.0, 1.4, 2.0, 5.0, Color(0.85, 0.92, 1.0), 0.20, int(S.fac))
	for aid in drips.keys():
		if stime > float(drips[aid]):
			drips.erase(aid)
			continue
		var p := _upos(snap, int(aid))
		if p != Vector2.INF and _rng.randf() < 0.5:
			_puff(p + Vector2(_rng.randf_range(-0.7, 0.7), _rng.randf_range(-0.7, 0.7)), 12.0, Vector2.ZERO, -26.0, 0.5, 0.7, 0.9, WATER, 0.6)


# ================================================================ dropship sorties
func _tick_crafts(snap: Dictionary) -> void:
	for cid in heli:
		var C: Dictionary = crafts.get(cid, {})
		crafts[cid] = C
		var p := _upos(snap, int(cid))
		if p == Vector2.INF:
			continue
		var landed := (_uflags(snap, int(cid)) & RS.FLAG_LANDED) != 0
		if C.has("landed") and bool(C.landed) != landed:
			C.burst = stime
			C.kind = "touchdown" if landed else "takeoff"
			n_dust += 1
			_focus = p
			_focus_t = stime
			for k in 34:
				var a := TAU * float(k) / 34.0 + _rng.randf() * 0.2
				var dir := Vector2.from_angle(a)
				_puff(p + dir * 1.6, 2.0, dir * _rng.randf_range(2.0, 3.6), 0.0, _rng.randf_range(1.8, 2.8), 6.0, 18.0, DUST_LT, 0.8)
		C.landed = landed
		C.pos = p
		C.f = _ufacing(snap, int(cid))
		var g = (snap.get("g7u", {}) as Dictionary).get(int(cid))
		var was_down := _ramp_down(C)
		C.bay = String(g.get("bay", "")) if g is Dictionary else ""
		if was_down and not _ramp_down(C) and landed and stime - float(C.get("spool", -100.0)) > 8.0:
			C.spool = stime   # SEQ7-3: the ramp came up on the pad (any mode): the lift fans wind up
		var spool := float(C.get("spool", -100.0))
		var burst := float(C.get("burst", -100.0))
		var k := 0.0
		if landed and stime - spool < 8.0:
			k = clampf((stime - spool) / 4.0, 0.0, 1.0) * 0.85   # SEQ7-3: stronger downwash as the fans wind up
		if stime - burst < 2.5:
			k = maxf(k, 1.0 - (stime - burst) / 2.5)
		C.k = k
		if k > 0.05:
			for _i in int(ceil(k * 3.0)):
				var a := _rng.randf() * TAU
				var dir := Vector2.from_angle(a)
				_puff(p + dir * _rng.randf_range(1.4, 2.6), 1.0, dir * (1.2 + 2.4 * k), 0.0, 1.5, 4.0, 13.0, DUST_LT, 0.85 * k)


# ================================================================ actors
func _tick_actors(snap: Dictionary, dt: float) -> void:
	var keep := []
	for A in actors:
		if bool(A.get("dead", false)):
			continue
		if stime < float(A.get("delay", 0.0)):
			keep.append(A)
			continue
		match String(A.kind):
			"crew":
				_step_crew(A, snap, dt)
			"cart":
				_step_cart(A, snap, dt)
			"litter":
				_step_litter(A, snap, dt)
		if not bool(A.get("dead", false)):
			keep.append(A)
	actors = keep


## Moves A along its path; true when the end is reached.
func _walk(A: Dictionary, dt: float) -> bool:
	var path: PackedVector2Array = A.path
	if path.size() < 2:
		A.p = path[0] if path.size() == 1 else A.get("p", Vector2.ZERO)
		return true
	A.d = float(A.d) + float(A.spd) * dt
	var d := float(A.d)
	for i in range(1, path.size()):
		var seg := path[i - 1].distance_to(path[i])
		if d <= seg:
			A.p = path[i - 1].lerp(path[i], d / maxf(seg, 0.0001))
			A.f = (path[i] - path[i - 1]).angle()
			return false
		d -= seg
	A.p = path[path.size() - 1]
	return true


func _step_crew(A: Dictionary, snap: Dictionary, dt: float) -> void:
	var st := String(A.get("st", ""))
	if st == "inside":
		if stime >= float(A.out_t):
			var L: Dictionary = lay.get(int(A.fac), {})
			var ex := _door(L, "decon_hall", 1)
			A.dirty = false
			n_clean += 1
			flashes.append([ex, RED if bool(A.exposed) else GREEN, stime, 0.6, -1])
			var dest: Vector2
			if bool(A.exposed):
				var keys: Dictionary = L.keys
				var q := String(keys.quarantine) if String(keys.quarantine) != "" else String(keys.aid)
				dest = _door(L, q) if q != "" else ex
				A.end = "quarantine"
			else:
				dest = _garage_door(int(A.fac), int(A.apc), ex)
				A.end = "fade"
			A.path = _route(L, ex, dest)
			A.d = 0.0
			A.st = ""
			A.hidden = false
		return
	if st == "fading":
		if stime - float(A.t_fade) > 0.35:
			A.dead = true
		return
	if st == "door":
		# SEQ7-2: chase the rear door each frame from where the figure stands (was: _walk reset the figure to the route's
		# end every frame, so it never closed the last metre and 0 of 20 boarded)
		var ap := _upos(snap, int(A.apc))
		if ap == Vector2.INF:
			A.dead = true
			return
		var rear := ap - Vector2.from_angle(_ufacing(snap, int(A.apc))) * 1.15
		var to := rear - (A.p as Vector2)
		if to.length() < 0.3:
			n_boarded += 1
			A.p = rear
			A.st = "fading"
			A.t_fade = stime
			return
		A.f = to.angle()
		# SEQ7-3 (13.9c-13 believable spacing): file in through the rear door one at a time; a man with a mate closer to
		# the door within ~1.3 m in front of him checks his pace and waits (was: everyone ran into the same point)
		A.hold = false
		for B in actors:
			if B != A and String(B.get("st", "")) == "door" and int(B.get("apc", -1)) == int(A.apc) and B.has("p") 					and (B.p as Vector2).distance_to(A.p) < 0.32 and (rear - (B.p as Vector2)).length() < to.length() - 0.05:
				A.hold = true
				break
		if bool(A.hold):
			return
		var step := minf(to.length(), float(A.spd) * dt)
		A.p = (A.p as Vector2) + to.normalized() * step
		A.d = float(A.d) + step   # SEQ7-3: the legs keep pace on the last metres (was a frozen frame sliding in)
		return
	var arrived := _walk(A, dt)
	if not arrived:
		return
	match String(A.end):
		"board":
			A.st = "door"   # off the route: close in on the APC's rear door (the APC may still be parking)
		"hall":
			A.st = "inside"
			A.out_t = stime + HALL_S + 0.3 * float(int(A.uid) % 4)
			A.hidden = true
			hall_busy[int(A.fac)] = maxf(float(hall_busy.get(int(A.fac), 0.0)), float(A.out_t))
		"quarantine":
			quarantine[int(A.fac)] = stime + 25.0
			n_quar += 1
			A.st = "fading"
			A.t_fade = stime
		_:
			A.st = "fading"
			A.t_fade = stime


func _garage_door(fid: int, aid: int, dflt: Vector2) -> Vector2:
	var L: Dictionary = lay.get(fid, {})
	for F in facs:
		if int(F.id) != fid:
			continue
		var tid := _team_of_apc(aid)
		var gt: Array = F.get("garage_team", [])
		for i in gt.size():
			if int(gt[i]) == tid and i < (F.garage_rects as Array).size():
				var g: Array = F.garage_rects[i]
				return _walkable(L, Vector2(float(g[0]) + float(g[2]) * 0.5, float(g[1]) + float(g[3]) * 0.5))
	return dflt


func _step_cart(A: Dictionary, snap: Dictionary, dt: float) -> void:
	var st := String(A.get("st", ""))
	if st == "loading":
		var tid := int(A.tid)
		var ph := String((teams.get(tid, {}) as Dictionary).get("phase", ""))
		var el := stime - float(A.t_load)
		A.row = 0 if el < 1.8 else (1 if el < 3.6 else 2)
		if (ph != "loading" and ph != "to_pad" and el > 1.0) or el > 9.0:
			var L: Dictionary = lay.get(int(A.fac), {})
			A.path = _route(L, A.p, A.home)
			A.d = 0.0
			A.st = "back"
			A.row = 2 if el >= 3.6 else A.row
		return
	var arrived := _walk(A, dt)
	if not arrived:
		return
	if st == "back":
		A.dead = true
		return
	A.st = "loading"
	A.t_load = stime
	n_loads += 1


func _step_litter(A: Dictionary, snap: Dictionary, dt: float) -> void:
	var st := String(A.get("st", ""))
	if st == "pick":
		if stime - float(A.t_pick) > 1.2:
			var L: Dictionary = lay.get(int(A.fac), {})
			A.row = 0
			A.path = _route(L, A.p, A.dest)
			A.d = 0.0
			A.spd = CARRY_SPD
			A.gait = "walk"
			A.st = "carry"
		return
	var arrived := _walk(A, dt)
	if not arrived:
		return
	if st == "carry":
		if bool(A.exposed):
			quarantine[int(A.fac)] = stime + 25.0
			n_quar += 1
		A.dead = true
		return
	A.st = "pick"
	A.t_pick = stime
	A.f = float(A.get("f", 0.0)) + PI


# ================================================================ particles
func _puff(p: Vector2, h: float, v: Vector2, vh: float, life: float, r0: float, r1: float, col: Color, a: float, occ_fac: int = -1) -> void:
	if puffs.size() >= MAX_PUFFS:
		return
	puffs.append({"p": p, "h": h, "v": v, "vh": vh, "t0": stime, "life": life, "r0": r0, "r1": r1, "col": col, "a": a, "of": occ_fac})


func _tick_puffs(dt: float) -> void:
	var keep := []
	for P in puffs:
		var age := stime - float(P.t0)
		if age > float(P.life) or age < 0.0:
			continue
		P.p = (P.p as Vector2) + (P.v as Vector2) * dt
		P.v = (P.v as Vector2) * maxf(0.0, 1.0 - 1.6 * dt)
		P.h = maxf(0.0, float(P.h) + float(P.vh) * dt)
		keep.append(P)
	puffs = keep


# ================================================================ drawing
func _scr(p: Vector2) -> Vector2:
	return ViewUtil.world_to_screen_h(hm, p) if not hm.is_empty() else ViewUtil.iso(p)


func _tex(path: String) -> Texture2D:
	if _texc.has(path):
		return _texc[path]
	var t: Texture2D = null
	if path != "":
		if path.ends_with(".png"):
			var img := _load_img(path)   # ORCH: works in exported builds too
			if img != null and not img.is_empty():
				t = ImageTexture.create_from_image(img)
		elif ResourceLoader.exists(path):
			t = load(path)
	_texc[path] = t
	return t


## Soldier sheet {tex, mask, dirty, idx {frame: i}, fw, fh, pv} for an infantry art id or unit def.
func _soldier(def: String) -> Dictionary:
	if _sheet.has(def):
		return _sheet[def]
	var man: Dictionary = ArtCat.manifest()
	var inf: Dictionary = man.get("infantry", {})
	var id := def
	if not inf.has(id):
		id = "g7_" + def
	if not inf.has(id):
		id = "g7_b_cn_gunner" if def.contains("b_") else "g7_cn_gunner"
	var e: Dictionary = inf.get(id, {})
	var idx := {}
	var fr: Array = e.get("frames", [])
	for i in fr.size():
		idx[String(fr[i])] = i
	var dirty: Dictionary = (man.get("seq7", {}) as Dictionary).get("crew_dirty", {})
	var S := {"tex": _tex(String(e.get("file", ""))), "mask": _tex(String(e.get("mask", ""))),
		"dirty": _tex(String(dirty.get(id, ""))), "idx": idx, "fw": int(e.get("fw", 32)), "fh": int(e.get("fh", 32)),
		"pv": Vector2(e.get("pivot", [16, 27])[0], e.get("pivot", [16, 27])[1])}
	_sheet[def] = S
	return S


func _row8(f: float) -> int:
	return posmod(int(round(f / (PI / 4.0))), 8)


func _draw_soldier(def: String, p: Vector2, f: float, frame: String, dirty: bool, owner: int, mod: Color = Color.WHITE, clip: float = INF) -> void:
	var S := _soldier(def)
	var t: Texture2D = S.dirty if dirty and S.dirty != null else S.tex
	if t == null:
		draw_circle(_scr(p) + Vector2(0, -6), 3.0, Color(0.5, 0.55, 0.5))
		return
	var fi := int((S.idx as Dictionary).get(frame, 0))
	var fw := int(S.fw)
	var fh := int(S.fh)
	var at := (_scr(p) - (S.pv as Vector2)).round()
	var vh := fh
	if clip < at.y + float(fh):
		vh = int(floor(clip - at.y))
		if vh <= 0:
			return
	var src := Rect2(fi * fw, _row8(f) * fh, fw, vh)
	draw_texture_rect_region(t, Rect2(at, Vector2(fw, vh)), src, mod)
	if S.mask != null:
		draw_texture_rect_region(S.mask, Rect2(at, Vector2(fw, vh)), src, _cols.get(owner, Color(0.85, 0.85, 0.8)) * mod)
	drawn += 1


func _gait_frame(A: Dictionary, S: Dictionary) -> String:
	var g := String(A.get("gait", "walk"))
	var d := float(A.get("d", 0.0))
	var idx: Dictionary = S.idx
	# SEQ7-3 (13.9c-13 "no sliding"): one frame per spd / fps tiles travelled, so the feet move at motion.gd's sprint
	# (16 fps) / walk (10 fps) cadence at this figure's own speed (was a fixed 0.34 / 0.26 tile per frame: legs at
	# half speed, the figures skated); a figure that stops stops its legs
	var spd := maxf(0.3, float(A.get("spd", WALK_SPD)))
	if g == "run" and idx.has("run_0"):
		return "run_%d" % (int(d / spd * RUN_FPS + float(int(A.get("uid", 0)) % 6)) % 6)
	if idx.has("walk_0"):
		return "walk_%d" % (int(d / spd * WALK_FPS + float(int(A.get("uid", 0)) % 6)) % 6)
	return "idle"


## True when world point p (a figure of height ~18 px) is hidden behind a building, a team APC or a dropship.
func _occluded(p: Vector2, fid: int) -> bool:
	var L: Dictionary = lay.get(fid, {})
	if _box_hidden(p, 8.0, L.get("occ", [])):
		return true
	return _hull_hidden(p, _scr(p) + Vector2(0, -8))


## SEQ7-3: true when the point h px above world ground point p is behind one of the boxes [Rect2, height px] on screen
## (wash jets, mist, figures in the wash behind the 5.85 m link walls and the gate pillars).
func _box_hidden(p: Vector2, h: float, boxes: Array) -> bool:
	var sp := _scr(p) + Vector2(0, -h)
	for b in boxes:
		var R: Rect2 = b[0]
		var x1 := R.end.x
		var y1 := R.end.y
		if p.x >= x1 or p.y >= y1 or R.has_point(p):
			continue
		if (x1 - p.x) + (y1 - p.y) > R.size.x + R.size.y + 6.0:
			continue
		var H := Vector2(0, -float(b[1]))
		var A0 := _scr(R.position)
		var B0 := _scr(Vector2(x1, R.position.y))
		var C0 := _scr(R.end)
		var D0 := _scr(Vector2(R.position.x, y1))
		var poly := PackedVector2Array([D0, C0, B0, B0 + H, A0 + H, D0 + H])
		if Geometry2D.is_point_in_polygon(sp, poly):
			return true
	return false


## SEQ7-3: screen y of the top edge of the box (Rect2, height px) that hides the feet of a figure standing at p, INF when
## the feet are in view.
func _clip_y(p: Vector2, boxes: Array) -> float:
	var sp := _scr(p) + Vector2(0, -1)
	var best := INF
	for b in boxes:
		var R: Rect2 = b[0]
		var x1 := R.end.x
		var y1 := R.end.y
		if p.x >= x1 or p.y >= y1 or R.has_point(p):
			continue
		if (x1 - p.x) + (y1 - p.y) > R.size.x + R.size.y + 6.0:
			continue
		var H := Vector2(0, -float(b[1]))
		var A0 := _scr(R.position)
		var B0 := _scr(Vector2(x1, R.position.y))
		var C0 := _scr(R.end)
		var D0 := _scr(Vector2(R.position.x, y1))
		var poly := PackedVector2Array([D0, C0, B0, B0 + H, A0 + H, D0 + H])
		if not Geometry2D.is_point_in_polygon(sp, poly):
			continue
		for i in poly.size():
			var a := poly[i]
			var c := poly[(i + 1) % poly.size()]
			if (a.x - sp.x) * (c.x - sp.x) <= 0.0 and absf(c.x - a.x) > 0.001:
				best = minf(best, lerpf(a.y, c.y, (sp.x - a.x) / (c.x - a.x)))
	return best


func _hull_hidden(p: Vector2, sp: Vector2) -> bool:
	var snap: Dictionary = mv.snap
	for tid in teams:
		for aid in teams[tid].apcs:
			var ap := _upos(snap, int(aid))
			if ap != Vector2.INF and ap.x + ap.y > p.x + p.y + 0.15 and ap.distance_to(p) < 1.6:
				var s := _scr(ap)
				if absf(sp.x - s.x) < 30.0 and sp.y > s.y - 30.0 and sp.y < s.y + 10.0:
					return true
	for cid in crafts:
		var C: Dictionary = crafts[cid]
		if C.has("pos"):
			var cp: Vector2 = C.pos
			if cp.x + cp.y > p.x + p.y + 0.2 and cp.distance_to(p) < 3.6:
				var s := _scr(cp)
				if absf(sp.x - s.x) < 92.0 and sp.y > s.y - 56.0 and sp.y < s.y + 22.0:
					return true
	return false


func _draw() -> void:
	drawn = 0
	if not on:
		return
	var snap: Dictionary = mv.snap if mv != null else {}
	# ground: dust / mist / runoff below the figures
	_draw_sprays(snap)
	var items := []
	for A in actors:
		if stime < float(A.get("delay", 0.0)) or bool(A.get("hidden", false)) or not A.has("p"):
			continue
		if _occluded(A.p, int(A.get("fac", -1))):
			hidden_occ += 1
			continue
		# SEQ7-3: a figure whose feet are behind a building but whose head shows above its roof line is cut at that line
		# (was drawn whole: it stood on the gatehouse roof)
		A.clip = _clip_y(A.p, (lay.get(int(A.get("fac", -1)), {}) as Dictionary).get("occ", [])) if String(A.kind) == "crew" else INF
		items.append([(A.p as Vector2).x + (A.p as Vector2).y, A])
	for cid in crafts:
		var C: Dictionary = crafts[cid]
		if C.has("pos") and _ramp_down(C):
			var fwd := Vector2.from_angle(float(C.f))
			var sd := Vector2(-fwd.y, fwd.x)
			var mp: Vector2 = (C.pos as Vector2) - fwd * 4.3 + sd * 1.9
			if not _occluded(mp, int(heli.get(cid, -1))):
				items.append([mp.x + mp.y, {"kind": "marshal", "p": mp, "f": float(C.f) + PI, "fac": int(heli.get(cid, -1))}])
	items.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for it in items:
		_draw_actor(it[1], snap)
	for P in puffs:
		var age := stime - float(P.t0)
		var k := age / float(P.life)
		var col: Color = P.col
		col.a = float(P.a) * (1.0 - k) * minf(1.0, age * 6.0)
		var r := lerpf(float(P.r0), float(P.r1), k)
		if int(P.of) >= 0 and _box_hidden(P.p, float(P.h), (lay.get(int(P.of), {}) as Dictionary).get("wocc", [])):
			continue   # SEQ7-3: wash mist behind the near link wall
		var s := _scr(P.p) + Vector2(0, -float(P.h))
		draw_set_transform(s, 0.0, Vector2(1.0, 0.62))
		# SEQ7-3: soft edge (outer half-alpha ring + denser core) so a dust cloud is not a flat disc
		var c2 := col
		c2.a = col.a * 0.55
		draw_circle(Vector2.ZERO, r, c2)
		draw_circle(Vector2(r * 0.15, -r * 0.1), r * 0.62, c2)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_actor(A: Dictionary, snap: Dictionary) -> void:
	match String(A.kind):
		"crew":
			var S := _soldier(String(A.def))
			var fr := _gait_frame(A, S) if String(A.get("st", "")) != "fading" and not bool(A.get("hold", false)) else "idle"
			var mod := Color(1, 1, 1, 1.0 - clampf((stime - float(A.get("t_fade", stime))) / 0.35, 0.0, 1.0))
			_draw_soldier(String(A.def), A.p, float(A.get("f", 0.0)), fr, bool(A.get("dirty", false)), int(A.owner), mod, float(A.get("clip", INF)))
		"cart":
			_draw_cart(A)
		"litter":
			_draw_litter(A)
		"marshal":
			var def := "g7_cn_deploy"
			_draw_soldier(def, A.p, float(A.f), "idle", false, int(_owner_of(int(A.fac))))
			# SEQ7-3: a hi-vis vest band and two lit batons beckoning the APC in ("come ahead": both batons swept up and
			# back toward the head), bolder so the marshaller reads at zoom 1.75
			var s := _scr(A.p)
			draw_rect(Rect2((s + Vector2(-3, -15)).round(), Vector2(6, 2)), Color(0.85, 1.0, 0.15, 0.9))
			var tips := _wand_tips(A.p)
			for i in 2:
				var side := -1.0 if i == 0 else 1.0
				var hand := s + Vector2(3.0 * side, -13.0)
				draw_line(hand, tips[i], Color(1.0, 0.62, 0.15), 2.0)
			n_marshal = maxi(n_marshal, 1)


## Screen tips of the marshaller's two batons (marshaller standing at world mp): the "come ahead" sweep, 0.8 s cycle.
func _wand_tips(mp: Vector2) -> Array:
	var s := _scr(mp)
	var sw := sin(stime * TAU / 0.8)
	var out := []
	for side: float in [-1.0, 1.0]:
		var hand := s + Vector2(3.0 * side, -13.0)
		out.append(hand + Vector2(side * (3.0 + 2.0 * sw), -6.0 - 3.0 * sw))
	return out


func _owner_of(fid: int) -> int:
	return int((lay.get(fid, {}) as Dictionary).get("owner", 0))


func _draw_cart(A: Dictionary) -> void:
	var man: Dictionary = (ArtCat.manifest().get("seq7", {}) as Dictionary)
	var c: Dictionary = man.get("cart", {})
	var t := _tex(String(c.get("file", "")))
	var f := float(A.get("f", 0.0))
	var st := String(A.get("st", ""))
	if st == "loading":
		var snap: Dictionary = mv.snap
		var ap := _upos(snap, int(A.apc))
		if ap != Vector2.INF:
			f = ((ap - (A.p as Vector2)).angle() + PI * 0.5)
	if t != null:
		var fw := int(c.fw)
		var fh := int(c.fh)
		var pv := Vector2(c.pivot[0], c.pivot[1])
		var at := (_scr(A.p) - pv).round()
		draw_texture_rect_region(t, Rect2(at, Vector2(fw, fh)), Rect2(_row8(f) * fw, int(A.get("row", 0)) * fh, fw, fh))
		drawn += 1
	if st == "loading":
		_draw_loaders(A)


## Two loaders between the trailer and the APC: one lifting the pod pack onto the APC, one handing up crates.
func _draw_loaders(A: Dictionary) -> void:
	var snap: Dictionary = mv.snap
	var ap := _upos(snap, int(A.apc))
	if ap == Vector2.INF:
		return
	var cp: Vector2 = A.p
	var el := stime - float(A.t_load)
	var to := (ap - cp)
	var dir := to.normalized()
	var def := "g7_b_cn_deploy" if _owner_of(int(A.fac)) != 0 and false else "g7_cn_deploy"
	var owner := int(A.owner)
	var man: Dictionary = (ArtCat.manifest().get("seq7", {}) as Dictionary)
	var ppk: Dictionary = man.get("podpack", {})
	var crt: Dictionary = man.get("crate", {})
	for j in 2:
		var side := Vector2(-dir.y, dir.x) * (0.45 if j == 0 else -0.45)
		var p0 := cp + dir * 0.6 + side
		var p1 := ap - dir * 0.9 + side
		# SEQ7-3 (13.9c-13): lift at the trailer, walk it over (walk cadence at 1 tile/s), hand it up onto the deck, walk
		# back; the legs move only while the loader moves (was an eased glide on the lift frames: the loaders slid)
		var span := maxf(0.2, p0.distance_to(p1))
		var cyc := 0.9 + 2.0 * span
		var tc := fmod(el + cyc * 0.5 * float(j), cyc)
		var p := p0
		var fr := "act_0"
		var phase := 0.0   # < 0.5: loaded, on the way to the APC
		var lift := 8.0
		if tc < 0.45:
			pass
		elif tc < 0.45 + span:
			var k := (tc - 0.45) / span
			p = p0.lerp(p1, k)
			fr = "walk_%d" % (int(k * span * WALK_FPS) % 6)
			phase = 0.25
			lift = 12.0
		elif tc < 0.9 + span:
			p = p1
			fr = "act_1"
			phase = 0.45
			lift = 18.0
		else:
			var k := (tc - 0.9 - span) / span
			p = p1.lerp(p0, k)
			fr = "walk_%d" % (int(k * span * WALK_FPS) % 6)
			phase = 0.75
		_draw_soldier(def, p, dir.angle() if phase < 0.5 else dir.angle() + PI, fr, false, owner)
		# what they carry on the way to the APC
		if phase < 0.5:
			var item: Dictionary = ppk if (j == 0 and el < 1.8) else crt
			var tt := _tex(String(item.get("file", "")))
			if tt != null and not (j == 0 and el >= 3.6) and not (j == 1 and el >= 3.6):
				var fw := int(item.fw)
				var fh := int(item.fh)
				var pv := Vector2(item.pivot[0], item.pivot[1])
				draw_texture_rect_region(tt, Rect2((_scr(p) - pv - Vector2(0, lift)).round(), Vector2(fw, fh)), Rect2(_row8(dir.angle()) * fw, 0, fw, fh))


func _draw_litter(A: Dictionary) -> void:
	var man: Dictionary = (ArtCat.manifest().get("seq7", {}) as Dictionary)
	var c: Dictionary = man.get("stretcher", {})
	var t := _tex(String(c.get("file", "")))
	var f := float(A.get("f", 0.0))
	var fwd := Vector2.from_angle(f)
	var front: Vector2 = (A.p as Vector2) + fwd * 0.34
	var back: Vector2 = (A.p as Vector2) - fwd * 0.34
	var S := _soldier(String(A.def))
	var fr := _gait_frame(A, S) if String(A.get("st", "")) != "pick" else "act_0"
	var parts := [[back.x + back.y, "b"], [front.x + front.y, "f"], [(A.p as Vector2).x + (A.p as Vector2).y, "s"]]
	parts.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for q in parts:
		match String(q[1]):
			"b":
				_draw_soldier(String(A.def), back, f, fr, false, int(A.owner))
			"f":
				_draw_soldier(String(A.def), front, f, fr, false, int(A.owner))
			"s":
				if t != null:
					var fw := int(c.fw)
					var fh := int(c.fh)
					var pv := Vector2(c.pivot[0], c.pivot[1])
					var row := int(A.get("row", 1))
					if String(A.get("st", "")) == "pick":
						row = 0 if stime - float(A.t_pick) > 0.6 else 1
					draw_texture_rect_region(t, Rect2((_scr(A.p) - pv).round(), Vector2(fw, fh)), Rect2(_row8(f) * fw, row * fh, fw, fh))
					drawn += 1


func _ramp_down(C: Dictionary) -> bool:
	var b := String(C.get("bay", ""))
	return b != "" and b != "ramp_up"


## Wash spray: nozzle bars on both sides of the lane, jets onto the hull, droplets, runoff that clears as it runs.
func _draw_sprays(_snap: Dictionary) -> void:
	for aid in sprays:
		var S: Dictionary = sprays[aid]
		if float(S.done) > 0.0:
			continue
		var p := _upos(mv.snap, int(aid))
		if p == Vector2.INF:
			continue
		var fwd: Vector2 = S.fwd
		var sd := Vector2(-fwd.y, fwd.x)
		var prog := clampf((stime - float(S.t0)) / 5.0, 0.0, 1.0)
		var wo: Array = (lay.get(int(S.fac), {}) as Dictionary).get("wocc", [])
		# SEQ7-3: everything stays inside the enclosed wash (nozzles inboard of the link walls, runoff to the lane edge
		# drains) and is hidden where the near link wall / a gate pillar stands in front of it
		# runoff sheets under the hull flowing out to the lane drains (green while contaminated, clearer as it rinses)
		var rc := RUNOFF.lerp(WATER, prog)
		for side: float in [-1.0, 1.0]:
			for k in 5:
				var u := (float(k) - 2.0) * 0.45
				var ph := fmod(stime * 1.6 + float(k) * 0.37, 1.0)
				var a0 := p + fwd * u + sd * side * (HULL + 0.55 * ph)
				var a1 := a0 + sd * side * 0.18
				if _box_hidden(a0, 0.0, wo):
					continue
				rc.a = 0.45 * (1.0 - ph)
				draw_line(_scr(a0), _scr(a1), rc, 1.0)
		var col := WATER
		col.a = 0.55
		for side: float in [-1.0, 1.0]:
			for k in 5:
				var u := (float(k) - 2.0) * 0.42
				for hh: float in [5.0, 15.0]:
					# jet from the nozzle bar to the hull side, drawn in 3 pieces so the near wall cuts it cleanly
					var n0 := p + fwd * u + sd * side * NOZ
					var n1 := p + fwd * (u * 0.92) + sd * side * HULL
					var h0 := hh
					var h1 := hh * 0.7 + 3.0
					for m in 3:
						var t0 := float(m) / 3.0
						var t1 := float(m + 1) / 3.0
						var mid := n0.lerp(n1, (t0 + t1) * 0.5)
						if _box_hidden(mid, lerpf(h0, h1, (t0 + t1) * 0.5), wo):
							continue
						var s0 := _scr(n0.lerp(n1, t0)) + Vector2(0, -lerpf(h0, h1, t0))
						var s1 := _scr(n0.lerp(n1, t1)) + Vector2(0, -lerpf(h0, h1, t1))
						draw_line(s0, s1, col, 1.0)
						var tt := fmod(stime * 3.0 + float(k) * 0.13 + hh * 0.01 + float(m) * 0.31, 1.0)   # a droplet
						draw_rect(Rect2(s0.lerp(s1, tt).round(), Vector2(1, 1)), Color(1, 1, 1, 0.85))
		# overhead gantry bar across the lane spraying down onto the roof (3.5 m), cut by the near wall too
		for m in 7:
			var v := (float(m) - 3.0) / 3.0 * NOZ * 0.9
			var q := p + sd * v
			if _box_hidden(q, 34.0, wo):
				continue
			var ph := fmod(stime * 2.5 + float(m) * 0.21, 1.0)
			var top := _scr(q) + Vector2(0, -34)
			draw_line(top, top + Vector2(0, 14.0 * ph + 4.0), Color(0.85, 0.93, 1.0, 0.5 * (1.0 - ph)), 1.0)


func _draw_glow() -> void:
	# SEQ7-3: every call draws on the additive glow child (was self.draw_*: Godot refused each one with "Drawing is only
	# allowed inside this node's _draw()", 8605 errors in one playtest, and no beacon / strobe / scan light ever showed)
	if not on:
		return
	var t := stime
	# scramble beacons: rotating amber on the launching team's garages and the loading pad corners
	for fid in scramble:
		var S: Dictionary = scramble[fid]
		if t > float(S.until):
			continue
		var L: Dictionary = lay.get(int(fid), {})
		var pts := []
		for g in S.garages:
			var R: Rect2 = g
			pts.append([R.position + Vector2(R.size.x, 0), 40.0])
			pts.append([R.end, 40.0])
		var pad = (L.get("zones", {}) as Dictionary).get("pad")
		if pad is Rect2:
			for c in [pad.position, pad.position + Vector2(pad.size.x, 0), pad.end, pad.position + Vector2(0, pad.size.y)]:
				pts.append([c, 1.0])   # ORCH (LIGHT7-2 CR 5928): flush pad-edge light, not 6 px in the air
		for i in pts.size():
			_beacon(pts[i][0], float(pts[i][1]), t * 5.5 + float(i) * 1.3, AMBER)
		# pad floor chasers round each loading APC slot while the team is at the pad
		var D: Dictionary = teams.get(int(S.tid), {})
		if pad is Rect2 and PHASE_LAUNCH.has(String(D.get("phase", ""))):
			var n := (D.apcs as Array).size()
			for i in n:
				var slot: Vector2 = pad.get_center() + Vector2((float(i) - 0.5 * float(maxi(0, n - 1))) * 3.0, 0.0)
				for k in 8:
					var a := TAU * float(k) / 8.0
					var on_k := int(t * 8.0) % 8 == k
					var q := _scr(slot + Vector2(cos(a) * 1.5, sin(a) * 1.2))
					glow.draw_circle(q, 2.5 if on_k else 1.2, Color(1.0, 0.7, 0.2, 0.9 if on_k else 0.35))
	# dropship: ramp strobes + lit bay spill while the ramp is down; lift-fan glow while spooling / lifting
	for cid in crafts:
		var C: Dictionary = crafts[cid]
		if not C.has("pos"):
			continue
		var p: Vector2 = C.pos
		var fwd := Vector2.from_angle(float(C.f))
		var sd := Vector2(-fwd.y, fwd.x)
		if _ramp_down(C):
			var spill := PackedVector2Array([_scr(p - fwd * 2.4 + sd * 0.9), _scr(p - fwd * 2.4 - sd * 0.9), _scr(p - fwd * 4.0 - sd * 1.5), _scr(p - fwd * 4.0 + sd * 1.5)])
			glow.draw_colored_polygon(spill, Color(1.0, 0.82, 0.55, 0.11))   # SEQ7-3: 0.22 washed out the APC on the ramp
			# SEQ7-3: ramp-edge strobes readable at zoom 1.75: 4 lamps per edge chasing toward the bay (the way in), a lit
			# lamp = hot core + halo, the others a steady dim amber so the ramp edges read between flashes
			for k in 4:
				for s: float in [-1.0, 1.0]:
					var on_k := 3 - (int(t * 8.0) % 4) == k
					var q := _scr(p - fwd * (2.2 + 0.45 * float(k)) + sd * s * 0.9) + Vector2(0, -2)
					if on_k:
						glow.draw_circle(q, 7.0, Color(1.0, 0.55, 0.10, 0.35))
						glow.draw_circle(q, 3.2, Color(1.0, 0.85, 0.45, 1.0))
					else:
						glow.draw_circle(q, 1.8, Color(1.0, 0.60, 0.15, 0.65))
			# marshaller's wands (lit batons) with a halo at each tip
			var mp := p - fwd * 4.3 + sd * 1.9
			for tip in _wand_tips(mp):
				glow.draw_circle(tip, 4.0, Color(1.0, 0.45, 0.08, 0.40))
				glow.draw_circle(tip, 1.6, Color(1.0, 0.80, 0.40, 1.0))
		var k := float(C.get("k", 0.0))
		if k > 0.05:
			for u: float in [-1.3, 1.3]:
				for v: float in [-1.5, 1.5]:
					var q := _scr(p + fwd * u + sd * v)
					glow.draw_set_transform(q, 0.0, Vector2(1.0, 0.5))
					glow.draw_circle(Vector2.ZERO, 7.0 + 5.0 * k, Color(0.55, 0.75, 1.0, 0.22 * k * (0.8 + 0.2 * sin(t * 30.0))))
					glow.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# decon hall: scan pulses in the doors while crews are inside
	for fid in hall_busy:
		if t > float(hall_busy[fid]):
			continue
		var L: Dictionary = lay.get(int(fid), {})
		for i in 2:
			var d := _door(L, "decon_hall", i)
			var pul := 0.5 + 0.5 * sin(t * 9.0 + float(i) * 2.0)
			glow.draw_set_transform(_scr(d) + Vector2(0, -8), 0.0, Vector2(1.0, 0.6))
			glow.draw_circle(Vector2.ZERO, 9.0, Color(SCAN.r, SCAN.g, SCAN.b, 0.25 + 0.35 * pul))
			glow.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if _rng.randf() < 0.25:
			var d0 := _door(L, "decon_hall", 0)
			_puff(d0, 4.0, Vector2(_rng.randf_range(-0.3, 0.3), 0.5), 6.0, 1.6, 2.0, 7.0, Color(0.85, 0.95, 1.0), 0.18)
	# quarantine bay: rotating violet beacon on the roof + a pulsing ring at its door
	for fid in quarantine:
		if t > float(quarantine[fid]):
			continue
		var L: Dictionary = lay.get(int(fid), {})
		var keys: Dictionary = L.get("keys", {})
		var q := String(keys.get("quarantine", "")) if String(keys.get("quarantine", "")) != "" else String(keys.get("aid", ""))
		var R = (L.get("zones", {}) as Dictionary).get(q)
		if R is Rect2:
			# SEQ7-3: one lamp on FACB7's quarantine-bay lamp spot (fact facb7.zone_heights: roof z 4.75 m, west end of
			# the aid station; was two beacons + ground beams floating off the zone corners)
			var lamp := Vector2((R as Rect2).position.x + 0.35, (R as Rect2).get_center().y)
			_beacon(lamp, 4.75 * 9.8, t * 6.0, VIOLET, false)
			glow.draw_circle(_scr(lamp) + Vector2(0, -4.75 * 9.8), 10.0, Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.10 + 0.10 * maxf(0.0, cos(t * 6.0))))
		# violet light spilling out of the bay door onto the ground (was a ring floating on the asphalt)
		var d := _door(L, q) if q != "" else Vector2.ZERO
		var pul := 0.5 + 0.5 * sin(t * 4.0)
		glow.draw_set_transform(_scr(d), 0.0, Vector2(1.0, 0.5))
		glow.draw_circle(Vector2.ZERO, 10.0, Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.10 + 0.12 * pul))
		glow.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# pass / flag lights at the decon exits and walkway decons
	var keep := []
	for fl in flashes:
		var age := t - float(fl[2])
		if age > float(fl[3]) or age < 0.0:
			continue
		keep.append(fl)
		var p: Vector2 = fl[0]
		if p == Vector2.INF:
			var pp := _upos(mv.snap, int(fl[4]))
			if pp == Vector2.INF:
				continue
			p = pp
		var col: Color = fl[1]
		col.a = 0.8 * (1.0 - age / float(fl[3]))
		glow.draw_circle(_scr(p) + Vector2(0, -10), 8.0, col)
	flashes = keep


## Rotating beacon at world corner c, h px above the ground: bright core when the lens faces the camera, a beam
## sweeping the ground round it.
func _beacon(c: Vector2, h: float, ang: float, col: Color, beam: bool = true) -> void:
	var s := _scr(c) + Vector2(0, -h)
	var face := maxf(0.0, cos(ang))
	glow.draw_circle(s, 3.0 + 4.0 * face, Color(col.r, col.g, col.b, 0.18 + 0.25 * face))   # SEQ7-3: halo
	glow.draw_circle(s, 1.6 + 1.6 * face, Color(col.r, col.g, col.b, 0.65 + 0.35 * face))
	if not beam:
		return
	# LIGHT7-2 CR 5928 (13.9c-18): the translucent ground wedge is gone; lens flash + halo only


## World tile position a "follow the launch" camera could centre on (most recent sequence), Vector2.INF when none
## ran in the last 20 s of game time.
func seq_focus() -> Vector2:
	return _focus if stime - _focus_t < 20.0 else Vector2.INF


## ORCH (G7 packaged fix): load an image in the editor AND in an exported build. Exported builds have no raw PNG in the
## .pck (only the imported texture), so Image.load_from_file / FileAccess fail there; fall back to the imported texture.
static func _load_img(path: String) -> Image:
	var p := path if path.begins_with("res://") else "res://" + path
	if FileAccess.file_exists(p):
		var bytes := FileAccess.get_file_as_bytes(p)
		if not bytes.is_empty():
			var im := Image.new()
			if im.load_png_from_buffer(bytes) == OK:
				return im
	if ResourceLoader.exists(p):
		var t = load(p)
		if t is Texture2D:
			var ti := (t as Texture2D).get_image()
			if ti != null and ti.is_compressed():
				ti.decompress()
			if ti != null and not ti.is_empty() and ti.get_format() != Image.FORMAT_RGBA8:
				ti.convert(Image.FORMAT_RGBA8)
			return ti
	return null
