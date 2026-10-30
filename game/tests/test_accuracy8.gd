extends "res://tests/test_base.gd"
## G7 ACCURACY8 (G7_REFERENCE 13.9c-49): realistic per-shot hit chance. Each factor moves the hit chance the right
## way with a sensible size (full Combat._fire accuracy chain: weapon x Status x G6 hooks x Wounds x Accuracy8), the
## real fire path hits less on the move, and the same seed gives the same hash.

const Movement = preload("res://sim/systems/movement.gd")
const Combat = preload("res://sim/systems/combat.gd")
const Status = preload("res://sim/systems/status.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const A8 = preload("res://sim/systems/accuracy8.gd")
const Senses7 = preload("res://sim/systems/senses7.gd")

func _world(seed_v: int = 0) -> SimWorld:
	var w := make_world() if seed_v == 0 else make_world({"seed": seed_v})
	w.ai_state = {}
	var t: PackedByteArray = w.map.terrain
	for y in range(0, 30):
		for x in range(10, 80):
			t[y * int(w.map.w) + x] = Terrain.GRASS
	w.map.terrain = t
	Movement.rebuild_nav(w)
	return w


## The full _fire accuracy chain for e shooting t (writes the sight-picture fields like a real shot).
func _acc(w: SimWorld, e: Dictionary, t: Dictionary) -> float:
	var s: Dictionary = Combat.stats(e)
	var a := float(s.accuracy) * Status.accuracy_mult(w, e)
	if SimIndex.g6m(w) & SimIndex.G6_ACC:
		a *= SimIndex.g6h().accuracy_mult(w, e, s, t)
	if e.has("wz"):
		a *= SimWorld.Wounds.acc_mult(e)
	a *= A8.mult(w, e, s, t)
	return clampf(a, 0.0, 1.0)


## Steady aim on t (sight picture 5 s old).
func _aimed(w: SimWorld, e: Dictionary, t: Dictionary) -> void:
	e["a8t"] = int(t.id)
	e["a8k"] = w.tick - 100
	e["a8l"] = w.tick


func _snap(e: Dictionary) -> void:
	e.erase("a8t")
	e.erase("a8k")
	e.erase("a8l")


func _pair(sd: String, td: String, rg: float, seed_v: int = 0) -> Array:
	var w := _world(seed_v)
	w.tick = 1000
	var sid := w.spawn_unit(sd, 0, Vector2(20.5, 10.5))
	var tid := w.spawn_unit(td, 1, Vector2(20.5 + rg, 10.5))
	return [w, w.entities[sid], w.entities[tid]]


func _row(name: String, a: float, b: float) -> void:
	print("ACC8 %s: %.3f vs %.3f" % [name, a, b])


func test_enabled_and_neutral_skips() -> void:
	check(A8.enabled(), "rules.accuracy8 loaded and enabled")
	var p := _pair("rifleman", "b_militia", 4.0)
	var w: SimWorld = p[0]
	var s: Dictionary = Combat.stats(p[1]).duplicate()
	s.indirect = true
	check_eq(A8.mult(w, p[1], s, p[2]), 1.0, "indirect fire: x1.0 (artillery keeps its own scatter)")
	s.indirect = false
	s.guided = true
	check_eq(A8.mult(w, p[1], s, p[2]), 1.0, "guided: x1.0")


func test_range_and_flight_time() -> void:
	var p := _pair("rifleman", "b_militia", 1.5)
	var w: SimWorld = p[0]
	_aimed(w, p[1], p[2])
	var near := _acc(w, p[1], p[2])
	p[2].pos = Vector2(20.5 + 5.8, 10.5)
	_aimed(w, p[1], p[2])
	var far := _acc(w, p[1], p[2])
	_row("rifle aimed static, 1.5 vs 5.8 tiles", near, far)
	check(near > far * 1.3, "close range hits far more often than near max range (%.3f vs %.3f)" % [near, far])
	check(far > 0.15 and near <= 1.0, "far aimed fire still hits sometimes (%.3f)" % far)
	var tf1 := A8.flight_s("rifle", 5.0)
	var tf2 := A8.flight_s("at_rocket", 5.0)
	check(tf1 > 0.1 and tf1 < 0.5, "5.56 flight time to 200 m ~0.25 s (%.3f)" % tf1)
	check(tf2 > tf1 * 1.5, "a rocket flies slower than a rifle round (%.3f vs %.3f s)" % [tf2, tf1])


func test_shooter_moving() -> void:
	var p := _pair("rifleman", "b_militia", 4.0)
	var w: SimWorld = p[0]
	_aimed(w, p[1], p[2])
	var st := _acc(w, p[1], p[2])
	p[1].moving = true
	var mv := _acc(w, p[1], p[2])
	_row("rifleman static vs moving @4", st, mv)
	check(mv < st * 0.45, "firing on the move: far less accurate (%.3f vs %.3f)" % [mv, st])
	check(mv > 0.05, "but not zero (%.3f)" % mv)
	# stabilised MBT vs an unstabilised carrier
	var q := _pair("mbt", "b_militia", 5.0)
	var w2: SimWorld = q[0]
	_aimed(w2, q[1], q[2])
	var t_st := _acc(w2, q[1], q[2])
	q[1].moving = true
	_aimed(w2, q[1], q[2])
	var t_mv := _acc(w2, q[1], q[2])
	var r := _pair("b_carrier", "b_militia", 5.0)
	var w3: SimWorld = r[0]
	_aimed(w3, r[1], r[2])
	var c_st := _acc(w3, r[1], r[2])
	r[1].moving = true
	_aimed(w3, r[1], r[2])
	var c_mv := _acc(w3, r[1], r[2])
	_row("MBT (stabilised) static vs moving", t_st, t_mv)
	_row("carrier (unstabilised) static vs moving", c_st, c_mv)
	check(t_mv / t_st > 0.8, "stabilised MBT barely loses on the move (x%.2f)" % (t_mv / t_st))
	check(c_mv / c_st < t_mv / t_st - 0.2, "unstabilised vehicle loses much more (x%.2f vs x%.2f)" % [c_mv / c_st, t_mv / t_st])


func test_target_moving_crossing() -> void:
	var p := _pair("rifleman", "b_militia", 5.0)
	var w: SimWorld = p[0]
	_aimed(w, p[1], p[2])
	var st := _acc(w, p[1], p[2])
	p[2].moving = true
	p[2].facing = PI / 2.0   # crossing (line of fire is +x)
	_aimed(w, p[1], p[2])
	var cr := _acc(w, p[1], p[2])
	p[2].facing = 0.0        # running straight away
	_aimed(w, p[1], p[2])
	var rd := _acc(w, p[1], p[2])
	_row("target static vs crossing vs radial @5", st, cr)
	print("ACC8   radial: %.3f" % rd)
	check(cr < rd and rd < st, "crossing < radial < static target (%.3f < %.3f < %.3f)" % [cr, rd, st])
	check(cr < st * 0.8, "a crossing runner is clearly harder (%.3f vs %.3f)" % [cr, st])


func test_sight_picture_and_optics() -> void:
	var p := _pair("rifleman", "b_militia", 4.0)
	var w: SimWorld = p[0]
	_snap(p[1])
	var snap := _acc(w, p[1], p[2])
	w.tick += 20
	var one := _acc(w, p[1], p[2])
	w.tick += 40
	var aimed := _acc(w, p[1], p[2])
	_row("rifleman snap (first shot) vs aimed (3 s on target)", snap, aimed)
	check(snap < one and one < aimed, "aim improves shot by shot (%.3f < %.3f < %.3f)" % [snap, one, aimed])
	check(aimed > snap * 1.3, "aimed fire clearly better than a snap shot (%.3f vs %.3f)" % [aimed, snap])
	# a new target starts over
	var t2id: int = p[0].spawn_unit("b_militia", 1, Vector2(24.5, 11.5))
	var other := _acc(w, p[1], w.entities[t2id])
	check(other < aimed * 0.8, "switching target: a snap shot again (%.3f)" % other)
	# optics: settle faster
	var q := _pair("a_sniper", "b_militia", 6.0)
	var w2: SimWorld = q[0]
	_snap(q[1])
	_acc(w2, q[1], q[2])
	w2.tick += 24   # 1.2 s
	var o := _acc(w2, q[1], q[2])
	var mk: Array = A8._profile_of(q[1])
	check(bool(mk[2]), "a_sniper counts as optics")
	var g := _pair("rifleman", "b_militia", 6.0)
	var w3: SimWorld = g[0]
	_snap(g[1])
	_acc(w3, g[1], g[2])
	w3.tick += 24
	var i := _acc(w3, g[1], g[2])
	check(A8.mult(w2, q[1], Combat.stats(q[1]), q[2]) > A8.mult(w3, g[1], Combat.stats(g[1]), g[2]), "optics: steadier after 1.2 s than iron sights")
	print("ACC8   sniper(optics) 1.2 s: %.3f, rifleman 1.2 s: %.3f" % [o, i])


func test_visibility() -> void:
	var p := _pair("rifleman", "b_militia", 4.0)
	var w: SimWorld = p[0]
	_aimed(w, p[1], p[2])
	var day := _acc(w, p[1], p[2])
	Senses7.set_light(w, 0.1)
	w.tick += 1
	_aimed(w, p[1], p[2])
	var night := _acc(w, p[1], p[2])
	_row("rifleman day vs night (light 0.1)", day, night)
	check(night < day * 0.6, "night: much worse without NVG (%.3f vs %.3f)" % [night, day])
	p[1]["nvg"] = true
	w.tick += 1
	_aimed(w, p[1], p[2])
	var nvg := _acc(w, p[1], p[2])
	check(nvg > night * 1.5, "NVG / thermal restores most of it (%.3f)" % nvg)
	p[1].erase("nvg")
	Senses7.set_light(w, 1.0)
	Senses7.add_smoke(w, Vector2(22.5, 10.5), 1.0, 30.0)
	w.tick += 1
	_aimed(w, p[1], p[2])
	var smoke := _acc(w, p[1], p[2])
	_row("rifleman clear vs through smoke", day, smoke)
	check(smoke < day * 0.5, "smoke on the line: much worse (%.3f)" % smoke)
	# target prone / in forest
	var q := _pair("rifleman", "b_militia", 4.0)
	var w2: SimWorld = q[0]
	_aimed(w2, q[1], q[2])
	var up := _acc(w2, q[1], q[2])
	q[2]["prone"] = true
	_aimed(w2, q[1], q[2])
	var dn := _acc(w2, q[1], q[2])
	_row("target standing vs prone", up, dn)
	check(dn < up * 0.8, "a prone target is harder to hit (%.3f vs %.3f)" % [dn, up])
	# fog edge: past the shooter's own sight
	var r := _pair("mbt", "b_militia", 8.0)
	var w3: SimWorld = r[0]
	var s3: Dictionary = Combat.stats(r[1])
	var m_in := A8.mult(w3, r[1], s3, r[2])
	r[1].pos = Vector2(20.5 - 1.5, 10.5)   # 9.5 tiles: past mbt sight 9
	var m_out := A8.mult(w3, r[1], s3, r[2])
	check(m_out < m_in, "past the shooter's own sight (team-spotted target) worse (%.3f vs %.3f)" % [m_out, m_in])
	# weather
	w2.cfg["weather"] = "fog"
	q[2].erase("prone")
	w2.tick += 1
	_aimed(w2, q[1], q[2])
	var fogw := _acc(w2, q[1], q[2])
	check(fogw < up * 0.8, "fog weather: worse (%.3f vs %.3f)" % [fogw, up])


func test_under_fire() -> void:
	var p := _pair("rifleman", "b_militia", 4.0)
	var w: SimWorld = p[0]
	_aimed(w, p[1], p[2])
	var calm := _acc(w, p[1], p[2])
	p[1]["supp"] = 40.0
	_aimed(w, p[1], p[2])
	var supp := _acc(w, p[1], p[2])
	p[1]["pinned"] = true
	_aimed(w, p[1], p[2])
	var pin := _acc(w, p[1], p[2])
	_row("rifleman calm vs suppressed vs pinned", calm, supp)
	print("ACC8   pinned: %.3f" % pin)
	check(supp < calm and pin < supp, "suppressed < calm, pinned < suppressed (%.3f, %.3f, %.3f)" % [calm, supp, pin])
	p[1].erase("supp")
	p[1].erase("pinned")
	p[1]["last_hit_tick"] = w.tick - 10
	_aimed(w, p[1], p[2])
	var hit := _acc(w, p[1], p[2])
	check(hit < calm * 0.85, "just hit: shaken (%.3f vs %.3f)" % [hit, calm])
	p[1]["last_hit_tick"] = w.tick - 200
	_aimed(w, p[1], p[2])
	check(absf(_acc(w, p[1], p[2]) - calm) < 1e-6, "the shock wears off")
	p[1]["b8d"] = w.tick + 100
	_aimed(w, p[1], p[2])
	var dz := _acc(w, p[1], p[2])
	check(dz < calm * 0.7, "concussion daze (b8d): much worse (%.3f)" % dz)


func test_posture_and_training() -> void:
	var p := _pair("rifleman", "b_militia", 5.0)
	var w: SimWorld = p[0]
	_aimed(w, p[1], p[2])
	var stand := _acc(w, p[1], p[2])
	p[1]["prone"] = true
	_aimed(w, p[1], p[2])
	var prone := _acc(w, p[1], p[2])
	p[1].erase("prone")
	p[1]["in_cover"] = true
	_aimed(w, p[1], p[2])
	var braced := _acc(w, p[1], p[2])
	_row("rifleman standing vs prone", stand, prone)
	print("ACC8   braced (cover rest): %.3f" % braced)
	check(prone > stand * 1.05 and braced > stand * 1.05, "prone / braced steadier than standing (%.3f, %.3f > %.3f)" % [prone, braced, stand])
	var mp: Array = A8._profile_of({"def": "b_militia", "kind": "unit"})
	var rp: Array = A8._profile_of({"def": "rifleman", "kind": "unit"})
	check(float(mp[5]) < float(rp[5]), "militia training < regular (%.2f vs %.2f)" % [float(mp[5]), float(rp[5])])


func test_real_fire_path_moving_and_determinism() -> void:
	var res := []
	for run in 2:
		var out := {}
		for mv in [false, true]:
			var p := _pair("rifleman", "mbt", 4.0, 4242)
			var w: SimWorld = p[0]
			var e: Dictionary = p[1]
			var t: Dictionary = p[2]
			var s: Dictionary = Combat.stats(e)
			var hits := 0
			var shots := 0
			for i in 400:
				w.tick += 20
				e.cd_ticks = 0
				if e.has("ammo"):
					e.ammo = 100
				e.moving = mv
				t.hp = 1.0e6
				w.events.clear()
				Combat._fire(w, e, s, t, true)
				for ev in w.events:
					if String(ev.type) == "ShotFired":
						shots += 1
						hits += 1 if bool(ev.hit) else 0
			out[mv] = [shots, hits, w.state_hash()]
		res.append(out)
	var st: Array = res[0][false]
	var mvv: Array = res[0][true]
	check(int(st[0]) >= 300 and int(mvv[0]) >= 300, "the real _fire path fired (%d / %d shots)" % [int(st[0]), int(mvv[0])])
	var rs := float(st[1]) / maxf(float(st[0]), 1.0)
	var rm := float(mvv[1]) / maxf(float(mvv[0]), 1.0)
	_row("REAL _fire rifleman->mbt @4 hit rate static vs moving", rs, rm)
	check(rm < rs * 0.6, "real fire on the move hits much less (%.3f vs %.3f)" % [rm, rs])
	check_eq(res[0][false], res[1][false], "same seed: same shots, hits and hash (static)")
	check_eq(res[0][true], res[1][true], "same seed: same shots, hits and hash (moving)")



# ======================================================================= ACCURACY8B (13.9c-53)
const Stray8 = preload("res://sim/systems/stray8.gd")
const Blast8 = preload("res://sim/systems/blast8.gd")
const Damage = preload("res://sim/systems/damage.gd")


func _count(w: SimWorld, typ: String, key: String = "", val = null) -> int:
	var n := 0
	for ev in w.events:
		if String(ev.type) == typ and (key == "" or ev.get(key) == val):
			n += 1
	return n


## A miss along the line shooter -> target flies on and hits the man standing behind the target.
func test_stray_hits_man_behind() -> void:
	var p := _pair("rifleman", "rifleman", 4.0, 777)
	var w: SimWorld = p[0]
	var e: Dictionary = p[1]
	var t: Dictionary = p[2]
	var bid := w.spawn_unit("rifleman", 1, Vector2(26.5, 10.5))
	var b: Dictionary = w.entities[bid]
	var s: Dictionary = Combat.stats(e)
	var hits_b := 0
	var strays := 0
	var deaths := 0
	for i in 200:
		w.events.clear()
		if not w.entities.has(bid) or bool(b.get("wunc", false)) or bool(b.get("wounded", false)):
			deaths += 1   # a head / torso hit can kill or knock him out: a fresh man takes his place
			if w.entities.has(bid):
				w.destroy(bid, "test")
			bid = w.spawn_unit("rifleman", 1, Vector2(26.5, 10.5))
			b = w.entities[bid]
		b.hp = 1.0e6
		var off := (float(i % 21) - 10.0) * 0.03   # -0.3 .. 0.3 tiles beside the aim point
		Stray8.on_miss(w, e, s, t, Vector2(e.pos), Vector2(t.pos) + Vector2(0.0, off))
		strays += _count(w, "StrayHit")
		hits_b += _count(w, "StrayHit", "target", bid)
	print("ACC8B stray: misses 200 -> stray hits %d (man 2 tiles behind the target: %d, replaced after kill / knock-out %d)" % [strays, hits_b, deaths])
	check(hits_b > 30, "strays hit the man behind the target (%d of 200 misses)" % hits_b)
	check_eq(strays, hits_b, "every stray hit is on the man behind (nothing else on the line)")
	# a round well off the line hits nobody
	w.events.clear()
	Stray8.on_miss(w, e, s, t, Vector2(e.pos), Vector2(t.pos) + Vector2(0.0, 1.5))
	check_eq(_count(w, "StrayHit"), 0, "a miss far off the line hits nobody")
	# beyond weapon range: nothing
	var fid := w.spawn_unit("rifleman", 1, Vector2(20.5 + float(s.range) + 2.0, 10.5))
	b.pos = Vector2(60.5, 60.5)
	var far_hits := 0
	for i in 100:
		w.events.clear()
		Stray8.on_miss(w, e, s, t, Vector2(e.pos), Vector2(t.pos))
		far_hits += _count(w, "StrayHit", "target", fid)
	check_eq(far_hits, 0, "the stray stops at the weapon's range")


## Shooting past your own men on the real fire path: friendly-fire events happen; same seed = same result.
func test_friendly_fire_real_path_and_determinism() -> void:
	var res := []
	for run in 2:
		var p := _pair("rifleman", "rifleman", 5.0, 9191)
		var w: SimWorld = p[0]
		var e: Dictionary = p[1]
		var t: Dictionary = p[2]
		var fid := w.spawn_unit("rifleman", 0, Vector2(24.0, 10.55))   # a friend on the line, 3.5 tiles out (past the discipline muzzle zone)
		var f: Dictionary = w.entities[fid]
		var s: Dictionary = Combat.stats(e)
		var shots := 0
		var misses := 0
		var ff := 0
		var stray := 0
		var leak := 0
		for i in 300:
			w.tick += 20
			e.cd_ticks = 0
			if e.has("ammo"):
				e.ammo = 100
			e.moving = true   # firing on the move: many misses
			t.hp = 1.0e6
			if not w.entities.has(fid) or bool(f.get("wunc", false)) or bool(f.get("wounded", false)):
				if w.entities.has(fid):
					w.destroy(fid, "test")
				fid = w.spawn_unit("rifleman", 0, Vector2(24.0, 10.55))   # a fresh friend in the same spot
				f = w.entities[fid]
			f.hp = 1.0e6
			w.events.clear()
			Combat._fire(w, e, s, t, true)
			for ev in w.events:
				match String(ev.type):
					"ShotFired":
						shots += 1
						misses += 0 if bool(ev.hit) else 1
					"FriendlyFire":
						ff += 1
					"StrayHit":
						stray += 1
			if w.cache.has("a8p"):
				leak += 1
		check_eq(leak, 0, "placement is transient (w.cache.a8p cleared after every shot)")
		res.append([shots, misses, stray, ff, w.state_hash()])
	var r0: Array = res[0]
	print("ACC8B friendly: shots %d misses %d stray hits %d friendly-fire %d" % [r0[0], r0[1], r0[2], r0[3]])
	check(int(r0[3]) > 0, "firing past a friend causes friendly fire (%d)" % int(r0[3]))
	check_eq(res[0], res[1], "same seed: same shots, misses, strays, friendly fire and hash")


## Aimed settled fire lands more on head / torso than snap / moving / dazed fire; same draw count per pick.
func test_shot_placement() -> void:
	var p := _pair("rifleman", "rifleman", 4.0, 31337)
	var w: SimWorld = p[0]
	var e: Dictionary = p[1]
	var t: Dictionary = p[2]
	var s: Dictionary = Combat.stats(e)
	var out := {}
	for mode in ["aimed", "neutral", "snap", "snap_moving", "dazed_moving"]:
		_snap(e)
		e.moving = false
		e.erase("b8d")
		if mode == "aimed":
			_aimed(w, e, t)
		elif mode == "snap_moving":
			e.moving = true
		elif mode == "dazed_moving":
			e.moving = true
			e.b8d = w.tick + 100
		A8.mult(w, e, s, t)
		var pl = A8.take_place()
		if mode == "neutral":
			pl = null
		if pl != null:
			w.cache["a8p"] = pl
		var vit := 0
		for i in 3000:
			var z := SimWorld.Wounds.pick_zone(w, t, Vector2(e.pos))
			if z == "head" or z == "torso":
				vit += 1
		w.cache.erase("a8p")
		out[mode] = float(vit) / 3000.0
		print("ACC8B zone %s: vital (head+torso) share %.3f  mult %s" % [mode, out[mode], str(pl)])
	check(float(out.aimed) > float(out.neutral) + 0.08, "aimed fire hits vitals more than neutral (%.3f vs %.3f)" % [out.aimed, out.neutral])
	check(float(out.snap) < float(out.neutral), "snap fire spreads to limbs (%.3f < %.3f)" % [out.snap, out.neutral])
	check(float(out.aimed) > float(out.snap_moving) + 0.2, "aimed vs snap on the move: vitals %.3f vs %.3f" % [out.aimed, out.snap_moving])
	check(float(out.dazed_moving) <= float(out.snap_moving) + 0.02, "dazed fire is no better placed than snap moving fire")
	# same draw count: a pick with placement consumes exactly the draws of a pick without
	var w1 := _world(55)
	var w2 := _world(55)
	var a := w1.spawn_unit("rifleman", 1, Vector2(30.5, 10.5))
	var b := w2.spawn_unit("rifleman", 1, Vector2(30.5, 10.5))
	w1.cache["a8p"] = Vector2(2.0, 0.5)
	for i in 50:
		SimWorld.Wounds.pick_zone(w1, w1.entities[a], Vector2(20.5, 10.5))
		SimWorld.Wounds.pick_zone(w2, w2.entities[b], Vector2(20.5, 10.5))
	check_eq(w1.rng.randf(), w2.rng.randf(), "placement keeps the draw count per zone pick")


## Vehicle hits use the real hit facing: a rear / side hit hurts more than a frontal one (flanking pays).
func test_vehicle_facing_flank() -> void:
	var dmg := {}
	var faces := {"front": PI, "side": PI / 2.0, "rear": 0.0}
	for face in ["front", "side", "rear"]:
		var p := _pair("mbt", "mbt", 4.0, 4040)
		var w: SimWorld = p[0]
		var e: Dictionary = p[1]
		var t: Dictionary = p[2]
		t.facing = float(faces[face])
		check_eq(Damage.hit_side(Vector2(e.pos), t), face, "hit_side %s" % face)
		var s: Dictionary = Combat.stats(e)
		var h0 := float(t.hp)
		Damage.apply_hit(w, e, t, s, true)
		dmg[face] = h0 - float(t.hp) if w.entities.has(int(t.id)) else h0
	print("ACC8B mbt->mbt one hit @4: front %.1f side %.1f rear %.1f" % [dmg.front, dmg.side, dmg.rear])
	check(float(dmg.rear) > float(dmg.front) and float(dmg.side) > float(dmg.front), "flank / rear hits hurt more than frontal ones")


## A soldier near a blast who is not knocked out is dazed (e.b8d), aims worse, reacts slower, and it clears.
func test_blast_daze() -> void:
	var p := _pair("rifleman", "rifleman", 4.0, 2024)
	var w: SimWorld = p[0]
	var e: Dictionary = p[1]
	var t: Dictionary = p[2]
	_aimed(w, e, t)
	var a_before := _acc(w, e, t)
	var bp := Vector2(e.pos) + Vector2(0.0, 3.0)   # a mortar round 3 tiles (12 m) away: beyond concussion, inside daze
	var ds := Blast8.daze_sev(0.9, 12.0, 1.0)
	check(ds > 0.0 and Blast8.conc_sev(0.9, 12.0, 1.0) == 0.0, "12 m from a mortar: dazed, not knocked out (sev %.2f)" % ds)
	Blast8.on_burst(w, bp, {"charge_kg": 0.9}, [int(e.id)], {})
	check(int(e.get("b8d", -1)) > w.tick, "dazed: e.b8d set (%d ticks)" % (int(e.get("b8d", -1)) - w.tick))
	check(not bool(e.get("wunc", false)), "not knocked out")
	check_eq(_count(w, "Dazed"), 1, "Dazed event")
	_aimed(w, e, t)
	var a_dazed := _acc(w, e, t)
	print("ACC8B daze: until +%d ticks, hit chance %.3f -> %.3f" % [int(e.get("b8d", 0)) - w.tick, a_before, a_dazed])
	check(a_dazed < a_before * 0.7, "dazed aim is worse (%.3f vs %.3f)" % [a_dazed, a_before])
	check(A8.daze_cd(w, e, t, 20) > 20, "dazed: slower weapon cycle")
	check(A8.daze_cd(w, e, {"id": 999999}, 20) > A8.daze_cd(w, e, t, 20), "dazed: switching targets costs extra")
	# a closer blast dazes longer
	var p2 := _pair("rifleman", "rifleman", 4.0, 2024)
	var w2: SimWorld = p2[0]
	var e2: Dictionary = p2[1]
	Blast8.on_burst(w2, Vector2(e2.pos) + Vector2(0.0, 2.6), {"charge_kg": 0.9}, [int(e2.id)], {})
	check(int(e2.get("b8d", -1)) > int(e.get("b8d", -1)), "closer blast: longer daze")
	# clears
	w.tick = int(e.get("b8d", 0)) + 1
	Blast8.tick(w)
	check(not e.has("b8d"), "daze cleared after it runs out")
	check(w.sys_state.get("blast8") == null, "blast8 state empty again")
	check_eq(A8.daze_cd(w, e, t, 20), 20, "no reaction delay once clear")


## Fire discipline (ships ON, STRAY8B): a mate right in front of the muzzle = hold fire (no shot); one farther along
## the line does not block.
func test_fire_discipline() -> void:
	var p := _pair("rifleman", "rifleman", 5.0, 6060)
	var w: SimWorld = p[0]
	var e: Dictionary = p[1]
	var t: Dictionary = p[2]
	var s: Dictionary = Combat.stats(e)
	check(float(Stray8.cfg().discipline.clear_tiles) > 0.0, "fire discipline ships on")
	check(not Stray8.cfg().has("friend_clear_tiles"), "no immunity zone (friend_clear_tiles removed)")
	e.order = {"type": "move", "target": Vector2(20.5, 10.5)}   # no sidestep / retarget: this test checks the hold alone
	var fid := w.spawn_unit("rifleman", 0, Vector2(21.5, 10.6))
	e.cd_ticks = 0
	w.events.clear()
	Combat._fire(w, e, s, t, true)
	check_eq(_count(w, "ShotFired"), 0, "mate 1 tile in front of the muzzle: holds fire")
	check(int(e.cd_ticks) > 0, "holds for hold_s")
	w.entities[fid].pos = Vector2(24.0, 10.6)
	e.cd_ticks = 0
	w.tick += 40
	w.events.clear()
	Combat._fire(w, e, s, t, true)
	check_eq(_count(w, "ShotFired"), 1, "mate 3.5 tiles out: fires (strays can still hit him)")
	# fire over: the mate in front kneels to fire (standing still with a target) -> the rear man fires over him
	w.entities[fid].pos = Vector2(21.5, 10.6)
	w.entities[fid].target = int(t.id)
	w.entities[fid].moving = false
	e.cd_ticks = 0
	w.tick += 40
	w.events.clear()
	Combat._fire(w, e, s, t, true)
	check_eq(_count(w, "ShotFired"), 1 if bool(Stray8.cfg().discipline.get("over_prone", false)) else 0, "mate kneeling to fire 1 tile in front: the rear man fires over him")
	check(Stray8.low(w.entities[fid]), "a still foot soldier with a target counts as kneeling")


## A real-loop scene: shooter with a mate 1 tile in front of him on the line to an enemy 5 tiles out that never fires
## back. Returns [w, shooter id, mate id, target id].
func _blocked_scene(seed_v: int, order_type: String = "idle", stance: String = "") -> Array:
	var w := _world(seed_v)
	w.tick = 1000
	var sid := w.spawn_unit("rifleman", 0, Vector2(20.5, 10.5))
	var mid := w.spawn_unit("rifleman", 0, Vector2(21.5, 10.5))
	var tid := w.spawn_unit("rifleman", 1, Vector2(25.5, 10.5))
	var e: Dictionary = w.entities[sid]
	e.order = {"type": order_type}
	if stance != "":
		e.stance = stance
	w.entities[mid].order = {"type": "hold"}
	return [w, sid, mid, tid]


## Steps the scene n ticks (everyone unkillable and unpinned, the enemy never shoots). Returns [shots by the shooter,
## first shot tick (or -1), max lateral offset of the shooter, distinct move starts].
func _run_scene(sc: Array, n: int, extra: Array = []) -> Array:
	var w: SimWorld = sc[0]
	var sid := int(sc[1])
	var shots := 0
	var first := -1
	var lat := 0.0
	var starts := 0
	var was := false
	var t0 := w.tick
	var dsc: Dictionary = Stray8.cfg().discipline
	var keep_ovp = dsc.get("over_prone", false)
	dsc.over_prone = false   # the mates here stand (the fire-over rule is checked in test_fire_discipline)
	for i in n:
		for id in [int(sc[1]), int(sc[2]), int(sc[3])] + extra:
			var u = w.entities.get(id)
			if u != null:
				u.hp = 1.0e6
				u.erase("pinned")
				u.supp = 0.0
				if u.has("ammo"):
					u.ammo = 100
				for k in ["wunc", "wounded", "wz", "broken"]:
					u.erase(k)
				if id != sid:
					u.cd_ticks = 999   # only the shooter under test fires
		if not w.entities.has(int(sc[3])):   # a lucky head shot kills even an unkillable man: a fresh enemy, same spot
			sc[3] = w.spawn_unit("rifleman", 1, Vector2(25.5, 10.5))
		w.step()
		var e = w.entities.get(sid)
		if e == null:
			break
		lat = maxf(lat, absf(float(e.pos.y) - 10.5))
		if bool(e.moving) and not was:
			starts += 1
		was = bool(e.moving)
		for ev in w.events:
			if String(ev.type) == "ShotFired" and int(ev.get("shooter", -1)) == sid:
				shots += 1
				if first < 0:
					first = w.tick - t0
	dsc.over_prone = keep_ovp
	return [shots, first, lat, starts]


## Discipline + reposition: the blocked man holds, sidesteps 0.5-1.5 tiles off the line, then fires.
func test_sidestep_then_fires() -> void:
	var sc := _blocked_scene(7171)
	var w: SimWorld = sc[0]
	var e: Dictionary = w.entities[int(sc[1])]
	var x0 := float(e.pos.x)
	var r := _run_scene(sc, 120)
	print("ACC8B sidestep: shots %d first at tick %d lateral %.2f moves %d pos %s" % [r[0], r[1], r[2], r[3], str(e.pos)])
	check(int(r[0]) > 0, "the blocked man fires after the sidestep (%d shots)" % int(r[0]))
	check(int(r[1]) > 2, "he held fire first (first shot at tick %d)" % int(r[1]))
	check(float(r[2]) >= 0.45 and float(r[2]) <= 1.6, "lateral sidestep 0.5-1.5 tiles (%.2f)" % float(r[2]))
	check(absf(float(e.pos.x) - x0) < 0.6, "the step is lateral, not an advance (dx %.2f)" % (float(e.pos.x) - x0))
	check(e.has("ss8"), "sidestep state on the entity (saved)")
	var sc2 := _blocked_scene(7171)
	var r2 := _run_scene(sc2, 120)
	check_eq(r2, r, "same seed: same sidestep and shots")
	check_eq((sc2[0] as SimWorld).state_hash(), w.state_hash(), "same seed: same hash")


## Player control first: a man on a Hold order or Hold Position stance never moves; he just holds fire.
func test_hold_order_does_not_sidestep() -> void:
	for v in [["hold", ""], ["idle", "hold_position"]]:
		var sc := _blocked_scene(7272, String(v[0]), String(v[1]))
		var w: SimWorld = sc[0]
		var e: Dictionary = w.entities[int(sc[1])]
		var p0: Vector2 = e.pos
		var r := _run_scene(sc, 200)
		check(Vector2(e.pos).distance_to(p0) < 0.05, "%s/%s: does not move (moved %.2f)" % [v[0], v[1], Vector2(e.pos).distance_to(p0)])
		check_eq(int(r[0]), 0, "%s/%s: holds fire (mate in front of the muzzle)" % [v[0], v[1]])


## No jitter: 30 s in the blocked scene = one sidestep, then he stays and fires; boxed in with no clear spot = never
## moves (holds fire).
func test_sidestep_no_jitter() -> void:
	var sc := _blocked_scene(7373)
	var r := _run_scene(sc, 600)
	print("ACC8B jitter 30 s: shots %d moves %d" % [r[0], r[3]])
	check(int(r[3]) <= 1, "one sidestep in 30 s (%d moves)" % int(r[3]))
	check(int(r[0]) > 10, "keeps firing from the new spot (%d shots; target alive %s)" % [int(r[0]), str((sc[0] as SimWorld).entities.has(int(sc[3])))])
	var sc2 := _blocked_scene(7474)
	var w: SimWorld = sc2[0]
	var mates := []
	for dy in [-2.0, -1.5, -1.0, -0.7, 0.7, 1.0, 1.5, 2.0]:
		for dx in [0.0, 0.75, 1.5]:
			mates.append(w.spawn_unit("rifleman", 0, Vector2(20.5 + dx, 10.5 + dy)))
	for dx in [0.75, 1.5]:
		mates.append(w.spawn_unit("rifleman", 0, Vector2(20.5 + dx, 10.5)))
	for m in mates:
		w.entities[m].order = {"type": "hold"}
	var e: Dictionary = w.entities[int(sc2[1])]
	var p0: Vector2 = e.pos
	var n0 := Stray8.n_steps
	var r2 := _run_scene(sc2, 600, mates)
	print("ACC8B boxed in 30 s: shots %d moves %d moved %.2f" % [r2[0], r2[3], Vector2(e.pos).distance_to(p0)])
	check(int(r2[3]) <= 2, "boxed in 30 s: no jitter, at most 2 move starts (%d; moved %.2f, pos %s)" % [int(r2[3]), Vector2(e.pos).distance_to(p0), str(e.pos)])
	check(Stray8.n_steps - n0 <= 1, "boxed in: at most one sidestep while the crowd settles (%d)" % (Stray8.n_steps - n0))
	check(int(r2[0]) <= 2, "boxed in: holds fire (%d shots)" % int(r2[0]))


## No immunity zone: a mate on the line 2 tiles out (inside the old 3-tile clearance) can be hit by a stray.
func test_friend_down_the_line_hittable() -> void:
	var p := _pair("rifleman", "rifleman", 5.0, 8181)
	var w: SimWorld = p[0]
	var e: Dictionary = p[1]
	var t: Dictionary = p[2]
	var s: Dictionary = Combat.stats(e)
	var fid := w.spawn_unit("rifleman", 0, Vector2(22.5, 10.5))
	var ff := 0
	for i in 100:
		if not w.entities.has(fid) or bool(w.entities[fid].get("wunc", false)) or bool(w.entities[fid].get("wounded", false)):
			if w.entities.has(fid):
				w.destroy(fid, "test")
			fid = w.spawn_unit("rifleman", 0, Vector2(22.5, 10.5))
		w.entities[fid].hp = 1.0e6
		w.events.clear()
		Stray8.on_miss(w, e, s, t, Vector2(e.pos), Vector2(t.pos) + Vector2(0.0, (float(i % 11) - 5.0) * 0.03))
		ff += _count(w, "FriendlyFire")
	print("ACC8B mate 2 tiles down the line: friendly fire %d of 100 misses" % ff)
	check(ff > 10, "a mate 2 tiles down the line is hittable by strays (%d of 100)" % ff)


## HUD: "Friendly fire!" alert on our FriendlyFire event, at most one per 8 s; none for another side's.
func test_hud_friendly_fire_alert_throttle() -> void:
	var w := _world(9292)
	var src := GDScript.new()
	src.source_code = "extends Node\nvar world = null\nvar player_fid := 0\n"
	src.reload()
	var mvn: Node = src.new()
	mvn.world = w
	var hud = load("res://presentation/hud/hud.gd").new()
	hud.mv = mvn
	for i in 400:   # 20 s, an FF event on us and on side 1 every tick
		w.tick += 1
		hud._on_events([{"type": "FriendlyFire", "shooter": 1, "target": 2, "owner": 0, "at": Vector2(5, 5)},
			{"type": "FriendlyFire", "shooter": 3, "target": 4, "owner": 1, "at": Vector2(5, 5)}])
	var n := 0
	for a in hud._alerts:
		if String(a.text) == "Friendly fire!":
			n += 1
	check_eq(n, 3, "20 s of friendly fire on us: 3 alerts (one per 8 s), none for the other side")
	hud.free()
	mvn.free()
