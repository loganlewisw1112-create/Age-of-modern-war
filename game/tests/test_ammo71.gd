extends "res://tests/test_base.gd"
## G7.1 ARMY71 B5 ammo tiers (docs/G71_SCOPE.md B5; roster 5A Q1 LP only, Q5 unlock / upgrade API, research_all):
## tier -> rounds8 round multipliers, unlock / upgrade, stock use + fallback, choice scopes, command, save / load,
## incendiary ignite, skirmish neutral.
const Bench = preload("res://tools/scale_bench.gd")
const Ammo71 = preload("res://sim/systems/ammo71.gd")
const Ballistics8 = preload("res://sim/systems/ballistics8.gd")
const Combat = preload("res://sim/systems/combat.gd")

static var _lp = null


func _lp_world() -> Dictionary:
	if _lp == null:
		var B: Dictionary = Bench.build_lp_peak(0, 0, 7, 1)
		var w: SimWorld = B.w
		var sp := Vector2(w.factions[int(B.hfid)].spawn) + Vector2(0.5, 0.5)
		var rdef := ""
		var ids: Array = w.entities.keys()
		ids.sort()
		for id in ids:
			var e: Dictionary = w.entities[id]
			if e.kind == "unit" and int(e.owner) == int(B.hfid) and e.has("morale") and String(Combat.stats(e).cls) == "small_arms":
				rdef = String(e.def)
				break
		Ammo71.ensure(w)
		_lp = {"w": w, "hfid": int(B.hfid), "mfid": int(B.mfid), "sp": sp, "rdef": rdef}
	return _lp


func test_off_lp_neutral() -> void:
	var w := make_world()
	var id := w.spawn_unit("rifleman", 0, Vector2(30, 30))
	var e: Dictionary = w.entities[id]
	Ammo71.ensure(w)
	check(not w.sys_state.has("ammo71"), "skirmish: ensure() creates nothing")
	check_eq(Ammo71.round_for(w, e, String(Combat.stats(e).weapon)), null, "skirmish: round_for null")
	check_eq(Ammo71.level(w, 0, "ap"), 0, "skirmish: level 0")
	check(not Ammo71.choose(w, "side", 0, "ap"), "skirmish: choose refused")
	Ammo71.on_fire(w, e, Combat.stats(e))
	check(not e.has("r8up") and not e.has("a71"), "skirmish: on_fire touches nothing")
	check(Ammo71.validate_command(w, {"type": "ammo_tier", "issuer": 0, "tier": "ap", "scope": "side"}) != "", "skirmish: command refused")


func test_tier_classes_and_mods() -> void:
	var L := _lp_world()
	var w: SimWorld = L.w
	var id := w.spawn_unit(String(L.rdef), int(L.hfid), Vector2(L.sp) + Vector2(60, 40))
	var e: Dictionary = w.entities[id]
	var wid := String(Combat.stats(e).weapon)
	var tf := Ammo71.tiers_for(wid)
	check(tf.has("ap") and tf.has("incendiary") and not tf.has("heat"), "rifle loads ap / incendiary, not heat: %s" % [tf])
	check(Ammo71.tiers_for("at").has("top_attack") and Ammo71.tiers_for("at").has("heat"), "AT class loads heat + top_attack")
	check(Ammo71.tiers_for("autocannon").has("airburst") and Ammo71.tiers_for("autocannon").has("rail"), "autocannon loads airburst + rail")
	var m1 := Ammo71.mods("ap", 1)
	var m3 := Ammo71.mods("ap", 3)
	check(float(m1.pen) > 1.0 and float(m3.pen) > float(m1.pen), "AP pen > 1 and grows with level (%s -> %s)" % [m1.pen, m3.pen])
	check(bool(Ammo71.mods("heat", 1).get("chem", false)), "HEAT is chemical (velocity-independent pen)")
	# a tier shot: e.r8up carries the multipliers and Ballistics8 builds the upgraded round from it
	check(Ammo71.choose(w, "unit", id, "ap"), "choose unit ap")
	var s0 := Ammo71.stock(w, int(L.hfid), "ap")
	Ammo71.on_fire(w, e, Combat.stats(e))
	check(e.has("r8up") and String(e.r8up.id).begins_with("a71:ap:1"), "r8up set by the ap tier: %s" % [e.get("r8up")])
	check_eq(Ammo71.stock(w, int(L.hfid), "ap"), s0 - 1, "one ap round drawn")
	var r = Ballistics8.round_of(wid)
	if r != null:
		var up = Ballistics8.round_for(r, e)
		check(float(up.pen) > float(r.pen), "ballistics8 round pen raised by the tier (%s -> %s)" % [r.pen, up.pen])
	# a tier the weapon cannot load is ignored; clearing restores the default round
	check(Ammo71.choose(w, "unit", id, "heat"), "choose unit heat")
	Ammo71.on_fire(w, e, Combat.stats(e))
	check(not e.has("r8up") and not e.has("a71"), "rifle cannot load heat: default round, r8up cleared")
	Ammo71.choose(w, "unit", id, "")


