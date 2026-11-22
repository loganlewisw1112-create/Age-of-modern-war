extends Node2D
## G7.1 ARMY71 view entry (attached by ORCH's presentation/view/g71_attach.gd, at "over_units").
## Hosts the ARMY71 presentation pieces so MatchView / HUD need no ARMY71 lines:
##   - B5 ammo panel (presentation/ui71/ammo_panel.gd): AmmoPanel71.attach(mv), mounts itself on the HUD root.
##   - D4 radio feed (presentation/ui71/radio_feed.gd): a subtitle Label on the HUD root, fed from
##     MatchView.world_events (the per-step sim events), for the local player's side.
##   - D4 hand signals: when a squad leader of ours calls contact / shift fire / takes over (the discipline71
##     radio71 events), a raised-arm signal and its word float over the squad for SIG_S seconds.
## Last Protocol only (roster 5A Q1): nothing mounts while the world has no discipline71 state, so skirmish shows and
## costs nothing. Display only: reads the world between steps, never writes it.
const AmmoPanel71 = preload("res://presentation/ui71/ammo_panel.gd")
const RadioFeed71 = preload("res://presentation/ui71/radio_feed.gd")
const Discipline71 = preload("res://sim/systems/discipline71.gd")
const SIG_S := 2.5
const SIG_MAX := 24
## radio71 key prefix -> [word, colour] of the hand signal
const SIGNALS := {
	"army71.contact_": ["CONTACT", Color(1.0, 0.82, 0.3)],
	"army71.shift_fire": ["SHIFT FIRE", Color(1.0, 0.45, 0.25)],
	"army71.nco_down": ["NCO DOWN", Color(0.95, 0.3, 0.3)],
}

const Crew71 = preload("res://sim/systems/crew71.gd")
const RenderSnap = preload("res://sim/render_snap.gd")
const SNAP_KEY := "army71"
const CREW_RESCAN := 60       # ticks between crew-id rescans in the snapshot provider

var mv: Node = null
var ammo: Node = null
var feed: Label = null
var sigs: Array = []          # [{pos: Vector2, word, col, t0}] live hand signals (tests read it)
var clashes: Array = []       # [{pos: Vector2, kind, t0}] I2 wall-walk melee (Melee71 events; tests / flow read it)
var crew: Dictionary = {}     # latest snap.g71.army71 {bz, bb, mk} (B3 crew marks)
var _on := false
var _sig_node: Node2D = null   # hand signals draw here, above the unit markers (z 6, absolute): gen 9 shots
var _t := 0.0

static var _crew_ids: Array = []
static var _crew_t := -100000
static var _pose_ids: Array = []   # members of the squads Discipline71 tracks (rescanned with the crews)
const NIGHT_LIGHT := 0.5          # Senses7 light below this = night: NVG / thermal gear shows on our soldiers
const CLASH_S := 0.8               # seconds a wall-walk melee clash mark lives (Melee71 events)
const CLASH_MAX := 32
const POSE_ZOOM := 0.55            # cover poses are drawn from this canvas zoom in (too small to read farther out)


## The newest layer owns the provider: the previous match's MatchView leaves the tree AFTER the next one's layer
## registered, and its unregister used to drop the live provider (flow army71 run 4: providers had no "army71").
static var _reg_owner := 0


func _init() -> void:
	_reg_owner = get_instance_id()
	RenderSnap.register_g71(SNAP_KEY, Callable(get_script(), "snap_army"))


func _exit_tree() -> void:
	if _reg_owner != get_instance_id():
		return
	RenderSnap.unregister_g71(SNAP_KEY)


