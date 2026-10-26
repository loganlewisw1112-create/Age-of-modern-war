extends "res://tests/test_base.gd"
## G6.1 VFX61 acceptance: every sim event maps to its effect (ShotFired by weapon class, hit / miss / water,
## EntityDestroyed by kind, splash), counts capped, decals capped and fading, quality Low halves particles,
## OFF61 "smoke" drill draws a smoke screen, ambient dust / fires from the snapshot, readability layering,
## and the view never writes the sim (state hash identical with effects on / off).

const RenderSnap = preload("res://sim/render_snap.gd")
const FxLayer = preload("res://presentation/view/fx_layer.gd")
const Core = preload("res://presentation/view/fx61_core.gd")
const Engine61 = preload("res://presentation/view/fx61_engine.gd")
const Tex = preload("res://presentation/view/fx61_tex.gd")
const FxView = preload("res://tests/test_view5.gd").FxView
const H = preload("res://tests/test_machine_g6.gd")


## A mock view: shooter 1 (mbt) at (5,5), target 2 (mbt) at (9,5), infantry 3 at (9,7), building 4 at (12,5);
## 20x20 dirt map with a water strip in column 15.
func _view() -> FxView:
	var v := FxView.new()
	v.world = {"entities": {
		1: {"id": 1, "kind": "unit", "def": "mbt", "owner": 0, "pos": Vector2(5, 5)},
		2: {"id": 2, "kind": "unit", "def": "mbt", "owner": 1, "pos": Vector2(9, 5)},
		3: {"id": 3, "kind": "unit", "def": "rifleman", "owner": 1, "pos": Vector2(9, 7)},
		4: {"id": 4, "kind": "building", "def": "s_garrison_bld", "owner": 1, "pos": Vector2(12, 5)}}}
	var tr := PackedByteArray()
	tr.resize(400)
	tr.fill(1)
	for y in 20:
		tr[y * 20 + 15] = 4
	v.snap = {"tick": 1, "n": 2, "map_w": 20, "map_h": 20, "terrain": tr, "ids": PackedInt32Array([1, 2]),
		"pos": PackedVector2Array([Vector2(5, 5), Vector2(9, 5)]), "prev": PackedVector2Array([Vector2(5, 5), Vector2(9, 5)]),
		"facing": PackedFloat32Array([0.0, PI]), "hp": PackedFloat32Array([1.0, 1.0]),
		"def": PackedInt32Array([0, 0]), "defs": PackedStringArray(["mbt"]),
		"owner": PackedInt32Array([0, 1]), "flags": PackedInt32Array([0, 0]), "statics": {}, "air": {}}
	return v


func _fx(q: String = "high"):
	var fx = FxLayer.new()
	fx.setup(_view())
	fx.set_fx_quality(q)
	fx.fx61.budget = 100000   # many shots in one frame here; the per-frame budget is tested on its own
	return fx


func _shot(fx, w: String, tgt: int, hit: bool, to: Vector2 = Vector2(9, 5), indirect := false) -> void:
	fx.on_shot({"shooter": 1, "target": tgt, "weapon": w, "hit": hit, "from": Vector2(5, 5), "to": to, "indirect": indirect})


func _m(fx, k: String) -> int:
	return int(fx.fx61.made.get(k, 0))


func test_weapon_classes_from_content() -> void:
	var want := {"rifle": "rifle", "hmg": "mg", "lmg": "mg", "autocannon": "autocannon", "tank_cannon": "cannon",
		"at_rocket": "rocket", "howitzer": "artillery", "mortar": "artillery", "laser_mg": "energy", "flamethrower": "flame",
		"sniper_rifle": "rifle", "g6_atgm": "rocket", "rail": "energy"}
	for wid in want:
		check_eq(Core.weapon_class(wid), want[wid], "weapon %s -> class" % wid)
	check_eq(Core.classify("x", {"class": "small_arms", "fx_class": "cannon"}), "cannon", "content fx_class overrides")
	for c in Core.CLASSES:
		check(Core.PARAMS.has(c), "params for class %s" % c)
	check_eq(Core.norm_quality("bogus"), Core.DEFAULT_QUALITY, "unknown quality -> default")
	for n in Tex.NAMES:
		var t: Texture2D = Tex.tex(n)
		check(t != null and t.get_width() > 0, "procedural sprite %s" % n)


