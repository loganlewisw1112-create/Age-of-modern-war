extends Node2D
## G7.1 I6 hive network draw: nests, relays, isolation marks, heartbeat pulse.
## Snapshot provider "hive71"; null when inactive. Never mv.world from refresh.

const RenderSnap = preload("res://sim/render_snap.gd")
const KEY := "hive71"

static var _reg_owner := 0
static var _cache: Variant = null
static var _cache_tick := -999
const CACHE_EVERY := 4   # rebuild at most every N sim ticks (nests are nearly static)

var mv: Node = null
var _nests: Array = []
var _relays: Array = []
var _iso: Dictionary = {}
var _pulse := false
var _sig := -1


func _init() -> void:
	_reg_owner = get_instance_id()
	RenderSnap.register_g71(KEY, Callable(get_script(), "snap"))


func _exit_tree() -> void:
	if _reg_owner == get_instance_id():
		RenderSnap.unregister_g71(KEY)


static func snap(w, _sn: Dictionary):
	if not w.sys_state.has("lp"):
		return null
	if _cache != null and w.tick - _cache_tick < CACHE_EVERY:
		return _cache
	var st = w.sys_state.get("hive71")
	if st == null or not (st is Dictionary):
		_cache = null
		_cache_tick = w.tick
		return null
	var nests: Array = []
	var relays: Array = []
	for id in (st.get("nests", {}) as Dictionary).keys():
		var n: Dictionary = st.nests[id]
		nests.append({"id": id, "pos": n.get("pos", [0, 0]), "alive": bool(n.get("alive", true))})
	for id in (st.get("relays", {}) as Dictionary).keys():
		var r: Dictionary = st.relays[id]
		relays.append({
			"id": id,
			"pos": r.get("pos", [0, 0]),
			"alive": bool(r.get("alive", true)),
			"links": r.get("links", []),
		})
	if nests.is_empty() and relays.is_empty():
		_cache = null
		_cache_tick = w.tick
		return null
	_cache = {
		"nests": nests,
		"relays": relays,
		"iso": (st.get("isolated", {}) as Dictionary).duplicate(),
		"pulse": bool(st.get("pulse", false)),
	}
	_cache_tick = w.tick
	return _cache


func setup(view: Node) -> void:
	mv = view
	z_index = 14


func refresh(snap: Dictionary) -> void:
	if snap.is_empty() or mv == null:
		return
	var row = (snap.get("g71", {}) as Dictionary).get(KEY)
	if row == null:
		if not _nests.is_empty() or not _relays.is_empty():
			_nests = []
			_relays = []
			_iso = {}
			_pulse = false
			_sig = -1
			queue_redraw()
		return
	var nests: Array = row.get("nests", [])
	var relays: Array = row.get("relays", [])
	var pulse := bool(row.get("pulse", false))
	var iso: Dictionary = row.get("iso", {})
	var sig := nests.size() * 17 + relays.size() * 13 + iso.size() * 7 + (1 if pulse else 0)
	if sig == _sig:
		return
	_sig = sig
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
