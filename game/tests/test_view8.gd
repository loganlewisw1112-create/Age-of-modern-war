extends "res://tests/test_base.gd"
## G8 ROT8: view facing math (90° steps) — world round-trip, ViewUtil live facing, art side, labels.


func test_view_facing_round_trip() -> void:
	var VF = load("res://presentation/view/view_facing.gd")
	var VU = load("res://presentation/view/view_util.gd")
	check(VF != null and VU != null, "view_facing + view_util load")
	var p := Vector2(12.5, 7.25)
	var saved: int = int(VU.view_facing)
	for f in 4:
		var back: Vector2 = VF.face0_to_world(VF.world_to_face0(p, f), f)
		check(back.distance_to(p) < 0.001, "world round-trip facing %d" % f)
		var s: Vector2 = VF.iso(p, f)
		var inv: Vector2 = VF.iso_inv(s, f)
		check(inv.distance_to(p) < 0.05, "iso round-trip facing %d (%.3f)" % [f, inv.distance_to(p)])
		VU.view_facing = f
		var live: Vector2 = VU.iso(p)
		check(live.distance_to(s) < 0.001, "ViewUtil.iso matches ViewFacing at facing %d" % f)
		var live_inv: Vector2 = VU.iso_inv(live)
		check(live_inv.distance_to(p) < 0.05, "ViewUtil.iso_inv round-trip facing %d" % f)
	VU.view_facing = saved
	check(VF.face_wrap(-1) == 3, "face_wrap -1 -> 3")
	check(VF.face_wrap(4) == 0, "face_wrap 4 -> 0")
	check(VF.art_side(0, 0) == 0, "art side identity")
	check(VF.art_side(1, 1) == 0, "art side rotates with camera")
	check(VF.label(0) == "NE", "label 0")
	check(VF.label(2) == "SW", "label 2")
	var target := Vector2(20.0, 14.0)
	for f in 4:
		VU.view_facing = f
		var scr: Vector2 = VU.iso(target)
		var hit: Vector2 = VU.iso_inv(scr)
		check(hit.distance_to(target) < 0.05, "order click world cell facing %d" % f)
	VU.view_facing = 0


func test_live_view_rotation_keeps_terrain_and_picking_aligned() -> void:
	var MV = preload("res://presentation/match_view.gd")
	var Terrain = preload("res://presentation/view/terrain_layer.gd")
	var RS = preload("res://sim/render_snap.gd")
	var VU = preload("res://presentation/view/view_util.gd")
	var mv = MV.new()
	var world := SimWorld.new_match(SimWorld.default_config())
	mv._world = world
	RS.build(world)
	mv.snap = RS.latest(world)
	mv.terrain_layer = Terrain.new()
	mv.add_child(mv.terrain_layer)
	mv.terrain_layer.setup(mv)
	var map_size := Vector2i(int(world.map.w), int(world.map.h))
	var p := Vector2(8.5, 6.5)
	for face in 4:
		mv.set_view_facing(face)
		var canvas: Vector2 = mv.world_to_screen(p)
		check((mv.pick_world(canvas) as Vector2).is_equal_approx(p), "camera %d click picks the projected world cell" % face)
		var raster: Vector2 = VU.iso_inv_raw(canvas + mv.terrain_layer._raster_offset)
		var terrain: PackedByteArray = mv.terrain_layer._terrain()
		var code := int(terrain[floori(raster.y) * mv.terrain_layer._w + floori(raster.x)])
		check_eq(code, int(world.map.terrain[floori(p.y) * map_size.x + floori(p.x)]), "camera %d keeps tile under the cursor" % face)
		check_eq(mv.terrain_layer._w, map_size.y if int(face) & 1 else map_size.x, "camera %d raster dimensions" % face)
	mv.set_view_facing(0)
	mv.free()
