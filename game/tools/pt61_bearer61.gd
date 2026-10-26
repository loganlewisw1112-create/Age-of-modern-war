extends RefCounted
## G6.1 playtest flow "bearer61" (owner: BEARER61): train a rifle squad and an Ammo Bearer at the barracks
## (UI clicks), join the bearer to the squad (the bearer card's Join squad button once SQUAD61 lands it, else
## the join_squad command), march away from the base supply radius, empty the squad's magazines (harness
## drain standing in for a firefight, so the base cannot resupply them), then watch the bearer restock them
## from its own load. Shots at each step.

const AmmoBearer = preload("res://sim/systems/ammo_bearer.gd")


func _members(pt, sq: int) -> Array:
	var out := []
	for e in pt._w().units_of(0):
		if int(e.get("squad", -1)) == sq and not AmmoBearer.is_bearer(e):
			out.append(e)
	return out


func _low(mem: Array) -> int:
	var n := 0
	for m in mem:
		if m.has("ammo") and float(m.ammo) < 0.5 * float(Content.unit(String(m.def)).get("ammo_max", 1)):
			n += 1
	return n


func run(pt) -> void:
	var sq_ids: Array = await pt._g6_squad()
	pt._log("bearer_squad_trained", not sq_ids.is_empty(), "units=%d" % sq_ids.size())
	if sq_ids.is_empty():
		return
	var bs: Array = await pt._train("a_ammo_bearer")
	pt._log("bearer_trained_click", not bs.is_empty())
	if bs.is_empty():
		return
	var b: Dictionary = bs[0]
	var lead = pt._w().get_e(int(sq_ids[0]))
	var sq := int(lead.get("squad", -1))
	pt._log("bearer_full_load", int(b.get("bearer_load", AmmoBearer.load_max(String(b.def)))) == 3000, AmmoBearer.load_line(b))
	# join: the card button when present (SQUAD61 CR), else the command
	pt._log("bearer_select_click", await pt._g5_select(int(b.id)))
	await pt._wait(0.3)
	var via := "button"
	if await pt._click_button("Join squad"):
		await pt._wait(0.3)
		await pt._g6_rclick(pt._to_screen(lead.pos))
	else:
		via = "command (Join squad button pending SQUAD61 CR)"
		pt._w().submit({"type": "join_squad", "issuer": 0, "unit_ids": [int(b.id)], "squad_unit_id": int(lead.id)})
	var joined: bool = await pt._wait_until(func(): return int(b.get("squad", -1)) == sq, 5.0)
	pt._log("bearer_joined_squad", joined, "via %s squad=%d" % [via, sq])
	await pt._shot("bearer61_01_joined")
	# march the squad out of the base supply radius; the bearer follows on its own
	var hq: Vector2 = pt._hq().pos
	var goal := Vector2(clampf(hq.x + 22.0, 2.0, float(pt._w().map.w) - 2.0), clampf(hq.y + 6.0, 2.0, float(pt._w().map.h) - 2.0))
	pt._w().submit({"type": "move", "issuer": 0, "unit_ids": sq_ids, "target": goal})
	var there: bool = await pt._wait_until(func():
		var m := _members(pt, sq)
		var c := Vector2.ZERO
		for e in m:
			c += Vector2(e.pos)
		return not m.is_empty() and (c / float(m.size())).distance_to(goal) < 3.0, 60.0)
	var mem := _members(pt, sq)
	var cen := Vector2.ZERO
	for e in mem:
		cen += Vector2(e.pos)
	cen /= float(maxi(mem.size(), 1))
	await pt._wait(3.0)
	pt._log("bearer_follows", there and Vector2(b.pos).distance_to(cen) < 5.0, "dist=%.1f" % Vector2(b.pos).distance_to(cen))
	pt._mv().center_camera_on(b.pos)
	await pt._shot("bearer61_02_following")
	# firefight stand-in: magazines down to 10%
	for e in mem:
		e.ammo = int(0.1 * float(Content.unit(String(e.def)).get("ammo_max", 0)))
	pt._log("bearer_squad_low", _low(mem) == mem.size(), "low=%d of %d" % [_low(mem), mem.size()])
	var l0 := int(b.bearer_load)
	var done: bool = await pt._wait_until(func(): return _low(_members(pt, sq)) == 0 or int(b.bearer_load) <= 0, 20.0)
	await pt._shot("bearer61_03_restocked")
	var mem2 := _members(pt, sq)
	pt._log("bearer_restocked_squad", done and int(b.bearer_load) < l0, "low_left=%d load %d -> %d (%s)" % [_low(mem2), l0, int(b.bearer_load), AmmoBearer.load_line(b)])
	# empty now: it walks back to the base supply point on its own (follow the camera)
	pt._mv().center_camera_on(b.pos)
	await pt._wait(0.4)
	pt._log("bearer_select_inspector_click", await pt._g5_select(int(b.id)))
	await pt._wait(0.5)
	await pt._shot("bearer61_04_inspector")
	var back: bool = await pt._wait_until(func(): return int(b.get("bearer_load", 0)) >= 3000, 60.0)
	pt._log("bearer_refilled_at_base", back, AmmoBearer.load_line(b))
	pt._mv().center_camera_on(b.pos)
	await pt._shot("bearer61_05_refilled")
