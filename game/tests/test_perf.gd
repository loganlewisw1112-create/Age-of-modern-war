extends "res://tests/test_base.gd"
## PERF4 (CONTRACTS_G3b section 0): fidelity tiers. Promotion on contact (never a REDUCED unit
## with an enemy inside the contact radius), no ammo / fuel / unit duplication across tier
## changes, determinism + mid-period save round trip with tiers, and a small fight with tiers
## gives the same winner and similar losses as FULL-only. Runs on whichever path is live.

const Tiers = preload("res://sim/systems/tiers.gd")
const Movement = preload("res://sim/systems/movement.gd")
const NativeCore = preload("res://sim/native_core.gd")
const Construction = preload("res://sim/systems/construction.gd")


## Endless 2-side world on the default map with the start units removed (HQs in the corners stay).
func _clean(seed_v: int = 3) -> SimWorld:
	var w := make_world({"seed": seed_v, "victory": "endless"})
	w.ai_state = {}
	for id in w.entities.keys():
		var k: String = w.entities[id].kind
		if k == "unit":
			w.destroy(int(id), "test_clear")  # start buildings stay: sides remain active
	return w


func _place(w: SimWorld, def: String, fid: int, at: Vector2) -> int:
	var mc := String(Content.unit(def).get("move_class", "foot"))
	var c := Movement.nearest_free_cell(w, Vector2i(floori(at.x), floori(at.y)), "vehicle" if mc == "vehicle" else "foot")
	return w.spawn_unit(def, fid, Vector2(c) + Vector2(0.5, 0.5))


## Two groups in opposite corners, both attack-moving to the centre.
func _armies(w: SimWorld, n0: int, n1: int) -> Array:
	var a := []
	var b := []
	for i in n0:
		a.append(_place(w, "ifv" if i % 4 == 3 else "rifleman", 0, Vector2(8 + (i % 4) * 2, 8 + (i / 4) * 2)))
	for i in n1:
		b.append(_place(w, "ifv" if i % 4 == 3 else "rifleman", 1, Vector2(86 - (i % 4) * 2, 86 - (i / 4) * 2)))
	var mid := Vector2(48.5, 48.5)
	w.submit({"type": "attack_move", "issuer": 0, "unit_ids": a, "target": mid})
	w.submit({"type": "attack_move", "issuer": 1, "unit_ids": b, "target": mid})
	return [a, b]


func _enemy_within(w: SimWorld, e: Dictionary, r: float) -> bool:
	for id in w.entities:
		var o: Dictionary = w.entities[id]
		if (o.kind == "unit" or o.kind == "building") and w.is_enemy(int(e.owner), int(o.owner)):
			if Vector2(o.pos).distance_to(Vector2(e.pos)) <= r:
				return true
	return false


func _totals(w: SimWorld) -> Dictionary:
	var ammo := 0
	var fuel := 0.0
	var units := 0
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "unit":
			units += 1
			ammo += int(e.get("ammo", 0))
			fuel += float(e.get("fuel", 0.0))
	for fid in w.factions:
		ammo += int(w.factions[fid].stock.get("ammo", 0))
		fuel += float(w.factions[fid].stock.get("fuel", 0))
	return {"ammo": ammo, "fuel": fuel, "units": units}


