extends "res://tests/test_base.gd"
## G7 PERF7I: the big-group formation fallback (Formations7 mass_fallback / _mass_line). A big attack-move whose
## shape cannot lie inside the map (the 2k gate fight: ~1000 men per side on a 96 x 96 map) used to fall back to one
## file clamped onto the map corner (the army walked back to its own corner, G6.1's d601e1d bug back in G7), then
## (PERF7H) to hollow-square boxes with the infantry stuck behind the armour block on its own start line (no fight).
## Now: chunks of <= 12 in a staggered assault line on the objective. These tests pin: no edge / corner slots, a sane
## distance from the goal, a line (not a blob) ahead of the start, the fight engaging like G6.1's, the old bug still
## reproducible with the toggle off, and small / fitting groups untouched.

const Bench = preload("res://tools/scale_bench.gd")
const F7 = preload("res://sim/systems/formations7.gd")
const Movement = preload("res://sim/systems/movement.gd")

## G6.1 (55b4e04) gate scene, measured by .plan/perf7i_eng.gd in C:/CODING/g7_regress2_wt/game (2026-10-28):
## kills by tick 600 = 1005, ShotFired by tick 600 = 13685, first ShotFired at tick 55.
const G61_KILLS := 1005
const G61_SHOTS := 13685
const G61_FIRST_SHOT := 55


func _gate_slots(st: Dictionary) -> Dictionary:
	var w: SimWorld = st.w
	var goal := Vector2(float(w.map.w) * 0.5, float(w.map.h) * 0.5)
	var mw := float(w.map.w)
	var mh := float(w.map.h)
	var out := {}
	for fid in st.fight:
		var cen := Vector2.ZERO
		var n0 := 0
		for id in st.fight[fid]:
			cen += Vector2(st.start_pos[id])
			n0 += 1
		cen /= float(maxi(n0, 1))
		var fwd := (goal - cen).normalized()
		var side := Vector2(-fwd.y, fwd.x)
		var b := {"n": 0, "edge": 0, "corner": 0, "sumd": 0.0, "sl": Vector2.ZERO, "ahead": 0.0, "go": cen.distance_to(goal),
				"ulo": INF, "uhi": -INF, "vlo": INF, "vhi": -INF}
		for id in st.fight[fid]:
			var e = w.entities.get(int(id))
			if e == null or not e.order.has("target") or typeof(e.order.target) != TYPE_VECTOR2:
				continue
			var g: Vector2 = e.order.target
			b.n += 1
			if g.x < 1.0 or g.y < 1.0 or g.x > mw - 1.0 or g.y > mh - 1.0:
				b.edge += 1
			for cc in [Vector2(0.5, 0.5), Vector2(mw - 0.5, 0.5), Vector2(0.5, mh - 0.5), Vector2(mw - 0.5, mh - 0.5)]:
				if g.distance_to(cc) < 1.0:
					b.corner += 1
			b.sumd += g.distance_to(goal)
			b.sl += g
			b.ahead += (g - cen).dot(fwd)
			if not F7.is_veh(e):
				b.ulo = minf(b.ulo, (g - goal).dot(side))
				b.uhi = maxf(b.uhi, (g - goal).dot(side))
				b.vlo = minf(b.vlo, (g - goal).dot(fwd))
				b.vhi = maxf(b.vhi, (g - goal).dot(fwd))
		out[fid] = b
	return out


func _build_gate() -> Dictionary:
	var st = Bench.build("river_crossing_s", 2000, ["human_a", "human_b"], "fight")
	var w: SimWorld = st.w
	var sp := {}
	for fid in st.fight:
		for id in st.fight[fid]:
			sp[id] = Vector2(w.entities[id].pos)
	st.start_pos = sp
	Bench.pre_tick(st, 0)
	w.step()
	return st


