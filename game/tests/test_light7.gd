extends "res://tests/test_base.gd"
## G7 LIGHT7 (owner 13.9c-24 "facility lights have all proper realistic placement nothing floating", 13.9c-24a
## "lighting and light fixtures still need upgrading and more realistic approach / placement / everything", 13.9c-18
## "NO transparent anything"): the facility lighting plan in presentation/view/fac_atmo7.gd. Display only.
##  - every fixture is mounted on a real surface at that surface's drawn height (wall cap, tower searchlight head,
##    lane verge pole, building / garage facade above its door, command-centre roof brim, roof-pad deck)
##  - every ground light pool is cut where a building / garage / tower / wall hides the ground: no light on a roof, no
##    translucent volume over a building; the cut keeps no holes; the rotating beacons draw no wedge
##  - the light count is bounded (fps); the state hash is identical with the layer on / off.

const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Movement = preload("res://sim/systems/movement.gd")
const RenderSnap = preload("res://sim/render_snap.gd")
const Atmo = preload("res://presentation/view/fac_atmo7.gd")


class FakeMV extends RefCounted:
	var _world = null
	var snap: Dictionary = {}
	func team_color(_f: int) -> Color:
		return Color(0.2, 0.5, 1.0)


func _setup() -> Array:
	var w := make_world()
	if Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")
	w.ai_state = {}
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var n := mini(60, mini(mw, mh) - 2)
	var o := Vector2i(mw / 2 - n / 2, mh / 2 - n / 2)
	var r := Rect2i(o, Vector2i(n, n))
	var t: PackedByteArray = w.map.terrain
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if r.has_point(w.cell_of(e.pos)) and e.kind != "building":
			w.entities.erase(id)
	w.cache.clear()
	Movement.rebuild_nav(w)
	var off: Array = CnFacility.conf().core_offset
	var fid := w.spawn_building("a_cn_facility", 0, o + Vector2i(2, 2) + Vector2i(int(off[0]), int(off[1])), true)
	w.run_ticks(CnFacility.DISCOVER_EVERY + 1)
	return [w, fid]


func _layer(w: SimWorld) -> Array:
	var mv := FakeMV.new()
	mv._world = w
	var L = Atmo.new()
	L.setup(mv)
	return [L, mv]


func _frame(L, mv, w: SimWorld, n := 1) -> void:
	for i in n:
		RenderSnap.build(w)
		mv.snap = RenderSnap.latest(w)
		L.on_events(w.events)
		L.refresh(mv.snap)
		L._fac_frame = -999


func _geo() -> Array:
	var s := _setup()
	var w: SimWorld = s[0]
	var lm := _layer(w)
	_frame(lm[0], lm[1], w)
	return [lm[0], lm[0].geo[0]]


static func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		var q := p[(i + 1) % p.size()]
		a += p[i].x * q.y - q.x * p[i].y
	return absf(a) * 0.5


static func _r(a: Array, O: Vector2) -> Rect2:
	return Rect2(O + Vector2(float(a[0]), float(a[1])), Vector2(float(a[2]), float(a[3])))