func test_tier_promotion_on_contact_and_no_duplication() -> void:
	Tiers.force_off = false
	var w := _clean()
	_armies(w, 8, 8)
	var cr := Tiers.contact_radius()
	var saw_reduced := 0
	var flips := 0
	var shots := 0
	var bad := []
	var prev := _totals(w)
	var last_tier := {}
	for t in 900:
		w.step()
		var now := _totals(w)
		if now.ammo > prev.ammo or now.fuel > prev.fuel + 0.0001 or now.units > prev.units:
			bad.append("tick %d: %s -> %s" % [w.tick, prev, now])
		prev = now
		for ev in w.events:
			if ev.type == "ShotFired":
				shots += 1
		for e in w.units_of(0) + w.units_of(1):
			var red := Tiers.is_reduced(e)
			if red:
				saw_reduced += 1
				if _enemy_within(w, e, cr):
					bad.append("tick %d: #%d REDUCED with an enemy within %.0f" % [w.tick, int(e.id), cr])
			if last_tier.has(int(e.id)) and bool(last_tier[int(e.id)]) != red:
				flips += 1
			last_tier[int(e.id)] = red
		if w.units_of(0).is_empty() or w.units_of(1).is_empty():
			break
	check(saw_reduced > 0, "units were REDUCED while far apart (%d unit-ticks)" % saw_reduced)
	check(flips > 0, "tier changes happened (%d)" % flips)
	check(shots > 0, "the armies met and fought (%d shots)" % shots)
	check(bad.is_empty(), "no REDUCED unit in contact, no ammo/fuel/unit created: %s" % str(bad.slice(0, 4)))
	var c := Tiers.counts(w)
	check(int(c.full) + int(c.reduced) == w.units_of(0).size() + w.units_of(1).size(), "tier_counts covers every unit")


func test_attack_order_promotes_at_once() -> void:
	var w := _clean()
	var a := _place(w, "rifleman", 0, Vector2(8, 8))
	var b := _place(w, "rifleman", 1, Vector2(86, 86))
	w.run_ticks(17)
	check(Tiers.is_reduced(w.entities[a]), "lone far unit is REDUCED")
	w.entities[b].pos = Vector2(w.entities[a].pos) + Vector2(5, 0)  # dropped next to it
	w.run_ticks(4 - w.tick % 4)   # next fog recompute: b becomes visible (tiers recompute only every 8)
	check(Tiers.is_reduced(w.entities[a]), "still REDUCED until the next tier recompute")
	var ev := do_cmd(w, 0, {"type": "attack", "unit_ids": [a], "target_id": b})
	check_eq(rejected_reason(ev), "", "attack accepted")
	check(not Tiers.is_reduced(w.entities[a]), "explicit attack order -> FULL immediately")


func _run_fight(seed_v: int, tiers_on: bool, ticks: int) -> SimWorld:
	Tiers.force_off = not tiers_on
	var w := _clean(seed_v)
	_armies(w, 10, 8)
	for t in ticks:
		w.step()
		if w.units_of(0).is_empty() or w.units_of(1).is_empty():
			break
	Tiers.force_off = false
	return w


func test_determinism_and_save_round_trip_with_tiers() -> void:
	var h1 := _run_fight(5, true, 300).state_hash()
	var h2 := _run_fight(5, true, 300).state_hash()
	check_eq(h1, h2, "same seed + commands -> same hash with tiers on")
	var w := _clean(5)
	_armies(w, 10, 8)
	w.run_ticks(37)   # mid tier period (recompute every 8 ticks)
	var w2 := SimWorld.from_dict(bytes_to_var(var_to_bytes(w.to_dict())))
	w2.ai_state = {}
	check_eq(w2.state_hash(), w.state_hash(), "hash equal right after restore")
	w.run_ticks(250)
	w2.run_ticks(250)
	check_eq(w2.state_hash(), w.state_hash(), "hash equal 250 ticks after a mid-period restore")


func test_small_fight_matches_full_only() -> void:
	var on := _run_fight(9, true, 1600)
	var off := _run_fight(9, false, 1600)
	var a_on := on.units_of(0).size()
	var b_on := on.units_of(1).size()
	var a_off := off.units_of(0).size()
	var b_off := off.units_of(1).size()
	print("  tiers on: %d vs %d left; FULL-only: %d vs %d left" % [a_on, b_on, a_off, b_off])
	check((a_on > b_on) == (a_off > b_off) and (a_on > 0) == (a_off > 0) and (b_on > 0) == (b_off > 0), "same winner")
	check(absi(a_on - a_off) <= 3 and absi(b_on - b_off) <= 3, "similar losses (within 3 units per side)")


