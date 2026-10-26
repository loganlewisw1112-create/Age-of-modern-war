extends SceneTree
## VIEW6 visual probe (owner: VIEW6). Stages every G6 visual state in one live match (real sim systems, a
## MatchView on the sim thread): labelled galleries of every G6 unit / building id, naval ids at sea, the
## airfield v2 aprons, mimic / cloak / submerge / garrison / art_def states, minefield + radar + sonar +
## cohesion + AI-command overlays, every G6 effect, and a plateau / ramp / valley patch for the height lift.
## It checks the layers' per-frame counters (entity_layer.g6_counts, ring/overlay g6_drawn, fx g6_made) and,
## windowed, saves one PNG per scene.
##   godot --path . -s presentation/art/view6_probe.gd -- --shots=<abs dir>
## Prints "VIEW6_PROBE <check> ok=<bool> ..." per check and "VIEW6_PROBE RESULT ok=<bool>"; exit 0 = all ok.

const MatchViewScript = preload("res://presentation/match_view.gd")
const AirHelper = preload("res://tests/test_airfield.gd")
const Movement = preload("res://sim/systems/movement.gd")
const G6Fx = preload("res://presentation/art/g6_fx.gd")
const ViewUtil = preload("res://presentation/view/view_util.gd")
const Loadouts = preload("res://sim/systems/loadouts.gd")
const HotState = preload("res://sim/hot_state.gd")
const C := Vector2(0.5, 0.5)
const SEA_W := 24   # sea columns on the east edge

var w: SimWorld
var mv
var shots := ""
var sea_x := 136
var scenes: Array = []    # [name, anchor world pos, zoom, selection ids, hold ms]
var labels: Array = []    # [world pos, text, dy px]
var seen: Dictionary = {}
var missing: Array = []
var fx_spots: Array = []  # [kind, world pos] (fx scene)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.substr(8)
	_run()


## Medium map (160x160) turned into flat grass with a sea strip on the east edge, plain height everywhere.
func _world() -> SimWorld:
	var c := SimWorld.default_config()
	c.map = "industrial_heartland_m"
	c.sides = [{"faction": "human_a", "stage": 9, "credits": 90000, "ai": false, "name": "You", "team": 0},
		{"faction": "machine", "stage": 9, "credits": 90000, "ai": false, "name": "Machine", "team": 1}]
	var nw := SimWorld.new_match(c)
	nw.ai_state = {}
	var mw := int(nw.map.w)
	var mh := int(nw.map.h)
	sea_x = mw - SEA_W
	var t: PackedByteArray = nw.map.terrain
	for y in mh:
		for x in mw:
			t[y * mw + x] = Terrain.WATER if x >= sea_x + 2 else (Terrain.SHALLOW if x >= sea_x else Terrain.GRASS)
	nw.map.terrain = t
	var hg := PackedByteArray()
	hg.resize(mw * mh)
	hg.fill(1)
	nw.map["height"] = hg
	var rp := PackedByteArray()
	rp.resize(mw * mh)
	nw.map["ramps"] = rp
	# the map's neutral props (factories, houses, tanks, wrecks, scrap) would sit on top of the galleries
	var gone := 0
	for id in nw.entities.keys():
		if not nw.factions.has(int(nw.entities[id].get("owner", -1))):
			nw.entities.erase(id)
			gone += 1
	print("VIEW6_PROBE removed %d neutral map entities" % gone)
	Movement.rebuild_nav(nw)
	for fid in nw.factions:
		var ex: PackedByteArray = nw.fog[fid].explored
		ex.fill(1)
		nw.fog[fid].explored = ex
	return nw


func _free(p: Vector2, mc: String) -> Vector2:
	return Vector2(Movement.nearest_free_cell(w, w.cell_of(p), mc)) + C


func _unit(def: String, fid: int, p: Vector2, label := true) -> int:
	if Content.unit(def).is_empty():
		missing.append(def)
		return -1
	var id := w.spawn_unit(def, fid, _free(p, String(Content.unit(def).get("move_class", "foot"))))
	if label and w.entities.has(id):
		labels.append([Vector2(w.entities[id].pos), def, 12.0])
	return id


func _bld(def: String, fid: int, cell: Vector2i, label := true) -> int:
	if Content.building(def).is_empty():
		missing.append(def)
		return -1
	var id := w.spawn_building(def, fid, cell, true)
	if id >= 0 and w.entities.has(id) and label:
		labels.append([Vector2(w.entities[id].pos), def, 8.0 + 16.0 * float(Content.building(def).get("size", 1))])
	return id


