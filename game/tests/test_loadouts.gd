extends "res://tests/test_base.gd"
## G6 acceptance (owner: EXO6). CONTRACTS_G6 sections 3.4, 5.1, 14, 17: set_loadout near a barracks /
## Company HQ for a cost, stat changes through Loadouts + G6Hooks, the exo tier at Stage 10 (art_def),
## the Human B and Machine sets, e.def never changes, and the nonstandard counter (PERF6 SPEED mask key).

const Movement = preload("res://sim/systems/movement.gd")
const Loadouts = preload("res://sim/systems/loadouts.gd")
const G6Hooks = preload("res://sim/systems/g6_hooks.gd")
const Damage = preload("res://sim/systems/damage.gd")
const Combat = preload("res://sim/systems/combat.gd")
const SaveSystem = preload("res://sim/save_system.gd")


# ---------------------------------------------------------------- helpers
## The side's HQ (Machine's HQ has its own def: fall back to its first building).
func _hq(w: SimWorld, fid: int = 0) -> Dictionary:
	var l := w.buildings_of(fid, "hq")
	if l.is_empty():
		l = w.buildings_of(fid)
	check(not l.is_empty(), "side %d has a building" % fid)
	return l[0] if not l.is_empty() else {"cell": Vector2i(10, 10), "pos": Vector2(10, 10)}


func _at(w: SimWorld, def: String, fid: int, p: Vector2) -> Dictionary:
	var mc := String(Content.unit(def).get("move_class", "foot"))
	var c := Movement.nearest_free_cell(w, w.cell_of(p), mc)
	return w.entities[w.spawn_unit(def, fid, Vector2(c) + Vector2(0.5, 0.5))]


func _spawn(w: SimWorld, def: String, fid: int, off: Vector2) -> Dictionary:
	return _at(w, def, fid, Vector2(_hq(w, fid).pos) + off)


## A built building of def for fid on the first free size x size block found around near.
func _place(w: SimWorld, def: String, fid: int, near: Vector2i) -> Dictionary:
	var size := int(Content.building(def).get("size", 2))
	for r in range(0, 30):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var o := near + Vector2i(dx, dy)
				var ok := true
				for yy in range(-1, size + 1):
					for xx in range(-1, size + 1):
						if not Movement.is_passable(w, o + Vector2i(xx, yy), "vehicle"):
							ok = false
				if ok:
					return w.entities[w.spawn_building(def, fid, o, true)]
	return {}


## A unit right beside building b (inside the loadout range).
func _beside(w: SimWorld, def: String, fid: int, b: Dictionary) -> Dictionary:
	var c := Vector2(b.cell) + Vector2(float(b.size), float(b.size)) * 0.5
	return _at(w, def, fid, c + Vector2(float(b.size) * 0.5 + 1.0, 0.0))


func _rich(w: SimWorld, fid: int) -> void:
	w.factions[fid].credits = 20000
	for k in ["salvage", "ore", "fuel", "ammo"]:
		w.factions[fid].stock[k] = 5000


func _lo(w: SimWorld, fid: int, ids: Array, loadout: String, bid: int) -> String:
	var ev := do_cmd(w, fid, {"type": "set_loadout", "unit_ids": ids, "loadout": loadout, "building_id": bid})
	return rejected_reason(ev)


func _preview(w: SimWorld, fid: int, ids: Array, loadout: String, bid: int) -> String:
	return w.preview_command({"type": "set_loadout", "issuer": fid, "unit_ids": ids, "loadout": loadout,
		"building_id": bid})


func _cost(id: String, k: String) -> int:
	return int(Loadouts.cost_of(id).get(k, 0))


func _research(w: SimWorld, fid: int, ids: Array) -> void:
	for rid in ids:
		if not (w.factions[fid].research.done as Array).has(rid):
			w.factions[fid].research.done.append(rid)
	w.cache.erase("exo_fx")