## Snapshot provider (sim worker thread, read-only; null off LP). B3 crew marks for the view:
##   bz [[cx, cy, len, wid, ang, fpf 0/1]] beaten zones, bb [[ax, ay, ang, len, half_w]] backblast zones,
##   mk [[x, y, part]] .50 spotter marks on their targets. Crew ids are rescanned every CREW_RESCAN ticks.
static func snap_army(w, _sn: Dictionary):
	if not w.sys_state.has(Discipline71.KEY):
		return null
	if w.tick - _crew_t >= CREW_RESCAN or w.tick < _crew_t:
		var ids: Array = []
		var pids: Array = []
		var sq: Dictionary = (w.sys_state[Discipline71.KEY] as Dictionary).get("sq", {})
		for id in w.entities:
			var en: Dictionary = w.entities[id]
			if en.has("c71"):
				ids.append(int(id))
			if not sq.is_empty() and en.has("squad") and sq.has(str(en.squad)):
				pids.append(int(id))
		ids.sort()
		pids.sort()
		_crew_ids = ids
		_pose_ids = pids
		_crew_t = w.tick
	var bz: Array = []
	var bb: Array = []
	var mk: Array = []
	for id in _crew_ids:
		var e = w.entities.get(id)
		if e == null:
			continue
		var z: Dictionary = Crew71.beaten_zone(w, e)
		if not z.is_empty():
			bz.append([float(z.c[0]), float(z.c[1]), float(z.len), float(z.wid), float(z.ang), 1 if bool(z.fpf) else 0])
		var b: Dictionary = Crew71.backblast(w, e)
		if not b.is_empty():
			bb.append([float(b.a[0]), float(b.a[1]), float(b.ang), float(b.len), float(b.half_w)])
		var m: Dictionary = Crew71.spot_mark(w, e)
		if not m.is_empty():
			var t = w.entities.get(int(m.tid))
			if t != null:
				mk.append([float(t.pos.x), float(t.pos.y), String(m.get("part", ""))])
	# D4 cover poses (gen 10): po [[x, y, pose, ang, overwatch 0/1]] pose 1 hug / 2 peek / 3 bounding mover / 4 bounding overwatch
	# (e.f7_bw: the team that halts and covers); ang = toward the target for a peeker, else the facing.
	var po: Array = []
	var nv: Array = []   # G1 at night: [[x, y, facing, 1 thermal / 0 NVG]] for our squad soldiers with the gear
	var night := float((w.sys_state.get("senses7", {}) as Dictionary).get("light", 1.0)) < NIGHT_LIGHT
	for id in _pose_ids:
		var e = w.entities.get(id)
		if e == null:
			continue
		if night and (e.has("g71nvg") or bool(e.get("thermal", false))):
			nv.append([float(e.pos.x), float(e.pos.y), float(e.get("facing", 0.0)), 0 if e.has("g71nvg") else 1])
		var p := int(e.get("d71c", 0))
		if p == 0 and e.has("f7_bw"):   # the halted overwatch team in the open; in cover it hugs / peeks AND shows the arc (po[4])
			p = 4
		if p == 0:
			continue
		var ang := float(e.get("facing", 0.0))
		if p == 2:
			var t = w.entities.get(int(e.get("target", -1)))
			if t != null:
				ang = (t.pos - e.pos).angle()
		po.append([float(e.pos.x), float(e.pos.y), p, ang, 1 if e.has("f7_bw") else 0])
	if bz.is_empty() and bb.is_empty() and mk.is_empty() and po.is_empty() and nv.is_empty():
		return null
	return {"bz": bz, "bb": bb, "mk": mk, "po": po, "nv": nv}


func setup(m: Node) -> void:
	mv = m
	_sig_node = Node2D.new()
	_sig_node.z_as_relative = false
	_sig_node.z_index = 6
	add_child(_sig_node)
	_sig_node.draw.connect(_draw_sigs)
	if mv.has_signal("world_events"):
		mv.connect("world_events", Callable(self, "_on_events"))


## Per frame (G71Attach.refresh_all). Mounts the panel + feed the first frame the world is a Last Protocol match.
func refresh(snap: Dictionary) -> void:
	var c = (snap.get("g71", {}) as Dictionary).get(SNAP_KEY)
	var had := not crew.is_empty()   # crew marks and / or cover poses (po)
	crew = c if c is Dictionary else {}
	if not sigs.is_empty() or had or not crew.is_empty():
		queue_redraw()
		if _sig_node != null:
			_sig_node.queue_redraw()
	if _on or mv == null:
		return
	if not mv.has_method("world_readable") or not mv.world_readable():
		return
	var w = mv.get("world")
	if w == null or not w.sys_state.has(Discipline71.KEY):
		return
	var main = mv.get_parent()
	var hud = main.get("hud") if main != null else null
	if hud == null or hud.get("layer") == null or hud.layer.root == null:
		return
	_on = true
	ammo = AmmoPanel71.attach(mv)
	feed = RadioFeed71.new()
	hud.layer.root.add_child(feed)
	feed.setup(int(mv.get("player_fid")))


