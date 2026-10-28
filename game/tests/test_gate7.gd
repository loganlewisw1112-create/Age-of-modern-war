extends "res://tests/test_base.gd"
## G7 acceptance (owner: GATE7). Owner note 13.9c-26: the APC entry gates (outer + inner) get heavy armoured blast doors
## with a real open / close animation driven by the sim gate state (13.9c-22), opaque (13.9c-18).
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const FacDrive7 = preload("res://sim/systems/fac_drive7.gd")
const Movement = preload("res://sim/systems/movement.gd")
const FacGate7 = preload("res://presentation/view/fac_gate7.gd")
const MAN := "res://assets/art/g7_fac7f/manifest.json"
const DIR := "res://assets/art/g7_fac7f/"
const GATES := ["g7_fac_gate_outer", "g7_fac_gate_inner"]


func _ensure_g7() -> void:
	if Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")


func _man() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(MAN))
	return (d.get("buildings", {}) as Dictionary) if d is Dictionary else {}


func _img(b: Dictionary, st: String) -> Image:
	var s: Dictionary = (b.states as Dictionary).get(st, {})
	if s.is_empty():
		return null
	return Image.load_from_file(ProjectSettings.globalize_path(DIR + String(s.file)))


func test_frames_exist_for_every_state_and_facing() -> void:
	var man := _man()
	for id in GATES:
		check(man.has(id), "%s in the g7_fac7f manifest" % id)
		if not man.has(id):
			continue
		var b: Dictionary = man[id]
		var miss := []
		var bad := []
		for f in 4:
			for st in FacGate7.states_for(f):
				var im := _img(b, st)
				if im == null:
					miss.append(st)
				elif im.get_width() != int(b.fw) or im.get_height() != int(b.fh):
					bad.append(st)
		check(miss.is_empty(), "%s: every door state on every side exists (%d per side; missing %s)" % [id, FacGate7.states_for(0).size(), miss])
		check(bad.is_empty(), "%s: every frame has the entry's canvas size %dx%d (off: %s)" % [id, int(b.fw), int(b.fh), bad])
		check_eq(int((b.get("anim", {}) as Dictionary).get("travel", 0)), FacGate7.N_TRAVEL, "%s: art travel frames = display N_TRAVEL" % id)
		check_eq(int((b.get("anim", {}) as Dictionary).get("bolt", 0)), FacGate7.N_BOLT, "%s: art lock-bar frames = display N_BOLT" % id)


## Pixels that differ from the open frame (alpha or colour).
func _diff(a: Image, b: Image) -> int:
	var n := 0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				n += 1
	return n


func test_leaves_close_progressively_and_open_differs_from_sealed() -> void:
	var man := _man()
	for id in GATES:
		if not man.has(id):
			check(false, "%s missing" % id)
			continue
		var b: Dictionary = man[id]
		for f in [1, 3]:
			var op := _img(b, "rot_%d" % f)
			var sealed := _img(b, "rot_%d_lockdown" % f)
			var d_seal := _diff(op, sealed)
			check(d_seal > 2500, "%s rot_%d: sealed vs open differ in %d px (> 2500: the leaves fill the opening)" % [id, f, d_seal])
			var prev := -1
			var mono := true
			var ds := []
			for k in range(0, FacGate7.N_TRAVEL, 3):
				var d := _diff(op, _img(b, "rot_%d_gm_%d" % [f, k]))
				ds.append(d)
				if d + 40 < prev:
					mono = false
				prev = d
			check(mono, "%s rot_%d: travel frames cover more of the opening step by step %s" % [id, f, ds])
			var last := _img(b, "rot_%d_gm_%d" % [f, FacGate7.N_TRAVEL - 1])
			var bolt := _img(b, "rot_%d_gb_1" % f)
			check(_diff(last, bolt) > 20, "%s rot_%d: the lock bars move between leaves-met and bars-driving" % [id, f])


