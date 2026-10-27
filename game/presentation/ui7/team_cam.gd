extends Control
## G7 OPSUI7: team cam (master scope 6.11): the strike team's overwatch feed (CNOPS7's overwatch drone, CnOps7.drone_of)
## or a helmet cam on one operator, with call signs, a timestamp / grid strip and radio subtitles. Same rendering path
## and look as DRONE7's drone camera: a SubViewport sharing the main view's world_2d with its own Camera2D, through
## presentation/view/drone_cam.gdshader (greyscale + link noise), then a phosphor overlay. Radio subtitles are the
## hub's radio log (CnBark / CnBuddyCallout / CnOverwatchWarning / CnFireSupport / relief / deployment events turned
## into short lines by ops_panel.gd radio_line()). Display only: it never writes the sim.

const S = preload("res://presentation/ui7/ops_style.gd")
const D = preload("res://presentation/ui7/ops_data.gd")
const CN = preload("res://sim/systems/counter_nanite.gd")
const CnOps7 = preload("res://sim/systems/cn_ops7.gd")
const ShaderRes = preload("res://presentation/view/drone_cam.gdshader")

var hub = null
var tid := -1
var source := "overwatch"     # overwatch | helmet
var member_ix := 0
var feed: Dictionary = {}     # what the feed shows now: {source, id, cs, pos, live, grid} (tests / playtest)
var frames := 0               # overlay frames drawn (playtest evidence)
var _sub: SubViewport
var _cam: Camera2D
var _tex: TextureRect
var _mat: ShaderMaterial
var _over: Control
var _t := 0.0


func _ready() -> void:
	name = "TeamCam"
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	_sub = SubViewport.new()
	_sub.size = Vector2i(640, 360)
	_sub.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	if hub != null and hub.mv != null and hub.mv.is_inside_tree():
		_sub.world_2d = hub.mv.get_viewport().world_2d
	add_child(_sub)
	_cam = Camera2D.new()
	_sub.add_child(_cam)
	_cam.enabled = true
	_tex = TextureRect.new()
	_tex.texture = _sub.get_texture()
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = ShaderRes
	_tex.material = _mat
	add_child(_tex)
	_over = Control.new()
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.draw.connect(_draw_overlay)
	add_child(_over)
	resized.connect(_on_resized)


func _on_resized() -> void:
	if _sub != null and size.x >= 16.0 and size.y >= 16.0:
		_sub.size = Vector2i(int(size.x), int(size.y))


func set_team(id: int) -> void:
	if id != tid:
		member_ix = 0
	tid = id
	refresh()


func set_source(s: String) -> void:
	source = s
	refresh()


func next_member() -> void:
	member_ix += 1
	refresh()


## What the feed follows: {source, id, cs, pos, live}. Overwatch falls back to a helmet cam when there is no drone.
static func pick(w: SimWorld, tid_: int, src: String, mix: int) -> Dictionary:
	var t = CN.team(w, tid_) if w != null else null
	if t == null:
		return {"source": "none", "id": -1, "cs": "", "pos": Vector2.ZERO, "live": false}
	if src == "overwatch":
		var did := CnOps7.drone_of(w, tid_)
		var de = w.entities.get(did) if did > 0 else null
		if de != null:
			return {"source": "overwatch", "id": did, "cs": "OVERWATCH %s" % String(t.name).to_upper(), "pos": Vector2(de.pos), "live": true}
	var mem: Array = []
	for id in CN.live_members(w, t):
		if w.entities.has(int(id)):
			mem.append(int(id))
	if mem.is_empty():
		var at = CnOps7.anchor(w, t)
		return {"source": "helmet", "id": -1, "cs": "%s (mounted)" % String(t.name).to_upper(), "pos": at if at != null else Vector2.ZERO, "live": at != null}
	var uid: int = mem[posmod(mix, mem.size())]
	var e: Dictionary = w.entities[uid]
	return {"source": "helmet", "id": uid, "cs": String(e.get("call_sign", "OPERATOR")), "pos": Vector2(e.pos), "live": true}


