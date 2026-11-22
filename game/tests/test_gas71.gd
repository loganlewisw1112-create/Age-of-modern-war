extends "res://tests/test_base.gd"
## G7.1 J10 (owner: CNOPS71): counter-nanite gas + gas masks + filter wear (Done-when 10, gas half). docs/G71_SCOPE.md J10,
## roster Q7 (gas from CN munitions + facility vents; minimal deterministic wind now). sim/systems/gas71.gd.

const Gas71 = preload("res://sim/systems/gas71.gd")
const Movement = preload("res://sim/systems/movement.gd")
const HotState = preload("res://sim/hot_state.gd")
const H := 0   # human side
const M := 1   # machine side
const P := Vector2(40.5, 40.5)


## Human A (fid 0) vs Machine (fid 1), inert; whole map grass, no entities.
func _setup() -> SimWorld:
	var w := make_world({"victory": "endless", "sides": [
		{"faction": "human_a", "stage": 8, "credits": 5000, "ai": false, "name": "H", "team": 0},
		{"faction": "machine", "stage": 8, "credits": 5000, "ai": false, "name": "M", "team": 1}]})
	w.ai_state = {}
	var t: PackedByteArray = w.map.terrain
	t.fill(Terrain.GRASS)
	w.map.terrain = t
	w.map.erase("burnt")
	for id in w.entities.keys():
		w.entities.erase(id)
	w.cache.clear()
	if w.hot != null:
		HotState.sync(w)
	Movement.rebuild_nav(w)
	return w


## Steps the world; ticks Gas71 by hand until world.gd registers it (then the world does it).
func _run(w: SimWorld, n: int) -> void:
	var reg := SimWorld.SYSTEM_ORDER.has(Gas71)
	for i in n:
		w.step()
		if not reg:
			Gas71.tick(w)


func _calm(w: SimWorld, e: Dictionary) -> void:
	e.cd_ticks = 1 << 30
	e.cooldown = 1e9


func _wind(w: SimWorld, a: int, s: int) -> void:
	var g = w.sys_state[Gas71.KEY]
	g.wind = {"a": a, "s": s, "r": 12345}


func test_unused_creates_no_state() -> void:
	var w := _setup()
	var id := w.spawn_unit("rifleman", H, P)
	_run(w, 120)
	check(not w.sys_state.has(Gas71.KEY), "no release: no gas state")
	check(not w.entities[id].has("g71mk"), "no release: no mask field on soldiers")
	check_eq(Gas71.conc_at(w, P), 0.0, "no gas anywhere")


func test_spread_decay_and_wind() -> void:
	var w := _setup()
	Gas71.release(w, P, 1.0, "test")
	_wind(w, 0, 900)   # wind blowing +x, strong
	var c0 := Gas71.conc_at(w, P)
	check(c0 >= 0.8, "fresh cloud at the release point (%.2f)" % c0)
	_run(w, 100)   # 5 s
	var cs := Gas71.cell_of(w, P)
	var cell := float(Gas71.ri("cell"))
	var down := Gas71.conc_at(w, P + Vector2(3.0 * cell, 0))
	var up := Gas71.conc_at(w, P - Vector2(3.0 * cell, 0))
	var side := Gas71.conc_at(w, P + Vector2(0, 3.0 * cell))
	print("  [gas71] after 5 s: centre %.3f down %.3f up %.3f side %.3f cell %s" % [Gas71.conc_at(w, P), down, up, side, str(cs)])
	check(Gas71.conc_at(w, P) < c0, "the cloud thins at its centre")
	check(down > 0.0, "gas spread downwind (%.3f)" % down)
	check(down > up, "wind carries it: downwind %.3f > upwind %.3f" % [down, up])
	check(side > 0.0 or down > 0.0, "it diffuses beyond the release cells")
	_run(w, 20 * 120)   # 2 min
	check(not Gas71.on(w), "the cloud decays away (%d live cells)" % (w.sys_state[Gas71.KEY].c as Dictionary).size())


func test_wind_changes_slowly_and_deterministically() -> void:
	var a := _setup()
	var b := _setup()
	Gas71.release(a, P, 0.1, "test")
	Gas71.release(b, P, 0.1, "test")
	var seen := []
	for i in 6:
		_run(a, 600)
		_run(b, 600)
		var wa = a.sys_state[Gas71.KEY].wind
		var wb = b.sys_state[Gas71.KEY].wind
		check_eq(str(wa), str(wb), "wind identical between runs at step %d" % i)
		seen.append(int(wa.a))
	print("  [gas71] wind headings every 30 s: ", seen)
	for i in range(1, seen.size()):
		var d := absi(posmod(int(seen[i]) - int(seen[i - 1]) + 180, 360) - 180)
		check(d <= 30, "wind turns at most 30 deg per 30 s (%d)" % d)