func test_fixtures_mounted_on_surfaces() -> void:
	var lg := _geo()
	var L = lg[0]
	var g: Dictionary = lg[1]
	var C: Dictionary = CnFacility.conf()
	var O: Vector2 = g.O
	var cs := float(g.cs)
	var bad := []
	var kinds := {}
	var reserved := [_r(C.gate_outer, O)]
	for tw in C.towers:
		reserved.append(Rect2(O + Vector2(float(tw[0]), float(tw[1])), Vector2(2, 2)))
	reserved.append(Rect2(O + Vector2(float(C.checkpoint[0]), float(C.checkpoint[1])), Vector2(2, 2)))
	var blds := []
	for zn in g.zones:
		blds.append(g.zones[zn])
	blds.append(g.core_r)
	for ga in g.garages:
		blds.append(ga[0])
	for F in g.fix:
		var k := String(F.k)
		kinds[k] = int(kinds.get(k, 0)) + 1
		var at: Vector2 = F.at
		var q := at - O
		var z := float(F.z)
		# a fixture never hangs in the air: its lamp head is within a short bracket / arm of its mount point
		if (F.head as Vector2).distance_to(F.hp) > 12.0:
			bad.append("%s %s head %.1f px off its mount" % [k, str(q), (F.head as Vector2).distance_to(F.hp)])
		match k:
			"wall", "wall_in", "alarm", "walk":
				# WALL7-2 heights (fact wall7.heights, seq 5356): outer parapet panel top 4.66 m (46 px) at 1.25 m from the wall axis,
				# inner guard rail 4.68 m at 1.37 m, walkway lamps 3.17 m on the inner face 1.552 m from the axis
				var dn := minf(minf(q.y, cs - q.y), minf(q.x, cs - q.x))   # distance to the nearest outer edge: the axis is at 1.0
				var ax := dn - 1.0
				var on_ns := minf(q.y, cs - q.y) < minf(q.x, cs - q.x)
				var along := q.x if on_ns else q.y
				var sec := fposmod(along, 2.0)   # sections are 2 tiles: centres at odd coordinates
				var clash := false
				for rs in reserved:
					clash = clash or (rs as Rect2).has_point(at)
				var want_z: float = L.WALL_CAP_Z
				var want_ax: float = L.PANEL_OFF
				var want_sec := [1.0]
				if k == "wall_in":
					want_z = L.RAIL_Z
					want_ax = -L.RAIL_OFF
					want_sec = [1.2]
				elif k == "walk":
					want_z = L.WALK_LAMP_Z
					want_ax = -L.WALK_OFF
					want_sec = [0.5, 1.5]
				var sec_ok := false
				for ws in want_sec:
					sec_ok = sec_ok or absf(sec - float(ws)) < 0.02
				if clash or not is_equal_approx(z, want_z) or absf(absf(ax) - absf(want_ax)) > 0.011 or not sec_ok:
					bad.append("%s %s not on its wall mount (z %.1f want %.1f, %.3f from the axis want %.3f, section phase %.2f)" % [k, str(q), z, want_z, ax, want_ax, sec])
				var inside := Rect2(O, Vector2(cs, cs)).has_point(F.pool)
				if k == "wall" and inside:
					bad.append("wall flood %s pool not outside the wall (clear zone)" % str(q))
				if k == "wall_in":
					var on_pad := false
					for zn in ["pad", "helipad"]:
						on_pad = on_pad or ((g.zones as Dictionary).has(zn) and (g.zones[zn] as Rect2).has_point(F.pool))
					if not on_pad:
						bad.append("apron flood %s pool not on a pad" % str(q))
			"corner":   # the junction mast floodlight in the wall art: head 5.44 m, 1.08 m from the junction centre on both axes
				var jc := Vector2(1.0 if q.x < cs * 0.5 else cs - 1.0, 1.0 if q.y < cs * 0.5 else cs - 1.0)
				if not (q - jc).abs().is_equal_approx(Vector2(0.27, 0.27)) or absf(z - 5.41 * L.PX_M) > 0.5:
					bad.append("corner flood %s not on the junction mast (z %.1f)" % [str(q), z])
			"gate":   # ECP flood on an outer gate bastion cap, its pool outside on the approach
				var on_post := false
				var posts: Array = L._gate_posts(g)
				for i in mini(2, posts.size()):
					on_post = on_post or (at.is_equal_approx(posts[i][0]) and is_equal_approx(z, float(posts[i][1])))
				if not on_post or Rect2(O, Vector2(cs, cs)).has_point(F.pool):
					bad.append("gate flood %s not on an outer bastion cap / pool not on the approach" % str(q))
			"tower":
				var ok := false
				for tc in g.towers:
					ok = ok or at.is_equal_approx((tc as Vector2) + L.SEARCH_OFF)
				if not ok or not is_equal_approx(z, L.SEARCH_Z):
					bad.append("tower flood %s not on a tower searchlight head" % str(q))
			"pole":
				if not Rect2(O + Vector2(2, 2), Vector2(cs - 4, cs - 4)).has_point(at) or not is_equal_approx(z, L.POLE_Z):
					bad.append("pole %s outside the yard / wrong height" % str(q))
				for r in blds:
					if (r as Rect2).has_point(at):
						bad.append("pole %s stands in a building / zone %s" % [str(q), str(r)])
				for ln in C.lanes:   # in a lane only on the kerb line of a wide (>= 2 tile) lane
					var lr := _r(ln, O)
					if lr.has_point(at):
						var horiz := lr.size.x >= lr.size.y
						var wide := (lr.size.y if horiz else lr.size.x) >= 2.0
						var kerb := minf(at.y - lr.position.y, lr.end.y - at.y) if horiz else minf(at.x - lr.position.x, lr.end.x - at.x)
						if not wide or kerb > 0.25:
							bad.append("pole %s stands in a lane's drive line" % str(q))
				if at.distance_to(F.pool) > 1.0:
					bad.append("pole %s pool not under its head" % str(q))
			"yard":   # LIGHT7-4: the inward flood on the inner guard-rail post: RAIL_Z, 1.37 m inside the wall axis, aimed into the yard, wash inside the footprint
				var ydn := minf(minf(q.y, cs - q.y), minf(q.x, cs - q.x))
				var yns := minf(q.y, cs - q.y) < minf(q.x, cs - q.x)
				var ysec := fposmod(q.x if yns else q.y, 2.0)
				var yin := Vector2(cs * 0.5, cs * 0.5) - q
				var aim_in := (F.aim as Vector2).dot(yin) > 0.0 and absf((F.aim as Vector2).length() - 1.0) < 0.001
				if not is_equal_approx(z, L.RAIL_Z) or absf((ydn - 1.0) - L.RAIL_OFF) > 0.011 or not (absf(ysec - 0.8) < 0.02 or absf(ysec - 1.2) < 0.02) or not aim_in:
					bad.append("yard flood %s not on the inner guard-rail post (z %.1f, %.3f from the axis, section phase %.2f, aim %s)" % [str(q), z, ydn - 1.0, ysec, str(F.aim)])
				if not Geometry2D.is_point_in_polygon(L._iso(F.pool), g.foot) or not bool(F.get("inside", false)) or bool(F.get("lift", true)):
					bad.append("yard flood %s pool not inside the compound footprint" % str(q))
			"mast":   # LIGHT7-5: a 9 m area mast on a free verge / kerb line, its pool under it; zv (what a building in front hides of the shaft) below the crossbar
				if not is_equal_approx(z, L.MAST_Z):
					bad.append("mast %s not at the crossbar height (z %.1f)" % [str(q), z])
				if not L._verge_ok(g, C, at, [], Rect2(), 3.0, L.MAST_Z, true, false):
					bad.append("mast %s stands on a building / zone / lane drive line / door front" % str(q))
				if not (float(F.zv) >= 0.0 and float(F.zv) < L.MAST_Z) or at.distance_to(F.pool) > 0.01:
					bad.append("mast %s foot hidden above its crossbar (zv %.1f) / pool not under it" % [str(q), float(F.zv)])
			"wallf":   # LIGHT7-6: a wall-pack flood on a +x / +y face of a drawn block (or garage shed), under its roof line, in view, wash on the open ground in front
				var host := false
				var hz := 0.0
				var hosts: Array = (L._bld_boxes(g) as Array).duplicate()
				for ga in g.garages:
					hosts.append([(ga[0] as Rect2).grow(-0.1), L.GARAGE_Z, 0.0, false])
				for b in hosts:
					var br: Rect2 = b[0]
					if float(b[2]) > 0.0:
						continue
					var on_x := absf(at.x - (br.end.x + 0.04)) < 0.011 and at.y >= br.position.y and at.y <= br.end.y and (F.aim as Vector2).is_equal_approx(Vector2(1, 0))
					var on_y := absf(at.y - (br.end.y + 0.04)) < 0.011 and at.x >= br.position.x and at.x <= br.end.x and (F.aim as Vector2).is_equal_approx(Vector2(0, 1))
					if on_x or on_y:
						host = true
						hz = float(b[1])
				if not host or z > hz or z > L.WALLF_Z + 0.001 or bool(F.hid):
					bad.append("wall flood %s not on a visible +x / +y face of a drawn block (z %.1f, block height %.1f, hid %s)" % [str(q), z, hz, str(F.hid)])
				if not Geometry2D.is_point_in_polygon(L._iso(F.pool), g.foot) or not bool(F.get("inside", false)):
					bad.append("wall flood %s pool not inside the compound footprint" % str(q))
				for r in hosts:
					if (r[0] as Rect2).has_point(F.pool):
						bad.append("wall flood %s pool inside a building" % str(q))
			"door":
				var on_face := false
				var f := int(F.f)
				for r in blds:
					var rr: Rect2 = r
					var ins := rr.grow(-L.INSET)
					if f == 0 and at.y > rr.position.y and at.y < rr.end.y and (absf(at.x - ins.end.x) < 0.02 or (at.x <= rr.end.x + 0.6 and at.x >= rr.get_center().x)):
						on_face = true
					if f == 2 and at.y > rr.position.y and at.y < rr.end.y and absf(at.x - ins.position.x) < 0.02:
						on_face = true
					if f == 1 and at.x > rr.position.x and at.x < rr.end.x and (absf(at.y - ins.end.y) < 0.02 or (at.y <= rr.end.y + 0.6 and at.y >= rr.get_center().y)):
						on_face = true
				if not on_face or z < 20.0 or z > 60.0:
					bad.append("door lamp %s face %d not on a building face above a door (z %.1f)" % [str(q), f, z])
				for r in blds:
					if (r as Rect2).grow(-0.05).has_point(F.pool):
						bad.append("door lamp %s pool inside a building" % str(q))
			"obst":
				if not (g.zones.planning as Rect2).has_point(at) or not is_equal_approx(z, L.BRIM_Z):
					bad.append("obstruction lamp %s not on the command-centre roof brim" % str(q))
			"deck":
				var rp: Dictionary = C.roof_pad
				var rr := _r(rp.rect, O)
				var edge := rr.grow(0.01).has_point(at) and not rr.grow(-0.01).has_point(at)
				if not edge or not is_equal_approx(z, float(rp.deck_z) * L.PX_M):
					bad.append("roof-pad lamp %s not on the deck edge at deck height" % str(q))
	check(bad.is_empty(), "every fixture mounted on a drawn surface at its height: %s" % str(bad))
	for k in ["wall", "wall_in", "alarm", "walk", "gate", "tower", "pole", "door", "obst", "deck", "yard"]:
		check(int(kinds.get(k, 0)) > 0, "the plan has %s fixtures (%d)" % [k, int(kinds.get(k, 0))])
	# LIGHT7-7: masts and wall-pack floods exist only where a work cell needs them: report which branches this layout exercised
	var khid := {}
	var kempty := {}
	for F in g.fix:
		khid[String(F.k)] = int(khid.get(String(F.k), 0)) + (1 if F.hid else 0)
		kempty[String(F.k)] = int(kempty.get(String(F.k), 0)) + (1 if (F.P as Dictionary).is_empty() or (F.P.polys as Array).is_empty() else 0)
	print("LIGHT7 fixtures by kind %s hid %s emptypool %s" % [str(kinds), str(khid), str(kempty)])
	check(int(kinds.get("pole", 0)) >= 4, "lane area-light poles (%d)" % int(kinds.get("pole", 0)))
	# WALL7-2 fact wall7.heights (board seq 5356): battlement top 4.66 m = 46 px, guard rail 4.68 m, walkway lamps 3.17 m,
	# tower obstruction lamp 12.78 m, rampart half width 1.45 m; the wall's occluder strip follows (a light never lies on it)
	check(is_equal_approx(L.WALL_CAP_Z, 46.0) and absf(L.RAIL_Z - 4.68 * 9.8) < 0.01 and absf(L.WALK_LAMP_Z - 3.17 * 9.8) < 0.01
		and absf(L.MAST_TOP_Z - 12.78 * 9.8) < 0.01 and absf(L.WALL_HT - 1.45 / 4.0) < 0.0001 and is_equal_approx(L.WALL_Z, 46.0),
		"wall fixture heights are the WALL7-2 art heights (46 px battlement, 4.68 m rail, 3.17 m lamps, 12.78 m mast)")
	var oc: Array = L._occ_rects(g, C)
	var strip := 0
	for o in oc:
		if is_equal_approx(float(o[1]), 46.0) and absf(minf((o[0] as Rect2).size.x, (o[0] as Rect2).size.y) - 2.0 * L.WALL_HT) < 0.001:
			strip += 1
	check(strip == 4, "the four wall strips block at 46 px, 2.9 m thick (%d)" % strip)
	# the floating dot of the old tower floodlight head (in the cupola) and the beacon beam wedges are gone
	var src := FileAccess.get_file_as_string("res://presentation/view/fac_atmo7.gd")
	check(not src.contains("TOWER_Z - 10.0") and not src.contains("func _beam_rot("), "no floating tower dot, no beacon beam wedge")
	L.free()