func test_unlock_upgrade_stock() -> void:
	var L := _lp_world()
	var w: SimWorld = L.w
	var f := int(L.hfid)
	check_eq(Ammo71.level(w, f, "rail"), 1, "research_all: rail unlocked at level 1")
	check_eq(Ammo71.upgrade(w, f, "rail"), 2, "upgrade -> 2")
	check_eq(Ammo71.upgrade(w, f, "rail"), 3, "upgrade -> 3")
	check_eq(Ammo71.upgrade(w, f, "rail"), 3, "capped at max_level 3")
	check(Ammo71.unlock(w, f, "he") and Ammo71.unlocked(w, f, "he"), "unlock he")
	check(not Ammo71.unlock(w, f, "plasma"), "unknown tier refused")
	var id := w.spawn_unit(String(L.rdef), f, Vector2(L.sp) + Vector2(60, 46))
	var e: Dictionary = w.entities[id]
	Ammo71.choose(w, "unit", id, "incendiary")
	var have := Ammo71.stock(w, f, "incendiary")
	check_eq(Ammo71.draw(w, f, "incendiary", have + 5), have, "draw never goes below 0")
	Ammo71.on_fire(w, e, Combat.stats(e))
	check(not e.has("a71"), "stock 0: falls back to the default round")
	Ammo71.add_stock(w, f, "incendiary", 2)
	Ammo71.on_fire(w, e, Combat.stats(e))
	check(e.has("a71") and Ammo71.stock(w, f, "incendiary") == 1, "add_stock (supply drop) re-arms the tier")
	Ammo71.choose(w, "unit", id, "")


func test_scopes_and_command() -> void:
	var L := _lp_world()
	var w: SimWorld = L.w
	var f := int(L.hfid)
	var a := w.spawn_unit(String(L.rdef), f, Vector2(L.sp) + Vector2(60, 52))
	var b := w.spawn_unit(String(L.rdef), f, Vector2(L.sp) + Vector2(61, 52))
	w.entities[a].squad = 9001
	w.entities[b].squad = 9001
	var wid := String(Combat.stats(w.entities[a]).weapon)
	check_eq(Ammo71.tier_of(w, w.entities[a], wid), "", "nothing chosen: default round")
	var bad := Ammo71.validate_command(w, {"type": "ammo_tier", "issuer": f, "tier": "ap", "scope": "unit", "unit_ids": []})
	check(bad != "", "no units: refused (%s)" % bad)
	check_eq(Ammo71.validate_command(w, {"type": "ammo_tier", "issuer": f, "tier": "ap", "scope": "squad", "unit_ids": [a]}), "", "squad ap valid")
	Ammo71.apply_command(w, {"type": "ammo_tier", "issuer": f, "tier": "ap", "scope": "squad", "unit_ids": [a]})
	check_eq(Ammo71.tier_of(w, w.entities[b], wid), "ap", "squad scope reaches the squad mate")
	Ammo71.apply_command(w, {"type": "ammo_tier", "issuer": f, "tier": "incendiary", "scope": "unit", "unit_ids": [b]})
	check_eq(Ammo71.tier_of(w, w.entities[b], wid), "incendiary", "unit scope beats squad scope")
	check_eq(Ammo71.tier_of(w, w.entities[a], wid), "ap", "the other member keeps the squad tier")
	Ammo71.apply_command(w, {"type": "ammo_tier", "issuer": f, "tier": "", "scope": "squad", "unit_ids": [a]})
	Ammo71.apply_command(w, {"type": "ammo_tier", "issuer": f, "tier": "", "scope": "unit", "unit_ids": [b]})
	Ammo71.apply_command(w, {"type": "ammo_tier", "issuer": f, "tier": "ap", "scope": "side"})
	check_eq(Ammo71.tier_of(w, w.entities[a], wid), "ap", "side default applies when nothing narrower is set")
	Ammo71.apply_command(w, {"type": "ammo_tier", "issuer": f, "tier": "", "scope": "side"})
	check_eq(Ammo71.tier_of(w, w.entities[a], wid), "", "side cleared")
	var mid := w.spawn_unit(String(L.rdef), int(L.mfid), Vector2(L.sp) + Vector2(62, 52))
	check(Ammo71.validate_command(w, {"type": "ammo_tier", "issuer": f, "tier": "ap", "scope": "unit", "unit_ids": [mid]}) != "", "another side's unit: refused")


