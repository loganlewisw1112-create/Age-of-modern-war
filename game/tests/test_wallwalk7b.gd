extends "res://tests/test_base.gd"
## G7 acceptance (owner: WALL7-2). G7_REFERENCE 13.9c-23 (castle-style hardened wall-walk, futuristic): soldiers on
## the facility wall stand ON the wall-walk deck behind the OUTER armoured parapet (right height and depth on every
## wall orientation and on the towers, never inside the tower shaft); they crouch behind the parapet to reload, when
## pinned / suppressed and between aimed shots, and rise to fire; the parapet's camera-side strip is an opaque occluder
## sheet drawn after them (never transparency) and sits at deck height (never over ground units' bodies); all of it is
## display only (hash unchanged) and costs nothing without a facility.

const CnFacility = preload("res://sim/systems/cn_facility.gd")
const WallWalk7 = preload("res://sim/systems/wallwalk7.gd")
const Motion = preload("res://presentation/view/motion.gd")
const ArtCat = preload("res://presentation/art/art_catalog.gd")
const RenderSnap = preload("res://sim/render_snap.gd")
const DECK_PX := 36.0   # g7_fac7f DECK_Z 3.66 m x 9.8 px/m

var _h = null


func _helper():
	if _h == null:
		_h = load("res://tests/test_wallwalk7.gd").new()
	return _h


## [w, F, O, statics (snapshot-shaped), compound centre]
func _ring() -> Array:
	var s: Array = _helper()._setup()
	var w: SimWorld = s[0]
	var F: Dictionary = s[1]
	var statics := {}
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "building":
			statics[id] = {"def": e.def, "pos": e.pos, "kind": "building"}
	var cs := float(CnFacility.conf().get("compound", 32))
	var O: Vector2i = s[2]
	return [w, F, O, statics, Vector2(O) + Vector2(cs, cs) * 0.5]


## Every wall-walk cell of the ring: the feet land on the deck (36 px up), on the piece, on the firing step
## right behind the outer parapet, for every orientation; towers keep the feet off the shaft.
func test_offset_on_every_orientation() -> void:
	var r := _ring()
	var w: SimWorld = r[0]
	var cells := Motion.wall_walk_cells(r[3], [r[4]])
	var ring := WallWalk7.ring_cells(w, r[1])
	check(ring.size() >= 100 and cells.size() == ring.size(), "display wall-walk cells = sim ring cells (%d / %d)" % [cells.size(), ring.size()])
	var runs := {}
	var bad := []
	var towers := 0
	for c in cells:
		var v: Array = cells[c]
		var ctr := Vector2(v[0], v[1])
		var q := int(v[4])
		var p := Vector2(c) + Vector2(0.37, 0.61)
		var off := Motion.wall_top_offset(v, p)
		# undo the projection: screen dx = (dx - dy) * 32, dy_screen = (dx + dy) * 16 - lift
		var sy := off.y + DECK_PX
		var dx := (off.x / 32.0 + sy / 16.0) * 0.5
		var dy := (sy / 16.0 - off.x / 32.0) * 0.5
		var f := p + Vector2(dx, dy)
		var run := int(v[3])
		runs[run] = int(runs.get(run, 0)) + 1
		var out := Vector2(1.0 if q & 1 else -1.0, 1.0 if q & 2 else -1.0)
		var head: bool = c == Vector2i(floori(ctr.x), floori(ctr.y))   # once per piece
		if head:
			var want := Vector2(1.0 if ctr.x >= r[4].x else -1.0, 1.0 if ctr.y >= r[4].y else -1.0)
			if out != want:
				bad.append([c, "outer quadrant", out, want])
			if Motion.wall_top_depth(v) != int((ctr.x + ctr.y) * 16.0) + Motion.WALL_DEPTH_PAD or Motion.wall_front_depth(v) != Motion.wall_top_depth(v) + 1:
				bad.append([c, "depth"])
		if absf(float(v[2]) - DECK_PX) > 0.01:
			bad.append([c, "lift", v[2]])
		if absf(f.x - ctr.x) > 1.0 or absf(f.y - ctr.y) > 1.0:
			bad.append([c, "off the piece", f])
		if run == 1 and absf((f.y - ctr.y) - out.y * Motion.WALL_FIRE_STEP) > 0.001:
			bad.append([c, "E-W deck line", f.y - ctr.y])
		if run == 2 and absf((f.x - ctr.x) - out.x * Motion.WALL_FIRE_STEP) > 0.001:
			bad.append([c, "N-S deck line", f.x - ctr.x])
		if bool(v[5]):
			towers += 1
			var s := f - ctr - Motion.TOWER_SHAFT
			if absf(s.x) < Motion.TOWER_CLEAR - 0.001 and absf(s.y) < Motion.TOWER_CLEAR - 0.001:
				bad.append([c, "inside the tower shaft", s])
	print("  ring cells %d, runs %s, tower cells %d" % [cells.size(), str(runs), towers])
	check(runs.has(1) and runs.has(2), "both E-W and N-S runs present")
	check(towers >= 16, "tower decks are part of the walk (%d cells)" % towers)
	check_eq(bad, [], "every wall-walk position is on the deck, on the firing step behind the outer parapet, clear of the shafts; outer side and depth right")