func _cmd(cmd: Dictionary) -> String:
	cmd.issuer = 0
	var why := w.preview_command(cmd)  # submit() only queues; rejections happen at apply time
	if why != "":
		print("VIEW6_PROBE cmd would be rejected %s: %s" % [cmd.type, why])
	var r: Dictionary = w.submit(cmd)
	if not r.ok:
		print("VIEW6_PROBE cmd rejected %s: %s" % [cmd.type, r.reason])
		return String(r.reason)
	return ""


func _is_sea(def: String) -> bool:
	var u: Dictionary = Content.unit(def)
	var mc := String(u.get("move_class", ""))
	return mc.begins_with("naval") or mc in ["ship", "sub", "water", "boat", "sea"]


## Rows run along the screen horizontal (+x -y), rows step down the screen (+x +y).
func _gallery(name: String, ids: Array, base: Vector2, per_row: int, step: float, zoom: float, bld := false) -> void:
	var n := 0
	for d in ids:
		var col := n % per_row
		var row := n / per_row
		var p := base + Vector2(col, -col) * step + Vector2(row, row) * step * 1.25
		if bld:
			_bld(String(d), 0, Vector2i(p))
		else:
			_unit(String(d), 0, p)
		n += 1
	var rows := maxi(1, (n + per_row - 1) / per_row)
	var mid := base + Vector2(per_row - 1, -(per_row - 1)) * step * 0.5 + Vector2(rows - 1, rows - 1) * step * 0.625
	scenes.append([name, mid, zoom, [], 2500])


func _stage() -> void:
	var man: Dictionary = ArtCatalog.manifest()
	var uids: Array = (man.get("g6_units", {}) as Dictionary).get("defs", [])
	var bids: Array = (man.get("g6_bld", {}) as Dictionary).get("defs", [])
	var groups := {"a": [], "b": [], "m": [], "sea": []}
	for d in uids:
		var k := "sea" if _is_sea(String(d)) else String(d).substr(0, 1)
		if not groups.has(k):
			k = "a"
		(groups[k] as Array).append(d)
		print("VIEW6_PROBE unit %s group=%s move_class=%s" % [d, k, String(Content.unit(String(d)).get("move_class", "?"))])
	_gallery("units_a", groups.a, Vector2(10, 24), 8, 1.8, 1.6)
	_gallery("units_b", groups.b, Vector2(10, 60), 8, 1.8, 1.6)
	_gallery("units_m", groups.m, Vector2(10, 96), 8, 1.8, 1.6)
	_gallery("units_sea", groups.sea, Vector2(sea_x + 5, 40), 5, 2.6, 1.3)
	var bh: Array = []
	var bm: Array = []
	for d in bids:
		(bh if String(d).begins_with("a_") or String(d).begins_with("b_") else bm).append(d)
	_gallery("bld_human", bh, Vector2(46, 22), 6, 4.0, 0.85, true)
	_gallery("bld_machine_struct", bm, Vector2(46, 62), 6, 4.0, 0.85, true)
	_stage_states()
	_stage_mimic()
	_stage_fx()
	_stage_height()
	_stage_air()