func refresh() -> void:
	var w: SimWorld = hub.world() if hub != null else null
	feed = pick(w, tid, source, member_ix)
	if w != null:
		feed.grid = D.grid_ref(w, Vector2(feed.pos))
	if _sub != null and _sub.world_2d == null and hub != null and hub.mv != null and hub.mv.is_inside_tree():
		_sub.world_2d = hub.mv.get_viewport().world_2d


func _process(delta: float) -> void:
	if not is_visible_in_tree() or _cam == null:
		return
	_t += delta
	var w: SimWorld = hub.world() if hub != null else null
	if w != null and int(feed.get("id", -1)) > 0 and w.entities.has(int(feed.id)):
		feed.pos = Vector2(w.entities[int(feed.id)].pos)
	if hub != null and hub.mv != null and bool(feed.get("live", false)):
		_cam.position = hub.mv.world_to_screen(Vector2(feed.pos))
		_cam.zoom = Vector2.ONE * (1.5 if String(feed.source) == "overwatch" else 2.6)
	_mat.set_shader_parameter("mode", 0)
	_mat.set_shader_parameter("noise_amt", 0.06 if String(feed.get("source", "")) == "overwatch" else 0.12)
	_mat.set_shader_parameter("lost", 0.0 if bool(feed.get("live", false)) else 1.0)
	_mat.set_shader_parameter("t", _t)
	_over.queue_redraw()


func _draw_overlay() -> void:
	frames += 1
	var r := Rect2(Vector2.ZERO, _over.size)
	S.scanlines(_over, r, _t)
	S.brackets(_over, r.grow(-10.0), Color(S.PHOS, 0.8), 18.0)
	var live := bool(feed.get("live", false))
	var src := String(feed.get("source", "none"))
	var title := "NO FEED" if src == "none" else ("OVERWATCH FEED" if src == "overwatch" else "HELMET CAM")
	S.text(_over, Vector2(20, 30), title, S.AMBER, 15, true)
	S.text(_over, Vector2(20, 48), String(feed.get("cs", "")), S.PHOS, 13, true)
	var w: SimWorld = hub.world() if hub != null else null
	var clock := D.fmt_s(float(w.tick) / float(SimWorld.TICK_RATE)) if w != null else "--"
	var right := "GRID %s   T+%s" % [String(feed.get("grid", "--")), clock]
	S.text(_over, Vector2(r.size.x - S.text_w(right, 13) - 20.0, 30), right, S.PHOS, 13)
	if live and fmod(_t, 1.0) < 0.6:
		_over.draw_circle(Vector2(r.size.x - 30.0, 46.0), 5.0, S.RED)
		S.text(_over, Vector2(r.size.x - 70.0, 51.0), "REC", S.RED, 12, true)
	if not live:
		S.text(_over, r.size * 0.5 - Vector2(S.text_w("NO SIGNAL", 22, true) * 0.5, 0), "NO SIGNAL", S.RED, 22, true)
	else:
		var c := r.size * 0.5
		_over.draw_arc(c, 26.0, 0.0, TAU, 32, Color(S.PHOS, 0.5), 1.0)
		_over.draw_line(c - Vector2(40, 0), c - Vector2(12, 0), Color(S.PHOS, 0.6), 1.0)
		_over.draw_line(c + Vector2(12, 0), c + Vector2(40, 0), Color(S.PHOS, 0.6), 1.0)
	# radio subtitles (newest at the bottom, fading)
	var lines: Array = hub.radio_for(tid) if hub != null else []
	var y := r.size.y - 18.0
	var n := 0
	for i in range(lines.size() - 1, -1, -1):
		if n >= 4:
			break
		var ln: Dictionary = lines[i]
		var a := clampf(1.0 - float(n) * 0.22, 0.25, 1.0)
		var s := "%s: %s" % [String(ln.get("who", "")), String(ln.get("text", ""))]
		var tw := S.text_w(s, 14)
		_over.draw_rect(Rect2(Vector2((r.size.x - tw) * 0.5 - 8.0, y - 16.0), Vector2(tw + 16.0, 21.0)), Color(0, 0, 0, 0.55 * a))
		S.text(_over, Vector2((r.size.x - tw) * 0.5, y), s, Color(S.AMBER if String(ln.get("kind", "")) == "warn" else S.PHOS, a), 14)
		y -= 24.0
		n += 1
