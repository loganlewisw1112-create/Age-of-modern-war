extends Node2D
## G7.1 DAMAGE71 (J2 + G1 combat medics+). PRESENTATION ONLY: reads snap.g71.care71 and never touches the sim.
## Draws the triage tag a medic tied on each casualty (Care71 c71tag: green / yellow / red / black) as a small coloured
## card above the soldier, a morphine "M" on the black-tagged who were made comfortable, and a pulsing ring on a
## casualty calling for a medic (untagged and down). Only the casualty list is walked (Care71 state cas), never all
## entities.
## Provider (registered here on load): {"t": [[id, x, y, tag 0 none / 1 green / 2 yellow / 3 red / 4 black, flags]]},
##   flags bit 1 = morphine given, bit 2 = player-set tag. null off Last Protocol (no Care71 state: no work).
## Wiring (ORCH, match_view.gd, same as turret71_look): layer = TriageTags.new(); z_index above the entity layer;
## each frame layer.refresh(snap).
const RenderSnap = preload("res://sim/render_snap.gd")
const KEY := "care71"
const TAG_I := {"": 0, "green": 1, "yellow": 2, "red": 3, "black": 4}
const COLS := [Color(0, 0, 0, 0), Color(0.2, 0.8, 0.25), Color(0.95, 0.82, 0.15), Color(0.9, 0.12, 0.1), Color(0.05, 0.05, 0.05)]

var _rows: Array = []
var _t := 0.0

## The provider is static, shared by every instance: only the newest instance unregisters it. A new match builds the
## new MatchView (and this layer) before the old one leaves the tree, and the old layer's _exit_tree wiped the new
## registration (pt71_gore71: no care71 in snap.g71, no card drawn; same fix as FIRES71-5 in fires71_view.gd).
static var _reg_owner := 0


func _init() -> void:
	_reg_owner = get_instance_id()
	RenderSnap.register_g71(KEY, Callable(get_script(), "snap"))


func _exit_tree() -> void:
	if _reg_owner != get_instance_id():
		return
	RenderSnap.unregister_g71(KEY)


func rows_n() -> int:
	return _rows.size()


## Snapshot provider (sim thread, read-only).
static func snap(w, _sn: Dictionary):
	var st = w.sys_state.get("care71")
	if st == null:
		return null
	var out := []
	var cas: Dictionary = st.get("cas", {})
	var fids: Array = cas.keys()
	fids.sort()
	for fid in fids:
		var ids: Array = (cas[fid] as Dictionary).keys()
		ids.sort()
		for id in ids:
			var e = w.entities.get(id)
			if e == null:
				continue
			var fl := 0
			if e.has("c71mor"):
				fl |= 1
			if e.has("c71ovr"):
				fl |= 2
			var p := Vector2(e.pos)
			out.append([int(id), p.x, p.y, int(TAG_I.get(String(e.get("c71tag", "")), 0)), fl])
	return {"t": out}


func refresh(snap_d: Dictionary) -> void:
	var d = (snap_d.get("g71", {}) as Dictionary).get(KEY)
	_rows = [] if d == null else d.get("t", [])
	visible = not _rows.is_empty()
	if visible:
		queue_redraw()


func _process(delta: float) -> void:
	_t += delta


static func _iso(x: float, y: float) -> Vector2:
	return Vector2((x - y) * 32.0, (x + y) * 16.0)


func _draw() -> void:
	for r in _rows:
		var p := _iso(float(r[1]), float(r[2])) + Vector2(0, -16)
		var tg := int(r[3])
		var fl := int(r[4])
		if tg == 0:   # untagged casualty: calling for a medic
			var ph := fmod(_t * 0.9 + float(int(r[0]) % 5) * 0.2, 1.0)
			draw_arc(p + Vector2(0, 12), 5.0 + ph * 10.0, 0.0, TAU, 16, Color(1.0, 0.3, 0.25, 0.8 * (1.0 - ph)), 1.5)
			continue
		# beside the G7 wound marker (red-cross disc + hp bar centred on p), not under it: it hid the card (pt71_gore71 shot)
		var c := p + Vector2(21, 0)
		var rc := Rect2(c + Vector2(-5, -4), Vector2(10, 8))
		draw_rect(rc.grow(1.0), Color(0.08, 0.08, 0.08, 0.85))
		draw_rect(rc, Color(0.95, 0.93, 0.85))
		draw_rect(rc.grow(-1.5), COLS[tg])
		draw_line(c + Vector2(-5, -4), c + Vector2(-8, -7), Color(0.8, 0.78, 0.7), 1.0)   # the tie
		if fl & 2:
			draw_rect(rc.grow(2.0), Color(1, 1, 1, 0.9), false, 1.0)   # player-set tag
		if fl & 1:   # morphine: "M" on the forehead, the old field practice
			var m := c + Vector2(7, -2)
			draw_polyline(PackedVector2Array([m + Vector2(0, 4), m, m + Vector2(2, 2), m + Vector2(4, 0), m + Vector2(4, 4)]), Color(0.9, 0.1, 0.1), 1.0)
