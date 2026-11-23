extends RefCounted
## G7.1 E1 end-battle atmosphere (Last Protocol). Flares, camera-shake requests, soundscape intensity,
## heat-haze / ash flags for presentation. Numbers PROVISIONAL.

const KEY := "atmo71"
const VER := 1


static func R() -> Dictionary:
	var c = Content.rules().get("g71_atmo", {})
	return c if c is Dictionary else {}


static func active(w: SimWorld) -> bool:
	return w.sys_state.has("lp")


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {
			"ver": VER,
			"shake": 0.0,
			"haze": false,
			"ash": false,
			"sound": 0.0,
			"flares": [],
		}
		w.sys_state[KEY] = s
	return s


static func board(w: SimWorld) -> Dictionary:
	if not active(w):
		return {}
	var s := _st(w)
	return {
		"shake": float(s.shake),
		"haze": bool(s.haze),
		"ash": bool(s.ash),
		"sound": float(s.sound),
		"flares_n": (s.flares as Array).size(),
	}


static func request_shake(w: SimWorld, amount: float) -> void:
	var s := _st(w)
	s.shake = maxf(float(s.shake), snappedf(clampf(amount, 0.0, 1.0), 0.01))


static func drop_flare(w: SimWorld, pos: Vector2, secs: float = -1.0) -> void:
	var s := _st(w)
	var dur := secs if secs > 0.0 else float(R().get("flare_s", 12.0))
	var flares: Array = s.flares
	flares.append({
		"pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)],
		"until": w.tick + int(ceil(dur * float(SimWorld.TICK_RATE))),
	})
	if flares.size() > int(R().get("flares_max", 8)):
		flares.pop_front()
	s.flares = flares
	w.emit("Atmo71Flare", {"pos": pos, "secs": dur})


static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	var s := _st(w)
	var dread := float(w.sys_state.lp.get("dread", 0.0))
	s.sound = snappedf(clampf(dread, 0.0, 1.0), 0.01)
	s.haze = dread >= float(R().get("haze_at", 0.55))
	s.ash = dread >= float(R().get("ash_at", 0.7))
	# Decay shake.
	if float(s.shake) > 0.0:
		s.shake = maxf(float(s.shake) - float(R().get("shake_decay", 0.04)), 0.0)
	# Expire flares.
	var keep := []
	for f in s.flares:
		if int(f.get("until", 0)) > w.tick:
			keep.append(f)
	s.flares = keep
	# Auto-flare near assault waves.
	for ev in w.events:
		var t := String(ev.get("type", ""))
		if t == "AssaultWave" or t == "LpBreakingPoint":
			var center = w.sys_state.lp.base.center if w.sys_state.lp.has("base") else Vector2.ZERO
			var ox := float((w.tick * 13) % 41) - 20.0
			var oy := float((w.tick * 17) % 41) - 20.0
			drop_flare(w, Vector2(center) + Vector2(ox, oy))
			request_shake(w, 0.35 if t == "AssaultWave" else 0.7)
		elif t == "Damage" and bool(ev.get("indirect", false)):
			request_shake(w, 0.15)