func test_no_light_over_buildings() -> void:
	var lg := _geo()
	var L = lg[0]
	var g: Dictionary = lg[1]
	var pools := []
	for F in g.fix:
		if not (F.P as Dictionary).is_empty():
			pools.append(["%s %s" % [F.k, str((F.at as Vector2) - g.O)], F.P])
	for P in g.fpool:
		pools.append(["facade", P])
	for i in (g.apool as Array).size():
		pools.append(["alarm t%d" % i, g.apool[i]])
	var bad := []
	var lit := 0
	for e in pools:
		var P: Dictionary = e[1]
		for poly in P.polys:
			lit += 1
			if Geometry2D.is_polygon_clockwise(poly) != Geometry2D.is_polygon_clockwise(P.polys[0]):
				bad.append("%s: a hole polygon" % e[0])
			for s in g.lsil:   # LIGHT7-6: the drawn blocks + walls / towers / garages / gates (a whole-zone prism counted the open apron as building)
				if not (s[1] as Rect2).intersects(L._bb(poly)):
					continue
				var a := 0.0
				for ip in Geometry2D.intersect_polygons(poly, s[0]):
					a += _area(ip)
				if a > 1.0:
					bad.append("%s: %.1f px2 of light over a building / wall" % [e[0], a])
	check(lit > 20, "pools drawn (%d polygons)" % lit)
	check(bad.is_empty(), "no light pool over a building footprint / face: %s" % str(bad.slice(0, 8)))
	# LIGHT7-6: the drawn blocks the light is cut by are real reads of the art: each lies inside its own zone, every zone building with art
	# has its blocks, and they cover a real share of the zone (a broken read would leave light over the building)
	var by := {}
	var outz := []
	for b in L._bld_boxes(g):
		var r: Rect2 = b[0]
		var zn := ""
		for z in g.zones:
			if (g.zones[z] as Rect2).grow(0.05).encloses(r) and (zn == "" or L.BLD_Z.has(z)):
				zn = String(z)
		if zn == "" and not r.is_equal_approx(g.get("core_r", Rect2())):
			outz.append(str(r))
		by[zn] = float(by.get(zn, 0.0)) + r.get_area() * (1.0 if float(b[2]) <= 0.0 else 0.0)
	check(outz.is_empty(), "every drawn block inside its zone %s" % str(outz))
	for zn in ["planning", "workshop", "barracks", "armory", "lab", "decon_hall", "aid_station"]:
		if (g.zones as Dictionary).has(zn) and L._has_art(zn):
			var za: float = (g.zones[zn] as Rect2).get_area()
			check(float(by.get(zn, 0.0)) >= 0.25 * za and float(by.get(zn, 0.0)) <= 1.0 * za + 0.01, "%s blocks cover %.2f of the zone" % [zn, float(by.get(zn, 0.0)) / za])
	# the cut: a pool fully behind a building is empty; a building inside a pool leaves no hole
	var sil := [L._sil(Rect2(Vector2(10, 10), Vector2(2, 2)), 60.0)]
	var hidden: Dictionary = L._mk_pool(L._iso(Vector2(10.5, 10.5)) - Vector2(0, 30), 10.0, sil)
	check((hidden.polys as Array).is_empty(), "a pool behind a building is fully hidden")
	var around: Dictionary = L._mk_pool(L._iso(Vector2(11, 11)) - Vector2(0, 20), 200.0, sil)
	var a2 := 0.0
	for p in around.polys:
		a2 += _area(p)
		check(Geometry2D.intersect_polygons(p, sil[0][0]).is_empty() or _area(Geometry2D.intersect_polygons(p, sil[0][0])[0]) < 1.0, "split pool part clear of the building")
	check((around.polys as Array).size() >= 2 and a2 > 200.0 * 100.0 * PI * 0.6, "a building inside a pool is cut out by a split (no hole), most of the pool stays (%.0f px2)" % a2)
	# washes only for visible door lamps, inside their own facade (between the lamp and the ground)
	for F in g.fix:
		if F.has("wash"):
			check(String(F.k) == "door" and int(F.f) < 2 and not F.hid, "wall wash only under a visible door lamp")
	L.free()