## The four ring faces get the four outer sides (the parapet faces out on the N, E, S and W walls).
func test_quadrants_face_out() -> void:
	var c := Vector2(50, 50)
	check_eq(Motion.wall_quadrant(Vector2(50, 35), [c]) & 2, 0, "north wall: outside toward -y")
	check_eq(Motion.wall_quadrant(Vector2(50, 65), [c]) & 2, 2, "south wall: outside toward +y")
	check_eq(Motion.wall_quadrant(Vector2(35, 50), [c]) & 1, 0, "west wall: outside toward -x")
	check_eq(Motion.wall_quadrant(Vector2(65, 50), [c]) & 1, 1, "east wall: outside toward +x")
	check_eq(Motion.wall_quadrant(Vector2(10, 10), [c, Vector2(0, 0)]), 3, "nearest facility decides")
	check_eq(Motion.wall_quadrant(Vector2(10, 10), []), 3, "no facility: default quadrant")
	# E-W runs: feet on the firing step toward the outside (north wall: -y of the axis; south wall: +y)
	var n := Motion.wall_top_offset([50.0, 35.0, DECK_PX, 1, 0, false], Vector2(50.2, 35.0))
	var s := Motion.wall_top_offset([50.0, 65.0, DECK_PX, 1, 2, false], Vector2(50.2, 65.0))
	check(n.y < s.y, "north wall feet step north to the parapet, south wall feet step south to it")
	check(Motion.WALL_FIRE_STEP * 4.0 < 1.05, "the firing step stays inside the parapet's inner face (1.05 m out)")