## Orch fix 2026-10-24: the refinery idles (no ore consumed, ore_refined unchanged) while both
## fuel and ammo stocks are at or above rules.refinery.stock_cap, and resumes below it.
func test_refinery_idles_at_stock_cap() -> void:
	var cfg: Dictionary = Content.rules().refinery
	var cap := int(cfg.get("stock_cap", 0))
	if not check(cap > 0, "rules.refinery.stock_cap set"):
		return
	var w := make_world()
	var hq: Vector2i = Vector2i(w.factions[0].spawn)
	var site := Vector2i(-1, -1)
	for r in range(4, 20):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if site != Vector2i(-1, -1) or maxi(absi(dx), absi(dy)) != r:
					continue
				var o := hq + Vector2i(dx, dy)
				var ok := true
				for yy in 3:
					for xx in 3:
						var cell := o + Vector2i(xx, yy)
						if not w.in_bounds(cell) or not Terrain.buildable(w.terrain_at(cell)) or Construction.building_at_cell(w, cell):
							ok = false
				if ok:
					site = o
	if not check(site != Vector2i(-1, -1), "refinery site"):
		return
	var r: Dictionary = w.entities[w.spawn_building("refinery", 0, site, true)]
	var f: Dictionary = w.factions[0]
	w.credit(0, {"ore": 500, "fuel": maxi(0, cap - int(f.stock.fuel)), "ammo": maxi(0, cap - int(f.stock.ammo))}, "test")
	var ore0 := int(f.stock.ore)
	var refined0 := int(f.stats.get("ore_refined", 0))
	w.run_ticks(300)
	check_eq(String(r.status), "STOCK_FULL", "both stocks at cap -> STOCK_FULL")
	check_eq(int(f.stock.ore), ore0, "no ore consumed at the cap")
	check_eq(int(f.stats.get("ore_refined", 0)), refined0, "ore_refined unchanged while idle")
	check(w.spend(0, {"fuel": int(f.stock.fuel) - (cap - 1)}, "test"), "drop fuel below the cap")
	var ammo0 := int(f.stock.ammo)
	var fuel0 := int(f.stock.fuel)
	w.run_ticks(130)
	# per-product cap (PERF4-3): only fuel is short -> the cycle burns the fuel share (ore_in / 2)
	# and credits fuel only; ammo (at the cap) is not produced
	var half := int(cfg.ore_in) / 2
	check_eq(int(f.stock.ore), ore0 - half, "only fuel below the cap: one cycle consumed the fuel share of ore")
	check_eq(int(f.stats.get("ore_refined", 0)), refined0 + half, "ore_refined counts real consumption")
	check_eq(int(f.stock.fuel), fuel0 + int(cfg.fuel_out), "fuel credited")
	check_eq(int(f.stock.ammo), ammo0, "no ammo produced while ammo is at the cap")
	# now ammo short too: the next cycle burns the full ore_in and credits both
	check(w.spend(0, {"ammo": int(f.stock.ammo) - (cap - 1), "fuel": int(f.stock.fuel) - (cap - 1)}, "test"), "drop both below the cap")
	var ore1 := int(f.stock.ore)
	ammo0 = int(f.stock.ammo)
	w.run_ticks(130)
	check_eq(int(f.stock.ore), ore1 - int(cfg.ore_in), "both below the cap: one cycle consumed ore_in")
	check_eq(int(f.stock.ammo), ammo0 + int(cfg.ammo_out), "ammo credited when below the cap")