func test_machine_dies_in_gas() -> void:
	var w := _setup()
	var id := w.spawn_unit("m_walker", M, P)
	_calm(w, w.entities[id])
	var hp0 := float(w.entities[id].hp)
	Gas71.release(w, P, 1.5, "test")
	_wind(w, 0, 150)
	var killed := false
	for i in 20 * 90:
		_run(w, 1)
		for ev in w.events:
			if String(ev.get("type", "")) == "GasKill" and int(ev.get("id", -1)) == id:
				killed = true
		if not w.entities.has(id):
			break
		if Gas71.conc_at(w, Vector2(w.entities[id].pos)) <= 0.0:
			Gas71.release(w, Vector2(w.entities[id].pos), 1.0, "test")   # keep it in the cloud
	check(not w.entities.has(id), "the walker died in the gas (hp was %.0f)" % hp0)
	check(killed, "GasKill event for it")


func test_unmasked_soldier_hurt_masked_soldier_safe() -> void:
	var w := _setup()
	var a := w.spawn_unit("rifleman", H, P)
	var b := w.spawn_unit("rifleman", H, P + Vector2(0.4, 0))
	for id in [a, b]:
		_calm(w, w.entities[id])
	Gas71.release(w, P, 1.0, "test")
	_wind(w, 0, 150)
	w.entities[b].g71mk = {"h": 0, "on": 0, "f": 1000, "t": -1}   # b lost its mask; no source, no bearer
	var hpa := float(w.entities[a].hp)
	var hpb := float(w.entities[b].hp)
	var on_ev := false
	for i in 20 * 6:
		_run(w, 1)
		for ev in w.events:
			if String(ev.get("type", "")) == "GasMask" and int(ev.get("id", -1)) == a and bool(ev.get("on", false)):
				on_ev = true
	var ea: Dictionary = w.entities[a]
	check(Gas71.masked(ea), "a's mask went on when the gas came near")
	check(on_ev, "GasMask on event (the view shows it)")
	check_eq(float(ea.hp), hpa, "masked soldier unhurt")
	check(w.entities.has(b) and float(w.entities[b].hp) < hpb, "unmasked soldier hurt (%.1f -> %.1f)" % [hpb, float(w.entities[b].get("hp", 0.0)) if w.entities.has(b) else 0.0])
	check(Gas71.acc_mult(ea) < 1.0 and Gas71.sight_mult(ea) < 1.0, "masked: a little less accuracy (%.2f) and vision (%.2f)" % [Gas71.acc_mult(ea), Gas71.sight_mult(ea)])
	check_eq(Gas71.acc_mult(w.entities[b]), 1.0, "no mask on: no accuracy cost")
	check(int(ea.g71mk.f) < 1000, "a's filter wore (%d/1000)" % int(ea.g71mk.f))


func test_vehicle_sealed() -> void:
	var w := _setup()
	var t := w.spawn_unit("mbt", H, P)
	_calm(w, w.entities[t])
	var hp := float(w.entities[t].hp)
	Gas71.release(w, P, 1.0, "test")
	_run(w, 20 * 5)
	check_eq(float(w.entities[t].hp), hp, "a tank (crew inside) is not hurt by the gas")
	check(not w.entities[t].has("g71mk"), "vehicles get no mask state")


func test_filter_wears_out_then_fresh_filter_from_source() -> void:
	var w := _setup()
	var a := w.spawn_unit("rifleman", H, P)
	_calm(w, w.entities[a])
	var spent := false
	var hurt_after := false
	var hp_at_spent := -1.0
	for i in 20 * 120:
		if Gas71.conc_at(w, P) < 0.8:
			Gas71.release(w, P, 1.0, "test")   # long exposure: keep the cloud thick
		_run(w, 1)
		for ev in w.events:
			if String(ev.get("type", "")) == "GasFilterSpent" and int(ev.get("id", -1)) == a:
				spent = true
				hp_at_spent = float(w.entities[a].hp)
		if spent and float(w.entities[a].hp) < hp_at_spent - 1.0:
			hurt_after = true
			break
	check(spent, "the filter wore out during long exposure (GasFilterSpent)")
	check(hurt_after, "a spent filter no longer protects")
	var sid := Gas71.add_source(w, P + Vector2(1, 0), "armory", 5, 5)
	var got := false
	for i in 20 * 3:
		_run(w, 1)
		for ev in w.events:
			if String(ev.get("type", "")) == "GasResupply" and int(ev.get("id", -1)) == a:
				got = true
	check(got, "fresh filter fetched from the armory stock within reach")
	check(int(w.entities[a].g71mk.f) > 500, "filter fresh again (%d)" % int(w.entities[a].g71mk.f))
	var S: Dictionary = {}
	for x in w.sys_state[Gas71.KEY].src:
		if int(x.id) == sid:
			S = x
	check_eq(int(S.f), 4, "the source gave one filter")


