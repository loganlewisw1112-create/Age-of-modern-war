extends RefCounted
## G7.1 J7 horror atmosphere (Last Protocol). Silence before a big wave, night eyes, tide songs,
## bodies on display. Presentation reads board(); sim owns the state. Numbers PROVISIONAL.

const KEY := "horror71"
const VER := 1
const Director71 = preload("res://sim/systems/director71.gd")


static func R() -> Dictionary:
	var c = Content.rules().get("g71_horror", {})
	return c if c is Dictionary else {}


static func active(w: SimWorld) -> bool:
	return w.sys_state.has("lp")


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {
			"ver": VER,
			"silence": false,
			"silence_until": -1,
			"silence_band": "",
			"night_eyes": false,
			"tide_song": 0.0,
			"bodies": [],
		}
		w.sys_state[KEY] = s
	return s


static func board(w: SimWorld) -> Dictionary:
	if not active(w):
		return {}
	var s := _st(w)
	return {
		"silence": bool(s.silence),
		"night_eyes": bool(s.night_eyes),
		"tide_song": float(s.tide_song),
		"bodies_n": (s.bodies as Array).size(),
	}


static func start_silence(w: SimWorld, secs: float = -1.0) -> void:
	var s := _st(w)
	var dur := secs if secs > 0.0 else float(R().get("silence_s", 8.0))
	s.silence = true
	s.silence_until = w.tick + int(ceil(dur * float(SimWorld.TICK_RATE)))
	w.emit("Horror71Silence", {"secs": dur})


static func set_night(w: SimWorld, on: bool) -> void:
	_st(w).force_night = on


static func display_body(w: SimWorld, pos: Vector2, src_id: int = -1) -> void:
	var s := _st(w)
	var bodies: Array = s.bodies
	var cap := int(R().get("bodies_max", 6))
	if bodies.size() >= cap:
		return
	bodies.append({"pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)], "id": src_id, "tick": w.tick})
	s.bodies = bodies
	w.emit("Horror71Body", {"pos": pos, "id": src_id})


static func tick(w: SimWorld) -> void:
	if not active(w):
		return
	var s := _st(w)
	var lp = w.sys_state.lp
	var dread := float(lp.get("dread", 0.0))
	var band := Director71.band(dread)
	if not bool(s.silence) and band != String(s.get("silence_band", "")):
		if band in ["mixed", "siege"] and dread >= float(R().get("silence_at", 0.42)):
			start_silence(w)
			s.silence_band = band
	if bool(s.silence) and w.tick >= int(s.silence_until):
		s.silence = false
		w.emit("Horror71SilenceEnd", {})
	var night := bool(s.get("force_night", false)) or dread >= float(R().get("night_dread", 0.9))
	var eyes := night and dread >= float(R().get("eyes_at", 0.35))
	if eyes != bool(s.night_eyes):
		s.night_eyes = eyes
		w.emit("Horror71NightEyes", {"on": eyes})
	var song := snappedf(clampf(dread, 0.0, 1.0), 0.01)
	if not is_equal_approx(song, float(s.tide_song)):
		s.tide_song = song
	var chance := float(R().get("body_chance", 0.08))
	for ev in w.events:
		if String(ev.get("type", "")) != "EntityDestroyed":
			continue
		if int(ev.get("owner", -1)) != int(lp.fid):
			continue
		if String(ev.get("kind", "")) != "unit":
			continue
		var id := int(ev.get("id", 0))
		if ((w.tick * 17 + id * 31) % 1000) < int(chance * 1000.0):
			var pos = ev.get("pos", Vector2.ZERO)
			display_body(w, Vector2(pos) if typeof(pos) == TYPE_VECTOR2 else Vector2.ZERO, id)