# ---------------------------------------------------------------- tests
func test_set_loadout_near_barracks_costs() -> void:
	var w := make_world()
	_rich(w, 0)
	var hq := _hq(w)
	var bar := _place(w, "barracks", 0, Vector2i(hq.cell) + Vector2i(-9, 7))
	check(not bar.is_empty(), "barracks placed")
	var a := _beside(w, "rifleman", 0, bar)
	var b := _beside(w, "rifleman", 0, bar)
	var far := _at(w, "rifleman", 0, Vector2(bar.cell) + Vector2(24, -14))
	w.step()
	check(Loadouts.footprint_dist(bar, far.pos) > float(Loadouts.cfg().loadout_range), "far unit is out of range")
	var c0 := int(w.factions[0].credits)
	var o0 := int(w.factions[0].stock.get("ore", 0))
	check_eq(_lo(w, 0, [int(a.id), int(b.id)], "at", int(bar.id)), "", "set_loadout at accepted next to the barracks")
	check_eq(Loadouts.of(a), "at", "a re-equipped")
	check_eq(Loadouts.of(b), "at", "b re-equipped")
	check_eq(c0 - int(w.factions[0].credits), 2 * _cost("at", "credits"), "credits charged per squad")
	check_eq(o0 - int(w.factions[0].stock.ore), 2 * _cost("at", "ore"), "ore charged per squad")
	check(_cost("at", "credits") > 0, "the loadout has a cost")
	check_eq(int(w.sys_state.loadouts.nonstandard), 2, "nonstandard counts both squads")
	check(_preview(w, 0, [int(far.id)], "assault", int(bar.id)).contains("next to"), "far squad rejected")
	check(_preview(w, 0, [int(a.id)], "at", int(bar.id)) != "", "already equipped -> nothing to do")
	check(_preview(w, 0, [int(a.id)], "assault", int(hq.id)).contains("barracks"), "the HQ is not a loadout building")
	check(_preview(w, 1, [int(a.id)], "assault", int(bar.id)) != "", "another side cannot use my barracks / squads")
	check(_preview(w, 0, [int(a.id)], "no_such", int(bar.id)) != "", "unknown loadout rejected")
	var chq := _place(w, "a_company_hq", 0, Vector2i(hq.cell) + Vector2i(10, -8))
	check(not chq.is_empty(), "company HQ placed")
	var d := _beside(w, "rifleman", 0, chq)
	w.step()
	w.factions[0].credits = 0
	check(_preview(w, 0, [int(d.id)], "assault", int(chq.id)).begins_with("Need"), "unaffordable loadout rejected")
	_rich(w, 0)
	check_eq(_lo(w, 0, [int(d.id)], "assault", int(chq.id)), "", "set_loadout accepted at a Company HQ")
	check_eq(int(w.sys_state.loadouts.nonstandard), 3, "nonstandard 3")
	check_eq(_lo(w, 0, [int(a.id)], "standard", int(bar.id)), "", "revert to standard")
	check(not a.has("loadout"), "standard clears e.loadout")
	check_eq(int(w.sys_state.loadouts.nonstandard), 2, "nonstandard follows the revert")