func test_incendiary_ignites() -> void:
	var L := _lp_world()
	var w: SimWorld = L.w
	var f := int(L.hfid)
	var id := w.spawn_unit(String(L.rdef), f, Vector2(L.sp) + Vector2(60, 58))
	var e: Dictionary = w.entities[id]
	var tid := w.spawn_unit(Bench.unit_def("machine", "infantry"), int(L.mfid), Vector2(L.sp) + Vector2(64, 58))
	var t: Dictionary = w.entities[tid]
	Ammo71.add_stock(w, f, "incendiary", 5)
	Ammo71.choose(w, "unit", id, "incendiary")
	Ammo71.on_fire(w, e, Combat.stats(e))
	check(e.has("a71"), "incendiary loaded")
	Ammo71.on_hit(w, e, t)
	check(Ammo71.Parts71.burning(t), "incendiary hit sets the Machine burning (Parts71.ignite)")
	Ammo71.choose(w, "unit", id, "")


func test_save_load_state() -> void:
	var L := _lp_world()
	var w: SimWorld = L.w
	var f := int(L.hfid)
	Ammo71.upgrade(w, f, "he")
	Ammo71.choose(w, "squad", 4242, "he")
	var st: Dictionary = w.sys_state["ammo71"]
	var back = JSON.parse_string(JSON.stringify(st))
	check(back is Dictionary, "ammo71 state is plain JSON data")
	check_eq(int(back.side[str(f)].lvl.he), Ammo71.level(w, f, "he"), "level survives a JSON round trip")
	check_eq(String(back.sq["4242"]), "he", "squad choice survives a JSON round trip (string keys)")
	Ammo71.choose(w, "squad", 4242, "")


## G2 flame / thermite tank: the new LP def + weapon load; a flame hit with g71_ignite_s sets a Machine burning.
func test_flame_tank_ignites() -> void:
	var u: Dictionary = Content.unit("a_g71_flame_tank")
	check(not u.is_empty() and bool(u.get("lp_only", false)), "a_g71_flame_tank def loaded (LP only)")
	var wd: Dictionary = Content.weapon("g71_heavy_flamer")
	check(String(wd.get("class", "")) == "flame" and float(wd.get("g71_ignite_s", 0.0)) > 0.0, "heavy flamer: flame class with g71_ignite_s")
	var L := _lp_world()
	var w: SimWorld = L.w
	var fid := w.spawn_unit("a_g71_flame_tank", int(L.hfid), Vector2(L.sp) + Vector2(60, 64))
	var tid := w.spawn_unit(Bench.unit_def("machine", "infantry"), int(L.mfid), Vector2(L.sp) + Vector2(63, 64))
	var s := Combat.stats(w.entities[fid])
	check_eq(String(s.cls), "flame", "flame tank fires a flame weapon")
	check(not Ammo71.Parts71.burning(w.entities[tid]), "target not burning before")
	Ammo71.on_flame(w, s, w.entities[tid])
	check(Ammo71.Parts71.burning(w.entities[tid]), "thermite flame hit sets the Machine burning (stops nanite regrowth)")
