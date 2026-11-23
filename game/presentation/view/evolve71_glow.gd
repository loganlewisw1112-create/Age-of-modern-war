extends Node2D
## G9 HIVE9: team-coloured evolve rim on Machine units (reads snap g71 evolve9). PROVISIONAL.

const RenderSnap = preload("res://sim/render_snap.gd")
const Evolve71 = preload("res://sim/systems/evolve71.gd")
const KEY := "evolve9"

static var _reg_owner := 0
static var _cache: Variant = null
static var _cache_tick := -999

var mv: Node = null
var _marks: Array = []
var _sig := -1


func _init() -> void:
	_reg_owner = get_instance_id()
	RenderSnap.register_g71(KEY, Callable(get_script(), "snap"))


func _exit_tree() -> void:
	if _reg_owner == get_instance_id():
		RenderSnap.unregister_g71(KEY)


static func snap(w, sn: Dictionary):
	if not w.sys_state.has("lp"):
		return null
	if _cache != null and w.tick - _cache_tick < 3:
		return _cache
	var Hive9 = load("res://sim/systems/hive9.gd")
	var R9: Dictionary = Hive9.R()
	var base_a := float(R9.get("glow_alpha_base", 0.22))
	var per_a := float(R9.get("glow_alpha_per_stage", 0.12))
	var marks: Array = []
	var ids: PackedInt32Array = sn.get("ids", PackedInt32Array())
	var poss: PackedVector2Array = sn.get("pos", PackedVector2Array())
	for i in ids.size():
		var id := int(ids[i])
		var e = w.entities.get(id)
		if e == null or String(e.get("kind", "")) != "unit":
			continue
		var o := int(e.get("owner", -1))
		if not w.factions.has(o) or String(w.factions[o].get("faction_def", "")) != "machine":
			continue
		var st := int(e.get("g71_evolve", 0))
		if st <= 0:
			continue
		var ipos: Vector2 = poss[i] if i < poss.size() else Vector2(e.pos)
		marks.append({
			"id": id,
			"pos": [snappedf(ipos.x, 0.01), snappedf(ipos.y, 0.01)],
			"owner": o,
			"stage": st,
			"alpha": snappedf(base_a + float(st) * per_a, 0.01),
		})
	_cache = {"marks": marks, "stage": Evolve71.stage(w)}
	_cache_tick = w.tick
	return _cache


func setup(view: Node) -> void:
	mv = view
	z_index = 16


func refresh(snap: Dictionary) -> void:
	if snap.is_empty() or mv == null:
		return
	var row = (snap.get("g71", {}) as Dictionary).get(KEY)
	if row == null:
		if not _marks.is_empty():
			_marks = []
			_sig = -1
			queue_redraw()
		return
	var marks: Array = row.get("marks", [])
	var sig := marks.size() * 11 + int(row.get("stage", 0))
	if sig == _sig:
		return
	_sig = sig
	_marks = marks
	queue_redraw()


func _draw() -> void:
	if mv == null:
		return
	for m in _marks:
		var p := _p(m.get("pos", [0, 0]))
		var col: Color = mv.team_color(int(m.get("owner", 0)))
		col.a = float(m.get("alpha", 0.25))
		var r := 10.0 + float(int(m.get("stage", 0))) * 1.5
		draw_arc(p, r, 0.0, TAU, 24, col, 2.0)
		draw_circle(p, 3.0, Color(col.r, col.g, col.b, col.a * 0.6))


func _p(pos) -> Vector2:
	if pos is Array and pos.size() >= 2:
		return mv.world_to_screen(Vector2(float(pos[0]), float(pos[1])))
	return Vector2.ZERO