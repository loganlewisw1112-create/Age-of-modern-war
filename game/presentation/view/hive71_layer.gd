extends Node2D
## G7.1 I6 hive network draw: nests, relays, isolation marks, heartbeat pulse. Never mv.world.

var mv: Node = null
var _nests: Array = []
var _relays: Array = []
var _iso: Dictionary = {}
var _pulse := false


func setup(view: Node) -> void:
	mv = view
	z_index = 14


func refresh(snap: Dictionary) -> void:
	if snap.is_empty() or mv == null:
		return
	if not mv.has_method("world_readable") or not mv.world_readable():
		return
	var w = mv.get("_world")
	if w == null:
		return
	var Hive71 = preload("res://sim/systems/hive71.gd")
	var b: Dictionary = Hive71.board(w)
	var st = w.sys_state.get("hive71")
	var nests: Array = []
	var relays: Array = []
	var iso := {}
	var pulse := bool(b.get("pulse", false))
	if st is Dictionary:
		for id in (st.get("nests", {}) as Dictionary).keys():
			var n: Dictionary = st.nests[id]
			nests.append({"id": id, "pos": n.get("pos", [0, 0]), "alive": bool(n.get("alive", true))})
		for id in (st.get("relays", {}) as Dictionary).keys():
			var r: Dictionary = st.relays[id]
			relays.append({"id": id, "pos": r.get("pos", [0, 0]), "alive": bool(r.get("alive", true)), "links": r.get("links", [])})
		iso = (st.get("isolated", {}) as Dictionary).duplicate()
	if nests.size() == _nests.size() and relays.size() == _relays.size() and pulse == _pulse and iso.size() == _iso.size():
		return
	_nests = nests
	_relays = relays
	_iso = iso
	_pulse = pulse
	queue_redraw()


func _draw() -> void:
	if mv == null:
		return
	# Relays + links first.
	for r in _relays:
		var rp := _p(r.get("pos", [0, 0]))
		var col := Color(0.55, 0.2, 0.85, 0.85) if bool(r.get("alive", true)) else Color(0.25, 0.15, 0.3, 0.4)
		draw_circle(rp, 5.0, col)
		for lid in r.get("links", []):
			for n in _nests:
				if String(n.get("id", "")) == String(lid):
					draw_line(rp, _p(n.get("pos", [0, 0])), col, 1.5)
	for n in _nests:
		var np := _p(n.get("pos", [0, 0]))
		var alive := bool(n.get("alive", true))
		var iso := _iso.has(String(n.get("id", "")))
		var col := Color(0.9, 0.25, 0.55, 0.9) if alive else Color(0.3, 0.2, 0.25, 0.4)
		if iso:
			col = Color(0.4, 0.4, 0.45, 0.7)
		draw_circle(np, 8.0 if _pulse else 6.5, col)
		draw_arc(np, 11.0, 0.0, TAU, 16, Color(col.r, col.g, col.b, 0.5), 1.5)


func _p(pos) -> Vector2:
	if pos is Array and pos.size() >= 2:
		return mv.world_to_screen(Vector2(float(pos[0]), float(pos[1])))
	return Vector2.ZERO
