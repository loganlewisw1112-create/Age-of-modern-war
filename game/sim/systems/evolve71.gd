extends RefCounted
## G7.1 H11 hive evolves mid-run: machines visibly change form at dread stages (new armour / limbs flags).
## Presentation reads stage tags; combat can use harden_mult. Numbers PROVISIONAL.

const KEY := "evolve71"
const VER := 1


static func R() -> Dictionary:
	var c = Content.rules().get("g71_evolve", {})
	return c if c is Dictionary else {}


static func active(w: SimWorld) -> bool:
	return w.sys_state.has("lp")


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {"ver": VER, "stage": 0, "tagged": 0}
		w.sys_state[KEY] = s
	return s


static func board(w: SimWorld) -> Dictionary:
	if not active(w):
		return {}
	var s := _st(w)
	return {"stage": int(s.stage), "tagged": int(s.tagged), "harden": harden_mult(w)}


static func stage(w: SimWorld) -> int:
	return int(_st(w).stage) if active(w) else 0


static func harden_mult(w: SimWorld) -> float:
	var st := stage(w)
	var per := float(R().get("harden_per_stage", 0.08))
	return snappedf(1.0 + float(st) * per, 0.01)


static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	var s := _st(w)
	var dread := float(w.sys_state.lp.get("dread", 0.0))
	var cuts: Array = R().get("stage_at", [0.35, 0.55, 0.75, 0.9])
	var want := 0
	for c in cuts:
		if dread >= float(c):
			want += 1
	if want != int(s.stage):
		s.stage = want
		w.emit("Evolve71Stage", {"stage": want, "dread": snappedf(dread, 0.01)})
	# Tag a batch of live machines with the current evolve stage (for presentation / harden).
	if w.tick % int(R().get("tag_every", 30)) != 5:
		return
	var n := 0
	for id in w.entities.keys():
		var e = w.entities.get(id)
		if e == null or String(e.get("kind", "")) != "unit":
			continue
		var o := int(e.get("owner", -1))
		if not w.factions.has(o) or String(w.factions[o].get("faction_def", "")) != "machine":
			continue
		if int(e.get("g71_evolve", 0)) != int(s.stage):
			e["g71_evolve"] = int(s.stage)
			n += 1
	if n > 0:
		s.tagged = int(s.tagged) + n