func _process(delta: float) -> void:
	_t += delta
	if not clashes.is_empty():
		var kc: Array = []
		for g in clashes:
			if _t - float(g.t0) < CLASH_S:
				kc.append(g)
		clashes = kc
		if _sig_node != null:
			_sig_node.queue_redraw()
	if sigs.is_empty():
		return
	var keep: Array = []
	for s in sigs:
		if _t - float(s.t0) < SIG_S:
			keep.append(s)
	if keep.size() != sigs.size():
		sigs = keep
		queue_redraw()
		if _sig_node != null:
			_sig_node.queue_redraw()


func _on_events(evs: Array) -> void:
	if not _on or mv == null:
		return
	feed.handle_events(evs, mv.get("world"))
	signal_events(evs, int(mv.get("player_fid")))


## Hand signals from our side's discipline71 radio71 events (also used by tests without a MatchView).
func signal_events(evs: Array, fid: int) -> void:
	for ev in evs:
		if String(ev.get("type", "")) == "Melee71":
			var mp = ev.get("pos", Vector2.ZERO)
			clashes.append({"pos": Vector2(mp) if mp is Vector2 else Vector2(float(mp[0]), float(mp[1])), "kind": String(ev.get("kind", "")), "t0": _t})
			continue
		if String(ev.get("type", "")) != "radio71" or int(ev.get("team", -1)) != fid:
			continue
		var key := String(ev.get("key", ""))
		for pre in SIGNALS:
			if key.begins_with(pre):
				var p = ev.get("pos", [0.0, 0.0])
				sigs.append({"pos": Vector2(float(p[0]), float(p[1])), "word": SIGNALS[pre][0], "col": SIGNALS[pre][1], "t0": _t})
				break
	while sigs.size() > SIG_MAX:
		sigs.pop_front()
	while clashes.size() > CLASH_MAX:
		clashes.pop_front()


static func _iso(p: Vector2) -> Vector2:
	return Vector2((p.x - p.y) * 32.0, (p.x + p.y) * 16.0)


## Ground ellipse in tile space (length along ang, width across), drawn in iso.
func _ell(c: Vector2, ln: float, wd: float, ang: float, col: Color, lw: float) -> void:
	var pk := PackedVector2Array()
	var u := Vector2.from_angle(ang)
	var v := Vector2(-u.y, u.x)
	for i in 17:
		var a := TAU * float(i) / 16.0
		pk.append(_iso(c + u * cos(a) * ln * 0.5 + v * sin(a) * wd * 0.5))
	draw_colored_polygon(pk, Color(col, col.a * 0.35))
	draw_polyline(pk, col, lw, true)


func _draw() -> void:
	var s: float = maxf(get_canvas_transform().get_scale().x, 0.05)
	var k := 1.0 / s
	# B3 crew marks: MG beaten zones (amber; red during an FPF), AT backblast danger zones, .50 spotter reticles
	for z in crew.get("bz", []):
		var zc := Color(1.0, 0.35, 0.15, 0.55) if int(z[5]) == 1 else Color(1.0, 0.78, 0.3, 0.45)
		_ell(Vector2(z[0], z[1]), float(z[2]), float(z[3]), float(z[4]), zc, 1.4 * k)
	for b in crew.get("bb", []):
		var a := Vector2(b[0], b[1])
		var u := Vector2.from_angle(float(b[2]))
		var v := Vector2(-u.y, u.x) * float(b[4])
		var e := a + u * float(b[3])
		var q := PackedVector2Array([_iso(a - v * 0.5), _iso(e - v), _iso(e + v), _iso(a + v * 0.5)])
		draw_colored_polygon(q, Color(1.0, 0.55, 0.2, 0.3))
		q.append(q[0])
		draw_polyline(q, Color(1.0, 0.4, 0.1, 0.7), 1.4 * k, true)
	for m in crew.get("mk", []):
		var p := _iso(Vector2(m[0], m[1])) + Vector2(0, -10.0 * k)
		var r := 9.0 * k
		draw_arc(p, r, 0.0, TAU, 20, Color(1.0, 0.2, 0.2, 0.85), 1.4 * k, true)
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			draw_line(p + d * r * 0.5, p + d * r * 1.4, Color(1.0, 0.2, 0.2, 0.85), 1.2 * k, true)
	if s >= POSE_ZOOM:
		_draw_poses(crew.get("po", []))
		_draw_gear(crew.get("nv", []))
	if _sig_node == null:
		_draw_sigs_on(self, k)