## 13.9c-18: nothing see-through. Partly transparent pixels are allowed only as (a) the drawn ground shadow (M.shadow
## alpha 102) or (b) the renderer's silhouette anti-alias rim: alpha >= 150 (solid enough that C.selout treats it as
## solid) within 3 px of an empty / shadow pixel. Anything fainter (a light pool, mist, a translucent slab or glass fill)
## fails anywhere, and so does a rim-alpha pixel deep inside the sprite.
func test_opaque_no_translucent_fill() -> void:
	var man := _man()
	var shadow_a := 102
	for id in GATES:
		if not man.has(id):
			check(false, "%s missing" % id)
			continue
		var b: Dictionary = man[id]
		for st in ["rot_3", "rot_3_gm_8", "rot_3_gb_2", "rot_3_lockdown", "rot_1", "rot_1_lockdown"]:
			var im := _img(b, st)
			var w := im.get_width()
			var h := im.get_height()
			var faint := 0
			var inner := 0
			for y in h:
				for x in w:
					var a := int(round(im.get_pixel(x, y).a * 255.0))
					if a == 0 or a == 255 or a == shadow_a:
						continue
					if a < 150:
						faint += 1
						continue
					var edge := false
					for dy in range(-3, 4):
						for dx in range(-3, 4):
							var q := Vector2i(clampi(x + dx, 0, w - 1), clampi(y + dy, 0, h - 1))
							var an := int(round(im.get_pixel(q.x, q.y).a * 255.0))
							if an == 0 or an == shadow_a:
								edge = true
					if not edge:
						inner += 1
			check_eq(faint, 0, "%s %s: no faint (alpha < 150) translucent pixel" % [id, st])
			check_eq(inner, 0, "%s %s: no translucent pixel inside the sprite" % [id, st])


func test_phase_sequence_closing_and_opening() -> void:
	var seq := []
	for i in 101:
		var s := FacGate7.phase_suffix(true, float(i) / 100.0)
		if seq.is_empty() or seq[seq.size() - 1] != s:
			seq.append(s)
	check_eq(seq[0], "_gm_0", "closing starts with the warning frame (beacons on, leaves still open)")
	check_eq(seq[seq.size() - 1], "_gb_%d" % (FacGate7.N_BOLT - 1), "closing ends with the lock bars nearly home (%s)" % [seq])
	var idx := []
	for s in seq:
		idx.append(_order(s))
	var mono := true
	for i in range(1, idx.size()):
		mono = mono and int(idx[i]) > int(idx[i - 1])
	check(mono, "closing frames run strictly forward: %s" % [seq])
	check(seq.size() >= FacGate7.N_TRAVEL + FacGate7.N_BOLT - 2, "closing shows (nearly) every travel and bolt frame (%d)" % seq.size())
	var op := []
	for i in 101:
		var s := FacGate7.phase_suffix(false, float(i) / 100.0)
		if op.is_empty() or op[op.size() - 1] != s:
			op.append(s)
	check_eq(op[0], "_gb_%d" % (FacGate7.N_BOLT - 1), "opening starts with the lock bars pulling back")
	check_eq(op[op.size() - 1], "_gm_0", "opening ends with the leaves parked, beacons still on")
	# heavy door: slow start and stop, steady middle
	check(FacGate7.travel(0.1) < 0.1 * 0.8 and FacGate7.travel(0.9) > 1.0 - 0.1 * 0.8, "travel eases in and out")
	check(absf(FacGate7.travel(0.5) - 0.5) < 0.01 and absf(FacGate7.travel(1.0) - 1.0) < 0.001, "travel is symmetric and ends at 1")


## Frame order key: gm_k = k, gb_k = N_TRAVEL + k, lockdown last, open first.
func _order(s: String) -> int:
	if s == "":
		return -1
	if s == "_lockdown":
		return 1000
	if s.begins_with("_gm_"):
		return int(s.substr(4))
	if s.begins_with("_gb_"):
		return FacGate7.N_TRAVEL + int(s.substr(4))
	return -2


# ---------------------------------------------------------------- with the real sim gate (13.9c-22)
func _setup() -> Array:
	var w := make_world()
	_ensure_g7()
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
	for i in CnFacility.DISCOVER_EVERY + 1:
		w.step()
	return [w, fid]