func test_light_count_bounded() -> void:
	var lg := _geo()
	var L = lg[0]
	var g: Dictionary = lg[1]
	# LIGHT7-7: every light a night + lockdown redraw can count: each fixture (1) with its wash pool (1) and hot core (1 when it has one), a mast's
	# second lens, the facade / alarm pools, pad edge lights, garage spill, tower pulse + beacon (2 each), gate posts, wall lamps, the bay's lights
	var cores := 0
	var masts := 0
	var pools := 0
	var fixed := 0
	for F in g.fix:
		cores += 1 if F.has("core") else 0
		masts += 1 if String(F.k) == "mast" else 0
		pools += 0 if (F.P as Dictionary).is_empty() else 1
		fixed += 0 if String(F.k) in ["mast", "wallf"] else 1
	var bay := 0
	if g.has("bay"):
		bay = (g.bay.pools as Array).size() + (g.bay.lamps as Array).size() + (g.bay.strips as Array).size() + (g.bay.surf as Array).size() + 1
	var n: int = (g.fix as Array).size() + pools + cores + masts + (g.fpool as Array).size() + (g.edge as Array).size() + (g.garages as Array).size() \
		+ 2 * (g.towers as Array).size() + (L._gate_posts(g) as Array).size() + (g.lamps as Array).size() + bay
	check((g.fix as Array).size() <= 140, "fixtures per facility bounded (%d)" % (g.fix as Array).size())
	check(n <= L.LIGHT_CAP, "worst-case lights per redraw (night + lockdown) %d <= cap %d (fixtures %d, pools %d, cores %d, mast lenses %d, bay %d)" % [n, L.LIGHT_CAP, (g.fix as Array).size(), pools, cores, masts, bay])
	var poly_n := 0
	for F in g.fix:
		if not (F.P as Dictionary).is_empty():
			poly_n += (F.P.polys as Array).size()
		if F.has("P2") and not (F.P2 as Dictionary).is_empty():
			poly_n += (F.P2.polys as Array).size()
	check(poly_n <= 400, "pool polygons cached per facility bounded (%d)" % poly_n)
	check((g.win as Array).size() <= 160, "window panes per facility bounded (%d)" % (g.win as Array).size())
	check(fixed <= 140, "the fixtures every facility has leave the masts / wall floods a budget (%d fixed of 140)" % fixed)
	L.free()