func test_loadout_changes_stats() -> void:
	var w := make_world()
	var foe := _spawn(w, "mbt", 1, Vector2(-6, 10))
	var std := _spawn(w, "rifleman", 0, Vector2(6, 4))
	var pl := _spawn(w, "rifleman", 0, Vector2(6, 6))
	var at := _spawn(w, "rifleman", 0, Vector2(6, 8))
	var mk := _spawn(w, "rifleman", 0, Vector2(8, 4))
	w.step()
	var s := Combat.stats(foe)
	var own := Combat.stats(std)
	check_eq(Loadouts.armor_mult(w, foe, s, std), 1.0, "standard: neutral damage")
	check_eq(Loadouts.speed_mult(w, std), 1.0, "standard: neutral speed")
	Loadouts.apply(w, pl, "plates")
	Loadouts.apply(w, at, "at")
	Loadouts.apply(w, mk, "marksman")
	var L: Dictionary = Loadouts.cfg().loadouts
	check_eq(int(w.sys_state.loadouts.nonstandard), 3, "nonstandard = 3")
	check(is_equal_approx(Loadouts.armor_mult(w, foe, s, pl), float(L.plates.taken)), "plates: damage taken x0.75")
	check(float(L.plates.taken) < 1.0 and float(L.plates.speed) < 1.0, "plates are armour, and slower")
	check(is_equal_approx(Loadouts.speed_mult(w, pl), float(L.plates.speed)), "plates: speed x0.85")
	var heavy := String(Content.unit("mbt").get("armor", ""))
	check(is_equal_approx(Loadouts.armor_mult(w, at, own, foe), float(L.at.dmg_vs.get(heavy, 1.0))), "AT: more damage vs armour")
	check(float(L.at.dmg_vs.get(heavy, 1.0)) > 1.0, "AT weapon swap hits vehicles harder")
	check(is_equal_approx(Loadouts.armor_mult(w, at, own, std), float(L.at.dmg_vs.infantry)), "AT: less vs infantry")
	check(is_equal_approx(Loadouts.acc_mult(w, mk), float(L.marksman.acc)), "marksman: accuracy x1.3")
	# through the G6Hooks dispatcher (ratios cancel the other owners' factors)
	check(is_equal_approx(G6Hooks.damage_mult(w, foe, s, pl) / G6Hooks.damage_mult(w, foe, s, std), float(L.plates.taken)), "dispatcher damage_mult carries the loadout")
	check(is_equal_approx(G6Hooks.accuracy_mult(w, mk, own, foe) / G6Hooks.accuracy_mult(w, std, own, foe), float(L.marksman.acc)), "dispatcher accuracy_mult carries the loadout")
	check(G6Hooks.active(w) & G6Hooks.G6_SPEED != 0, "SPEED mask bit set while nonstandard > 0")
	check(is_equal_approx(G6Hooks.speed_mult_ex(w, pl) / G6Hooks.speed_mult_ex(w, std), float(L.plates.speed)), "dispatcher speed_mult_ex carries the loadout")
	for e in [pl, at, mk]:
		Loadouts.apply(w, e, "standard")
	check_eq(int(w.sys_state.loadouts.nonstandard), 0, "nonstandard back to 0")
	if not w.map.has("height"):
		check(G6Hooks.active(w) & G6Hooks.G6_SPEED == 0, "SPEED mask bit clear again (flat map, no wire)")
	# EXO6 research effects: armour kits (vehicles take less), exo weapons (exo shooters deal more)
	_research(w, 1, ["g6_armor_kits_1"])
	var kits := float(Content.table("research").g6_armor_kits_1.value)
	check(is_equal_approx(Loadouts.armor_mult(w, std, own, foe), kits), "armour kits: enemy vehicle takes x0.9")
	var foe_inf := _spawn(w, "rifleman", 1, Vector2(-4, 10))
	check_eq(Loadouts.armor_mult(w, std, own, foe_inf), 1.0, "armour kits: infantry unaffected")
	_research(w, 0, ["g6_exo_weapons_1"])
	var suit := _spawn(w, "a_exo_rifle", 0, Vector2(10, 4))
	var xs := Combat.stats(suit)
	var exo := float(Content.table("research").g6_exo_weapons_1.value)
	check(is_equal_approx(Loadouts.armor_mult(w, suit, xs, foe_inf), exo), "exo weapons: suit deals x1.2")
	check_eq(Loadouts.armor_mult(w, std, own, foe_inf), 1.0, "exo weapons: ordinary rifleman unaffected")