## Every G6 unit state and overlay in one coastal patch: radar ring, enemy mimic (viewer 0 sees a recon
## drone), own cloaked stalker, own submerged sub, minesweeper sonar ring, garrisoned marines, a planned
## minefield (boundary + mine markers), art_def override, company captain cohesion ring + AI-command badge.
func _stage_states() -> void:
	var S := Vector2(sea_x - 6, 24)
	var radar := _bld("a_radar_station", 0, Vector2i(S))
	var stalker := _unit("m_stalker_synth", 0, S + Vector2(-3, 2))
	var sub := _unit("a_submarine", 0, Vector2(sea_x + 4, 24))
	var sweeper := _unit("a_minesweeper", 0, Vector2(sea_x + 3, 29))
	var gb := _bld("s_garrison_bld", 0, Vector2i(S + Vector2(-7, -4)))
	var mar := _unit("a_marines", 0, S + Vector2(-4, -4))
	var clr := _unit("a_combat_engineer", 0, S + Vector2(1, -4))  # a mine clearer cannot lay (Mines.can_lay)
	var exo := _unit("a_exo_trooper", 0, S + Vector2(-2, 5))
	var lo := _unit("a_marines", 0, S + Vector2(-5, 6))
	var cap := _unit("a_captain", 0, S + Vector2(-6, 3))
	if stalker >= 0:
		_cmd({"type": "cloak", "unit_ids": [stalker], "on": true})
	if sub >= 0:
		_cmd({"type": "submerge", "unit_ids": [sub], "on": true})
	if gb >= 0 and mar >= 0:
		_cmd({"type": "garrison", "unit_ids": [mar], "building_id": gb})
	if clr >= 0:
		_cmd({"type": "lay_minefield", "unit_ids": [clr], "rect": [int(S.x) + 2, int(S.y) - 9, int(S.x) + 5, int(S.y) - 7], "kind": "at"})
	if exo >= 0:  # art override by hand (a loadout variant sheet on another exo)
		w.entities[exo].art_def = "a_exo_aa"
		HotState.touch(w, exo)
	if lo >= 0:   # the real path: exo loadout on marines -> e.art_def a_exo_trooper
		Loadouts.apply(w, w.entities[lo], "exo")
		HotState.touch(w, lo)
		labels.append([Vector2(w.entities[lo].pos), "a_marines +exo loadout", 24.0])
	if cap >= 0:  # full CONTRACTS_G6 company record (companies.gd header), captain only
		w.sys_state["companies"] = {"companies": {1: {"id": 1, "owner": 0, "template": "a_rifle_co", "name": "1st Company",
			"size": "platoon", "captain": cap, "platoons": [], "refill": false, "army": -1, "losses": 0, "elements": [],
			"next_eid": 1, "confused_until": 0, "hq": -1}}, "armies": {}, "custom": {}, "training": [], "refill": [],
			"next_cid": 2, "next_aid": 1, "next_tid": 1, "ver": 1}
		w.entities[cap].company = 1
		w.entities[cap].rank_role = "captain"
		_cmd({"type": "set_ai_commander", "slot": 0, "target": {"formation": 1}, "playstyle": "aggressive",
			"objective": {"type": "hold", "cell": [int(S.x) - 6, int(S.y) + 3]}, "stance": "aggressive"})
	for i in 60:
		w.step()
	for f in (w.sys_state.get("mines", {}) as Dictionary).get("fields", []):
		print("VIEW6_PROBE minefield id=%d owner=%d rect=%s cells=%d done=%s" % [int(f.id), int(f.owner), str(f.rect),
			(f.get("cells", []) as Array).size(), str(f.get("done", false))])
	var sel: Array = []
	for id in [sweeper, radar]:
		if int(id) >= 0:
			sel.append(id)
	scenes.append(["states", S, 1.4, sel, 3500])


## Enemy mimic drone alone, seen by an unarmed side-0 radar station (sight 14) 12.5 tiles away: outside the
## mimic's own sight (9) so it never dives on it, beyond its reveal_range (3), so viewer 0 must draw it as a
## Human A recon drone (in the busy states patch it dove on an exo / the radar and was revealed).
func _stage_mimic() -> void:
	var r := _bld("a_radar_station", 0, Vector2i(30, 139), false)  # 12.5 tiles: in radar sight (14), outside the mimic's (9)
	var mim := _unit("m_mimic_drone", 1, Vector2(43.5, 140.5), false)
	if mim >= 0:
		labels.append([Vector2(w.entities[mim].pos), "m_mimic_drone (enemy, disguised for viewer 0)", 14.0])
	scenes.append(["mimic", Vector2(39, 140), 1.6, [r] if r >= 0 else [], 2000])


## Every G6Fx kind on its own labelled spot (3 JTACs give the fog vision the fx layer needs).
func _stage_fx() -> void:
	var F := Vector2(96, 60)
	for o in [Vector2(-3, 3), Vector2(6, -6), Vector2(10, 4)]:
		_unit("a_jtac", 0, F + o, false)
	var i := 0
	var ctr := Vector2.ZERO
	for kind in G6Fx.KINDS:
		var p := F + Vector2(i % 5, -(i % 5)) * 2.2 + Vector2(i / 5, i / 5) * 2.6
		fx_spots.append([String(kind), p])
		labels.append([p, String(kind), 10.0])
		ctr += p
		i += 1
	scenes.append(["fx", ctr / maxf(1.0, float(i)), 1.5, [], 2600])