## LIGHT7-7 (owner 13.9c-24d "interior lighting shouldnt be so dark"): every lane / apron cell where units work and the camera sees the ground
## (the planner's own work set) gets at least IL_MIN of interior tint lift from the fixtures that are actually fitted. Recomputed here from the
## final fixture list (not the planner's cached sum), so a mast the budget trimmed cannot leave a dark pocket unreported.
func test_work_cells_lit() -> void:
	var lg := _geo()
	var L = lg[0]
	var g: Dictionary = lg[1]
	var C: Dictionary = CnFacility.conf()
	var work: Array = L._work_cells(g, C)
	check(work.size() >= 100, "the work set covers the lanes / pads / staging / wash (%d visible cells)" % work.size())
	var lv: PackedFloat32Array = L._work_lift(work, g.fix)
	var dark := []
	var lo := 9.0
	for i in work.size():
		lo = minf(lo, lv[i])
		if lv[i] < L.IL_MIN:
			dark.append("%s:%.2f" % [str((work[i] as Vector2) - g.O), lv[i]])
	check(dark.is_empty(), "no dark pocket where units work: %d of %d cells below IL_MIN %.2f (min %.3f): %s" % [dark.size(), work.size(), L.IL_MIN, lo, " ".join(dark.slice(0, 80))])
	var cached: PackedFloat32Array = g.get("work_lv", PackedFloat32Array())
	check(cached.size() == lv.size(), "the planner's coverage record covers the same cells")
	var same := cached.size() == lv.size()
	for i in mini(cached.size(), lv.size()):
		same = same and absf(cached[i] - lv[i]) < 0.0005
	check(same, "the planner's coverage record is the fitted fixtures' (trimmed masts do not count)")
	L.free()


