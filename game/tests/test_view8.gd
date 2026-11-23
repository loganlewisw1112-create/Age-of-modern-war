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