## 13.9c-23 crouch rule on the wall: reloading -> crouched; pinned / suppressed -> crouched (never prone, head over
## the parapet); firing -> up at the parapet WALL_UP of every WALL_DUCK s, crouched in between; walking keeps its frame.
func test_crouch_rule() -> void:
	var a61 := {"crouch": 10, "fire_s": 11, "fire_c": 12, "fire_p": 13, "prone": 14, "reload": [15, 16]}
	var F := Motion.P_FIRING
	check_eq(Motion.wall_col(a61, 1, 0, 0.0, 0.3, 15), 10, "reloading (s7 bit 1) -> crouched behind the parapet")
	check_eq(Motion.wall_col(a61, 1, F, 0.7, 0.3, 11), 10, "reloading while the fire flag is still set -> crouched")
	check_eq(Motion.wall_col(a61, 0, Motion.P_PINNED, 0.0, 0.3, 14), 10, "pinned on the wall -> crouched, not prone")
	check_eq(Motion.wall_col(a61, 0, Motion.P_SUPPRESSED, 0.0, 0.3, 10), 10, "suppressed -> crouched")
	check_eq(Motion.wall_col(a61, 0, Motion.P_MOVING, 0.0, 0.3, 3), -1, "walking along the wall keeps its walk frame")
	check_eq(Motion.wall_col(a61, 1, Motion.P_WOUNDED, 0.0, 0.3, 7), -1, "wounded keeps the wound pose")
	check_eq(Motion.wall_col(a61, 0, 0, 0.0, 0.3, 0), -1, "on watch: stands")
	var up := 0
	var down := 0
	for k in 320:
		var c := Motion.wall_col(a61, 0, F, k * 0.05, 0.3, 11)
		if c == -1:
			up += 1
		elif c == 10:
			down += 1
	check(up + down == 320, "firing is either up (fire / aim frame) or crouched")
	check(absf(float(up) / 320.0 - Motion.WALL_UP / Motion.WALL_DUCK) < 0.05, "up at the parapet %d / 320 samples (~%.0f%%), crouched between shots %d" % [up, Motion.WALL_UP / Motion.WALL_DUCK * 100.0, down])
	var pin_up := Motion.wall_col(a61, 0, F | Motion.P_PINNED, 0.0, 0.0, 13)
	check(pin_up == 12 or pin_up == 10, "pinned while firing -> crouched fire or ducked, never prone fire")
	var mixed := {}
	for k in 40:   # at one instant a line of soldiers is not all up or all down (phase per soldier)
		mixed[Motion.wall_col(a61, 0, F, 1.0, Motion.seed_of(1000 + k), 11)] = true
	check(mixed.size() == 2, "a manned wall mixes risen and ducked soldiers at one moment")
	check_eq(Motion.wall_col({}, 1, 0, 0.0, 0.0, 0), -1, "sheets without anim61 columns are left alone")


## The occluder sheet: same layout as the wall / tower sheets, holds the camera-side parapet (south / east walls)
## and the inner rail (north / west walls) at deck height and above only, so it never paints over ground units.
func test_parapet_occluder_sheet() -> void:
	var man: Dictionary = ArtCat.manifest().get("buildings", {})
	for key in ["g7_fac_wall", "g7_fac_tower"]:
		var b: Dictionary = man.get(key, {})
		if not check(not b.is_empty() and (b.states as Dictionary).has("front"), "%s has its front occluder sheet" % key):
			continue
		var img: Image = ArtCat._image(String(b.states.built.file))
		var fr: Image = ArtCat._image(String(b.states.front.file))
		check(img != null and fr != null and img.get_size() == fr.get_size() and img.get_height() == int(b.fh) * 8, "%s: 16 masks x 4 quadrants x 2 rows, front sheet same size" % key)
		check_eq(int(b.get("deck_px", 0)), int(DECK_PX), "%s deck height in the manifest = the display lift" % key)
		if fr == null:
			continue
		var fw := int(b.fw)
		var fh := int(b.fh)
		var py := int(b.pivot[1])
		for q in [0, 3]:
			var m := 10   # E-W straight run
			var n := 0
			var low := 0
			for y in fh:
				for x in fw:
					if fr.get_pixel(m * fw + x, q * 2 * fh + y).a > 0.0:
						n += 1
						if y > py - 12:
							low += 1
			check(n > 40, "%s q%d E-W: occluder strip present (%d px)" % [key, q, n])
			check_eq(low, 0, "%s q%d E-W: occluder strip stays at deck height and above" % [key, q])


## Display only: building the snapshot and running every wall-walk display function each tick leaves the hash alone.
func test_display_hash_unchanged() -> void:
	var a := _scripted(false)
	var b := _scripted(true)
	check_eq(b, a, "wall-walk display on == off hash")


