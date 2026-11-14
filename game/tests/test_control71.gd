extends "res://tests/test_base.gd"
## G7.1 CONTROL71 (A4): pick accuracy oracle, zoom-to-cursor oracle, edge-scroll oracle, roster model.
const ViewUtil = preload("res://presentation/view/view_util.gd")
const CameraRig = preload("res://presentation/view/camera_rig.gd")
const Roster71 = preload("res://presentation/ui71/roster.gd")
const MatchViewScript = preload("res://presentation/match_view.gd")


func test_reach_scales_with_zoom() -> void:
	check(ViewUtil.unit_reach(0.3, 1.0) >= 14.0 + 0.3 * 16.0, "zoom 1: at least the old radius")
	var small := ViewUtil.unit_reach(0.3, 0.25)
	check(small * 0.25 >= ViewUtil.PICK_PX - 0.01, "zoomed out the reach is >= %d screen px (%.1f)" % [int(ViewUtil.PICK_PX), small * 0.25])
	check(ViewUtil.unit_reach(0.3, 0.2) > ViewUtil.unit_reach(0.3, 0.5), "reach grows as zoom drops")
	check(ViewUtil.unit_reach(0.7, 1.0) > ViewUtil.unit_reach(0.3, 1.0), "vehicles reach further")
	check(ViewUtil.unit_reach(0.3, 0.001) <= ViewUtil.PICK_MAX_CANVAS, "capped")


func test_nearest_wins() -> void:
	var c := Vector2(100, 100)
	var a := ViewUtil.unit_dist(c, Vector2(104, 112), 0.3, 0.5)
	var b := ViewUtil.unit_dist(c, Vector2(120, 140), 0.3, 0.5)
	check(a >= 0.0 and b >= 0.0 and a < b, "both reachable, the nearer scores lower (%.1f < %.1f)" % [a, b])
	check_eq(ViewUtil.unit_dist(c, Vector2(900, 900), 0.3, 0.5), -1.0, "far = miss")


func test_zoom_anchor_holds_point() -> void:
	var vs := Vector2(1920, 1080)
	var worst := 0.0
	for pos in [Vector2(0, 0), Vector2(1234, 567), Vector2(-800, 2000)]:
		for vp in [Vector2(0, 0), Vector2(960, 540), Vector2(1800, 100), Vector2(300, 1000)]:
			for pr in [[1.0, 1.15], [1.0, 0.87], [0.4, 2.0], [2.5, 0.5]]:
				var p2 := CameraRig.zoom_anchor(pos, pr[0], pr[1], vp, vs)
				var before = pos + (vp - vs * 0.5) / pr[0]
				var after = p2 + (vp - vs * 0.5) / pr[1]
				worst = maxf(worst, before.distance_to(after))
	check(worst < 0.001, "point under the cursor stays put (worst drift %.6f canvas px)" % worst)


func test_edge_scroll() -> void:
	var vs := Vector2(1280, 720)
	check_eq(CameraRig.edge_dir(Vector2(640, 360), vs), Vector2.ZERO, "centre: no pan")
	check_eq(CameraRig.edge_dir(Vector2(2, 360), vs), Vector2(-1, 0), "left edge")
	check_eq(CameraRig.edge_dir(Vector2(1279, 360), vs), Vector2(1, 0), "right edge")
	check_eq(CameraRig.edge_dir(Vector2(640, 1), vs), Vector2(0, -1), "top edge")
	check_eq(CameraRig.edge_dir(Vector2(1279, 719), vs), Vector2(1, 1), "bottom-right corner")
	check_eq(CameraRig.edge_dir(Vector2(-5, 360), vs), Vector2.ZERO, "cursor outside the window: no pan")
	check(CameraRig.PAN_BASE > 900.0 and CameraRig.DRAG_MULT > 1.0, "pan is faster than G7 (900)")