## Plateau (level 2) with a ramp column on its west edge and a valley (level 0) to the east; units and a
## selected radar station on each level. Runs before the MatchView exists (the terrain bakes the heights).
func _stage_height() -> void:
	var mw := int(w.map.w)
	var hg: PackedByteArray = w.map.height
	var rp: PackedByteArray = w.map.ramps
	for y in range(96, 103):
		for x in range(94, 101):
			hg[y * mw + x] = 2
		rp[y * mw + 93] = 1
		for x in range(104, 109):
			hg[y * mw + x] = 0
	w.map.height = hg
	w.map.ramps = rp
	Movement.rebuild_nav(w)
	var radar := _bld("a_radar_station", 0, Vector2i(97, 97))
	_unit("mbt", 0, Vector2(95.5, 100.5))            # plateau (G1 tank for scale)
	_unit("a_exo_trooper", 0, Vector2(99.5, 101.5))  # plateau
	_unit("a_jtac", 0, Vector2(93.5, 98.5))          # ramp
	_unit("mbt", 0, Vector2(93.5, 101.5))            # ramp
	_unit("a_captain", 0, Vector2(105.5, 98.5))      # valley
	_unit("mbt", 0, Vector2(107.5, 101.5))           # valley
	_unit("mbt", 0, Vector2(90.5, 99.5))             # plain reference
	var sel: Array = [radar] if radar >= 0 else []
	scenes.append(["height", Vector2(100, 100), 1.5, sel, 2500])


## Airfield v2: a_airfield and b_aerodrome with a light + heavy hangar and parked jets (apron pads).
func _stage_air() -> void:
	var ah = AirHelper.new()
	var hq: Dictionary = ah._hq(w, 0)
	if hq.is_empty():
		print("VIEW6_PROBE air: no HQ for side 0")
		missing.append("hq")
		return
	var hc := Vector2i(hq.cell)
	for spec in [["a_airfield", Vector2i(108, 128), ["a_strike_jet"]], ["b_aerodrome", Vector2i(108, 148), ["b_recon_plane", "b_bomber"]]]:
		var fdef := String(spec[0])
		var fb: int = ah._field(w, fdef, (spec[1] as Vector2i) - hc)
		if fb < 0 or not w.entities.has(fb):
			missing.append(fdef)
			continue
		var hl: int = ah._hangar(w, fb, "light", 0)
		var hh: int = ah._hangar(w, fb, "heavy", 0)
		var k := 0
		for jd in spec[2]:
			var at := hl if k == 0 else hh
			if not Content.unit(String(jd)).is_empty() and at >= 0 and w.entities.has(at):
				ah._jet(w, String(jd), at)
			k += 1
		labels.append([Vector2(w.entities[fb].pos), fdef, 40.0])
		scenes.append(["airfield_" + fdef, Vector2(w.entities[fb].pos), 1.4, [], 2500])


## [a offset, b offset, life, colour, size, own_only] per kind, matching G6Fx.from_event (lives >= 0.8 s so
## the 650 ms re-emission always has one live in the capture frame).
func _fx_spec(kind: String) -> Array:
	match kind:
		"laser": return [Vector2.ZERO, Vector2(2.5, -1.2), 0.8, G6Fx.C_LASER, 2.0, false]
		"net": return [Vector2(2.0, -1.0), Vector2.ZERO, 0.9, G6Fx.C_NET, 1.0, false]
		"jam": return [Vector2.ZERO, Vector2.ZERO, 0.9, G6Fx.C_JAM, 1.0, false]
		"sonar": return [Vector2.ZERO, Vector2.ZERO, 1.4, G6Fx.C_SONAR, 3.0, true]
		"mine_blast": return [Vector2.ZERO, Vector2.ZERO, 0.9, G6Fx.C_FIRE, 1.4, false]
		"line_charge": return [Vector2.ZERO, Vector2(3.0, -1.5), 0.8, G6Fx.C_NET, 1.0, false]
		"chute": return [Vector2.ZERO, Vector2.ZERO, 1.6, Color(0.85, 0.85, 0.78), 1.0, false]
		"shimmer": return [Vector2.ZERO, Vector2.ZERO, 0.9, G6Fx.C_ASSIM, 1.0, true]
		"nanite": return [Vector2.ZERO, Vector2.ZERO, 0.9, G6Fx.C_NANITE, 4.0, false]
		"assimilate": return [Vector2(1.5, -0.8), Vector2.ZERO, 1.6, G6Fx.C_ASSIM, 1.0, false]
		"ciws": return [Vector2.ZERO, Vector2(2.0, -2.0), 0.8, G6Fx.C_LASER, 1.0, false]
		"strike": return [Vector2.ZERO, Vector2.ZERO, 1.0, G6Fx.C_FIRE, 1.6, false]
		"train_smoke": return [Vector2.ZERO, Vector2(-0.6, -0.6), 1.8, Color(0.32, 0.31, 0.3), 1.0, false]
	return [Vector2.ZERO, Vector2(2, -1), 1.2, Color.WHITE, 1.0, false]