## LIGHT7-3 (owner 13.9c-24a / 24c): lit window panes. Every pane sits on its own building's visible wall (its centre inside that
## building's silhouette), on a +x / +y face, never inside a silhouette that stands in front of it; the grid covers the four
## multi-storey buildings and mixes dark, dim, lit and screen rooms; lit rooms are opaque (alpha 1 everywhere in the plan).
func test_window_panes_on_buildings() -> void:
	var lg := _geo()
	var L = lg[0]
	var g: Dictionary = lg[1]
	var by := {}
	var kinds := [0, 0, 0, 0]
	var off := []
	for P in g.win:
		by[String(P.zn)] = int(by.get(String(P.zn), 0)) + 1
		kinds[int(P.kind)] += 1
		var c := Vector2.ZERO
		var nv := 0
		for poly in P.polys:
			for v in poly:
				c += v
				nv += 1
		c /= float(maxi(nv, 1))
		var sl: Array = L._sil(g.zones[P.zn], float(L.BLD_Z[P.zn]))
		if not Geometry2D.is_point_in_polygon(c, sl[0]):
			off.append("%s %s" % [P.zn, str(c)])
		for tint in [P.tone]:
			check(float((tint as Color).a) == 1.0, "pane tone opaque")
	check(off.is_empty(), "every pane centre lies on its own building's silhouette: off %s" % str(off.slice(0, 4)))
	for zn in ["planning", "workshop", "barracks"]:   # the Suit Foundry's only windows (issue wing) are behind the decon hall: may have none
		if (g.zones as Dictionary).has(zn):
			check(int(by.get(zn, 0)) >= 6, "%s has window panes (%d)" % [zn, int(by.get(zn, 0))])
	check(kinds[0] >= 4 and kinds[1] >= 4 and kinds[2] >= 8 and kinds[3] >= 1, "dark / dim / lit / screen rooms all present %s" % str(kinds))
	var dark_share := float(kinds[0] + kinds[1]) / float(maxi(g.win.size(), 1))
	check(dark_share >= 0.3, "many windows dark or dim (%.2f)" % dark_share)
	L.free()


func _run(view: bool) -> String:
	var s := _setup()
	var w: SimWorld = s[0]
	var fid: int = s[1]
	var lm := _layer(w) if view else []
	for i in 120:
		if i == 30:
			CnFacility._lockdown(w, CnFacility.fac(w, fid), true)
		w.step()
		if view:
			lm[0].set_time_of_day("night")
			_frame(lm[0], lm[1], w)
	if view:
		lm[0].free()
	return w.state_hash()


func test_view_never_writes_sim() -> void:
	check_eq(_run(true), _run(false), "state hash identical with the lighting layer on / off")