func test_exo_tier_stage10_uses_art_def() -> void:
	var w := make_world()
	_rich(w, 0)
	var bar := _place(w, "barracks", 0, Vector2i(_hq(w).cell) + Vector2i(-9, 7))
	var e := _beside(w, "rifleman", 0, bar)
	w.step()
	w.factions[0].stage = 9
	check(_preview(w, 0, [int(e.id)], "exo", int(bar.id)).contains("Stage 10"), "exo needs Stage 10")
	check(_preview(w, 0, [int(e.id)], "plates", int(bar.id)).contains("research"), "plates need g6_infantry_plates_1")
	w.factions[0].stage = 10
	check(_preview(w, 0, [int(e.id)], "exo", int(bar.id)).contains("research"), "exo needs g6_exo_armor_1")
	check_eq(Loadouts.research_for("exo"), "g6_exo_armor_1", "exo unlocked by g6_exo_armor_1")
	check_eq(Loadouts.research_for("plates"), "g6_infantry_plates_1", "plates unlocked by g6_infantry_plates_1")
	check((Content.table("research").g6_exo_armor_1.get("requires_research", []) as Array).has("g6_infantry_plates_1"), "plates -> exo research chain")
	_research(w, 0, ["g6_infantry_plates_1", "g6_exo_armor_1"])
	var c0 := int(w.factions[0].credits)
	check_eq(_lo(w, 0, [int(e.id)], "exo", int(bar.id)), "", "exo accepted at Stage 10 with the research")
	check_eq(Loadouts.of(e), "exo", "exo loadout set")
	check_eq(String(e.get("art_def", "")), "a_exo_trooper", "exo renders with the a_exo_trooper sheet")
	check_eq(String(e.def), "rifleman", "e.def unchanged")
	check_eq(c0 - int(w.factions[0].credits), _cost("exo", "credits"), "exo cost charged")
	check(Loadouts.armor_mult(w, e, Combat.stats(e), _spawn(w, "rifleman", 1, Vector2(-6, 6))) > 1.0, "exo tier hits harder")
	check_eq(_lo(w, 0, [int(e.id)], "plates", int(bar.id)), "", "swap exo -> plates")
	check(not e.has("art_def"), "art_def cleared when leaving the exo tier")
	check_eq(_lo(w, 0, [int(e.id)], "standard", int(bar.id)), "", "revert to standard")
	check(not e.has("loadout") and not e.has("art_def"), "standard: no loadout, no art override")
	check_eq(int(w.sys_state.loadouts.nonstandard), 0, "nonstandard 0")
	check(not Content.production("a_exo_trooper").is_empty(), "a_exo_trooper is also producible directly")