func test_big_attack_move_forms_a_line_on_the_objective() -> void:
	var st := _build_gate()
	var w: SimWorld = st.w
	var goal := Vector2(float(w.map.w) * 0.5, float(w.map.h) * 0.5)
	var res := _gate_slots(st)
	for fid in res:
		var b: Dictionary = res[fid]
		var n := maxi(int(b.n), 1)
		check(int(b.n) >= 900, "side %d: every attack-move unit has a slot (%d)" % [fid, b.n])
		check(int(b.edge) == 0 and int(b.corner) == 0, "side %d: no slot on the map edge / corner (edge %d, corner %d; the bug had ~800 on the corner)" % [fid, b.edge, b.corner])
		# a line of <= 0.9 x the ~136-tile anti-diagonal: mean |lateral| <= ~31, depth a few ranks; 40 leaves room for
		# fit() de-crowding around the river, far below the bug's 63.5
		check(float(b.sumd) / n <= 40.0, "side %d: mean slot distance from the goal %.1f <= 40 (bug 63.5)" % [fid, float(b.sumd) / n])
		var sc: Vector2 = b.sl / float(n)
		check(sc.distance_to(goal) <= 6.0, "side %d: the block is on the objective (slot centroid %.1f tiles from the goal)" % [fid, sc.distance_to(goal)])
		check(float(b.ahead) / n >= 0.75 * float(b.go), "side %d: slots lie ahead of the start, not back toward base (mean advance %.1f of %.1f)" % [fid, float(b.ahead) / n, float(b.go)])
		var wid := float(b.uhi) - float(b.ulo)
		var dep := float(b.vhi) - float(b.vlo)
		print("FORM7 side=%d slots=%d edge=%d corner=%d mean_d=%.1f centroid_off=%.1f advance=%.1f/%.1f front=%.0f depth=%.0f mass=%s" % [fid, b.n, b.edge, b.corner, float(b.sumd) / n, sc.distance_to(goal), float(b.ahead) / n, float(b.go), wid, dep, str(F7.last_mass)])
		check(wid >= 2.0 * dep, "side %d: the infantry stands as a line facing the enemy, not a blob (front %.0f x depth %.0f tiles)" % [fid, wid, dep])
	check(F7.last_mass.size() == 4 and String(F7.last_mass[0]) != "box", "massed chunks keep a combat shape (%s)" % str(F7.last_mass))


func test_mass_fallback_off_still_shows_the_corner_bug() -> void:
	F7.mass_fallback = false
	var st := _build_gate()
	F7.mass_fallback = true
	var res := _gate_slots(st)
	var corner := 0
	for fid in res:
		corner += int(res[fid].corner)
	print("FORM7 mass_fallback=false corner_slots=%d" % corner)
	check(corner > 0, "toggle off reproduces the pre-fix corner slots (corner slots %d), so the test above proves the fix" % corner)


func test_gate_fight_engages_like_g61() -> void:
	# Bands, set before the run: kills 0.75-1.5 x G6.1 (G7's wound rules kill ~1.4x per shot in every formation
	# variant; a fight that does not happen, PERF7H's boxes, gave 0.26x), shots 0.75-1.25 x G6.1 (the fight's
	# intensity, most of the sim cost), first contact within 30 ticks of G6.1's.
	var st = Bench.build("river_crossing_s", 2000, ["human_a", "human_b"], "fight")
	var w: SimWorld = st.w
	var shots := 0
	var kills := 0
	var first := -1
	for i in 600:
		Bench.pre_tick(st, i)
		w.step()
		for ev in w.events:
			if String(ev.type) == "ShotFired":
				shots += 1
				if first < 0:
					first = w.tick
			elif String(ev.type) == "EntityDestroyed" and String(ev.get("kind", "")) == "unit":
				kills += 1
	print("FORM7 fight kills=%d shots=%d first_shot=%d hash=%s" % [kills, shots, first, String(w.state_hash()).left(16)])
	check(kills >= int(0.75 * G61_KILLS) and kills <= int(1.5 * G61_KILLS), "kills by tick 600: %d in [%d, %d] (G6.1 %d)" % [kills, int(0.75 * G61_KILLS), int(1.5 * G61_KILLS), G61_KILLS])
	check(shots >= int(0.75 * G61_SHOTS) and shots <= int(1.25 * G61_SHOTS), "shots by tick 600: %d in [%d, %d] (G6.1 %d)" % [shots, int(0.75 * G61_SHOTS), int(1.25 * G61_SHOTS), G61_SHOTS])
	check(first >= 0 and first <= G61_FIRST_SHOT + 30, "first shot at tick %d <= %d (G6.1 %d)" % [first, G61_FIRST_SHOT + 30, G61_FIRST_SHOT])


func test_small_and_fitting_groups_unchanged() -> void:
	for n in [12, 60]:
		var outs := []
		for on in [true, false]:
			F7.mass_fallback = on
			var w := make_world()
			w.ai_state = {}
			var us := []
			for k in n:
				var id := w.spawn_unit("rifleman", 0, Vector2(Movement.nearest_free_cell(w, Vector2i(10 + k % 10, 40 + k / 10), "foot")) + Vector2(0.5, 0.5))
				w.entities[id].formation = "wedge"
				us.append(w.entities[id])
			outs.append(Movement.formation_slots(w, us, Vector2(30.5, 40.5)))
		F7.mass_fallback = true
		check(outs[0] == outs[1], "%d-man wedge: identical slots with the mass fallback on and off" % n)