## D4 cover poses, in world pixels at the soldier (the sprite is ~22 px tall), so they scale with the unit:
##   hug   : pressed low behind cover: a dark flattened shadow, a sandbag lip on the facing side, a down chevron
##   peek  : leaning out to fire: the head dot leans out of cover toward the target, with a short muzzle tick
##   bound : the moving fire team: a green arrow along its run;  overwatch: the halted team's covering arc
func _draw_poses(po: Array) -> void:
	for q in po:
		var c := _iso(Vector2(q[0], q[1]))
		var u := Vector2.from_angle(float(q[3]))
		var du := (_iso(Vector2(q[0], q[1]) + u) - c).normalized()
		match int(q[2]):
			1:
				_flat(c + Vector2(0, 1.5), 11.0, 4.0, Color(0.0, 0.0, 0.0, 0.62))
				var lip := c + du * 7.0
				var side := Vector2(-du.y, du.x)
				for i in [-1, 0, 1]:
					var b := lip + side * 4.2 * float(i) + Vector2(0, -1.5)
					_flat(b, 3.0, 1.9, Color(0.72, 0.62, 0.42, 1.0))
					draw_arc(b, 3.0, PI, TAU, 6, Color(0.15, 0.12, 0.08, 0.9), 1.0, true)
				var h := c + Vector2(0, -27.0)
				draw_polyline(PackedVector2Array([h + Vector2(-4, -2.5), h + Vector2(0, 1.5), h + Vector2(4, -2.5)]), Color(0.55, 0.8, 1.0, 0.9), 1.6, true)
			2:
				var hd := c + Vector2(0, -15.0) + du * 6.0
				draw_line(c + Vector2(0, -9.0), hd, Color(0.05, 0.05, 0.05, 0.8), 2.6, true)
				draw_circle(hd, 2.4, Color(1.0, 0.9, 0.55, 0.95))
				draw_line(hd + du * 3.0, hd + du * 9.0, Color(1.0, 0.85, 0.3, 0.9), 1.4, true)
			3:
				var a0 := c + Vector2(0, 2.0) + du * 5.0
				var a1 := a0 + du * 16.0
				var sd := Vector2(-du.y, du.x)
				draw_line(a0, a1, Color(0.02, 0.1, 0.02, 0.8), 4.4, true)
				draw_line(a0, a1, Color(0.35, 1.0, 0.45, 0.95), 2.4, true)
				draw_colored_polygon(PackedVector2Array([a1 + du * 4.0, a1 + sd * 3.5, a1 - sd * 3.5]), Color(0.35, 1.0, 0.45, 0.9))
		if int(q[2]) == 4 or (q.size() > 4 and int(q[4]) == 1):
			var ar := PackedVector2Array()
			for i in 9:
				var a := float(q[3]) + deg_to_rad(-35.0 + 70.0 * float(i) / 8.0)
				ar.append(_iso(Vector2(q[0], q[1]) + Vector2.from_angle(a) * 0.55))
			draw_polyline(ar, Color(0.4, 0.9, 1.0, 0.85), 1.6, true)
			draw_circle(c + Vector2(0, -27.0), 2.0, Color(0.4, 0.9, 1.0, 0.85))


