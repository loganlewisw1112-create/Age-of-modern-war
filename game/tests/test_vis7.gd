extends "res://tests/test_base.gd"
## G7 (VIS7) display integration: render keys for the CN APCs, the walker topple and the threat states; the vis7 layer
## builds its frame swaps / overlays / fx from a fixture snapshot; the world7 recovering ground, the minimap palette;
## the state hash is identical with the whole view on or off.

const CN = preload("res://sim/systems/counter_nanite.gd")
const Apc7 = preload("res://sim/systems/apc7.gd")
const Threats7 = preload("res://sim/systems/threats7.gd")
const Movement = preload("res://sim/systems/movement.gd")
const RenderSnap = preload("res://sim/render_snap.gd")
const Vis7 = preload("res://presentation/view/vis7_layer.gd")
const Minimap = preload("res://presentation/hud/minimap.gd")


class FakeEL extends RefCounted:
	var x7: Dictionary = {}
	var _team: Dictionary = {0: Color(0.2, 0.5, 1.0), 1: Color(0.9, 0.2, 0.2)}


class FakeMV extends RefCounted:
	var world = null
	var _alpha := 1.0
	var entity_layer = FakeEL.new()
	var snap: Dictionary = {}


func _ensure_g7() -> void:
	if Content.unit("g7_cn_strike_apc").is_empty():
		Content._merge_fragment_dir("res://content/g7")


## Inert 2-side world with a cleared GRASS arena; [w, arena centre].
func _setup() -> Array:
	var w := make_world({"seed": 7})
	_ensure_g7()
	w.ai_state = {}
	var mw := int(w.map.w)
	var o := Vector2i(mw / 2 - 20, int(w.map.h) / 2 - 15)
	var r := Rect2i(o, Vector2i(40, 30))
	var t: PackedByteArray = w.map.terrain
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if r.grow(12).has_point(w.cell_of(e.pos)) and e.kind != "building":
			w.entities.erase(id)
	Movement.rebuild_nav(w)
	return [w, Vector2(o) + Vector2(20.5, 15.5)]


func _apc(w: SimWorld, def: String, pos: Vector2) -> Dictionary:
	var a: Dictionary = w.entities[w.spawn_unit(def, 0, pos)]
	Apc7.init_apc(w, a)
	a.a7.rl.eng = 99   # no auto fire: the test drives the launcher
	return a


## A scene with every VIS7 state: a toppled walker, a domed strike APC with its launcher up, a tactical APC, a burrowed
## burrower, a disguised mimic, a cocooned soldier. Returns [w, ids {walker, strike, tactical, burrower, mimic, soldier}].
func _scene() -> Array:
	var s := _setup()
	var w: SimWorld = s[0]
	var c: Vector2 = s[1]
	var k: Dictionary = w.entities[w.spawn_unit("m_walker", 1, c + Vector2(6, 0))]
	var a := _apc(w, "g7_cn_strike_apc", c)
	var b := _apc(w, "g7_op_tactical_apc", c + Vector2(0, 5))
	Apc7.set_dome(w, a, true)
	a.a7.rl.st = 2
	Apc7._rl_render(w, a)
	Apc7.topple(w, k)
	var bid := Threats7.spawn(w, "g7_m_burrower", 1, c + Vector2(-6, 4))
	var mid := Threats7.spawn(w, "g7_m_mimic", 1, c + Vector2(-6, -4))
	var sid := w.spawn_unit("g7_cn_gunner", 0, c + Vector2(3, -6))
	var sol: Dictionary = w.entities[sid]
	sol.t7c = {"by": mid, "cut": 0.25, "on": 0, "p": sol.pos}
	var st: Dictionary = w.sys_state.threats7
	st.cocoons.append(sid)
	return [w, {"walker": int(k.id), "strike": int(a.id), "tactical": int(b.id), "burrower": bid, "mimic": mid, "soldier": sid}]