func _scripted(view: bool) -> String:
	var s: Array = _helper()._setup(23)
	var w: SimWorld = s[0]
	var F: Dictionary = s[1]
	var O: Vector2i = s[2]
	var ids := []
	for i in 4:
		ids.append(_helper()._unit(w, "rifleman", 0, Vector2(O.x + 6 + i, O.y + 6) + Vector2(0.5, 0.5)))
	var wc: Vector2i = _helper()._north_wall(w, F, O, 7)
	_helper()._move(w, ids, Vector2(wc) + Vector2(0.5, 0.5))
	var a61 := {"crouch": 1, "fire_s": 2, "fire_c": 3, "fire_p": 4, "prone": 5}
	for k in 150:
		w.run_ticks(1)
		if view:
			RenderSnap.build(w)
			var sn: Dictionary = RenderSnap.latest(w)
			var cells := Motion.wall_walk_cells(sn.get("statics", {}), [Vector2(O) + Vector2(16, 16)])
			for id in ids:
				var e = w.entities.get(id)
				if e != null:
					var v = cells.get(Vector2i(floori(e.pos.x), floori(e.pos.y)))
					if v != null:
						Motion.wall_top_offset(v, e.pos)
						Motion.wall_col(a61, 1, Motion.P_FIRING, k * 0.05, 0.2, 2)
	return w.state_hash()


## No facility: no wall-walk cells, nothing for the entity layer to do.
func test_no_facility_no_cost() -> void:
	var w := make_world()
	w.run_ticks(5)
	RenderSnap.build(w)
	var sn: Dictionary = RenderSnap.latest(w)
	check_eq(Motion.wall_walk_cells(sn.get("statics", {}), []).size(), 0, "no facility: no wall-walk cells (entity layer skips the whole pass)")


## The parapet is breast height for the real soldiers on the wall: every Sentinel's crouched frame keeps its helmet
## over the parapet line (never fully hidden, still clickable) and a standing / firing Sentinel shows head and chest.
func test_crouched_helmet_over_parapet() -> void:
	var wb: Dictionary = ArtCat.manifest().get("buildings", {}).get("g7_fac_wall", {})
	var par := int(wb.get("parapet_px", 0))
	check(par >= 8, "wall parapet height recorded (%d px over the deck)" % par)
	var f := FileAccess.open("res://assets/art/g7_sentinels/manifest.json", FileAccess.READ)
	if not check(f != null, "Sentinel art manifest present"):
		return
	var inf: Dictionary = (JSON.parse_string(f.get_as_text()) as Dictionary).get("infantry", {})
	var n := 0
	var bad := []
	for k in inf:
		var v: Dictionary = inf[k]
		var img: Image = ArtCat._image("res://assets/art/g7_sentinels/" + String(v.file))
		if img == null:
			bad.append([k, "no sheet"])
			continue
		var fr: Array = v.frames
		var fw := int(v.fw)
		var fh := int(v.fh)
		var py := int(v.pivot[1])
		for pose in [["crouch", par + 3], ["fire_c", par + 3], ["fire_s", par + 6], ["idle", par + 6]]:
			var c := fr.find(pose[0])
			if c < 0:
				continue
			for row in 8:
				var top := fh
				for y in fh:
					for x in fw:
						if img.get_pixel(c * fw + x, row * fh + y).a > 0.0:
							top = y
							break
					if top < fh:
						break
				if py - top < int(pose[1]):
					bad.append([k, pose[0], row, py - top])
		n += 1
	print("  Sentinel sheets checked %d, parapet %d px" % [n, par])
	check(n >= 8, "every Sentinel type checked (%d)" % n)
	check_eq(bad, [], "crouched: helmet >= 3 px over the parapet; standing / firing: >= 6 px (head and chest)")


## The motion layer's per-soldier spread keeps a wall-walker on his firing step: along the run only.
func test_motion_spread_stays_on_the_step() -> void:
	var mo := Vector2(0.2, -0.3)
	check_eq(Motion.wall_motion_off([0.0, 0.0, DECK_PX, 1, 0, false], mo), Vector2(0.2, 0.0), "E-W run: spread along x only")
	check_eq(Motion.wall_motion_off([0.0, 0.0, DECK_PX, 2, 0, false], mo), Vector2(0.0, -0.3), "N-S run: spread along y only")
	check_eq(Motion.wall_motion_off([0.0, 0.0, DECK_PX, 0, 0, true], mo), Vector2.ZERO, "tower deck: no spread (kept clear of the shaft)")
	check_eq(Motion.wall_motion_off([0.0, 0.0, DECK_PX, 3, 0, false], mo), Vector2.ZERO, "junction: no spread")