func _emit_fx() -> void:
	if mv == null or mv.fx_layer == null:
		return
	for sp in fx_spots:
		var kind := String(sp[0])
		var p: Vector2 = sp[1]
		var s := _fx_spec(kind)
		mv.fx_layer._add_g6_list([G6Fx._fx(kind, p + (s[0] as Vector2), p + (s[1] as Vector2), float(s[2]), s[3], float(s[4]), 0.0, bool(s[5]))])


func _add_labels() -> void:
	for lb in labels:
		var l := Label.new()
		l.text = String(lb[1])
		l.add_theme_font_size_override("font_size", 9)
		l.add_theme_color_override("font_color", Color(1, 1, 0.85))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		l.add_theme_constant_override("outline_size", 3)
		var hm: Dictionary = mv.terrain_layer.height_map() if mv.terrain_layer != null else {}
		l.position = ViewUtil.world_to_screen_h(hm, lb[0]) + Vector2(-34, float(lb[2]))
		l.z_index = 100
		mv.add_child(l)


func _collect() -> void:
	var cnt: Dictionary = {}
	var el = mv.entity_layer
	if el != null:
		cnt.merge(el.g6_counts, true)
		cnt["apron"] = int(el.g5_counts.get("apron", 0))
	for lay in [mv.get("ring_layer"), mv.get("overlay_layer")]:
		if lay != null and lay.get("g6_drawn") is Dictionary:
			for k in lay.g6_drawn:
				cnt[k] = maxi(int(cnt.get(k, 0)), int(lay.g6_drawn[k]))
	for k in cnt:
		seen[k] = maxi(int(seen.get(k, 0)), int(cnt[k]))


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	ArtCatalog.load_all()
	w = _world()
	_stage()
	print("VIEW6_PROBE map %dx%d sea_x=%d scenes=%d" % [int(w.map.w), int(w.map.h), sea_x, scenes.size()])
	mv = MatchViewScript.new()
	mv.world = w
	root.add_child(mv)
	for i in 10:
		await process_frame
		_collect()  # cached draws (airfield strips / aprons) count only on their first frame
	_add_labels()
	for sc in scenes:
		mv.center_camera_on(sc[1])
		if mv.camera != null:
			mv.camera.zoom = Vector2(sc[2], sc[2])
		var t0 := Time.get_ticks_msec()
		var next_fx := 0
		while Time.get_ticks_msec() - t0 < int(sc[4]):
			if not (sc[3] as Array).is_empty():
				mv.selection.assign(sc[3])
			if String(sc[0]) == "fx" and Time.get_ticks_msec() >= next_fx:
				_emit_fx()
				next_fx = Time.get_ticks_msec() + 650
			await process_frame
			_collect()
		if shots != "":
			if String(sc[0]) == "fx":  # capture every effect near the start of its life
				_emit_fx()
				for k in 4:
					await process_frame
			await RenderingServer.frame_post_draw
			var img: Image = root.get_texture().get_image()
			var path := shots.path_join("view6_%s.png" % sc[0])
			img.save_png(path)
			print("VIEW6_PROBE shot %s" % path)
		mv.selection.clear()
	var ok := true
	var want := {"lifted": "units drawn at their cell height", "art_override": "e.art_def override",
		"disguised": "mimic disguise for the enemy viewer", "cloaked": "own cloaked stalker translucent",
		"submerged": "own submerged sub", "garrisoned": "garrisoned infantry inside", "command": "officer command pose",
		"apron": "airfield v2 apron pads", "minefields": "minefield boundary (owner view)", "markers": "mine_marker sheet",
		"radar": "radar ring", "sonar": "sonar ring", "cohesion": "cohesion ring", "garrison_pips": "garrison_pip sheet",
		"ai_badges": "AI-command badges"}
	for k in want:
		var v := int(seen.get(k, 0))
		print("VIEW6_PROBE %s ok=%s max=%d (%s)" % [k, str(v > 0), v, want[k]])
		ok = ok and v > 0
	var made: Dictionary = mv.fx_layer.g6_made if mv.fx_layer != null else {}
	for kd in G6Fx.KINDS:
		var n := int(made.get(kd, 0))
		print("VIEW6_PROBE fx_%s ok=%s made=%d" % [kd, str(n > 0), n])
		ok = ok and n > 0
	print("VIEW6_PROBE info jam=%d seen=%s" % [int(seen.get("jam", 0)), str(seen)])
	print("VIEW6_PROBE missing %s" % str(missing))
	ok = ok and missing.is_empty()
	print("VIEW6_PROBE RESULT ok=%s" % str(ok))
	mv.queue_free()
	await process_frame
	quit(0 if ok else 1)