func test_render_keys_present_for_each_state() -> void:
	var sc := _scene()
	var w: SimWorld = sc[0]
	var ids: Dictionary = sc[1]
	RenderSnap.build(w)
	var sn := RenderSnap.latest(w)
	var g: Dictionary = sn.get("g7u", {})
	var v7: PackedInt32Array = sn.get("v7", PackedInt32Array())
	check(g.has(ids.walker) and String(g[ids.walker].get("topple", "")) == "fall", "toppled walker: topple = fall")
	check(g.has(ids.walker) and g[ids.walker].has("topple_dir"), "toppled walker: topple_dir")
	check(v7.has(ids.walker), "snap.v7 lists the toppling walker")
	check(g.has(ids.strike) and int(g[ids.strike].get("apc", 0)) == 1, "strike APC flagged apc")
	check(g.has(ids.strike) and float(g[ids.strike].get("dome", -1.0)) > 0.9 and float(g[ids.strike].get("dome_r", 0.0)) > 0.0,
		"domed APC: dome charge + radius (%s)" % str(g.get(ids.strike)))
	check(g.has(ids.strike) and int(g[ids.strike].get("rl", -1)) == 2 and int(g[ids.strike].get("rl_n", -1)) == 6, "launcher popped, 6 rounds (rl / rl_n)")
	check(g.has(ids.tactical) and not g[ids.tactical].has("dome"), "tactical APC without a dome has no dome key")
	check(g.has(ids.burrower) and String(g[ids.burrower].t7.k) == "burrower" and String(g[ids.burrower].t7.st) == "burrowed", "burrowed burrower t7 state")
	check(g.has(ids.mimic) and String(g[ids.mimic].t7.get("as", "")) != "", "disguised mimic t7.as")
	check(g.has(ids.soldier) and absf(float(g[ids.soldier].get("coc", -1.0)) - 0.25) < 0.01, "cocooned soldier coc = cut progress")
	g[ids.strike]["dome"] = 0.0
	check(bool(w.entities[ids.strike].a7.dome_on) and float(w.entities[ids.strike].a7.dome) > 0.0, "snapshot copy does not alias the sim")


func _layer(w: SimWorld) -> Array:
	var mv := FakeMV.new()
	mv.world = w
	var L = Vis7.new()
	L.setup(mv)
	L.sync_tint = true
	L.view_rect_override = Rect2(-100000, -100000, 200000, 200000)
	return [L, mv]


func test_overlays_build_from_fixture_snapshot() -> void:
	var sc := _scene()
	var w: SimWorld = sc[0]
	var ids: Dictionary = sc[1]
	var lm := _layer(w)
	var L = lm[0]
	var mv: FakeMV = lm[1]
	RenderSnap.build(w)
	var sn := RenderSnap.latest(w)
	mv.snap = sn
	L.refresh(sn)
	var x7: Dictionary = mv.entity_layer.x7
	check(x7.has(ids.walker) and int(x7[ids.walker][1]) == L.col_of(L.spec_of(Vis7.TOPPLE_SHEET), "fall_0"), "walker drawn with the topple sheet, fall frame")
	check(x7.has(ids.walker) and int(x7[ids.walker][2]) == ArtCatalog.facing_index(float(sn.g7u[ids.walker].topple_dir)), "fall row follows topple_dir")
	check(x7.has(ids.strike) and String((x7[ids.strike][0] as Dictionary).get("file", "")).contains("strike_apc_rkt"), "strike APC with the launcher up uses the _rkt sheet")
	check(x7.has(ids.burrower) and (x7[ids.burrower][0] as Dictionary).is_empty(), "burrowed burrower sprite hidden (mound only)")
	check(x7.has(ids.mimic) and String((x7[ids.mimic][0] as Dictionary).get("file", "")).contains("gunner"), "disguised mimic drawn as the as_foot soldier")
	check(x7.has(ids.soldier) and (x7[ids.soldier][0] as Dictionary).is_empty(), "cocooned soldier hidden under the cocoon")
	var kinds := {}
	for it in L._items:
		kinds[String(it[0])] = true
	for k in ["dome", "mound", "coc", "exposed"]:
		check(kinds.has(k), "overlay item %s built" % k)
	# events -> fx: salvo, topple impact, blow-up, limpet, harpoon, disruptor, threat events
	var wpos: Vector2 = w.entities[ids.walker].pos
	var apos: Vector2 = w.entities[ids.strike].pos
	L.on_events([
		{"type": "RocketSalvo", "id": ids.strike, "from": apos, "to": wpos, "kinds": ["tandem", "emp"], "tube": 4},
		{"type": "CnLimpetPlanted", "id": ids.tactical, "target": ids.walker, "pos": wpos},
		{"type": "CnHarpoon", "id": ids.tactical, "target": ids.walker, "from": apos, "to": wpos},
		{"type": "CnDisruptorShot", "id": ids.tactical, "target": ids.walker, "from": apos, "to": wpos},
		{"type": "ApcPanel", "id": ids.strike, "kind": "smoke", "pos": apos},
		{"type": "BurrowerErupt", "id": ids.burrower, "pos": wpos}, {"type": "NaniteSlug", "id": 1, "from": apos, "to": wpos},
		{"type": "WebSpit", "id": 1, "from": apos, "to": wpos}, {"type": "PackhunterSwipe", "id": 1, "target": ids.strike},
		{"type": "MimicExposed", "id": ids.mimic, "pos": wpos}, {"type": "LeechDrill", "id": 5, "vehicle": ids.strike},
		{"type": "WalkerBlownUp", "id": ids.walker, "dir": 0.5}])
	var fk := {}
	for f in L._fx:
		fk[String(f.k)] = int(fk.get(String(f.k), 0)) + 1
	check(int(fk.get("rocket", 0)) == 2 and int(fk.get("backblast", 0)) == 2, "salvo of 2: two rockets + two backblasts (%s)" % str(fk))
	for k in ["limpet", "harpoon", "disrupt", "panel_smoke", "erupt", "slug", "webline", "claw", "glitch", "sparks", "wblast", "debris", "smokecol"]:
		check(fk.has(k), "fx %s queued" % k)
	L.refresh(sn)
	check(x7.has(ids.strike) and String(L.x7[ids.strike][0].get("file", "")).contains("_rkt") and int(L.x7[ids.strike][1]) == L.col_of(L.spec_of("g7_cn_strike_apc_rkt"), "rk_fire_0"),
		"salvo plays the ripple fire frames (first fired tube)")
	L.free()