func test_shots_map_to_effects_by_class() -> void:
	var fx = _fx()
	_shot(fx, "rifle", 3, true, Vector2(9, 7))
	check(_m(fx, "muzzle_rifle") == 1 and _m(fx, "impact_soft") == 1, "rifle: muzzle + soft impact %s" % str(fx.fx61.made))
	var tr: Dictionary = fx._fx[fx._fx.size() - 1]
	check(String(tr.kind) == "tracer" and float(tr.size) == float(Core.PARAMS.rifle.tw), "rifle tracer, class width")
	_shot(fx, "hmg", 3, true, Vector2(9, 7))
	check(_m(fx, "muzzle_mg") == 1 and _m(fx, "casing") >= 1, "mg: casings")
	check(float(fx._fx[fx._fx.size() - 1].get("glow", 0.0)) > 0.0, "mg tracer glows")
	_shot(fx, "tank_cannon", 2, true)
	check(_m(fx, "muzzle_cannon") == 1 and _m(fx, "barrel_smoke") >= 1, "cannon: flash + barrel smoke")
	check(_m(fx, "impact_armor") == 1 and _m(fx, "explosion") >= 1, "cannon hit on armour: sparks + blast")
	_shot(fx, "at_rocket", 4, true, Vector2(12, 5))
	check(_m(fx, "backblast") == 1, "rocket: backblast")
	check(_m(fx, "impact_building") == 0 and int(fx.fx61.made.get("decal_scorch", 0)) >= 1, "rocket hit on a building: blast + scorch")
	_shot(fx, "autocannon", 4, true, Vector2(12, 5))
	check(_m(fx, "impact_building") == 1, "autocannon hit on a building: debris chunks")
	_shot(fx, "rifle", 2, false)
	check(_m(fx, "impact_dirt") == 1, "miss on dirt: dust kick")
	_shot(fx, "rifle", 2, false, Vector2(15.5, 5.5))
	check(_m(fx, "impact_water") == 1, "miss on water: splash")
	_shot(fx, "laser_mg", 2, true)
	check(_m(fx, "muzzle_energy") == 1, "energy weapon: energy flash")
	_shot(fx, "flamethrower", 2, true)
	check(_m(fx, "muzzle_flame") == 1 and int(fx.flames) == 1, "flamer keeps its jet + flame light")
	# artillery: launch flash, shell arc, then layered blast + crater on landing; splash sizes the blast
	_shot(fx, "howitzer", 2, true, Vector2(9, 9), true)
	check(_m(fx, "muzzle_artillery") == 1, "artillery launch flash")
	var ex0 := _m(fx, "explosion")
	for i in 40:
		fx.tick(0.05)
	check(_m(fx, "explosion") == ex0 + 1 and int(fx.fx61.made.get("decal_crater", 0)) == 1, "shell landed: blast + crater")
	_shot(fx, "howitzer", 2, true, Vector2(15.5, 9.5), true)
	for i in 40:
		fx.tick(0.05)
	check(int(fx.fx61.made.get("decal_crater", 0)) == 1 and _m(fx, "impact_water") == 2, "shell into water: splash, no crater")
	fx.free()


