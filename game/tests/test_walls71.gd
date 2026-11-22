extends "res://tests/test_base.gd"
## G7.1 BASTION71 acceptance (sim/systems/walls71.gd, sensors71.gd): wall tiers, anti-climb effects, gate defence,
## choke seal + passability, lifts, firing-port exemption, sensors. Walls71 / Sensors71 tick inside w.step()
## (SYSTEM_ORDER, ORCH 2026-11-21): no hand tick.

const W71 = preload("res://sim/systems/walls71.gd")
const S = preload("res://sim/systems/sensors71.gd")
const LP = preload("res://sim/systems/last_protocol.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Damage = preload("res://sim/systems/damage.gd")
const HotState = preload("res://sim/hot_state.gd")
const H := 0
const M := 1


func _setup(lp := true) -> SimWorld:
	var w := make_world({"seed": 7, "victory": "endless", "sides": [
		{"faction": "human_a", "stage": 10, "credits": 50000, "ai": false, "name": "H", "team": 0},
		{"faction": "machine", "stage": 10, "credits": 50000, "ai": false, "name": "M", "team": 1}]})
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
	if lp:
		w.cfg["mode"] = LP.MODE
	return w


func _unit(w: SimWorld, def_id: String, fid: int, pos: Vector2) -> int:
	var id := w.spawn_unit(def_id, fid, pos)
	w.entities[id].order = {"type": "hold"}
	w.entities[id].cd_ticks = 100000
	return id


func _run(w: SimWorld, n: int) -> Array:
	var out := []
	for i in n:
		w.step()
		out.append_array(w.events)
	return out


func _dmg_by(evs: Array, shooter: int, target: int) -> float:
	var d := 0.0
	for ev in evs:
		if String(ev.type) == "Damage" and int(ev.get("shooter", -1)) == shooter and int(ev.get("target", -1)) == target:
			d += float(ev.amount)
	return d


func _count(evs: Array, type: String) -> int:
	var n := 0
	for ev in evs:
		if String(ev.type) == type:
			n += 1
	return n


func test_tiers() -> void:
	var w := _setup()
	var id := w.spawn_building("a_wall", H, Vector2i(20, 20), true)
	var b: Dictionary = w.entities[id]
	var hp0 := float(b.max_hp)
	check_eq(W71.tier(w, b), 0, "starts steel")
	check_eq(W71.upgrade(w, b, 1), "", "composite upgrade ok (LP: all unlocked)")
	check_eq(W71.tier_id(w, b), "composite", "tier id")
	check(absf(float(b.max_hp) - hp0 * 1.6) < 0.1, "composite hp x1.6: %f" % float(b.max_hp))
	check(W71.upgrade(w, b, 1) != "", "no re-upgrade to the same tier")
	check_eq(W71.upgrade(w, b, 2, true), "", "nanite coat ok")
	check(bool(b.get("nres", false)), "nanite-resistant flag set")
	var w2 := _setup(false)
	var id2 := w2.spawn_building("a_wall", H, Vector2i(20, 20), true)
	check_eq(W71.upgrade(w2, w2.entities[id2], 1), "Not researched.", "skirmish: locked until unlock()")
	W71.unlock(w2, H, 1)
	check_eq(W71.upgrade(w2, w2.entities[id2], 1), "", "unlock API opens the tier")


func test_anti_climb_and_gate_defence() -> void:
	var w := _setup()
	var id := w.spawn_building("a_wall", H, Vector2i(20, 20), true)
	check(W71.fit(w, w.entities[id], "electric"), "electrified top fitted")
	var e := _unit(w, "m_scout_crawler", M, Vector2(21.5, 21.8))
	w.entities[e].hp = 100000.0
	# the LP garrison (LpSetup) fights in LP mode too: count only the damage the fitted wall / gate itself deals
	var evs := _run(w, 40)
	check(_dmg_by(evs, id, e) > 0.0, "electric top hurts a crawler at the wall foot")
	var g := w.spawn_building("a_gate", H, Vector2i(30, 20), true)
	check(W71.fit(w, w.entities[g], "murder"), "murder holes fitted")
	check(W71.fit(w, w.entities[g], "popup"), "pop-up gun fitted")
	var f := _unit(w, "m_scout_crawler", M, Vector2(31.5, 21.8))
	w.entities[f].hp = 100000.0
	evs = _run(w, 40)
	check(_dmg_by(evs, g, f) > 0.0, "gate guns hurt an attacker at the gate")
	var hpg := float(w.entities[g].max_hp)
	check(W71.fit(w, w.entities[g], "reinforce"), "gate reinforced")
	check(float(w.entities[g].max_hp) > hpg, "reinforcement adds hp")


func test_choke_seal_and_pathing() -> void:
	var w := _setup()
	var id := w.spawn_building("a_wall", H, Vector2i(20, 20), true)
	W71.fit(w, w.entities[id], "choke")
	var cell := Vector2i(20, 20)
	check(not W71.choke_sealed(w, cell), "open before any enemy")
	_unit(w, "m_scout_crawler", M, Vector2(24.5, 21.0))
	_run(w, 25)
	check(W71.choke_sealed(w, cell), "seals when an enemy closes on the choke")
	check(not W71.passable_for(w, M, cell), "enemies cannot pass the sealed choke")
	check(W71.passable_for(w, H, cell), "own troops always pass (pathing stays valid)")
	var en := _unit(w, "m_scout_crawler", M, Vector2(26.5, 26.5))
	check(not Movement.is_passable_e(w, w.entities[en], cell), "Movement.is_passable_e: enemy cannot enter the sealed choke")
	check(Movement.is_passable_e(w, w.entities[en], Vector2i(26, 26)), "Movement.is_passable_e: open ground stays passable")


func test_lift_and_port() -> void:
	var w := _setup()
	var id := w.spawn_building("a_wall", H, Vector2i(20, 20), true)
	W71.fit(w, w.entities[id], "lift")
	W71.fit(w, w.entities[id], "port")
	check_eq(W71.lift_of(w, Vector2i(21, 22)), id, "lift found next to the wall")
	var u := _unit(w, "rifleman", H, Vector2(21.0, 22.8))
	var cmd := {"type": "lift_use", "issuer": H, "building_id": id, "unit_ids": [u]}
	check_eq(W71.validate_command(w, cmd), "", "lift_use valid")
	W71.apply_command(w, cmd)
	check_eq(_count(_run(w, 70), "LiftArrived"), 1, "the lift carried the rifleman up (LiftArrived)")
	check(W71.port_exempt(w, w.entities[u]), "a rifleman at a fitted port may fire through the wall")
	var far := _unit(w, "rifleman", H, Vector2(40.0, 40.0))
	check(not W71.port_exempt(w, w.entities[far]), "a rifleman far from any port is not exempt")


func test_port_is_a_wallfire_case() -> void:
	var WF = load("res://sim/systems/wallfire7.gd")
	var w := _setup()
	var id := w.spawn_building("a_wall", H, Vector2i(20, 20), true)
	var u := _unit(w, "rifleman", H, Vector2(22.4, 21.0))
	var far := _unit(w, "rifleman", H, Vector2(40.0, 40.0))
	var s := {"indirect": false}
	var any0: bool = WF.any(w)
	check(not WF.shooter_exempt(w, w.entities[u], s), "no port fitted: the WallFire7 rule applies")
	W71.fit(w, w.entities[id], "port")
	check(WF.shooter_exempt(w, w.entities[u], s), "a rifleman at a fitted port is an allowed WallFire7 case")
	check(not WF.shooter_exempt(w, w.entities[far], s), "a rifleman far from the port is not")
	check_eq(WF.any(w), any0, "WallFire7.any (native combat guard) is unchanged by a port")


func test_determinism() -> void:
	var hs := []
	for k in 2:
		var w := _setup()
		var id := w.spawn_building("a_wall", H, Vector2i(20, 20), true)
		W71.upgrade(w, w.entities[id], 1)
		W71.fit(w, w.entities[id], "electric")
		W71.fit(w, w.entities[id], "choke")
		_unit(w, "m_scout_crawler", M, Vector2(21.5, 21.8))
		_run(w, 80)
		hs.append(var_to_str(w.sys_state.get("walls71")).hash())
	check_eq(hs[0], hs[1], "two runs, same walls71 state")


func test_unused_is_stateless() -> void:
	# BASTION71-6: "unused" = off Last Protocol (roster Q1). An LP world now builds the LP starting base at tick 10
	# (LpSetup.build_g71 places the wave-2 defences from content/g71_lp/, ORCH fits ports), so it USES walls71 /
	# turrets71 / sensors71 by design (.plan/bastion71/dbg_stateless.gd); the rule is checked on a skirmish world.
	var w := _setup(false)
	w.spawn_building("a_wall", H, Vector2i(20, 20), true)
	_run(w, 20)
	check(w.sys_state.get("walls71") == null, "no walls71 state without a fit / upgrade")
	check(w.sys_state.get("turrets71") == null and w.sys_state.get("sensors71") == null, "no turret / sensor state")


func test_port_cache_matches_scan() -> void:
	# BASTION71-5: port_exempt answers from a per-tick cell grid; it must equal the plain scan of every fit
	var w := _setup()
	var walls := []
	for k in 6:
		var id := w.spawn_building("a_wall", H, Vector2i(10 + k * 3, 20 + (k % 2)), true)
		walls.append(id)
		if k % 2 == 0:
			W71.fit(w, w.entities[id], "port")
	W71.fit(w, w.entities[walls[1]], "electric")
	var probe := w.spawn_unit("rifleman", H, Vector2(5.5, 15.5))
	var e: Dictionary = w.entities[probe]
	var bad := 0
	var n_true := 0
	for step in 2:
		if step == 1:
			w.entities.erase(walls[2])   # a ported wall gone in the same tick: the cache must not keep it
		for i in 120:
			for j in 40:
				e.pos = Vector2(6.0 + i * 0.25, 16.0 + j * 0.25)
				for fid in [H, M]:
					e.owner = fid
					var want := false
					for id in w.sys_state.walls71.fit:
						var b = w.entities.get(int(id))
						if b != null and W71.has_fit(w, b, "port") and int(b.owner) == fid and Vector2(e.pos).distance_to(Vector2(b.pos)) <= float(b.size) + 1.5:
							want = true
					if W71.port_exempt(w, e) != want:
						bad += 1
					if want:
						n_true += 1
	e.owner = H
	check(n_true > 100, "the probe grid crosses the ports: %d" % n_true)
	check_eq(bad, 0, "cached port_exempt == scan over every probe point")


func test_dozer_clears_wrecks() -> void:
	# BASTION71-7 G2: doze_clear sends own breacher dozers to a spot; they remove the Gore71 bodies / wrecks there
	# (one per rules doze.clear_s), leave the rest, then go idle. Only dozers; Last Protocol only.
	var G = load("res://sim/systems/gore71.gd")
	var w := _setup(true)
	var dz := w.spawn_unit("a_g71_breacher", H, Vector2(20.5, 20.5))
	var eng := w.spawn_unit("a_g71_siege_engineer", H, Vector2(20.5, 22.5))
	G.enable(w)
	var spot := Vector2(30.5, 20.5)
	var b1: int = G.add_body(w, {"kind": "wreck", "def": "m_scout_crawler", "owner": M, "pos": spot, "rot": 0.0, "out": "", "t": 0, "sz": 0.6})
	var b2: int = G.add_body(w, {"kind": "body", "def": "m_scout_crawler", "owner": M, "pos": spot + Vector2(1.0, 0.5), "rot": 0.0, "out": "", "t": 0, "sz": 0.4})
	var far: int = G.add_body(w, {"kind": "wreck", "def": "m_scout_crawler", "owner": M, "pos": spot + Vector2(9.0, 0.0), "rot": 0.0, "out": "", "t": 0, "sz": 0.6})
	w.step()
	check(W71.validate_command(w, {"type": "doze_clear", "issuer": H, "unit_ids": [eng], "at": [spot.x, spot.y]}) != "", "only a dozer clears")
	var cmd := {"type": "doze_clear", "issuer": H, "unit_ids": [dz], "at": [spot.x, spot.y]}
	check_eq(W71.validate_command(w, cmd), "", "doze_clear valid (LP)")
	W71.apply_command(w, cmd)
	var evs := _run(w, 600)
	check_eq(_count(evs, "DozeCleared"), 2, "both bodies at the spot cleared")
	check(not G.bodies(w).has(b1) and not G.bodies(w).has(b2), "the wreck and the body are gone")
	check(G.bodies(w).has(far), "a wreck outside clear_r stays")
	check_eq(_count(evs, "DozeDone"), 1, "the dozer reports done")
	check_eq(String(w.entities[dz].order.get("type", "")), "idle", "then goes idle")
	var w2 := _setup(false)
	var dz2 := w2.spawn_unit("a_g71_breacher", H, Vector2(20.5, 20.5))
	check(W71.validate_command(w2, {"type": "doze_clear", "issuer": H, "unit_ids": [dz2], "at": [25.0, 20.0]}) != "", "off LP: refused")


func test_dozer_builds_berm() -> void:
	# BASTION71-7 G2: berm_build = the dozers push an earth berm line (Fortify build_line of a_g71_berm).
	var w := _setup(true)
	var dz := w.spawn_unit("a_g71_breacher", H, Vector2(20.5, 26.5))
	var eng := w.spawn_unit("a_g71_siege_engineer", H, Vector2(20.5, 28.5))
	w.step()
	var cmd := {"type": "berm_build", "issuer": H, "unit_ids": [dz], "from": [24, 24], "to": [28, 24]}
	check(W71.validate_command(w, {"type": "berm_build", "issuer": H, "unit_ids": [eng], "from": [24, 24], "to": [28, 24]}) != "", "only a dozer builds berms")
	check_eq(W71.validate_command(w, cmd), "", "berm_build valid (LP)")
	W71.apply_command(w, cmd)
	_run(w, 1200)
	var built := 0
	for e in w.entities.values():
		if e.kind == "building" and String(e.def) == "a_g71_berm" and int(e.owner) == H and bool(e.get("built", false)):
			built += 1
	check(built >= 3, "the berm line stands (%d segments)" % built)
	check(W71.validate_command(_setup(false), cmd) != "", "off LP: refused")


func test_nanite_coat_resists_machine_hits() -> void:
	# BASTION71-7 G3: the nanite_coat tier (tier 2) marks the wall nres; Walls71.nres_mult gives the damage factor
	# Damage.apply_hit applies (DAMAGE71 CR): rules walls.nanite_resist_mult vs Machine shooters, 1.0 otherwise.
	var w := _setup()
	var id := w.spawn_building("a_wall", H, Vector2i(20, 20), true)
	var b: Dictionary = w.entities[id]
	var mach := _unit(w, "m_scout_crawler", M, Vector2(24.5, 21.0))
	var ours := _unit(w, "rifleman", H, Vector2(18.5, 21.0))
	check_eq(W71.nres_mult(w, w.entities[mach], b), 1.0, "steel: no resist")
	check_eq(W71.upgrade(w, b, 2), "", "nanite coat upgrade ok (LP)")
	check(b.has("nres"), "nanite coat marks the wall")
	check(absf(W71.nres_mult(w, w.entities[mach], b) - float(W71.R().nanite_resist_mult)) < 0.0001, "Machine hits resisted")
	check_eq(W71.nres_mult(w, w.entities[ours], b), 1.0, "own / human shooters: x1")


func test_nanite_coat_hp_loss() -> void:
	# BASTION71-9 / DAMAGE71 hook (CR seq 3364): the same Machine shooter and the same hit cost a nanite-coated wall
	# 0.6x the hp a plain wall loses; a non-Machine shooter (human) hits both for the same hp.
	var w := _setup()
	var plain := w.spawn_building("a_wall", H, Vector2i(20, 20), true)
	var coated := w.spawn_building("a_wall", H, Vector2i(30, 20), true)
	var cb: Dictionary = w.entities[coated]
	check_eq(W71.upgrade(w, cb, 2), "", "nanite coat upgrade ok (LP)")
	check(cb.has("nres"), "the coated wall carries the flag")
	check(not (w.entities[plain] as Dictionary).has("nres"), "the plain wall does not")
	var mach := _unit(w, "m_scout_crawler", M, Vector2(25.0, 24.0))
	var ours := _unit(w, "rifleman", H, Vector2(25.0, 16.0))
	var s := {"damage": 100.0, "cls": "small_arms", "weapon": ""}
	var hp0p := float(w.entities[plain].hp)
	var hp0c := float(w.entities[coated].hp)
	Damage.apply_hit(w, w.entities[mach], w.entities[plain], s, true)
	Damage.apply_hit(w, w.entities[mach], w.entities[coated], s, true)
	var lp := hp0p - float(w.entities[plain].hp)
	var lc := hp0c - float(w.entities[coated].hp)
	check(lp > 0.0, "the plain wall loses hp to the Machine shooter (%.2f)" % lp)
	check(absf(lc - float(W71.R().nanite_resist_mult) * lp) < 0.06, "coated wall loses 0.6x the plain wall's hp (%.2f vs %.2f)" % [lc, lp])
	var hp1p := float(w.entities[plain].hp)
	var hp1c := float(w.entities[coated].hp)
	Damage.apply_hit(w, w.entities[ours], w.entities[plain], s, true)
	Damage.apply_hit(w, w.entities[ours], w.entities[coated], s, true)
	var hp_p := hp1p - float(w.entities[plain].hp)
	var hp_c := hp1c - float(w.entities[coated].hp)
	check(hp_p > 0.0 and absf(hp_p - hp_c) < 0.0001, "a non-Machine shooter is unaffected by the coat (%.2f vs %.2f)" % [hp_p, hp_c])