func test_gun_frames_and_reload() -> void:
	var sc := _scene()
	var w: SimWorld = sc[0]
	var ids: Dictionary = sc[1]
	var lm := _layer(w)
	var L = lm[0]
	var mv: FakeMV = lm[1]
	RenderSnap.build(w)
	var sn := RenderSnap.latest(w)
	mv.snap = sn
	var tid: int = ids.tactical
	var tp: Vector2 = w.entities[tid].pos
	L.refresh(sn)
	L.on_events([{"type": "ShotFired", "shooter": tid, "target": ids.walker, "from": tp, "to": tp + Vector2(5, 0)}])
	L.refresh(sn)
	check(L.x7.has(tid) and String(L.x7[tid][0].get("file", "")).contains("tactical_apc_gun"), "firing tactical APC plays the _gun sheet")
	var gspec: Dictionary = L.spec_of("g7_op_tactical_apc_gun")
	var col := int(L.x7[tid][1]) if L.x7.has(tid) else -1
	check(col >= L.col_of(gspec, "fire_0") and col <= L.col_of(gspec, "fire_3"), "a fire_0..3 column")
	L._ap[tid].burst = Vis7.GUN_BURST_S + 0.1
	L.on_events([{"type": "ShotFired", "shooter": tid, "target": ids.walker, "from": tp, "to": tp + Vector2(5, 0)}])
	L.refresh(sn)
	L.refresh(sn)
	col = int(L.x7[tid][1]) if L.x7.has(tid) else -1
	check(col >= L.col_of(gspec, "reload_0") and col <= L.col_of(gspec, "reload_2"), "a long burst plays the belt reload (col %d)" % col)
	L.free()


func _run(view: bool) -> String:
	var sc := _scene()
	var w: SimWorld = sc[0]
	var lm := _layer(w) if view else []
	for i in 140:
		w.step()
		if view:
			RenderSnap.build(w)
			var sn := RenderSnap.latest(w)
			lm[1].snap = sn
			lm[0].on_events(w.events)
			lm[0].refresh(sn)
	if view:
		lm[0].free()
	return w.state_hash()


func test_view_never_writes_sim() -> void:
	var a := _run(false)
	var b := _run(true)
	check_eq(b, a, "state hash identical with the VIS7 view on / off")


func test_minimap_palette_has_chasm() -> void:
	check(Minimap.TERRAIN_COLORS.size() >= Terrain.CHASM + 1, "minimap colour for every terrain code up to CHASM")
	check(Minimap.TERRAIN_COLORS[Terrain.CHASM] != Minimap.TERRAIN_COLORS[Terrain.RIDGE], "CHASM is not drawn in ridge colour")