## G1 at night: NVG = a green goggle glint + a faint green look wedge; thermal = the same in heat orange.
func _draw_gear(nv: Array) -> void:
	for q in nv:
		var c := _iso(Vector2(q[0], q[1]))
		var col := Color(0.35, 1.0, 0.4) if int(q[3]) == 0 else Color(1.0, 0.55, 0.15)
		var wedge := PackedVector2Array([c + Vector2(0, -14.0)])
		for i in 7:
			var a := float(q[2]) + deg_to_rad(-22.0 + 44.0 * float(i) / 6.0)
			wedge.append(_iso(Vector2(q[0], q[1]) + Vector2.from_angle(a) * 2.2))
		draw_colored_polygon(wedge, Color(col, 0.2))
		draw_circle(c + Vector2(0, -16.0), 2.2, Color(col, 0.95))
		draw_circle(c + Vector2(0, -16.0), 4.0, Color(col, 0.25))


func _flat(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pk := PackedVector2Array()
	for i in 12:
		var a := TAU * float(i) / 12.0
		pk.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pk, col)


## Hand signals (on _sig_node when set up, so the word is not hidden under the squad shield markers).
func _draw_sigs() -> void:
	_draw_sigs_on(_sig_node, 1.0 / maxf(_sig_node.get_canvas_transform().get_scale().x, 0.05))


func _draw_sigs_on(c: CanvasItem, k: float) -> void:
	var font: Font = ThemeDB.fallback_font
	# I2 wall-walk melee: a white-hot clash star with crossed strokes and the weapon word (BAYONET / SHOTGUN / FLAMER)
	for g in clashes:
		var a0 := clampf(1.0 - (_t - float(g.t0)) / CLASH_S, 0.0, 1.0)
		var cp := _iso(g.pos) + Vector2(0, -12.0)
		var rr := (7.0 + 5.0 * (1.0 - a0)) * maxf(k, 0.6)
		for i in 8:
			var d := Vector2.from_angle(TAU * float(i) / 8.0 + 0.2)
			c.draw_line(cp + d * rr * 0.3, cp + d * rr * (1.0 if i % 2 == 0 else 0.6), Color(1.0, 0.95, 0.7, a0), 1.6 * maxf(k, 0.6), true)
		c.draw_line(cp + Vector2(-rr, -rr) * 0.7, cp + Vector2(rr, rr) * 0.7, Color(0.85, 0.85, 0.9, a0), 2.0 * maxf(k, 0.6), true)
		c.draw_line(cp + Vector2(rr, -rr) * 0.7, cp + Vector2(-rr, rr) * 0.7, Color(0.85, 0.85, 0.9, a0), 2.0 * maxf(k, 0.6), true)
		var word := String(g.kind).to_upper() if String(g.kind) != "other" else "MELEE"
		var fs2 := maxi(int(12.0 * k), 6)
		var tw2 := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
		var at2 := cp + Vector2(-tw2 * 0.5, -rr - 3.0 * k)
		c.draw_string_outline(font, at2, word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, maxi(int(3.0 * k), 1), Color(0, 0, 0, a0))
		c.draw_string(font, at2, word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(1.0, 0.9, 0.6, a0))
	if sigs.is_empty():
		return
	for g in sigs:
		var age := _t - float(g.t0)
		var a := clampf(1.0 - age / SIG_S, 0.0, 1.0)
		var col: Color = Color(g.col, a)
		var base := _iso(g.pos) + Vector2(0, -40.0 * k)
		# raised forearm + open hand, pumped once a second
		var lift := 4.0 * k * absf(sin(age * PI))
		var hand := base + Vector2(0, -14.0 * k - lift)
		c.draw_line(base, hand, Color(0.05, 0.05, 0.05, a), 4.0 * k, true)
		c.draw_line(base, hand, col, 2.2 * k, true)
		c.draw_circle(hand, 3.2 * k, col)
		var fs := maxi(int(16.0 * k), 6)
		var tw := font.get_string_size(String(g.word), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := hand + Vector2(-tw * 0.5, -6.0 * k)
		# dark plate behind the word: the night CanvasModulate dims the amber text into the roof colours (gen 9 shot)
		c.draw_rect(Rect2(at + Vector2(-4.0 * k, -float(fs) - 1.0 * k), Vector2(tw + 8.0 * k, float(fs) + 6.0 * k)), Color(0.02, 0.02, 0.02, 0.7 * a))
		c.draw_string_outline(font, at, String(g.word), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(int(3.0 * k), 1), Color(0, 0, 0, a))
		c.draw_string(font, at, String(g.word), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