func _crowd(w: SimWorld, n: int) -> Array:
	var ids: Array = []
	for i in n:
		var cell := Vector2(40 + (i % 8) * 1.2, 40 + (i / 8) * 1.2)
		ids.append(w.spawn_unit("rifleman", 0, cell))
	return ids


## Legacy (G7) pick: screen-space radius 14 + r*16 at any zoom, nearest wins.
func _legacy(mv, p: Vector2):
	var sp := MatchViewScript.world_to_screen(p)
	var best = null
	var bd := 1e9
	for id in mv.world.entities:
		var e: Dictionary = mv.world.entities[id]
		if e.kind != "unit":
			continue
		var r := float(Content.unit(e.def).get("radius", 0.3))
		var d := (MatchViewScript.world_to_screen(e.pos) + Vector2(0, -10 - r * 12.0)).distance_to(sp)
		if d < 14.0 + r * 16.0 and d < bd:
			best = e
			bd = d
	return best


## Sweep: cursor placed at a deterministic offset (up to 12 screen px) from each unit's body; the intended entity is
## that unit. Reports hit % of the old pick vs the new one at zoom 0.5 and 1.0.
func test_pick_sweep_crowd() -> void:
	var w := make_world()
	var ids := _crowd(w, 40)
	var mv = MatchViewScript.new()
	mv.world = w
	mv.camera = CameraRig.new()
	var res := {}
	for zm in [1.0, 0.5, 0.3]:
		mv.camera.zoom = Vector2(zm, zm)
		var hit_new := 0
		var hit_old := 0
		var tot := 0
		for i in ids.size():
			var e: Dictionary = w.entities[ids[i]]
			var r := float(Content.unit(e.def).get("radius", 0.3))
			var body: Vector2 = MatchViewScript.world_to_screen(e.pos) + Vector2(0, -10 - r * 12.0)
			var ang := float(i) * 2.399
			var off = Vector2(cos(ang), sin(ang)) * (12.0 / zm) * (0.35 + 0.65 * float((i * 7) % 10) / 9.0)
			var cursor = body + off
			var pw := MatchViewScript.screen_to_world(cursor)
			tot += 1
			var want = e   # the unit the cursor was aimed at
			var got = mv.entity_at(pw, false)
			var old = _legacy(mv, pw)
			if got != null and want != null and int(got.id) == int(want.id):
				hit_new += 1
			if old != null and want != null and int(old.id) == int(want.id):
				hit_old += 1
		res[zm] = [hit_old, hit_new, tot]
		print("CONTROL71 pick sweep zoom %.1f: old %d/%d  new %d/%d" % [zm, hit_old, tot, hit_new, tot])
		check(hit_new >= hit_old, "zoom %.1f: new pick is no worse (%d vs %d of %d)" % [zm, hit_new, hit_old, tot])
	check(res[0.5][1] >= int(res[0.5][2] * 0.85), "zoom 0.5: >= 85%% of crowd clicks hit the intended unit (%d/%d)" % [res[0.5][1], res[0.5][2]])
	check(res[0.3][1] > res[0.3][0], "zoomed far out the new pick beats the old (%d vs %d)" % [res[0.3][1], res[0.3][0]])
	mv.free()


func test_roster_groups() -> void:
	var w := make_world()
	var ids: Array = []
	for i in 5:
		ids.append(w.spawn_unit("rifleman", 0, Vector2(30 + i, 30)))
	for i in 2:
		ids.append(w.spawn_unit("mbt", 0, Vector2(30 + i, 33)))
	w.entities[ids[0]].hp = 1.0
	var gs := Roster71.groups(w, ids)
	check_eq(gs.size(), 2, "two types")
	check_eq(int(gs[0].count), 5, "biggest group first")
	check(float(gs[0].hp_frac) < 1.0, "damaged unit lowers the group's health")
	check_eq(int(gs[1].count), 2, "tanks counted")
	var c := Roster71.centroid(w, gs[1].ids)
	check(c.y > 32.0 and c.y < 34.0, "centroid of the tank group")
