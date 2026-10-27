extends RefCounted
## G7 CREEP7 playtest: Human A vs the Machine with creep on (cfg.creep). Creep spreads from the Machine base, a
## standard purge clears it for good, a dormant seed regrows a structure after a wipe, a living core pulses and, as
## the last core at low hp, tears out of the ground and walks. Screenshot of each.
## The view: uses match_view.creep_layer when ORCH has wired it; otherwise this flow adds a CreepLayer itself and
## feeds it Creep.snap(w) every frame (flows may write the sim; the layer itself only reads).

const Creep = preload("res://sim/systems/creep.gd")
const Cores = preload("res://sim/systems/cores.gd")
const CreepLayer = preload("res://presentation/view/creep_layer.gd")

var _cl = null
var _own := false


func _steps(w: SimWorld, n: int, types: Array) -> Array:
	var out := []
	for i in n:
		w.step()
		for ev in w.events:
			if types.has(String(ev.type)):
				out.append(ev)
	return out


func _show(pt, w: SimWorld, at: Vector2, secs: float = 0.8) -> void:
	pt._mv().center_camera_on(at)
	var t := 0.0
	while t < secs:
		if _own and _cl != null:
			_cl.refresh({"creep": Creep.snap(w)})
		await pt.get_tree().process_frame
		t += pt.get_process_delta_time()


func run(pt) -> void:
	var cfg := SimWorld.default_config()
	cfg.sides[1].faction = "machine"
	cfg.sides[1].ai = false
	cfg.creep = true
	cfg.victory = "endless"
	var started: bool = pt.main.start_match(cfg)
	pt._log("creep7_match_started", started, "machine vs human_a, cfg.creep")
	if not started:
		return
	await pt._wait(1.5)
	var mv = pt._mv()
	var w: SimWorld = pt._w()
	mv.join_sim()
	var ex: PackedByteArray = w.fog[0].explored
	ex.fill(1)
	w.fog[0].explored = ex
	_cl = mv.get("creep_layer")
	if _cl == null:
		_own = true
		_cl = CreepLayer.new()
		_cl.z_index = 0
		var tl: Node = mv.get("terrain_layer")
		mv.add_child(_cl)
		if tl != null:
			mv.move_child(_cl, tl.get_index() + 1)
	pt._log("creep7_layer", _cl != null, "wired by match_view" if not _own else "added by the flow (CR: match_view wiring)")
	var mb = null
	for b in w.buildings_of(1):
		if mb == null or int(b.id) < int(mb.id):
			mb = b
	pt._log("creep7_machine_base", mb != null, "")
	if mb == null:
		return
	var base: Vector2 = mb.pos
	# 1. spread
	_steps(w, 300, [])
	var c1 := Creep.coverage(w)
	_steps(w, 900, [])
	var c2 := Creep.coverage(w)
	pt._log("creep7_spread", c2 > c1 and c1 > 0.0 and Creep.on_creep(w, w.cell_of(base)),
		"coverage %.4f -> %.4f" % [c1, c2])
	await _show(pt, w, base)
	await pt._shot("creep7_spread")
	# 2. purge clears it for good
	var pc := base + Vector2(7, 3)
	var r := Creep.purge(w, pc, 7.0, "standard", 0)
	_steps(w, 600, [])
	pt._log("creep7_purge", int(r.lost) > 0 and Creep.is_sterile(w, w.cell_of(pc)) and Creep.at(w, w.cell_of(pc)) == 0.0,
		"lost=%d cells, still clear 30 s later" % int(r.lost))
	await _show(pt, w, pc)
	await pt._shot("creep7_purge")
	# 3. a dormant seed regrows after the base near it is gone
	var rg: Dictionary = Content.rules().g7_machine.creep.regrow
	var old_s: float = rg.regrow_s
	rg.regrow_s = 3.0
	var sp := Vector2(float(w.map.w) * 0.5, float(w.map.h) * 0.5)
	if sp.distance_to(base) < 30.0:
		sp = base + (sp - base).normalized() * 30.0 if sp != base else base + Vector2(30, 0)
	Creep.add_seed(w, sp, "seed", 1)
	Creep.reveal(w, sp, 4.0, 0)
	var evs := _steps(w, 120, ["SeedRegrown"])
	rg.regrow_s = old_s
	pt._log("creep7_seed_regrow", evs.size() >= 1, "regrown=%s" % str(evs.map(func(e): return e.def)))
	_steps(w, 600, [])
	await _show(pt, w, sp)
	await pt._shot("creep7_seed_regrow")
	# 4. a living core pulses; as the last core at low hp it walks
	var kr: Dictionary = Content.rules().g7_machine.cores
	var old_p: float = kr.plate_every_s
	kr.plate_every_s = 1.0
	var cc := w.cell_of(sp + Vector2(-8, 8))
	var bid := Cores.place(w, 1, cc)
	evs = _steps(w, 80, ["CorePulse", "CorePlated"])
	kr.plate_every_s = old_p
	var pulses := evs.filter(func(e): return String(e.type) == "CorePulse").size()
	pt._log("creep7_core_pulse", pulses >= 1 and int(Cores.list(w)[0].plate) >= 1, "pulses=%d plate=%d" % [pulses, int(Cores.list(w)[0].plate)])
	await _show(pt, w, Vector2(cc))
	await pt._shot("creep7_core_pulse")
	var b = w.entities.get(bid)
	if b != null:
		b.hp = float(b.max_hp) * 0.25
	evs = _steps(w, 2, ["CoreUprooted"])
	var wk := Cores.walker(w)
	var p0: Vector2 = w.entities[wk].pos if wk >= 0 else Vector2.ZERO
	_steps(w, 200, [])
	var p1: Vector2 = w.entities[wk].pos if wk >= 0 and w.entities.has(wk) else p0
	pt._log("creep7_core_walks", evs.size() == 1 and wk >= 0 and p1.distance_to(p0) > 1.0,
		"walker=%d moved %.1f tiles" % [wk, p1.distance_to(p0)])
	await _show(pt, w, p1)
	await pt._shot("creep7_core_walking")
	pt._log("creep7_view_uploads", int(_cl.get("uploads")) > 0 if _cl != null else false, "uploads=%s" % str(_cl.get("uploads")))
