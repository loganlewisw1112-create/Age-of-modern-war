extends "res://tests/test_base.gd"
## G6 MECH6c (CONTRACTS_G6 section 9, section 17): call-ins. JTAC designation (accuracy x1.25 for friendly
## artillery, strike delay x0.7), the aerostat (+12 sight deployed, packs when moved), the Drone Control Center
## (+1 charge cap, x1.5 drone range for friendly drone teams in range, via AIRDEF6's g5_mech hook), and the
## AWACS air-picture share (a side with an airborne AWACS shares its radar picture with its team).

const Callins = preload("res://sim/systems/callins.gd")
const G6Hooks = preload("res://sim/systems/g6_hooks.gd")
const G5Mech = preload("res://sim/systems/g5_mech.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Fog = preload("res://sim/systems/fog.gd")


## Inert world with a 30x30 GRASS arena in the map centre; returns [w, origin].
func _setup() -> Array:
	var w := make_world()
	w.ai_state = {}
	var mw := int(w.map.w)
	var o := Vector2i(mw / 2 - 15, int(w.map.h) / 2 - 15)
	var r := Rect2i(o, Vector2i(30, 30))
	var t: PackedByteArray = w.map.terrain
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if e.kind != "unit" and e.kind != "building" and r.grow(2).has_point(w.cell_of(e.pos)):
			w.entities.erase(id)
	Movement.rebuild_nav(w)
	return [w, o]


func _c(o: Vector2i, x: int, y: int) -> Vector2:
	return Vector2(o) + Vector2(x, y) + Vector2(0.5, 0.5)


func _steps(w: SimWorld, n: int) -> void:
	for i in n:
		w.step()


func test_designate_raises_accuracy_and_cuts_delay() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var jtac := w.spawn_unit("a_jtac", 0, _c(o, 5, 5))
	var arty := w.spawn_unit("a_mortar", 0, _c(o, 3, 8))
	var tgt := w.spawn_unit("a_apc", 1, _c(o, 14, 5))
	var other := w.spawn_unit("a_apc", 1, _c(o, 14, 9))
	var far := w.spawn_unit("a_apc", 1, _c(o, 5, 27))   # 22 tiles: beyond designator range 14
	_steps(w, 12)   # fog sees the targets
	check(not Callins.is_designated(w, tgt), "nothing designated at start")
	check_eq(Callins.designated_mult(w, w.entities[arty], w.entities[tgt]), 1.0, "neutral before any designation")
	check(not w.sys_state.has("callins"), "no callins state before the first call-in command")
	var cmd := {"type": "designate", "unit_id": far, "target_id": tgt, "issuer": 0}
	check(Callins.validate_command(w, cmd) != "", "only a JTAC can designate")
	cmd = {"type": "designate", "unit_id": jtac, "target_id": far, "issuer": 0}
	w.entities[far].pos = _c(o, 5, 27)
	check(Callins.validate_command(w, cmd) != "", "a target beyond designator range is refused")
	var ev := do_cmd(w, 0, {"type": "designate", "unit_id": jtac, "target_id": tgt})
	check(rejected_reason(ev) == "", "designate accepted: %s" % rejected_reason(ev))
	check(Callins.is_designated(w, tgt), "target designated")
	var a: Dictionary = w.entities[arty]
	check(is_equal_approx(Callins.designated_mult(w, a, w.entities[tgt]), 1.25), "friendly artillery x1.25 on the designated target")
	check_eq(Callins.designated_mult(w, a, w.entities[other]), 1.0, "undesignated target stays x1.0")
	check_eq(Callins.designated_mult(w, w.entities[jtac], w.entities[tgt]), 1.0, "direct-fire rifle gets no bonus")
	var m1 := G6Hooks.accuracy_mult(w, a, {}, w.entities[tgt])
	var m0 := G6Hooks.accuracy_mult(w, a, {}, w.entities[other])
	check(is_equal_approx(m1 / m0, 1.25), "G6Hooks.accuracy_mult carries the x1.25 (%s / %s)" % [m1, m0])
	check(is_equal_approx(Callins.strike_delay_mult(w, 0, tgt, w.entities[tgt].pos), 0.7), "strike delay x0.7 on the designated target")
	check_eq(Callins.strike_delay_mult(w, 1, tgt, w.entities[tgt].pos), 1.0, "the enemy side gets no designation benefit")
	check_eq(Callins.strike_delay_mult(w, 0, other, w.entities[other].pos), 1.0, "undesignated strike delay x1.0")
	# a cell designation replaces the JTAC's target mark (one designation per JTAC)
	ev = do_cmd(w, 0, {"type": "designate", "unit_id": jtac, "cell": [o.x + 12, o.y + 12]})
	check(rejected_reason(ev) == "", "cell designate accepted: %s" % rejected_reason(ev))
	check(not Callins.is_designated(w, tgt), "the old target mark is replaced")
	check(is_equal_approx(Callins.strike_delay_mult(w, 0, -1, _c(o, 13, 12)), 0.7), "strike near the designated cell x0.7")
	check_eq(Callins.strike_delay_mult(w, 0, -1, _c(o, 20, 20)), 1.0, "strike far from the cell x1.0")
	# designation ends when the JTAC dies
	do_cmd(w, 0, {"type": "designate", "unit_id": jtac, "target_id": tgt})
	check(Callins.is_designated(w, tgt), "re-designated")
	w.destroy(jtac, "test")
	_steps(w, 12)
	check(not Callins.is_designated(w, tgt), "designation ends when the JTAC dies")
	check_eq(Callins.designated_mult(w, a, w.entities[tgt]), 1.0, "bonus gone with the designation")


func test_aerostat_adds_sight() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var id := w.spawn_unit("a_aerostat", 0, _c(o, 3, 15))
	var spot := _c(o, 19, 15)   # 16 tiles: beyond sight 10, inside 10 + 12
	_steps(w, 25)
	var e: Dictionary = w.entities[id]
	var base := G6Hooks.sight_bonus(w, e)
	check_eq(Callins.sight_bonus(w, e), 0.0, "no bonus while packed")
	check(not w.is_visible(0, spot), "16 tiles away is dark before deploying")
	var ev := do_cmd(w, 0, {"type": "aerostat", "unit_id": id, "on": true})
	check(rejected_reason(ev) == "", "aerostat deploy accepted: %s" % rejected_reason(ev))
	check_eq(String(e.get("aerostat", "")), "rising", "rising during setup")
	check((w.sys_state.callins.aerostats as Dictionary).is_empty(), "not deployed during setup (mask key stays empty)")
	_steps(w, 6 * 20 + 2)
	check(w.sys_state.callins.aerostats.has(id), "deployed after setup_s")
	check_eq(String(e.get("aerostat", "")), "up", "render hint up")
	check(is_equal_approx(Callins.sight_bonus(w, e), 12.0), "+12 sight deployed")
	check(is_equal_approx(G6Hooks.sight_bonus(w, e) - base, 12.0), "G6Hooks.sight_bonus carries +12")
	check((G6Hooks.active(w) & G6Hooks.G6_SIGHT) != 0, "SIGHT hook bit set while an aerostat is deployed")
	_steps(w, 25)
	check(w.is_visible(0, spot), "the deployed aerostat reveals 16 tiles away")
	check(Callins.validate_command(w, {"type": "aerostat", "unit_id": w.spawn_unit("a_jtac", 0, _c(o, 4, 4)), "on": true, "issuer": 0}) != "", "only an aerostat deploys")
	# moving packs it (tethered)
	Movement.order_path(w, e, _c(o, 8, 15))
	e.order = {"type": "move", "target": _c(o, 8, 15)}
	_steps(w, 3)
	check(not w.sys_state.callins.aerostats.has(id), "moving packs the aerostat")
	check(not e.has("aerostat"), "render hint cleared")
	check_eq(Callins.sight_bonus(w, e), 0.0, "bonus gone once packed")


func test_drone_cc_boosts_drone_teams() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var near := w.spawn_unit("a_drone_team", 0, _c(o, 14, 10))
	var far := w.spawn_unit("a_drone_team", 0, _c(o, 28, 28))
	var foe := w.spawn_unit("b_drone_team", 1, _c(o, 12, 12))
	var en: Dictionary = w.entities[near]
	var ef: Dictionary = w.entities[far]
	var base_cap := int(Content.unit("a_drone_team").get("drone_charges", 4))
	check_eq(Callins.drone_cap_bonus(w, en), 0, "no CC: no cap bonus")
	check_eq(Callins.drone_range_mult(w, en), 1.0, "no CC: range x1.0")
	var cc := w.spawn_building("a_drone_cc", 0, Vector2i(o.x + 10, o.y + 10), false)
	w.step()
	check_eq(Callins.drone_cap_bonus(w, en), 0, "an unfinished CC gives nothing")
	w.entities[cc].built = true
	w.step()
	check_eq(Callins.drone_cap_bonus(w, en), 1, "+1 charge cap in range")
	check(is_equal_approx(Callins.drone_range_mult(w, en), 1.5), "x1.5 drone range in range")
	check(is_equal_approx(Callins.drone_restock_mult(w, en), 1.5), "x1.5 restock in range")
	check_eq(Callins.drone_cap_bonus(w, ef), 0, "out of range: no bonus")
	check_eq(Callins.drone_range_mult(w, ef), 1.0, "out of range: x1.0")
	check_eq(Callins.drone_cap_bonus(w, w.entities[foe]), 0, "enemy drone teams get nothing")
	check_eq(Callins.drone_cap_bonus(w, w.entities[w.spawn_unit("a_jtac", 0, _c(o, 12, 11))]), 0, "only drone teams")
	# AIRDEF6's g5_mech hook reads it (charge cap, launch range and the launch_drone range check)
	check_eq(G5Mech.charge_cap(w, en), base_cap + 1, "G5Mech charge cap = def + 1 near the CC")
	check_eq(G5Mech.charge_cap(w, ef), base_cap, "G5Mech charge cap = def far from the CC")
	check(is_equal_approx(G5Mech.launch_range(w, en), G5Mech.LAUNCH_RANGE * 1.5), "G5Mech launch range x1.5 near the CC")
	var goal := Vector2i(int(en.pos.x) + 26, int(en.pos.y))   # 26 tiles: beyond 20, inside 30
	var r_near := G5Mech.validate_command(w, {"type": "launch_drone", "issuer": 0, "unit_id": near, "drone": "recon", "cell": [goal.x, goal.y]})
	var gf := Vector2i(int(ef.pos.x) - 26, int(ef.pos.y))
	var r_far := G5Mech.validate_command(w, {"type": "launch_drone", "issuer": 0, "unit_id": far, "drone": "recon", "cell": [gf.x, gf.y]})
	check(r_near != "Target out of drone range.", "a 26-tile launch is in range near the CC (%s)" % r_near)
	check_eq(r_far, "Target out of drone range.", "the same launch is out of range far from the CC")


func test_awacs_shares_air_picture() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	var awacs := w.spawn_unit("a_awacs", 0, _c(o, 5, 5))
	var near := w.spawn_unit("b_recon_plane", 1, _c(o, 15, 5))   # 10 tiles from the AWACS
	var radar := w.spawn_building("a_radar_station", 0, Vector2i(o.x + 40, o.y + 4), true)
	var far := w.spawn_unit("b_recon_plane", 1, _c(o, 44, 8))    # ~39 from the AWACS, ~4 from the radar
	check(radar >= 0, "radar station placed")
	_steps(w, 21)
	var tm := int(w.factions[0].get("team", 0))
	var pic: Array = Callins._airdef().air_picture(w, 0)
	check(pic.has(near), "the AWACS sees the near aircraft (air picture %s)" % [pic])
	var en: Dictionary = w.entities[near]
	check(int(en.get("marked_team", -999)) == tm and int(en.get("marked_until", 0)) > w.tick, "near aircraft marked for the AWACS team")
	check(Fog.entity_visible(w, 0, en), "near aircraft visible to the AWACS side")
	check(pic.has(far), "the radar station covers the far aircraft (air picture %s)" % [pic])
	var ef: Dictionary = w.entities[far]
	check(int(ef.get("marked_team", -999)) == tm and int(ef.get("marked_until", 0)) > w.tick, "far radar contact shared with the team while the AWACS is up")
	check(Fog.entity_visible(w, 0, ef), "far radar contact visible through the AWACS share")
	# no airborne AWACS: the radar picture stays a picture, the share lapses
	w.destroy(awacs, "test")
	_steps(w, 40)
	if w.entities.has(far):
		ef = w.entities[far]
		check(int(ef.get("marked_until", 0)) <= w.tick, "the share lapses without an airborne AWACS")