func _enemy(w: SimWorld, fid: int) -> int:
	var cr := CnFacility.compound_rect(CnFacility.fac(w, fid))
	var en := w.spawn_unit("rifleman", 1, cr.end + Vector2(-14, 9))
	var ee: Dictionary = w.entities[en]
	ee.order = {"type": "hold"}
	ee.cd_ticks = 100000
	ee.hp = 1.0e9
	ee.max_hp = 1.0e9
	return en


## Runs the harden + stand-down cycle; view = call the display picker every tick like entity_layer. Returns
## [state hash, outer frame sequence, sim outer state sequence, tick sim locked, tick display showed sealed].
func _cycle(view: bool) -> Array:
	var s := _setup()
	var w: SimWorld = s[0]
	var fid: int = s[1]
	var en := _enemy(w, fid)
	var seq := []
	var sims := []
	var t_lock := -1
	var t_seal := -1
	for i in CnFacility.secs(FacDrive7.STAND_DOWN_S) + CnFacility.secs(FacDrive7.GATE_S) * 3 + 120:
		if i == CnFacility.secs(FacDrive7.GATE_S) + 60 and w.entities.has(en):
			w.entities.erase(en)
			w.cache.erase("sim_index")
		w.step()
		var gv := FacDrive7.gate_view(CnFacility.fac(w, fid))
		if sims.is_empty() or sims[sims.size() - 1] != gv[0]:
			sims.append(gv[0])
			if gv[0] == "hardened" and t_lock < 0:
				t_lock = w.tick
		if view:
			var es := CnFacility.render_entries(w)
			FacGate7.sync(w, es, w.tick)
			for F in es:
				if int(F.id) == fid:
					var sfx := FacGate7.suffix(F, "gate_outer", bool(F.get("lock", false)), w.tick)
					FacGate7.suffix(F, "gate_inner", bool(F.get("lock", false)), w.tick)
					if seq.is_empty() or seq[seq.size() - 1] != sfx:
						seq.append(sfx)
						if sfx == "_lockdown" and t_seal < 0:
							t_seal = w.tick
	return [w.state_hash(), seq, sims, t_lock, t_seal]


func test_animation_follows_the_sim_gate_and_display_is_hash_neutral() -> void:
	if not FacDrive7.GATES_ON:
		print("  GATE7 sim test NOT EXECUTED: FacDrive7.GATES_ON false")
		return
	var a := _cycle(true)
	var b := _cycle(false)
	check_eq(a[0], b[0], "display only: state hash with the door picker running = without it")
	var sims: Array = a[2]
	check(sims.has("closing") and sims.has("hardened") and sims.has("opening"), "the sim gate cycles closing -> hardened -> opening (%s)" % [sims])
	var seq: Array = a[1]
	check(seq.size() > 0 and seq[0] == "", "open gate shows the open frame first (%s)" % [seq.slice(0, 3)])
	# closing: from the open frame forward to sealed, never backwards
	var ci := seq.find("_lockdown")
	check(ci > 0, "the display reaches the sealed frame")
	var fwd := true
	var nt := 0
	for i in range(1, maxi(1, ci + 1)):
		fwd = fwd and _order(seq[i]) > _order(seq[i - 1])
		if String(seq[i]).begins_with("_gm_"):
			nt += 1
	check(fwd, "closing frames only run forward: %s" % [seq.slice(0, ci + 1)])
	check(nt >= 10, "the leaves travel through >= 10 distinct frames (%d): a smooth heavy slide" % nt)
	check_eq(a[4], a[3], "the display shows sealed on the tick the sim locks the gate")
	# opening: from sealed back to open, never forwards
	var bwd := true
	for i in range(ci + 1, seq.size()):
		bwd = bwd and (_order(seq[i]) < _order(seq[i - 1]) or (seq[i] == "" and seq[i - 1] == "_gm_0"))
	check(ci + 1 < seq.size() and bwd, "opening frames run backwards to open: %s" % [seq.slice(ci, seq.size())])
	check_eq(seq[seq.size() - 1], "", "after standing down the gate shows open again")