## G3b PERF4-3: RtsFog stamping (native) gives byte-identical visible/explored to the Image path.
func test_native_fog_matches_gdscript_fog() -> void:
	const FogS = preload("res://sim/systems/fog.gd")
	const NC = preload("res://sim/native_core.gd")
	if NC.new_fog(null) == null:
		check(true, "native fog not available: GDScript path only (skipped)")
		return
	var hs := []
	var fogs := []
	for off in [false, true]:
		FogS.native_off = off
		var w := _clean(9)
		_armies(w, 10, 8)
		for t in 120:
			w.step()
		hs.append(w.state_hash())
		var snap := {}
		for fid in w.fog:
			snap[fid] = [w.fog[fid].visible, w.fog[fid].explored]
		fogs.append(snap)
	FogS.native_off = false
	var same := true
	for fid in fogs[0]:
		if fogs[0][fid][0] != fogs[1][fid][0] or fogs[0][fid][1] != fogs[1][fid][1]:
			same = false
	check(same, "visible + explored byte-identical native vs Image path")
	check_eq(hs[0], hs[1], "state hash equal with native fog on/off")


## PERF4-4: RtsCombat.line_clear (combat.gd LOS with the native core live) answers exactly as
## Damage.line_clear: random segments (quarter-tile coordinates hit exact cell corners, some
## leave the map) over the map with extra ridge cells, then a fight whose state hash must be
## equal with Combat.native_los on/off.
func test_native_los_matches_gdscript_los() -> void:
	const CombatS = preload("res://sim/systems/combat.gd")
	const DamageS = preload("res://sim/systems/damage.gd")
	var lc = NativeCore.new_combat(null)
	if lc == null:
		check(true, "native RtsCombat not available: GDScript path only (skipped)")
		return
	var w := _clean(5)
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var keep: PackedByteArray = w.map.terrain
	var terr := keep.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in terr.size() / 12:
		terr[rng.randi_range(0, terr.size() - 1)] = DamageS.RIDGE
	w.map.terrain = terr
	var bad := 0
	var blocked := 0
	for i in 4000:
		var a := Vector2(float(rng.randi_range(-8, mw * 4 + 8)) * 0.25, float(rng.randi_range(-8, mh * 4 + 8)) * 0.25)
		var span := 4.0 if i % 2 == 0 else 24.0
		var b := a + Vector2(rng.randf_range(-span, span), rng.randf_range(-span, span))
		if i % 5 == 0:
			b = a + Vector2(float(rng.randi_range(-40, 40)) * 0.25, float(rng.randi_range(-40, 40)) * 0.25)
		var g := DamageS.line_clear(w, a, b)
		if not g:
			blocked += 1
		if bool(lc.line_clear(mw, mh, terr, DamageS.RIDGE, a, b)) != g:
			bad += 1
	w.map.terrain = keep
	check_eq(bad, 0, "native line_clear == Damage.line_clear on 4000 segments")
	check(blocked > 400 and blocked < 3600, "segments mix clear and blocked (%d blocked)" % blocked)
	var hs := []
	var shots := []
	for on in [true, false]:
		CombatS.native_los = on
		var w2 := _clean(9)
		var a := []
		var b := []
		for i in 12:
			a.append(_place(w2, "ifv" if i % 4 == 3 else "rifleman", 0, Vector2(38 + (i % 4) * 2, 38 + (i / 4) * 2)))
			b.append(_place(w2, "ifv" if i % 4 == 3 else "rifleman", 1, Vector2(58 - (i % 4) * 2, 58 - (i / 4) * 2)))
		w2.submit({"type": "attack_move", "issuer": 0, "unit_ids": a, "target": Vector2(48.5, 48.5)})
		w2.submit({"type": "attack_move", "issuer": 1, "unit_ids": b, "target": Vector2(48.5, 48.5)})
		var n := 0
		for t in 160:
			w2.step()
			for ev in w2.events:
				if String(ev.type) == "ShotFired":
					n += 1
		hs.append(w2.state_hash())
		shots.append(n)
	CombatS.native_los = true
	check(int(shots[0]) > 0, "the fight fired shots (%d)" % int(shots[0]))
	check_eq(shots[0], shots[1], "same shot count with native LOS on/off")
	check_eq(hs[0], hs[1], "state hash equal with native LOS on/off")
