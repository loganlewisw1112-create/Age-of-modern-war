extends RefCounted
## G6 effect rules (owner: VIEW6). Pure mapping from sim events (+ the render snapshot for positions)
## to effect specs that fx_layer draws: {g6: kind, a: world Vector2, b: world Vector2, life, delay, size,
## color, own_only}. Kinds: laser, net, jam, sonar, mine_blast, line_charge, chute, shimmer, nanite,
## assimilate, ciws, strike, train_smoke. fx_layer culls by fog (own_only effects skip the fog test but
## are made only for the owner's side) and by the camera. No class_name: preload it.

const KINDS := ["laser", "net", "jam", "sonar", "mine_blast", "line_charge", "chute", "shimmer", "nanite",
	"assimilate", "ciws", "strike", "train_smoke"]
const C_LASER := Color(1.0, 0.25, 0.3)
const C_LASER_M := Color(0.45, 0.9, 1.0)
const C_JAM := Color(0.75, 0.55, 1.0)
const C_SONAR := Color(0.35, 0.95, 0.85)
const C_NANITE := Color(0.45, 1.0, 0.55)
const C_ASSIM := Color(0.55, 0.95, 1.0)
const C_NET := Color(0.92, 0.88, 0.7)
const C_FIRE := Color(1.0, 0.7, 0.25)


## World position of entity id from the snapshot (units: packed arrays; statics: dict); null = unknown.
static func pos_of(sn: Dictionary, id: int):
	var ids: PackedInt32Array = sn.get("ids", PackedInt32Array())
	var k := ids.find(id)
	if k >= 0:
		return (sn.pos as PackedVector2Array)[k]
	var st = (sn.get("statics", {}) as Dictionary).get(id)
	return Vector2(st.pos) if st is Dictionary else null


static func _v(p) -> Vector2:
	if p is Vector2:
		return p
	if p is Vector2i:
		return Vector2(p) + Vector2(0.5, 0.5)
	if p is Array and (p as Array).size() >= 2:
		return Vector2(float(p[0]) + 0.5, float(p[1]) + 0.5)
	return Vector2(-1, -1)


static func _fx(kind: String, a: Vector2, b: Vector2, life: float, col: Color, size := 1.0, delay := 0.0, own := false) -> Dictionary:
	return {"g6": kind, "a": a, "b": b, "life": life, "delay": delay, "size": size, "color": col, "own_only": own}


## True when weapon wid is a beam weapon (class "laser" / "beam", or a laser id): drawn as a beam, not a tracer.
static func is_laser(wid: String) -> bool:
	var wd: Dictionary = Content.weapon(wid) if wid != "" else {}
	var cls := String(wd.get("class", ""))
	return cls == "laser" or cls == "beam" or wid.contains("laser")