func test_destroyed_by_kind_and_burning_wreck() -> void:
	var fx = _fx()
	fx.on_destroyed({"id": 3, "kind": "unit", "def": "rifleman", "owner": 1, "pos": Vector2(9, 7)})
	check(_m(fx, "destruction") == 0 and _m(fx, "impact_dirt") == 1, "infantry fall: dust, no fireball")
	fx.on_destroyed({"id": 2, "kind": "unit", "def": "mbt", "owner": 1, "pos": Vector2(9, 5)})
	check(_m(fx, "destruction") == 1 and _m(fx, "secondary") >= 2, "tank: blast + secondaries %s" % str(fx.fx61.made))
	check(fx.fx61.emitters.has(2) and String(fx.fx61.emitters[2].kind) == "wreck", "tank leaves a burning wreck")
	fx.on_destroyed({"id": 4, "kind": "building", "def": "s_garrison_bld", "owner": 1, "pos": Vector2(12, 5)})
	check(_m(fx, "destruction") == 2 and fx.fx61.emitters.has(4), "building: blast + fire")
	var p0: int = fx.fx61.parts.size()
	for i in 20:
		fx.tick(0.05)
	var flames := 0
	for f in fx.fx61.parts:
		flames += 1 if String(f.tx) == "flame" else 0
	check(flames > 0, "burning wreck keeps spawning flames (%d parts, was %d)" % [fx.fx61.parts.size(), p0])
	var drift := false
	for f in fx.fx61.parts:
		drift = drift or (String(f.tx) == "puff" and (f.v as Vector2).x > 3.0)
	check(drift, "smoke plume drifts with the wind")
	fx.fx61.now += 100.0
	fx.fx61.tick(0.05, Rect2(-1e6, -1e6, 2e6, 2e6))
	check(fx.fx61.emitters.is_empty(), "wreck fires burn out")
	fx.free()


func test_quality_low_halves_particles_and_caps() -> void:
	check_eq(Core.scaled(10, "low"), 5, "Low = half of High (10 -> 5)")
	check_eq(Core.scaled(10, "high"), 10, "High base count")
	check_eq(int(Core.QCAP.low) * 2, int(Core.QCAP.high), "Low cap = half of High")
	var cnt := {}
	for q in ["low", "high"]:
		var e = Engine61.new()
		e.set_quality(q)
		e.budget = 100000
		for i in 4:
			e.explosion(Vector2(i * 50, 0), 20.0, "")
			e.muzzle("cannon", Vector2(0, i * 30), Vector2.RIGHT, Vector2(0, i * 30 + 10))
			e.impact("armor", Vector2(10, 10), 1.0)
		cnt[q] = e.parts.size()
	var r: float = float(cnt.low) / float(cnt.high)
	check(r >= 0.4 and r <= 0.62, "Low spawns about half the particles of High (%d vs %d)" % [cnt.low, cnt.high])
	# per-frame budget: a 50-shot volley in one frame spawns particle impacts for QBUDGET shots only
	var e3 = Engine61.new()
	e3.set_quality("medium")
	for i in 50:
		e3.impact("dirt", Vector2(i, 0), 1.0)
	check_eq(int(e3.made.get("impact_dirt", 0)), int(Core.QBUDGET.medium), "impacts limited to the per-frame budget")
	e3.tick(0.016, Rect2(-1e6, -1e6, 2e6, 2e6))
	e3.impact("dirt", Vector2.ZERO, 1.0)
	check_eq(int(e3.made.get("impact_dirt", 0)), int(Core.QBUDGET.medium) + 1, "budget refills every frame")
	var e2 = Engine61.new()
	e2.set_quality("high")
	for i in 400:
		e2.explosion(Vector2(i, 0), 24.0, "crater")
	check(e2.parts.size() <= int(Core.QCAP.high), "live particles capped (%d)" % e2.parts.size())
	var live := 0
	for d in e2.decals:
		live += 1 if float(d.fade) < 0.0 else 0
	check(live <= int(Core.DECAL_CAP.high), "persistent decals capped (%d)" % live)
	check(e2.decals.size() > live, "the oldest decals are fading out")
	for i in 50:
		e2.tick(0.05, Rect2(-1e6, -1e6, 2e6, 2e6))
	check(e2.decals.size() <= int(Core.DECAL_CAP.high), "faded decals removed (%d)" % e2.decals.size())
	check(float(e2.decals[0].fade) < 0.0, "the newest decals persist")


func test_smoke_drill_draws_a_smoke_screen() -> void:
	var fx = _fx()
	fx._on_world_events([{"type": "AiDecision", "fid": 1, "tag": "contact", "unit_ids": [2], "reason": ""}])
	check_eq(_m(fx, "smoke_screen"), 0, "other drill tags draw no smoke")
	fx._on_world_events([{"type": "AiDecision", "fid": 1, "tag": "smoke", "unit_ids": [1, 2], "reason": "Smoke to cover the break."}])
	check_eq(_m(fx, "smoke_screen"), 1, "smoke tag -> smoke screen")
	var big := 0
	var max_a := 0.0
	for f in fx.fx61.parts:
		if String(f.tx) == "puff" and float(f.life) >= 15.0:
			big += 1
			max_a = maxf(max_a, (f.c as Color).a)
	check(big >= 10, "long-lived cloud puffs (%d)" % big)
	check(max_a <= Core.MAX_SMOKE_ALPHA, "smoke stays see-through (alpha %.2f)" % max_a)
	fx.free()