func test_human_b_and_machine_loadout_sets() -> void:
	var sets: Dictionary = Loadouts.cfg().sets
	check_eq(Loadouts.loadouts_for(0, "rifleman"), ["standard", "assault", "at", "marksman", "breacher", "plates", "exo"], "Human A set")
	check_eq(Loadouts.loadouts_for(1, "b_conscripts"), ["standard", "assault", "at", "breacher", "plates"], "Human B set")
	check_eq(Loadouts.loadouts_for(1, "b_conscripts"), sets.human_b, "Human B set from rules")
	check_eq(Loadouts.loadouts_for(2, "m_scout_crawler"), ["mod_armor", "mod_sensor", "mod_weapon"], "Machine crawler module set")
	for d in ["mbt", "a_exo_rifle", "a_exo_trooper", "a_captain", "m_walker", "m_drone"]:
		check_eq(Loadouts.loadouts_for(0, d), [], "%s takes no loadout" % d)
	var side := {"stage": 10, "credits": 20000, "ai": false}
	var sb := side.duplicate()
	sb.merge({"faction": "human_b", "name": "B", "team": 0})
	var sm := side.duplicate()
	sm.merge({"faction": "machine", "name": "M", "team": 1})
	var w := make_world({"sides": [sb, sm]})
	_rich(w, 0)
	_rich(w, 1)
	_research(w, 0, ["g6_infantry_plates_1", "g6_exo_armor_1"])
	check(Loadouts.available(w, 0, "exo") != "", "Human B has no exo tier even with the research")
	check(Loadouts.available(w, 0, "marksman") != "", "Human B has no marksman loadout")
	check_eq(Loadouts.available(w, 0, "plates"), "", "Human B plates with the research")
	check_eq(Loadouts.available(w, 1, "mod_armor"), "", "Machine module available")
	check(Loadouts.available(w, 1, "plates") != "", "Machine has no plates")
	var bar := _place(w, "b_barracks", 0, Vector2i(_hq(w, 0).cell) + Vector2i(-9, 7))
	var cw := _place(w, "m_crawler_works", 1, Vector2i(_hq(w, 1).cell) + Vector2i(8, -7))
	check(not bar.is_empty() and not cw.is_empty(), "b_barracks and m_crawler_works placed")
	var con := _beside(w, "b_conscripts", 0, bar)
	var cr := _beside(w, "m_scout_crawler", 1, cw)
	w.step()
	check_eq(_lo(w, 0, [int(con.id)], "breacher", int(bar.id)), "", "Human B breacher at the barracks")
	check_eq(_lo(w, 1, [int(cr.id)], "mod_armor", int(cw.id)), "", "Machine armour module at the crawler works")
	check(is_equal_approx(Loadouts.armor_mult(w, con, Combat.stats(con), cr), float(Loadouts.cfg().loadouts.mod_armor.taken)), "armour module: crawler takes less damage")
	check(_preview(w, 1, [int(cr.id)], "exo", int(cw.id)) != "", "Machine cannot take exo")
	check_eq(_lo(w, 1, [int(cr.id)], "standard", int(cw.id)), "", "Machine module removed (standard revert)")


func test_def_never_changes() -> void:
	var w := make_world()
	w.factions[0].stage = 10
	_research(w, 0, ["g6_infantry_plates_1", "g6_exo_armor_1"])
	var e := _spawn(w, "rifleman", 0, Vector2(6, 4))
	var k := _spawn(w, "rifleman", 0, Vector2(6, 6))
	var foe := _spawn(w, "mbt", 1, Vector2(-6, 10))
	w.step()
	for l in Loadouts.loadouts_for(0, "rifleman"):
		Loadouts.apply(w, e, String(l))
		check_eq(String(e.def), "rifleman", "def unchanged under %s" % l)
	Loadouts.apply(w, e, "exo")
	Loadouts.apply(w, k, "plates")
	check_eq(int(w.sys_state.loadouts.nonstandard), 2, "nonstandard 2")
	var res: Dictionary = SaveSystem.decode_bytes(SaveSystem.encode_dict(w.to_dict()))
	check(bool(res.ok), "save decodes")
	var w2 := SimWorld.from_dict(res.dict)
	check_eq(w2.state_hash(), w.state_hash(), "hash equal after load")
	var e2: Dictionary = w2.entities[int(e.id)]
	check_eq(String(e2.def), "rifleman", "def after load")
	check_eq(Loadouts.of(e2), "exo", "loadout after load")
	check_eq(String(e2.get("art_def", "")), "a_exo_trooper", "art_def after load")
	check_eq(int(w2.sys_state.loadouts.nonstandard), 2, "nonstandard after load")
	for i in 40:
		w.step()
		w2.step()
	check_eq(w2.state_hash(), w.state_hash(), "same hash 40 ticks after load")
	# removal keeps the counter exact: a Damage kill at once (G6Hooks.on_destroyed), any other removal by Exo.tick
	k.hp = 0.001
	Damage.apply_hit(w, foe, k, Combat.stats(foe), true)
	check(not w.entities.has(int(k.id)), "plated rifleman killed")
	check_eq(int(w.sys_state.loadouts.nonstandard), 1, "Damage kill decrements nonstandard at once")
	w.destroy(int(e.id), "test")
	w.step()
	check_eq(int(w.sys_state.loadouts.nonstandard), 0, "other removals pruned by the next Exo tick")
	check((w.sys_state.loadouts.units as Dictionary).is_empty(), "registry empty")
