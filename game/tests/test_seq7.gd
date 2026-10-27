extends "res://tests/test_base.gd"
## G7 SEQ7 (13.9c-7): facility mission sequences (presentation/view/fac_seq7.gd), display only.
## Art present and registered; routes stay on walkable compound cells; launch (scramble, crew runners boarding,
## ammo carts loading the APCs); return (wash spray, crews dismount dirty, walk the decon hall, come out clean, an
## exposed soldier to the quarantine bay, a casualty carried on a stretcher); nothing without a facility; the state
## hash identical with the layer on / off.

const CnFacility = preload("res://sim/systems/cn_facility.gd")
const RenderSnap = preload("res://sim/render_snap.gd")
const Seq = preload("res://presentation/view/fac_seq7.gd")
const ArtCat = preload("res://presentation/art/art_catalog.gd")


class FakeMV extends Node:
	signal world_events(evs)
	var world = null
	var snap: Dictionary = {}
	var _alpha := 1.0
	var _idx := {}
	var _idx_t := -1
	func team_color(_f: int) -> Color:
		return Color(0.2, 0.5, 1.0)
	func sim_busy() -> bool:
		return false
	func snap_index(id: int) -> int:
		if int(snap.get("tick", -1)) != _idx_t:
			_idx.clear()
			var ids: PackedInt32Array = snap.get("ids", PackedInt32Array())
			for i in ids.size():
				_idx[ids[i]] = i
			_idx_t = int(snap.get("tick", -1))
		return int(_idx.get(id, -1))


func _ensure_g7() -> void:
	if Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")


## Inert world, cleared GRASS arena, a completed facility. [w, fid]
func _setup() -> Array:
	var w := make_world()
	_ensure_g7()
	w.ai_state = {}
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var n := mini(44, mini(mw, mh) - 2)
	var o := Vector2i(mw / 2 - n / 2, mh / 2 - n / 2)
	var t: PackedByteArray = w.map.terrain
	for y in range(o.y, o.y + n):
		for x in range(o.x, o.x + n):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if Rect2i(o, Vector2i(n, n)).has_point(w.cell_of(e.pos)) and e.kind != "building":
			w.entities.erase(id)
	w.cache.clear()
	var off: Array = CnFacility.conf().core_offset
	var fid := w.spawn_building("a_cn_facility", 0, o + Vector2i(2, 2) + Vector2i(int(off[0]), int(off[1])), true)
	w.run_ticks(CnFacility.DISCOVER_EVERY + 1)
	return [w, fid]


func _frame(w: SimWorld, mv, L) -> void:
	w.step()
	RenderSnap.build(w)   # the match view builds the snapshot either way; only the layer is on / off
	mv.snap = RenderSnap.latest(w)
	if L != null:
		L.on_events(w.events)
		L.refresh(mv.snap)


func _until(w: SimWorld, mv, L, fn: Callable, max_ticks: int) -> bool:
	for _i in max_ticks:
		if fn.call():
			return true
		_frame(w, mv, L)
	return fn.call()


func test_art_registered() -> void:
	check(ArtCat.G5_GROUPS.has("g7_seq7"), "g7_seq7 art group registered")
	var m: Dictionary = ArtCat.manifest().get("seq7", {})
	for k in ["stretcher", "cart", "podpack", "crate"]:
		var f := String((m.get(k, {}) as Dictionary).get("file", ""))
		check(f != "" and FileAccess.file_exists(f), "seq7 %s art present (%s)" % [k, f])
	var cd: Dictionary = m.get("crew_dirty", {})
	check(cd.size() >= 12, "dirty crew sheets for every strike crew / operator (%d)" % cd.size())
	check(FileAccess.file_exists(String(cd.get("g7_cn_gunner", ""))), "dirty gunner sheet present")


## Runs the full launch -> return scenario. view = the layer is fed every tick. Returns [hash, layer, notes].
func _scenario(view: bool) -> Array:
	var r := _setup()
	var w: SimWorld = r[0]
	var fid: int = r[1]
	var F := CnFacility.fac(w, fid)
	var mv := FakeMV.new()
	mv.world = w
	var L = null
	if view:
		L = Seq.new()
		L.setup(mv)
	var tid := CnFacility.spawn_team(w, F, "strike_team")
	var notes := {"tid": tid}
	for _i in 20:
		_frame(w, mv, L)
	var T := CnFacility.team(w, tid)
	# a wounded and an exposed crew member (display keys in the sparse g7v table, as WOUND7 / CNSIM7 write them)
	var crew := []
	for aid in T.get("apcs", []):
		var a = w.entities.get(int(aid))
		if a != null:
			for u in a.get("cargo", []):
				crew.append(int(u.id))
	notes.crew = crew.size()
	CnFacility.apply_command(w, {"type": "cn_rollout", "team": tid, "issuer": 0})
	notes.launch = _until(w, mv, L, func(): return String(CnFacility.team(w, tid).get("phase", "")) == "loading", 1200)
	if L != null:
		notes.runners = int(L.n_runners)
		notes.carts = int(L.n_carts)
		notes.scramble = (L.scramble as Dictionary).has(fid)
	notes.out = _until(w, mv, L, func(): return String(CnFacility.team(w, tid).get("phase", "")) == "out", 1600)
	if L != null:
		var left := 0
		for A in L.actors:
			if String(A.kind) == "crew" and String(A.end) == "board" and not bool(A.get("dead", false)):
				left += 1
		notes.unboarded = left
		notes.boarded = int(L.n_boarded)
		notes.loads = int(L.n_loads)
	if crew.size() >= 2:
		var gv = w.sys_state.get("g7v")
		if gv == null:
			gv = {}
			w.sys_state["g7v"] = gv
		gv[int(crew[0])] = {"unc": true, "bleed": true}
		gv[int(crew[1])] = {"ex": 0.5}
	CnFacility.apply_command(w, {"type": "cn_return", "team": tid, "issuer": 0})
	CnFacility._order_slots(w, CnFacility.team(w, tid), "decon")
	notes.parked = _until(w, mv, L, func(): return String(CnFacility.team(w, tid).get("phase", "")) == "garage", 2400)
	if L != null:
		notes.spray = int(L.n_spray)
		notes.decon = int(L.n_decon)
	for _i in 400:   # both runs step the same ticks (SEQ7-2: these 400 ran only with the layer on: the hash 'diff')
		_frame(w, mv, L)
	if L != null:
		notes.clean = int(L.n_clean)
		notes.quar = int(L.n_quar)
		notes.stretcher = int(L.n_stretcher)
	mv.free()
	if L != null:
		L.free()
	return [w.state_hash(), null, notes]