func test_ambient_dust_and_fires_from_snapshot() -> void:
	var fx = _fx()
	var v = fx.mv
	v.snap.flags = PackedInt32Array([RenderSnap.FLAG_MOVING, RenderSnap.FLAG_MOVING])
	v.snap.statics = {4: {"id": 4, "kind": "building", "def": "s_garrison_bld", "pos": Vector2(12, 5), "hp": 0.2, "built": true, "size": 2}}
	v.snap.fires = PackedInt32Array([3 * 20 + 3])
	for t in 6:
		v.snap.tick = 10 + t
		fx.tick(0.05)
	check(_m(fx, "dust") >= 2, "moving tanks raise dust (%d)" % _m(fx, "dust"))
	check(fx.fx61.emitters.has("b4") and fx.fx61.emitters.has("c63"), "burning building + forest fire emitters")
	check_eq(Core.dust_color(4).a > 0.0 and Core.is_water(4), true, "vehicles spray on water")
	check_eq(Core.dust_color(1).r > Core.dust_color(2).r - 0.1 and Core.dust_color(1).a > Core.dust_color(2).a, true, "dirt dustier than road")
	fx.free()


func test_readability_layering() -> void:
	var fx = _fx()
	fx._e()
	check(fx._dec_node.z_as_relative and fx._dec_node.z_index == -3, "decals at absolute z 0 (fx z 3 - 3): under rings (1) and units (2)")
	check(fx._lit_node.show_behind_parent and fx._lit_node.material is CanvasItemMaterial, "lights additive, behind the particles")
	check((fx._lit_node.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_ADD, "additive light blend")
	check(Core.MAX_SMOKE_ALPHA <= 0.5, "smoke alpha capped for readability")
	var src: String = (load("res://presentation/match_view.gd") as GDScript).source_code
	check(src.contains("fx_layer.z_index = 3") and src.contains("overlay_layer.z_index = 5"), "health bars (overlay z 5) draw above every effect (z <= 3)")
	fx.free()


## The view only reads: stepping a real battle with every event fed to the fx layer leaves the hash unchanged.
func _battle(with_fx: bool) -> Array:
	var h = H.new()
	var w := make_world()
	var c: Vector2i = h._open(w, 6)
	for i in 3:
		h._unit(w, "mbt", 0, Vector2(c) + Vector2(-3.5, i - 1.0))
		h._unit(w, "rifleman", 1, Vector2(c) + Vector2(2.5, i - 1.0))
	h._unit(w, "mbt", 1, Vector2(c) + Vector2(3.5, 0.5))
	var fx = null
	var v := FxView.new()
	if with_fx:
		fx = FxLayer.new()
		fx.setup(v)
		fx.set_fx_quality("high")
	for t in 160:
		w.step()
		RenderSnap.build(w)   # both runs build the snapshot, so only the fx layer differs
		if fx != null:
			v.snap = RenderSnap.latest(w)
			v.world = w
			for ev in w.events:
				if String(ev.type) == "ShotFired":
					fx.on_shot(ev)
				elif String(ev.type) == "EntityDestroyed":
					fx.on_destroyed(ev)
			fx._on_world_events(w.events)
			fx.tick(0.05)
	var made: Dictionary = fx.fx61.made.duplicate() if fx != null else {}
	if fx != null:
		fx.free()
	return [w.state_hash(), made]


func test_view_never_writes_the_sim() -> void:
	var a: Array = _battle(true)
	var b: Array = _battle(false)
	check_eq(String(a[0]), String(b[0]), "state hash identical with effects on / off")
	var m: Dictionary = a[1]
	check(int(m.get("muzzle_cannon", 0)) + int(m.get("muzzle_rifle", 0)) > 0, "the battle produced effects %s" % str(m))