## Effect specs for one sim event. pf / allies decide own-only effects (cloak shimmer, sonar pings).
static func from_event(ev: Dictionary, sn: Dictionary, pf: int, allies: Array) -> Array:
	var out: Array = []
	var own := func(o) -> bool: return int(o) == pf or allies.has(int(o))
	match String(ev.get("type", "")):
		"ShotFired":
			if is_laser(String(ev.get("weapon", ""))) and ev.get("from") is Vector2 and ev.get("to") is Vector2:
				var mac := String(Content.weapon(String(ev.weapon)).get("faction", "")) == "machine"
				out.append(_fx("laser", ev.from, ev.to, 0.28, C_LASER_M if mac else C_LASER, 2.0))
		"DroneCaptured":
			var at = ev.get("pos", pos_of(sn, int(ev.get("id", -1))))
			var src = pos_of(sn, int(ev.get("net", -1)))
			if at != null:
				out.append(_fx("net", src if src != null else _v(at), _v(at), 0.9, C_NET, 1.0))
		"DroneJammed", "GuidedJammed", "LoiterJammed":
			var p := _v(ev.get("pos"))
			if p.x >= 0.0:
				out.append(_fx("jam", p, p, 0.7, C_JAM, 1.0))
		"SonarContact":
			var by := int(ev.get("by", -1))
			if own.call(by):
				var p2 := _v(ev.get("cell"))
				out.append(_fx("sonar", p2, p2, 1.4, C_SONAR, 3.0, 0.0, true))
				out.append(_fx("sonar", p2, p2, 1.4, C_SONAR, 3.0, 0.35, true))
		"MineTriggered", "ChargeDetonated":
			var p3 := _v(ev.get("cell", ev.get("pos")))
			out.append(_fx("mine_blast", p3, p3, 0.9, C_FIRE, 1.4))
		"MineCleared":
			if String(ev.get("cause", "")) != "line_charge":
				var p4 := _v(ev.get("cell"))
				out.append(_fx("mine_blast", p4, p4, 0.6, C_FIRE, 0.7))
		"LineCharge":
			var cells: Array = ev.get("cells", [])
			if not cells.is_empty():
				var a0 := _v(cells[0])
				var a1 := _v(cells[cells.size() - 1])
				out.append(_fx("line_charge", a0, a1, 0.6, C_NET, 1.0))
				for i in cells.size():
					var c := _v(cells[i])
					out.append(_fx("mine_blast", c, c, 0.7, C_FIRE, 1.0, 0.45 + 0.06 * i))
		"Airdrop", "PalletDropped":
			var p5 := _v(ev.get("cell"))
			var n: int = maxi(1, (ev.get("ids", [0]) as Array).size()) if ev.has("ids") else 1
			for i in mini(n, 6):
				var j := Vector2(0.45 * float((i * 37) % 5 - 2), 0.35 * float((i * 53) % 5 - 2))
				out.append(_fx("chute", p5 + j, p5 + j, 1.6, Color(0.85, 0.85, 0.78), 1.0, 0.12 * i))
		"CloakChanged":
			if own.call(ev.get("owner", -1)):
				var p6 = pos_of(sn, int(ev.get("id", -1)))
				if p6 != null:
					out.append(_fx("shimmer", p6, p6, 0.8, C_ASSIM, 1.0, 0.0, true))
		"NaniteHeal":
			var p7 = pos_of(sn, int(ev.get("src", -1)))
			if p7 != null:
				out.append(_fx("nanite", p7, p7, 0.9, C_NANITE, float(clampi(int(ev.get("n", 1)), 1, 8))))
		"AssimilateStarted", "WreckAssimilated":
			var u = pos_of(sn, int(ev.get("unit", -1)))
			var wr = pos_of(sn, int(ev.get("wreck", -1)))
			if u != null:
				out.append(_fx("assimilate", wr if wr != null else u, u, 1.6 if String(ev.type) == "AssimilateStarted" else 0.7, C_ASSIM,
					1.0 if String(ev.type) == "AssimilateStarted" else 2.0))
		"CiwsKill", "CiwsIntercept":
			var src2 = pos_of(sn, int(ev.get("ciws", -1)))
			var at2 := _v(ev.get("pos"))
			if at2.x >= 0.0:
				out.append(_fx("ciws", src2 if src2 != null else at2, at2, 0.35, C_LASER, 1.0))
		"StrikeImpact":
			var p8 := _v(ev.get("pos"))
			out.append(_fx("strike", p8, p8, 1.0, C_FIRE, 1.6))
	return out


## Per-tick train smoke: moving rail-class units in the snapshot (b_armored_train) -> one puff each.
static func train_smoke(sn: Dictionary) -> Array:
	var out: Array = []
	var defs: PackedStringArray = sn.get("defs", PackedStringArray())
	var rail := PackedInt32Array()
	for i in defs.size():
		if String(Content.unit(defs[i]).get("move_class", "")) == "rail":
			rail.append(i)
	if rail.is_empty():
		return out
	var def_a: PackedInt32Array = sn.def
	var fl: PackedInt32Array = sn.flags
	for i in int(sn.get("n", 0)):
		if rail.has(def_a[i]) and fl[i] & 1:  # RenderSnap.FLAG_MOVING
			var p: Vector2 = (sn.pos as PackedVector2Array)[i]
			out.append(_fx("train_smoke", p, p + Vector2(-0.6, -0.6), 1.8, Color(0.32, 0.31, 0.3), 1.0))
	return out