func test_sequences_and_hash() -> void:
	var off := _scenario(false)
	var on := _scenario(true)
	var n: Dictionary = on[2]
	check(int(n.crew) >= 10, "the strike team spawned with its crews aboard (%d)" % int(n.crew))
	check(bool(n.launch) and bool(n.get("scramble", false)), "launch: the team reached the pad and the scramble lights came on")
	check(int(n.get("runners", 0)) >= 10, "launch: crew runners left the ready room (%d)" % int(n.get("runners", 0)))
	check(int(n.get("carts", 0)) == 2, "resupply: one ammo rig per APC (%d)" % int(n.get("carts", 0)))
	check(bool(n.out), "the team rolled out")
	check(int(n.get("boarded", 0)) >= int(n.get("runners", 0)) * 8 / 10, "runners reached their APC's rear door and climbed in (%d of %d)" % [int(n.get("boarded", 0)), int(n.get("runners", 0))])
	check(int(n.get("loads", 0)) >= 1, "resupply: a rig reached its APC and loaded it (%d)" % int(n.get("loads", 0)))
	check(bool(n.parked), "the team came back through the wash and parked")
	check(int(n.get("spray", 0)) >= 1, "return: wash spray on a stopped team APC (%d)" % int(n.get("spray", 0)))
	check(int(n.get("decon", 0)) >= 1, "return: crews dismounted for the decon hall (%d)" % int(n.get("decon", 0)))
	check(int(n.get("clean", 0)) >= 1, "return: crews came out of the decon hall clean (%d)" % int(n.get("clean", 0)))
	check(int(n.get("stretcher", 0)) >= 1, "casualty: a stretcher team carried the wounded (%d)" % int(n.get("stretcher", 0)))
	check(int(n.get("quar", 0)) >= 1, "exposure: quarantine-bay lights for the exposed soldier (%d)" % int(n.get("quar", 0)))
	check_eq(on[0], off[0], "state hash identical with the sequence layer on / off")


func test_routes_walkable() -> void:
	var r := _setup()
	var w: SimWorld = r[0]
	var mv := FakeMV.new()
	mv.world = w
	var L = Seq.new()
	L.setup(mv)
	RenderSnap.build(w)
	mv.snap = RenderSnap.latest(w)
	for _i in 16:
		L.refresh(mv.snap)
	check(not L.lay.is_empty(), "facility layout read")
	var bad := 0
	var n := 0
	for fid in L.lay:
		var Ly: Dictionary = L.lay[fid]
		var keys: Dictionary = Ly["keys"]
		check(["ready_room", "barracks", "staging"].has(String(keys.ready)), "ready room found (%s)" % String(keys.ready))
		var pts := [L._door(Ly, String(keys.ready)), L._door(Ly, String(keys.magazine)), L._door(Ly, "decon_hall", 0),
			L._door(Ly, "decon_hall", 1), L._door(Ly, String(keys.aid)), (Ly.zones.pad as Rect2).get_center(),
			(Ly.zones.apc_wash as Rect2).get_center()]
		for a in pts:
			for b in pts:
				var p: PackedVector2Array = L._route(Ly, a, b)
				n += 1
				for q in p:
					var c: Vector2i = L._cell(Ly, q)
					if (Ly.grid as PackedByteArray)[c.y * int(Ly.cs) + c.x] == 0 and q.distance_to(b) > 0.8 and q.distance_to(a) > 0.8:
						bad += 1
	check(n > 0 and bad == 0, "every planned route stays on walkable cells (%d routes, %d bad points)" % [n, bad])
	mv.free()
	L.free()


func test_no_facility_costs_nothing() -> void:
	var w := make_world()
	var mv := FakeMV.new()
	mv.world = w
	var L = Seq.new()
	L.setup(mv)
	for _i in 40:
		_frame(w, mv, L)
	check(not L.visible and L.actors.is_empty() and L.lay.is_empty(), "no facility: hidden, no actors, no layout")
	mv.free()
	L.free()