func test_idle_soldier_walks_to_a_source_for_a_filter() -> void:
	var w := _setup()
	var a := w.spawn_unit("rifleman", H, P)
	_calm(w, w.entities[a])
	Gas71.release(w, P, 1.0, "test")
	Gas71.add_source(w, P + Vector2(12, 0), "crate", 5, 5)
	w.entities[a].g71mk = {"h": 1, "on": 1, "f": 0, "t": w.tick}
	var moved := false
	for i in 20 * 20:
		_run(w, 1)
		if Vector2(w.entities[a].pos).distance_to(P) > 3.0:
			moved = true
		if w.entities.has(a) and int(w.entities[a].g71mk.f) > 500:
			break
	check(moved, "the idle soldier walked off toward the crate")
	check(int(w.entities[a].g71mk.f) > 500, "and came back with a fresh filter (%d)" % int(w.entities[a].g71mk.f))


func test_bearer_hands_out_spare_masks() -> void:
	var w := _setup()
	var a := w.spawn_unit("rifleman", H, P)
	var bb := w.spawn_unit("a_ammo_bearer", H, P + Vector2(2, 0))
	for id in [a, bb]:
		_calm(w, w.entities[id])
	Gas71.release(w, P, 1.0, "test")
	w.entities[a].g71mk = {"h": 0, "on": 0, "f": 1000, "t": -1}
	check_eq(Gas71.spares(w.entities[bb]), Gas71.ri("spares"), "a bearer carries spares (plus his own)")
	_run(w, 20 * 2)
	check_eq(int(w.entities[a].g71mk.h), 1, "the soldier got a spare mask from the bearer")
	check_eq(Gas71.spares(w.entities[bb]), Gas71.ri("spares") - 1, "one spare used")


func test_mask_comes_off_after_the_gas_is_gone() -> void:
	var w := _setup()
	var a := w.spawn_unit("rifleman", H, P)
	_calm(w, w.entities[a])
	Gas71.release(w, P, 0.4, "test")
	_run(w, 20 * 2)
	check(Gas71.masked(w.entities[a]), "mask on near gas")
	(w.sys_state[Gas71.KEY].c as Dictionary).clear()
	_run(w, int(20.0 * (Gas71.rf("off_s") + 2.0)))
	check(not Gas71.masked(w.entities[a]), "mask off %.0f s after the gas is gone" % Gas71.rf("off_s"))


func test_same_hash_two_runs_and_save_load_mid_cloud() -> void:
	var hs := []
	for k in 2:
		var w := _setup()
		w.spawn_unit("rifleman", H, P)
		w.spawn_unit("m_walker", M, P + Vector2(3, 0))
		Gas71.release(w, P, 1.0, "test")
		_run(w, 300)
		hs.append(w.state_hash())
	check_eq(hs[0], hs[1], "two runs, same hash")
	var w := _setup()
	w.spawn_unit("rifleman", H, P)
	Gas71.release(w, P, 1.0, "test")
	_run(w, 150)
	var w2 := SimWorld.from_dict(w.to_dict().duplicate(true))
	_run(w, 200)
	_run(w2, 200)
	check_eq(w2.state_hash(), w.state_hash(), "save / load mid-cloud keeps the same future")


func test_commands_lp_only() -> void:
	var w := _setup()
	var why := w.preview_command({"type": "gas_release", "issuer": H, "pos": [P.x, P.y]})
	check(why != "", "outside Last Protocol gas_release is refused (%s)" % why)
	check_eq(Gas71.validate_command(w, {"type": "gas_release", "issuer": H, "pos": [P.x, P.y]}), "Gas is a Last Protocol weapon.", "Gas71 refuses it off LP")
