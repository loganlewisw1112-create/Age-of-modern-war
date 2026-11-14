extends RefCounted
## G7.1 PERFDRAW71 playtest flow (windowed): render-side checks that need a real viewport.
##  1. AIRFIX71 CR seq 148 (air_hot): a helicopter homed on a FARP lands there and is hot-pit serviced; while
##     e.air_hot is set the drawn frame keeps cycling through the rotor anim (sampled from entity_layer.drawn7 over
##     ~1 s) and two close-up shots 0.15 s apart are taken (perfdraw71_hot_pit_a / _b).
## The LP zoomed-out / pan / peak fps numbers come from tools/perf71_draw_lp.gd (fps log per run), not this flow.
## Screenshots: perfdraw71_*.png.
const Air = preload("res://sim/systems/air.gd")
const Pads71 = preload("res://sim/systems/pads71.gd")
const Movement = preload("res://sim/systems/movement.gd")


func _near_open(w: SimWorld, c: Vector2i, size: int) -> Vector2i:
	for r in range(0, 30):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var o := c + Vector2i(dx, dy)
				var ok := true
				for yy in range(-1, size + 1):
					for xx in range(-1, size + 1):
						var q := o + Vector2i(xx, yy)
						if not w.in_bounds(q) or not Terrain.buildable(w.terrain_at(q)) or preload("res://sim/systems/construction.gd").building_at_cell(w, q):
							ok = false
				if ok:
					return o
	return c


func run(pt) -> void:
	var cfg := SimWorld.default_config()
	cfg.sides[1].ai = false
	if not pt.main.start_match(cfg):
		pt._log("perfdraw71_start", false, "start_match failed")
		return
	await pt._wait(2.0)
	var mv = pt._mv()
	var w: SimWorld = pt._w()
	mv.join_sim()
	var hq = mv._player_hq()
	var base: Vector2i = Vector2i(hq.cell) if hq != null else w.cell_of(Vector2(w.factions[0].spawn))
	w.factions[0].credits = 200000
	for k in ["salvage", "ore", "fuel", "ammo"]:
		w.factions[0].stock[k] = 200000
	var fp := w.spawn_building("a_g71_farp", 0, _near_open(w, base + Vector2i(16, 4), 4), true)
	pt._log("perfdraw71_farp_built", fp >= 0, "farp id=%d" % fp)
	if fp < 0:
		return
	await pt._wait(0.5)
	mv.join_sim()
	var h := w.spawn_unit("a_attack_heli", 0, Vector2(w.entities[fp].pos) + Vector2(10, -8))
	await pt._wait(0.3)
	mv.join_sim()
	Pads71.set_home(w, h, "farp:%d" % fp)
	var e: Dictionary = w.entities[h]
	Air._ensure(w, e)
	Air.sync71(w)
	if Air.adef(e).has("ammo_max"):
		e.ammo = 0
	e.fuel = 0.15 * float(Air.adef(e).get("fuel_max", 100.0))
	Movement.stop_path(e)
	e.order = {"type": "idle"}
	var t := 0.0
	var hot := false
	while t < 60.0:
		await pt._wait(0.25)
		t += 0.25
		if not w.entities.has(h):
			break
		if bool(w.entities[h].get("air_landed", false)) and bool(w.entities[h].get("air_hot", false)):
			hot = true
			break
	pt._log("perfdraw71_hot_pit_reached", hot, "landed+air_hot=%s after %.1fs" % [str(hot), t])
	if not hot:
		return
	mv.center_camera_on(Vector2(w.entities[h].pos))
	mv.camera.zoom = Vector2(2.0, 2.0)
	await pt._wait(0.3)
	var el = mv.entity_layer
	var frames := {}
	var samples := 0
	for k in 12:
		await pt._wait(0.08)
		if not bool(w.entities.get(h, {}).get("air_hot", false)):
			break
		var d = el.drawn7.get(h)
		if d is Array:
			frames[int(d[0])] = true
			samples += 1
		if k == 4:
			await pt._shot("perfdraw71_hot_pit_a")
		elif k == 6:
			await pt._shot("perfdraw71_hot_pit_b")
	pt._log("perfdraw71_hot_pit_rotors_turn", frames.size() >= 2,
		"distinct drawn frames while air_hot over %d samples: %d %s" % [samples, frames.size(), str(frames.keys())])
