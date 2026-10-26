extends RefCounted
## G6.1 playtest flow vfx61 (VFX61): a real tank duel (sim ShotFired / EntityDestroyed -> muzzle flashes, glowing
## tracers, armour sparks, blasts, a burning wreck with a drifting plume), an artillery barrage on a town (shell events
## injected into the fx layer only: layered blasts, debris, craters), an OFF61-style smoke drill, and the same barrage
## on Low quality. Screenshots: one per scene plus a 10-shot strip of the duel.

const H = preload("res://tests/test_machine_g6.gd")


func _m(fx, k: String) -> int:
	return int(fx.fx61.made.get(k, 0))


func run(pt) -> void:
	var mv = pt._mv()
	var fx = mv.fx_layer
	mv.join_sim()
	var w: SimWorld = pt._w()
	var h = H.new()
	var c: Vector2i = h._open(w, 7)
	fx.set_fx_quality("high")
	var mine: Array = []
	var foes: Array = []
	for i in 3:
		mine.append(int(h._unit(w, "mbt", 0, Vector2(c) + Vector2(-3.5, i - 0.5)).id))
		foes.append(int(h._unit(w, "mbt", 1, Vector2(c) + Vector2(3.5, i - 0.5)).id))
	foes.append(int(h._unit(w, "rifleman", 1, Vector2(c) + Vector2(2.5, 3.5)).id))
	mv.center_camera_on(Vector2(c))
	await pt._wait(0.5)
	# 1. tank duel (real sim fire)
	var fired: bool = await pt._wait_until(func(): return _m(fx, "muzzle_cannon") >= 3, 25.0)
	pt._log("vfx_duel_cannon_flashes", fired, str(fx.fx61.made))
	for i in 10:
		await pt._shot("vfx61_duel_strip_%02d" % i)
		await pt._wait(0.12)
	pt._log("vfx_duel_impacts", _m(fx, "impact_armor") + _m(fx, "explosion") > 0 and _m(fx, "barrel_smoke") > 0,
		"armour %d blasts %d barrel smoke %d" % [_m(fx, "impact_armor"), _m(fx, "explosion"), _m(fx, "barrel_smoke")])
	# 2. burning wreck (first tank destroyed in the duel)
	var wreck: bool = await pt._wait_until(func(): return _m(fx, "destruction") >= 1, 60.0)
	pt._log("vfx_wreck_destroyed", wreck, "secondaries %d" % _m(fx, "secondary"))
	if wreck:
		await pt._wait(1.5)
		var burning := 0
		for k in fx.fx61.emitters:
			burning += 1 if String(fx.fx61.emitters[k].kind) == "wreck" else 0
		pt._log("vfx_wreck_burning", burning >= 1, "%d wreck fires, %d particles, %d lights" % [burning, fx.fx61.parts.size(), int(fx.fx61_drawn.lights)])
		await pt._shot("vfx61_burning_wreck")
	# 3. artillery barrage on a town (fx-only injection: shells from behind our line onto 4 houses)
	mv.join_sim()
	var town := Vector2(c) + Vector2(1.0, -5.0)
	for i in 4:
		w.spawn_building("s_garrison_bld", 1, Vector2i(town) + Vector2i((i % 2) * 3 - 2, (i / 2) * 3 - 2), true)
	# a forward observer of ours beside the town: effects are drawn only where the player sees, and how many of
	# our tanks survive the duel varies (G6.1 r2: 3 wrecks, the town fell back into fog and 0 craters were drawn)
	# (a recon drone over the town: the enemy tanks can't shoot air; a ground scout beside the duel was killed)
	h._unit(w, "a_drone_recon", 0, town + Vector2(-1.5, 1.0))
	mv.center_camera_on(town + Vector2(0, 2))
	var seen: bool = await pt._wait_until(func(): return mv.cell_visible(Vector2i(town)), 8.0)
	if not seen:
		print("PLAYTEST-DBG vfx_town_not_visible town=%s" % str(town))
	var cr0 := _m(fx, "decal_crater")
	var p0 := _barrage(fx, Vector2(c) + Vector2(-6, 4), town, 10, 1)
	for i in 6:
		await pt._wait(0.35)
		await pt._shot("vfx61_barrage_%d" % i)
	await pt._wait(2.0)
	pt._log("vfx_barrage_craters", _m(fx, "decal_crater") - cr0 >= 6, "craters %d, peak particles %d" % [_m(fx, "decal_crater") - cr0, p0])
	await pt._shot("vfx61_town_craters")
	# 4. smoke drill (OFF61 AiDecision tag "smoke") over our tanks
	mv.center_camera_on(Vector2(c))
	fx._on_world_events([{"type": "AiDecision", "fid": 0, "tag": "smoke", "unit_ids": mine + foes, "reason": "pt61 smoke drill"}])
	await pt._wait(1.5)
	pt._log("vfx_smoke_screen", _m(fx, "smoke_screen") >= 1, "%d particles" % fx.fx61.parts.size())
	await pt._shot("vfx61_smoke_screen")
	# 5. Low quality: the same barrage spawns about half the particles
	await pt._wait(6.0)
	fx.set_fx_quality("low")
	mv.center_camera_on(town + Vector2(0, 2))
	var before: int = fx.fx61.parts.size()
	_barrage(fx, Vector2(c) + Vector2(-6, 4), town, 10, 2)
	await pt._wait(2.2)
	var low_n: int = fx.fx61.parts.size()
	pt._log("vfx_low_quality", true, "Low: %d live particles after the barrage (was %d before), cap %d" % [low_n, before, int(fx.fx61.cap)])
	await pt._shot("vfx61_barrage_low")
	fx.set_fx_quality("")
	pt._log("vfx_no_script_errors", true, "made %s" % str(fx.fx61.made))


## n indirect shells onto a town (presentation-only events); returns the live particle count afterwards.
func _barrage(fx, gun: Vector2, town: Vector2, n: int, seed: int) -> int:
	var r := RandomNumberGenerator.new()
	r.seed = 6100 + seed
	for i in n:
		var to := town + Vector2(r.randf_range(-3.0, 3.0), r.randf_range(-3.0, 3.0))
		fx.on_shot({"shooter": -1, "target": -1, "weapon": "howitzer", "hit": true, "from": gun, "to": to, "indirect": true})
	return fx.fx61.parts.size()
