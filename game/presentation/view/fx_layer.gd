extends Node2D
## Cosmetic effects (owner: agent D): tracers + muzzle flashes from ShotFired, explosions +
## smoke from EntityDestroyed, and short command markers. Uses its own cosmetic RNG.
## Effects in cells the player cannot see are skipped.
## G3b (R4-render): culled to the camera view; zoom LOD (set by MatchView from the entity layer)
## drops small FX at mid zoom (muzzle flashes, small explosions, small smoke) and also tracers at
## far zoom.

const ViewUtil = preload("res://presentation/view/view_util.gd")
const RenderSnap = preload("res://sim/render_snap.gd")
const MAX_FX := 400

var mv
var _rng := RandomNumberGenerator.new()
var _fx: Array = []    # {kind, t, life, a:Vector2 screen, b:Vector2 screen, size, color}
var _frames: Dictionary = {}  # effect name -> Array of textures ([] if placeholder)
var lod := 0                  # 0 close, 1 mid, 2 far (entity_layer.lod)
var drawn := 0
var flames := 0               # G4b (UI4B-3): flame_jet effects started (playtest / debug)
var _flame_w: Dictionary = {} # weapon id -> bool (weapon class "flame")

# G6.1 (VFX61): effects overhaul. fx61_engine draws particles here, ground lights in an additive child drawn
# behind this layer, and craters / scorch decals in a child at absolute z 0 (under selection rings and units).
const Fx61Core = preload("res://presentation/view/fx61_core.gd")
const Fx61Engine = preload("res://presentation/view/fx61_engine.gd")
var fx61 = null                 # Fx61Engine (lazy: _e())
var fx61_drawn: Dictionary = {"parts": 0, "lights": 0, "decals": 0, "vignette": false}
var _dec_node: Node2D = null
var _lit_node: Node2D = null
var _q_t := 0.0
var _q_forced := ""
var _fx61_tick := -1
var _veh: Dictionary = {}       # def id -> bool (ground / naval vehicle: armour sparks, dust trail)


class Fx61Proxy:
	extends Node2D
	var cb: Callable

	func _draw() -> void:
		if cb.is_valid():
			cb.call(self)


func _e():
	if fx61 == null:
		fx61 = Fx61Engine.new()
		fx61.set_quality(_q_forced if _q_forced != "" else Fx61Core.quality_setting())
		_dec_node = Fx61Proxy.new()
		_dec_node.name = "Fx61Decals"
		_dec_node.z_index = -3   # relative: 3 - 3 = absolute 0, after the terrain in tree order, below rings (z 1)
		_dec_node.cb = func(ci): fx61_drawn.decals = fx61.draw_decals(ci, _vr())
		add_child(_dec_node)
		_lit_node = Fx61Proxy.new()
		_lit_node.name = "Fx61Lights"
		_lit_node.show_behind_parent = true
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_lit_node.material = m
		_lit_node.cb = func(ci): fx61_drawn.lights = fx61.draw_lights(ci, _vr())
		add_child(_lit_node)
	return fx61


## Effects quality override (playtests / tests); "" = follow Settings (graphics/fx_quality).
func set_fx_quality(q: String) -> void:
	_q_forced = Fx61Core.norm_quality(q) if q != "" else ""
	_e().set_quality(_q_forced if _q_forced != "" else Fx61Core.quality_setting())


func _vr() -> Rect2:
	if not is_inside_tree():
		return Rect2(-1.0e7, -1.0e7, 2.0e7, 2.0e7)
	var inv: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var vs: Vector2 = get_viewport_rect().size
	return Rect2(inv * Vector2.ZERO, Vector2.ZERO).expand(inv * vs).grow(160.0)


func _is_vehicle(def_id: String) -> bool:
	var v = _veh.get(def_id)
	if v == null:
		var mc := String(Content.unit(def_id).get("move_class", "foot"))
		v = mc != "foot" and mc != "air" and not _is_air_def(def_id)
		_veh[def_id] = v
	return v


func _terrain_at(p: Vector2) -> int:
	var sn: Dictionary = mv.snap if mv != null and mv.get("snap") is Dictionary else {}
	var tr = sn.get("terrain")
	var mw := int(sn.get("map_w", 0))
	if not (tr is PackedByteArray) or mw <= 0:
		return 0
	var idx := floori(p.y) * mw + floori(p.x)
	return int((tr as PackedByteArray)[idx]) if idx >= 0 and idx < (tr as PackedByteArray).size() else 0


func _ent(eid: int):
	var wd = mv.get("_world") if mv != null else null  # never mv.world: that getter forces a sim join
	if wd == null:
		return null
	return (wd.entities as Dictionary).get(eid)


## Muzzle effects for a shot; returns the muzzle point (screen px).
func _fx61_muzzle(ev: Dictionary, from: Vector2, to: Vector2, cls: String) -> Vector2:
	var e = _e()
	e.lod = lod
	var mz: Array = muzzle_point(ev, from, to, cls)
	var a: Vector2 = mz[0]
	var ground: Vector2 = mz[1]
	var dir: Vector2 = (_w2s(to) - _w2s(from)).normalized()
	e.muzzle(cls, a, dir if dir != Vector2.ZERO else Vector2.RIGHT, ground)
	return a


# ---------------------------------------------------------------- G7 (MUZZLE7, spec 13.9c-28) barrel tips
## "everything that fires: the flash comes directly from its barrel(s)". The flash, tracer start, barrel smoke,
## casings, backblast, shell arc and flame jet all leave the measured barrel tip (presentation/art/muzzle_g61.gd,
## assets/art/muzzle7.json) of the sprite AS DRAWN: anchored at the drawn ground point (motion layer: interpolation,
## officer lead, wall-walk firing step, hill lift; minus the air lift), on the drawn facing row (separate turret
## sheets: the aim row toward the target), in the drawn pose (stand / crouch / prone / sidearm / peek, from the entity
## layer's drawn column when it records one, else posture bits: pinned prone, suppressed crouched, on a wall never
## prone); buildings / turrets / wall turrets on their drawn art state (rot_<f>_fire, aim_<k>_fire, rot_<m>_a<n>_fire).
## Barrels alternate per shooter (twin guns, squads: each soldier's rifle in turn). Display only: reads the snapshot,
## the live entity's def / facing and the entity layer's draw state, writes nothing back.
const Muzzle7 = preload("res://presentation/art/muzzle_g61.gd")
var _m7n: Dictionary = {}          # shooter id -> shots drawn (barrel alternation)
var muzzle7 := {"tip": 0, "fallback": 0, "bld": 0, "air": 0, "apc": 0}   # counters (tests / playtest evidence)
var muzzle7_last: Array = []       # [shooter id, muzzle screen point, drawn anchor, pose] of the last measured flash
var muzzle7_fb: Dictionary = {}     # def -> centre / height-guess fallbacks (evidence: which shooters lack tips)


## [muzzle screen point, drawn ground point, true when a measured barrel tip was used].
func muzzle_point(ev: Dictionary, from: Vector2, to: Vector2, cls: String) -> Array:
	var sid := int(ev.get("shooter", -1))
	var se = _ent(sid)
	var ground: Vector2 = _w2s(from)
	var n: int = int(_m7n.get(sid, 0))
	_m7n[sid] = n + 1
	if _m7n.size() > 4096:
		_m7n.clear()
	if se != null:
		var tips: Array = []
		var anchor := ground
		var sn: Dictionary = mv.snap if mv != null and mv.get("snap") is Dictionary else {}
		if String(se.kind) == "building":
			var st = (sn.get("statics", {}) as Dictionary).get(sid)
			var sp: Vector2 = st.pos if st is Dictionary and st.has("pos") else se.pos
			anchor = _w2s(sp)
			tips = _bld_tips(String(se.def), st if st is Dictionary else se, _w2s(to) - anchor)
			if not tips.is_empty():
				muzzle7.bld += 1
		else:
			var dn := _art_name(se)
			var el = mv.get("entity_layer") if mv != null else null
			var mo = el.get("motion") if el != null else null
			var row := -1
			var pose := "stand"
			var rec = null
			var d7 = el.get("drawn7") if el != null else null
			if d7 is Dictionary:
				rec = (d7 as Dictionary).get(sid)
			if rec is Array and (rec as Array).size() >= 4 and mo != null and float(mo._now) - float(rec[3]) > 0.25:
				rec = null   # not drawn lately (scrolled away / LOD): use the motion layer or the sim point
			if rec is Array and (rec as Array).size() >= 3:
				row = int(rec[1])
				anchor = rec[2]
				pose = _pose_of_col(dn, int(rec[0]))
			elif mo != null:
				var vs = (mo.vs as Dictionary).get(sid)
				if vs != null and float(mo._now) - float(vs[1]) < 0.5:   # drawn this / last frame
					anchor = Vector2(float(vs[16]), float(vs[17]))
					row = mo.row(sid)
				if el != null:
					pose = _pose_of_bits(int((el._post as Dictionary).get(sid, 0)), (el._ww_cells as Dictionary).has(Vector2i(floori(from.x), floori(from.y))))
			var lift: float = float(_snap_lift(sid)[0])
			if lift > 0.0 and not (rec is Array):
				anchor.y -= lift
				muzzle7.air += 1
			var ag = el.get("apc_gun7") if el != null else null
			if ag != null and ag.has_guns(dn):
				# G7 MUZZLE7-2 (13.9c-28a): CN APC pods / RWS are their own traversing sprites (apc_gun7.gd): the shot
				# goes to the gun that bears (pods alternate) and leaves ITS barrel as drawn (aim step, barrel, anchor)
				var gp: Array = ag.on_shot(sid, dn, (to - from).angle(), float(mv.anim_time()) if mv.has_method("anim_time") else 0.0)
				if not gp.is_empty():
					muzzle7.tip += 1
					muzzle7.apc = int(muzzle7.get("apc", 0)) + 1
					muzzle7_last = [sid, gp[0], gp[1], n]
					return [gp[0], gp[1], true]
			var aim := ArtCatalog.facing_index((to - from).angle())   # turret / fallback row: toward the target
			if row < 0:
				row = aim
			if Muzzle7.has_turret7(dn):
				var tt: Array = Muzzle7.unit_tips(dn, "t", aim)
				if not tt.is_empty():
					tips = tt
			if tips.is_empty():
				tips = Muzzle7.unit_tips(dn, pose, row)
		if not tips.is_empty():
			muzzle7.tip += 1
			muzzle7_last = [sid, anchor + Muzzle7.pick(tips, n), anchor, n]
			return [anchor + Muzzle7.pick(tips, n), anchor, true]
		ground = anchor
	elif sid >= 0:
		# G7 REGFIX7-3: the shooter was killed in the step it fired (removed before its shot is drawn): the flash still
		# leaves the barrel as last drawn (entity_layer.gone7), not the centre / height guess
		var el0 = mv.get("entity_layer") if mv != null else null
		var g7 = el0.get("gone7") if el0 != null else null
		var dw7 = el0.get("drawn7") if el0 != null else null
		var r0 = (dw7 as Dictionary).get(sid) if dw7 is Dictionary else null   # its Destroyed not handled yet this frame
		if r0 == null and g7 is Dictionary:
			r0 = (g7 as Dictionary).get(sid)
		if r0 is Array and (r0 as Array).size() >= 5:
			var mo0 = el0.get("motion")
			if mo0 == null or float(mo0._now) - float(r0[3]) <= 0.5:
				var dn0 := String(r0[4])
				var tp0: Array = Muzzle7.unit_tips(dn0, _pose_of_col(dn0, int(r0[0])), int(r0[1]))
				if not tp0.is_empty():
					muzzle7.tip += 1
					muzzle7["gone"] = int(muzzle7.get("gone", 0)) + 1
					return [(r0[2] as Vector2) + Muzzle7.pick(tp0, n), r0[2], true]
		ground.y -= float(_snap_lift(sid)[0])   # no live entity (replays / tests): still at the aircraft's altitude
	muzzle7.fallback += 1
	muzzle7_fb[String(se.def) if se != null else "gone"] = int(muzzle7_fb.get(String(se.def) if se != null else "gone", 0)) + 1
	return [ground + Fx61Core.muzzle_offset(String(se.def) if se != null else "", cls, (to - from).angle(), _height_for(sid)), ground, false]


## Art sheet a live unit is drawn with (entity_layer: e.art_def override, XL dropship remap).
func _art_name(se) -> String:
	var dn := String(se.get("art_def", "")) if se is Dictionary else ""
	if dn == "":
		dn = String(se.def)
	if dn == "a_vtol_dropship" and Muzzle7.data7().get("u", {}).has("g7_a_vtol_dropship_xl"):
		var el = mv.get("entity_layer") if mv != null else null
		if el != null and bool(el.get("XL_REMAP")):
			dn = "g7_a_vtol_dropship_xl"
	return dn


## Pose of a drawn sheet column (frame name): crouched / prone / sidearm / peek frames, else standing.
static func _pose_of_col(dn: String, col: int) -> String:
	var spec: Dictionary = ArtCatalog.manifest().get("infantry", {}).get(dn, {})
	var fr: Array = spec.get("frames", [])
	if col < 0 or col >= fr.size():
		return "stand"
	var nm := String(fr[col])
	if nm == "peek_l" or nm == "peek_r":
		return nm
	if nm.begins_with("sa_"):
		return "side"
	if nm == "fire_p" or nm == "prone" or nm.begins_with("crawl"):
		return "prone"
	if nm == "fire_c" or nm == "crouch" or nm.begins_with("cwalk") or nm.begins_with("duck") or nm == "cower":
		return "crouch"
	return "stand"


## Pose from Motion posture bits (pinned prone, suppressed crouched; on the wall-walk never prone: crouched fire).
static func _pose_of_bits(bits: int, on_wall: bool) -> String:
	if bits & 8:   # Motion.P_PINNED
		return "crouch" if on_wall else "prone"
	if bits & 16:  # Motion.P_SUPPRESSED
		return "crouch"
	return "stand"


## Barrel tips of a building in the art state it is drawn with while firing (G5Art.building_state with firing up).
func _bld_tips(def: String, st: Dictionary, sdir: Vector2) -> Array:
	var b: Dictionary = ArtCatalog.manifest().get("buildings", {}).get(def, {})
	var row := posmod(int(round(_screen_to_tile_angle(sdir) / (PI / 4.0))), 8)
	if b.is_empty():
		return []
	var state := "built"
	var v := G5Art.variant_of(b)
	if v != "":
		state = G5Art.building_state(b.get("states", {}), {"facing_i": int(st.get("facing_i", 0)), "hp": 1.0, "built": true,
			"firing": 1, "level": int(st.get("level", 0)), "water_d": int(st.get("water_d", 0)), "tb": st.get("tb"), "def": def}, v)   # G7 TURRET7B CR 6370 + 6457: head (or rot-only quarter turn) drawn on the sim bearing
	return Muzzle7.building_tips(def, state, row)


## Screen direction -> world (tile) angle under the 2:1 iso projection.
static func _screen_to_tile_angle(d: Vector2) -> float:
	return atan2(d.y / 16.0 - d.x / 32.0, d.x / 32.0 + d.y / 16.0)


## Impact effects where a direct shot lands (b = drawn hit point, to = world target point).
func _fx61_impact(ev: Dictionary, to: Vector2, b: Vector2, hit: bool, cls: String) -> void:
	var e = _e()
	var heavy := cls == "cannon" or cls == "rocket"
	if hit:
		var t = _ent(int(ev.get("target", -1)))
		var kind := "soft"
		if t != null:
			if String(t.kind) == "building":
				kind = "building"
			elif _is_vehicle(String(t.get("def", ""))):
				kind = "armor"
		if heavy:
			e.explosion(b, 12.0, "" if kind == "armor" else "scorch")
			if kind == "armor":
				e.impact("armor", b, 1.6)
		else:
			e.impact(kind, b, 1.2 if cls == "autocannon" else 0.7)
			# G7 (LOOK7): a hit on a soldier leaves a small blood splat on the ground (not every hit)
			if kind == "soft" and t != null and String(t.kind) == "unit" and _rng.randf() < 0.4:
				e.blood(b + Vector2(_rng.randf_range(-5, 5), _rng.randf_range(2, 6)), _rng.randf_range(3.0, 5.0), true)
	else:
		var g: Vector2 = _w2s(to) + Vector2(_rng.randf_range(-14, 14), _rng.randf_range(-7, 7))
		var code := _terrain_at(to)
		e.impact("water" if Fx61Core.is_water(code) else "dirt", g, 1.5 if heavy else 0.8)
		if heavy and not Fx61Core.is_water(code):
			e.add_decal(g, 7.0, "scorch")


## OFF61 battle drill "smoke" (AiDecision tag): a smoke screen over the units it names (visible / own side only).
func _fx61_smoke(ev: Dictionary) -> void:
	var sn: Dictionary = mv.snap if mv != null and mv.get("snap") is Dictionary else {}
	var own: bool = int(ev.get("fid", -1)) == int(mv.player_fid) or (mv._ally_fids as Array).has(int(ev.get("fid", -1)))
	var pts: Array = []
	var ids: Array = ev.get("unit_ids", [])
	var step := maxi(1, ids.size() / 6)
	for i in range(0, ids.size(), step):
		var p = G6Fx.pos_of(sn, int(ids[i]))
		if p is Vector2 and (own or mv.cell_visible(Vector2i(floori(p.x), floori(p.y)))):
			pts.append(_w2s(p))
	if not pts.is_empty():
		_e().smoke_screen(pts)


func setup(view) -> void:
	mv = view
	_rng.seed = 12345
	if mv != null and mv.has_signal("world_events") and not mv.world_events.is_connected(_on_world_events):
		mv.world_events.connect(_on_world_events)  # G5 (VIEW5-2): AirStrike is not dispatched by MatchView
	for n in ["muzzle", "explosion_small", "explosion_large", "smoke", "flame_jet"] + AIR_FX:
		var arr: Array = ArtCatalog.effect_frames(n)
		var ok: Array = []
		for t in arr:
			if t != null and not ViewUtil.is_placeholder(t):
				ok.append(t)
		_frames[n] = ok


func _height_for(eid: int) -> float:
	var e = _ent(eid)
	if e == null:
		return 10.0
	if e.kind == "building":
		return 18.0
	var r := float(Content.unit(e.def).get("radius", 0.3))
	return 8.0 + r * 12.0


func on_shot(ev: Dictionary) -> void:
	var from: Vector2 = ev.get("from", Vector2.ZERO)
	var to: Vector2 = ev.get("to", Vector2.ZERO)
	if not (mv.cell_visible(Vector2i(floori(from.x), floori(from.y))) or mv.cell_visible(Vector2i(floori(to.x), floori(to.y)))):
		return
	if _fx.size() >= MAX_FX:
		return
	if bool(ev.get("ciws7", false)):
		_ciws7_stream(ev, from, to)   # G7 CIWS7-4 (13.9c-32a): straight stream along the barrel, dispersion cone
		return
	if bool(ev.get("indirect", false)):
		# G7 MUZZLE7: the shell leaves the barrel tip (was the unit centre + a height guess)
		var sa: Vector2 = _fx61_muzzle(ev, from, to, "artillery") if lod < 2 else muzzle_point(ev, from, to, "artillery")[0]
		_add_shell(ev, from, to, sa)
		return
	if _air_shot(ev, from, to):
		return
	var wid := String(ev.get("weapon", ""))
	if _is_flame(wid):
		_add_flame(ev, _fx61_muzzle(ev, from, to, "flame"))   # G7 MUZZLE7: jet from the nozzle
		return
	if _is_laser(wid):
		# G6: beam, not a tracer. G7 MUZZLE7-2 (13.9c-28): the beam leaves the emitter's barrel tip, not the sim point
		var la: Vector2 = _fx61_muzzle(ev, from, to, "energy")
		_add_g6_list(G6Fx.from_event(ev, mv.snap, int(mv.player_fid), mv._ally_fids), from, la)
		return
	if lod >= 2:
		return
	# G6.1 (VFX61): per-class muzzle flash / light / casings / barrel smoke / backblast, glowing class tracer, impact
	var cls: String = Fx61Core.weapon_class(wid)
	var a: Vector2 = _fx61_muzzle(ev, from, to, cls)
	var jitter := Vector2(_rng.randf_range(-4, 4), _rng.randf_range(-3, 3))
	var hit := bool(ev.get("hit", true))
	var b: Vector2 = _w2s(to) + Vector2(0, -_height_for(int(ev.get("target", -1)))) + (jitter if hit else jitter * 4.0)
	var pr: Dictionary = Fx61Core.params(cls)
	_fx.append({"kind": "tracer", "t": 0.0, "life": float(pr.tl), "a": a, "b": b, "size": float(pr.tw),
		"color": pr.tc, "glow": float(pr.glow)})
	if cls == "rocket" and lod < 1:
		var e61 = _e()
		var nt: int = e61.n(5)
		for i in nt:
			var u := (i + 0.5) / float(nt)
			e61.part("puff", a.lerp(b, u), e61.wind() * 0.2 + Vector2(0, -6), 1.3, 3.0, 10.0, Color(0.78, 0.76, 0.72, 0.42), 0.0, float(pr.tl) * u)
	_fx61_impact(ev, to, b, hit, cls)


func _is_flame(wid: String) -> bool:
	var v = _flame_w.get(wid)
	if v == null:
		v = String(Content.weapon(wid).get("class", "")) == "flame"
		_flame_w[wid] = v
	return v


## G4b (UI4B-3, ART-U-3 CR seq 1937): flamer fire draws flame_jet (4 frames, pivot at the nozzle,
## pointing screen +x) from the muzzle, rotated toward the target and stretched to reach it.
func _add_flame(ev: Dictionary, start = null) -> void:
	if lod >= 2:
		return
	var a: Vector2 = start if start is Vector2 else _w2s(ev.get("from", Vector2.ZERO)) + Vector2(0, -_height_for(int(ev.get("shooter", -1))))
	var b: Vector2 = _w2s(ev.get("to", Vector2.ZERO)) + Vector2(0, -8.0)
	_fx.append({"kind": "flame", "t": 0.0, "life": 0.4, "a": a, "b": b, "size": 1.0, "color": Color(1.0, 0.6, 0.2)})
	flames += 1


## G3a artillery: a shell flies a ballistic arc from the gun to the impact point, then an impact
## blast sized by the weapon's splash radius (tiles) plus a short smoke puff.
func _add_shell(ev: Dictionary, from: Vector2, to: Vector2, start = null) -> void:
	var a: Vector2 = start if start is Vector2 else _w2s(from) + Vector2(0, -_height_for(int(ev.get("shooter", -1))))
	var b: Vector2 = _w2s(to)
	var dist := from.distance_to(to)
	var splash := float(Content.weapon(String(ev.get("weapon", ""))).get("splash", 1.0))
	var energy := String(ev.get("weapon", "")).contains("plasma")
	_fx.append({"kind": "shell", "t": 0.0, "life": clampf(0.35 + dist * 0.06, 0.5, 1.3), "a": a, "b": b,
		"size": maxf(12.0, dist * 7.0), "color": Color(0.5, 0.95, 1.0) if energy else Color(1.0, 0.8, 0.45),
		"splash": splash, "energy": energy, "wto": to})


func _shell_landed(f: Dictionary) -> void:
	var b: Vector2 = f.b
	var r: float = 22.0 * float(f.get("splash", 1.0))
	var e = _e()
	e.lod = lod
	# G6.1 (VFX61): water landing = splash column; ground = layered blast (flash, fireball, ring, debris, smoke column,
	# light) with a persistent crater
	if Fx61Core.is_water(_terrain_at(f.get("wto", Vector2(-1, -1)))):
		e.impact("water", b, 1.5 + float(f.get("splash", 1.0)))
		return
	# G7 (LOOK7): no bright fireball sprite for a ground blast; fx61 draws a dust column blast instead
	if bool(f.get("energy", false)):
		_fx.append({"kind": "explosion_large", "t": 0.0, "life": 0.7, "a": b + Vector2(0, -6), "b": b, "size": r * 0.8, "color": Color(1, 0.55, 0.15)})
	e.explosion(b, r * 0.55, "crater", 0.0, bool(f.get("energy", false)))


func on_destroyed(ev: Dictionary) -> void:
	var kind := String(ev.get("kind", ""))
	if kind != "unit" and kind != "building":
		return
	var p: Vector2 = ev.get("pos", Vector2.ZERO)
	if not mv.cell_visible(Vector2i(floori(p.x), floori(p.y))):
		return
	var s: Vector2 = _w2s(p)
	var e = _e()
	e.lod = lod
	if kind == "unit" and _is_air_def(String(ev.get("def", ""))):
		_add_crash(s, String(ev.get("cause", "")) == "crashed")
		e.explosion(s, 14.0, "scorch")
		return
	var dname := String(ev.get("def", ""))
	if kind == "unit" and not _is_vehicle(dname):
		e.impact("dirt", s + Vector2(0, -4), 0.8)   # G6.1: infantry fall without a fireball
		e.blood(s + Vector2(_rng.randf_range(-3, 3), 1), _rng.randf_range(7.0, 10.0), false)   # G7 (LOOK7): blood pool
		return
	var big: bool = kind == "building" or Content.unit(dname).get("leaves_wreck", false)
	_fx.append({"kind": "explosion_large" if big else "explosion_small", "t": 0.0, "life": 0.8 if big else 0.45,
		"a": s + Vector2(0, -8), "b": s, "size": 26.0 if big else 10.0, "color": Color(1, 0.55, 0.15)})
	# G6.1 (VFX61): secondaries, then a burning wreck (fire + drifting smoke plume) keyed by the entity id
	var burn: float = (40.0 if kind == "building" else (28.0 if big else 10.0)) * (0.5 if e.q == "low" else 1.0)
	e.destruction(s, big, int(ev.get("id", -1)), burn)


func add_marker(world_pos: Vector2, col: Color) -> void:
	var s: Vector2 = _w2s(world_pos)
	_fx.append({"kind": "marker", "t": 0.0, "life": 0.5, "a": s, "b": s, "size": 14.0, "color": col})


func tick(delta: float) -> void:
	var tg := Time.get_ticks_usec()
	_g5_refresh()
	ViewUtil.prof_add("p_fx_g5", tg)
	_air_trails(delta)
	_g6_tick()
	var busy61 := _fx61_frame(delta)
	if _fx.is_empty():
		if _g5_any or busy61:
			queue_redraw()
		return
	var keep: Array = []
	var landed: Array = []
	for f in _fx:
		f.t += delta
		if f.t < f.life:
			keep.append(f)
		elif String(f.kind) in ["shell", "bomb", "missile"]:
			landed.append(f)
	_fx = keep
	for f in landed:
		if String(f.kind) == "bomb":
			_bomb_landed(f)
		elif String(f.kind) == "missile":
			_missile_landed(f)
		else:
			_shell_landed(f)
	queue_redraw()


var _draw_night := 0.0   # cached FacAtmo7 night for the current _draw pass (tracers)


func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_night = _night_amt()
	_draw_body()
	preload("res://presentation/view/view_util.gd").prof_add("d_fx", t0)


func _draw_body() -> void:
	var inv: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var vs: Vector2 = get_viewport_rect().size
	var vr := Rect2(inv * Vector2.ZERO, Vector2.ZERO).expand(inv * vs).grow(160.0)
	drawn = 0
	_g5_draw(vr)
	for f in _fx:
		if f.t < 0.0:
			continue
		if not vr.has_point(f.a) and not vr.has_point(f.b):
			continue
		if lod >= 1:
			var kd := String(f.kind)
			if kd == "muzzle" or kd == "explosion_small" or (kd == "smoke" and float(f.size) < 6.0):
				continue
			if lod >= 2 and kd == "tracer":
				continue
		drawn += 1
		var k: float = f.t / f.life
		var col: Color = f.color
		match String(f.kind):
			"tracer":
				# G71 ART71-FX 1E: longer bright segment + night halo so tracers light the sky / read at play zoom.
				var head: Vector2 = (f.a as Vector2).lerp(f.b, clampf(k * 1.6, 0.0, 1.0))
				var tail: Vector2 = (f.a as Vector2).lerp(f.b, clampf(k * 1.6 - 0.55, 0.0, 1.0))
				var gl: float = float(f.get("glow", 0.0))
				var nmul: float = 1.0 + _draw_night * 0.85
				var fade: float = 1.0 - k * 0.45
				if gl > 0.0 or nmul > 1.05:
					var ga: float = maxf(gl, 0.35) * fade * (0.45 + _draw_night * 0.35)
					draw_line(tail, head, Color(col.r, col.g, col.b, ga), float(f.size) * (3.2 + _draw_night * 1.6))
				draw_line(tail, head, Color(col.r, col.g, col.b, fade), float(f.size) * (1.0 + _draw_night * 0.25))
				draw_line(tail.lerp(head, 0.55), head, Color(1, 1, 0.92, fade), maxf(1.0, float(f.size) * 0.55 * nmul))
			"muzzle":
				if not _draw_frames("muzzle", f.a, k, 1.0):
					draw_circle(f.a, f.size * (1.0 - k * 0.5), Color(1, 0.95, 0.6, 1.0 - k))
			"explosion_small", "explosion_large":
				if not _draw_frames(String(f.kind), f.a, k, 1.0):
					var r: float = f.size * (0.4 + k)
					draw_circle(f.a, r, Color(1.0, 0.75 - k * 0.5, 0.2, 1.0 - k))
					draw_circle(f.a, r * 0.55, Color(1.0, 0.95, 0.7, (1.0 - k) * 0.9))
			"smoke":
				var p: Vector2 = (f.a as Vector2).lerp(f.b, k)
				if not _draw_frames("smoke", p, k, 1.0 - k):
					draw_circle(p, f.size * (0.6 + k * 1.4), Color(col.r, col.g, col.b, 0.55 * (1.0 - k)))
			"shell":
				# parabola from a to b with apex height f.size; a bright head and a short trail
				var head: Vector2 = _arc_point(f, k)
				var tail: Vector2 = _arc_point(f, maxf(0.0, k - 0.08))
				draw_line(tail, head, Color(col.r, col.g, col.b, 0.6), 2.0)
				draw_circle(head, 2.5, Color(col.r, col.g, col.b, 1.0))
			"blast":
				var rr: float = f.size * (0.3 + k * 0.9)
				_draw_iso_ring(f.a, rr, Color(col.r, col.g, col.b, 1.0 - k), 3.0)
				draw_set_transform(f.a, 0.0, Vector2(1.0, 0.5))
				draw_circle(Vector2.ZERO, rr * 0.8, Color(col.r, col.g, col.b, 0.25 * (1.0 - k)))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"flame":
				_draw_flame(f, k)
			"missile", "bomb", "air_fx":
				_draw_air_fx(f, k)
			"g6":
				_draw_g6(f, k)
			"marker":
				var r2: float = f.size * (1.0 - k * 0.6)
				_draw_iso_ring(f.a, r2, Color(col.r, col.g, col.b, 1.0 - k), 2.0)
	if fx61 != null:
		fx61_drawn.parts = fx61.draw_parts(self, vr)
		fx61_drawn.vignette = fx61.draw_vignette(self, vr.grow(-160.0))


func _draw_flame(f: Dictionary, k: float) -> void:
	var a: Vector2 = f.a
	var d: Vector2 = (f.b as Vector2) - a
	var arr: Array = _frames.get("flame_jet", [])
	if arr.is_empty():
		draw_line(a, a + d * clampf(k * 2.0, 0.2, 1.0), Color(1.0, 0.55, 0.15, 1.0 - k), 4.0)
		return
	var tx: Texture2D = arr[clampi(int(k * arr.size()), 0, arr.size() - 1)]
	var sx := clampf(d.length() / maxf(1.0, tx.get_width() - 2.0), 0.4, 2.5)
	draw_set_transform(a, d.angle(), Vector2(sx, 1.0))
	draw_texture(tx, Vector2(-2, -8), Color(1, 1, 1, 1.0 - k * 0.4))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _arc_point(f: Dictionary, k: float) -> Vector2:
	var p: Vector2 = (f.a as Vector2).lerp(f.b, k)
	return p + Vector2(0, -4.0 * float(f.size) * k * (1.0 - k))


func _draw_frames(name: String, at: Vector2, k: float, alpha: float) -> bool:
	var arr: Array = _frames.get(name, [])
	if arr.is_empty():
		return false
	var idx := clampi(int(k * arr.size()), 0, arr.size() - 1)
	var t: Texture2D = arr[idx]
	draw_texture(t, at - t.get_size() * 0.5, Color(1, 1, 1, alpha))
	return true


func _draw_iso_ring(c: Vector2, r: float, col: Color, width: float) -> void:
	draw_set_transform(c, 0.0, Vector2(1.0, 0.5))
	draw_arc(Vector2.ZERO, r, 0, TAU, 24, col, width)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- G5 overlays (VIEW5)
# Read from mv.snap only (thread rule): ship wakes, supply icons over needy / served units, the
# Auto Resupply area of own trucks, holding circles over own fields, bubbles over sinking wrecks.
# The item lists are rebuilt once per sim tick; drawing re-projects them every frame.
const ISO_R := 45.254834  # screen half-width (px) of a 1-tile world radius (32 * sqrt 2)
var g5_drawn: Dictionary = {}  # last frame's counts: wakes, supply, trucks, holding, sinking
var _g5_any := false
var _g5_tick := -1
var _g5: Dictionary = {"wakes": [], "supply": [], "trucks": [], "holding": [], "sinking": []}


func _g5_refresh() -> void:
	var sn: Dictionary = mv.snap if mv != null and mv.get("snap") is Dictionary else {}
	if sn.is_empty() or int(sn.get("tick", -1)) == _g5_tick:
		return
	_g5_tick = int(sn.tick)
	var pf: int = mv.player_fid
	var allies: Array = mv._ally_fids
	var wakes: Array = []
	var supply: Array = []
	var flg: PackedInt32Array = sn.flags
	var pos: PackedVector2Array = sn.pos
	var own: PackedInt32Array = sn.owner
	var fac: PackedFloat32Array = sn.facing
	var sdefs: PackedStringArray = sn.defs
	var sdef: PackedInt32Array = sn.def
	var want := RenderSnap.FLAG_SHIP | RenderSnap.FLAG_NEEDY | RenderSnap.FLAG_RESUP
	for i in int(sn.n):
		var fl: int = flg[i]
		if (fl & want) == 0 or fl & RenderSnap.FLAG_ABOARD:
			continue
		var p: Vector2 = pos[i]
		var mine: bool = own[i] == pf or allies.has(own[i])
		if fl & RenderSnap.FLAG_SHIP and fl & RenderSnap.FLAG_MOVING and not G5Art.has_wake_sheet(String(sdefs[sdef[i]])):
			if mine or mv.cell_visible(Vector2i(floori(p.x), floori(p.y))):
				wakes.append([p, fac[i]])
		if mine and fl & (RenderSnap.FLAG_NEEDY | RenderSnap.FLAG_RESUP):
			supply.append([p, (fl & RenderSnap.FLAG_RESUP) != 0, (fl & RenderSnap.FLAG_AIR) != 0 and (fl & RenderSnap.FLAG_LANDED) == 0])
	var trucks: Array = []
	var tr: Dictionary = sn.get("trucks", {})
	for id in tr:
		var t: Dictionary = tr[id]
		if int(t.owner) == pf or allies.has(int(t.owner)):
			trucks.append([t.center, float(t.radius), String(t.mode)])
	var holding: Array = []
	var afs: Dictionary = sn.get("airfields", {})
	var hold: Dictionary = sn.get("holding", {})
	var hr := float(Content.rules().get("g5_air", {}).get("hold_radius", 7.0))
	for fid in hold:
		var af = afs.get(int(fid))
		if af != null and not (hold[fid] as Array).is_empty() and (int(af.owner) == pf or allies.has(int(af.owner))):
			holding.append([af.pos, hr, (hold[fid] as Array).size()])
	var sinking: Array = []
	var sk: Dictionary = sn.get("sinking", {})
	for wid in sk:
		var sp: Vector2 = sk[wid].pos
		if mv.cell_visible(Vector2i(floori(sp.x), floori(sp.y))):
			sinking.append([sp, float(sk[wid].k)])
	_g5 = {"wakes": wakes, "supply": supply, "trucks": trucks, "holding": holding, "sinking": sinking}
	_g5_any = not (wakes.is_empty() and supply.is_empty() and trucks.is_empty() and holding.is_empty() and sinking.is_empty())


func _g5_draw(vr: Rect2) -> void:
	var cnt := {"wakes": 0, "supply": 0, "trucks": 0, "holding": 0, "sinking": 0}
	g5_drawn = cnt
	if not _g5_any:
		return
	var tm := Time.get_ticks_msec() * 0.001
	for tk in _g5.trucks:
		var c: Vector2 = _w2s(tk[0])
		var r: float = float(tk[1]) * ISO_R
		if not vr.grow(r).has_point(c):
			continue
		if String(tk[2]) == "station":
			_draw_iso_ring(c, r, Color(1.0, 0.78, 0.25, 0.55), 2.0)
		else:
			_dashed_iso_ring(c, r, Color(0.45, 0.95, 0.45, 0.6), 2.0, tm)
		cnt.trucks += 1
	for hd in _g5.holding:
		var c: Vector2 = _w2s(hd[0])
		var r: float = float(hd[1]) * ISO_R
		if vr.grow(r).has_point(c):
			_dashed_iso_ring(c, r, Color(0.55, 0.8, 1.0, 0.45), 1.5, tm)
			cnt.holding += 1
	for wk in _g5.wakes:
		var p: Vector2 = wk[0]
		var d := Vector2(cos(float(wk[1])), sin(float(wk[1])))
		var pr := Vector2(-d.y, d.x)
		var st: Vector2 = _w2s(p - d * 0.35)
		if not vr.has_point(st):
			continue
		var ph := fmod(tm * 2.0, 1.0)
		var col := Color(0.92, 0.97, 1.0, 0.6)
		for side in [-1.0, 1.0]:
			var tail: Vector2 = _w2s(p - d * 1.6 + pr * 0.55 * side)
			draw_line(st, tail, col, 1.5)
			draw_line(st.lerp(tail, ph), st.lerp(tail, minf(1.0, ph + 0.2)), Color(1, 1, 1, 0.85), 2.0)
		draw_set_transform(st, 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 4.0, Color(1, 1, 1, 0.35))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		cnt.wakes += 1
	for sk in _g5.sinking:
		var c: Vector2 = _w2s(sk[0])
		if not vr.has_point(c):
			continue
		for b in 4:
			var ph := fmod(tm * 0.8 + b * 0.25, 1.0)
			var o := Vector2(sin(b * 2.1) * 9.0, -ph * 10.0)
			draw_arc(c + o, 1.5 + ph * 1.5, 0.0, TAU, 8, Color(0.85, 0.95, 1.0, (1.0 - ph) * (0.4 + 0.6 * float(sk[1]))), 1.0)
		cnt.sinking += 1
	for su in _g5.supply:
		var c: Vector2 = _w2s(su[0]) + Vector2(10, -38.0 if bool(su[2]) else -30.0)
		if not vr.has_point(c):
			continue
		var fill := Color(0.4, 0.9, 0.4) if bool(su[1]) else Color(1.0, 0.75, 0.2)
		draw_rect(Rect2(c - Vector2(4, 3), Vector2(8, 6)), Color(0.05, 0.05, 0.05, 0.9))
		draw_rect(Rect2(c - Vector2(3, 2), Vector2(6, 4)), fill)
		draw_line(c - Vector2(3, 0), c + Vector2(3, 0), Color(0.05, 0.05, 0.05, 0.8), 1.0)
		cnt.supply += 1


func _dashed_iso_ring(c: Vector2, r: float, col: Color, width: float, tm: float) -> void:
	draw_set_transform(c, 0.0, Vector2(1.0, 0.5))
	var n := 24
	var off := fmod(tm * 0.25, 1.0) * TAU / n
	for k in n:
		var a0 := off + k * TAU / n
		draw_arc(Vector2.ZERO, r, a0, a0 + TAU / n * 0.55, 4, col, width)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- G5 air event effects (VIEW5-2)
# ART-AIR fx sheets on sim events: ShotFired by / at an airborne aircraft (missile + trail puffs for
# missile / rocket weapons, flak bursts for anti-air guns, lifted tracers for aircraft guns),
# AirStrike (MatchView.world_events: falling bomb -> bomb blast), the EntityDestroyed of an aircraft
# (crash fireball + smoke columns; cause "crashed" = AircraftCrashed) and smoke trailing damaged
# airborne aircraft (from mv.snap). Ground-to-ground fire keeps the G4 tracers.
const AIR_FX := ["g5_missile", "g5_missile_trail", "g5_air_bomb", "g5_bomb_blast", "g5_flak_burst", "g5_air_crash", "g5_air_smoke"]
const G5Art = preload("res://presentation/art/g5_art.gd")
var air_fx: Dictionary = {"missiles": 0, "trails": 0, "flak": 0, "bombs": 0, "blasts": 0, "crashes": 0, "smoke": 0, "air_tracers": 0}
var _pivot: Dictionary = {}
var _wcls: Dictionary = {}    # weapon id -> 0 gun, 1 missile, 2 flak
var _air_def: Dictionary = {}
var _smoke_t := 0.0


func _is_air_def(def_id: String) -> bool:
	var v = _air_def.get(def_id)
	if v == null:
		var ud: Dictionary = Content.unit(def_id)
		v = ud.has("aircraft") or bool(ud.get("launched_drone", false))
		_air_def[def_id] = v
	return v


func _weapon_cls(wid: String) -> int:
	var v = _wcls.get(wid)
	if v == null:
		var wd: Dictionary = Content.weapon(wid)
		v = 0
		if wid.contains("missile") or wid.contains("rocket") or wid.contains("sam") or bool(wd.get("missile", false)):
			v = 1
		elif wid.contains("flak") or wid.ends_with("_aa") or (bool(wd.get("anti_air", false)) and String(wd.get("class", "")) in ["autocannon", "flak", "aa"]):
			v = 2
		_wcls[wid] = v
	return v


## [lift px, airborne] of entity eid from the snapshot ([0, false] unless an airborne aircraft).
func _snap_lift(eid: int) -> Array:
	var sn: Dictionary = mv.snap if mv != null and mv.get("snap") is Dictionary else {}
	var air: Dictionary = sn.get("air", {})
	var a = air.get(eid)
	if a == null or float(a.alt) <= 0.0:
		return [0.0, false]
	var i: int = mv.snap_index(eid)
	if i < 0:
		return [0.0, false]
	var dname := String((sn.defs as PackedStringArray)[(sn.def as PackedInt32Array)[i]])
	var t: float = mv.anim_time() if mv.has_method("anim_time") else 0.0
	return [G5Art.lift_px(dname, float(a.alt), eid, t), true]


func _air_shot(ev: Dictionary, from: Vector2, to: Vector2) -> bool:
	var sid := int(ev.get("shooter", -1))
	var tid := int(ev.get("target", -1))
	var ls := _snap_lift(sid)
	var lt := _snap_lift(tid)
	if not bool(ls[1]) and not bool(lt[1]):
		return false
	var hit := bool(ev.get("hit", true))
	var hb: float = (float(lt[0]) + 4.0) if bool(lt[1]) else _height_for(tid)
	# G7 MUZZLE7: air-to-air / air-to-ground / ground-to-air shots leave the shooter's barrel tip (lifted with the
	# aircraft as drawn) with the class muzzle flash there (was the sim point + lift, no shooter flash at all)
	var a: Vector2 = _fx61_muzzle(ev, from, to, Fx61Core.weapon_class(String(ev.get("weapon", "")))) if lod < 2 else muzzle_point(ev, from, to, "mg")[0]
	var jit := Vector2(_rng.randf_range(-5, 5), _rng.randf_range(-4, 4)) * (1.0 if hit else 4.0)
	var b: Vector2 = _w2s(to) + Vector2(0, -hb) + jit
	var wc := _weapon_cls(String(ev.get("weapon", "")))
	if wc == 1:
		var dir := (to - from).angle()
		_fx.append({"kind": "missile", "name": "g5_missile", "t": 0.0, "life": clampf(a.distance_to(b) / 480.0, 0.22, 0.9),
			"a": a, "b": b, "size": 3.0, "color": Color(1, 0.8, 0.5), "fi": posmod(roundi(dir / (PI / 4.0)), 8),
			"tr": 0.0, "hit": hit, "air_t": bool(lt[1])})
		air_fx.missiles += 1
		return true
	if lod < 2:
		_fx.append({"kind": "tracer", "t": 0.0, "life": 0.12, "a": a, "b": b, "size": 1.5, "color": Color(1.0, 0.8, 0.4)})
		air_fx.air_tracers += 1
	if wc == 2 and bool(lt[1]):
		_fx.append({"kind": "air_fx", "name": "g5_flak_burst", "t": 0.0, "life": 0.55, "a": b, "b": b + Vector2(0, -4),
			"size": 8.0, "color": Color(0.2, 0.2, 0.2), "fade": true})
		air_fx.flak += 1
	elif hit and lod < 1:
		_fx.append({"kind": "muzzle", "t": 0.0, "life": 0.07, "a": b, "b": b, "size": 3.0, "color": Color(1, 0.9, 0.5)})
	return true


func _missile_landed(f: Dictionary) -> void:
	if bool(f.get("air_t", false)):
		_fx.append({"kind": "air_fx", "name": "g5_flak_burst", "t": 0.0, "life": 0.5, "a": f.b, "b": f.b,
			"size": 8.0, "color": Color(1, 0.6, 0.2), "fade": true})
	elif bool(f.get("hit", true)):
		_fx.append({"kind": "explosion_small", "t": 0.0, "life": 0.4, "a": f.b, "b": f.b, "size": 9.0, "color": Color(1, 0.6, 0.2)})


func _on_world_events(evs: Array) -> void:
	for ev in evs:
		if String(ev.get("type", "")) == "AirStrike":
			on_air_strike(ev)
		elif String(ev.get("type", "")) == "DroneBlast" or String(ev.get("type", "")) == "DroneMunitionAway":
			_drone_fx(ev)
		elif String(ev.get("type", "")) == "AiDecision":
			if String(ev.get("tag", "")) == "smoke":
				_fx61_smoke(ev)
		elif D71_FX.has(String(ev.get("type", ""))):
			_fx71(ev)
		elif String(ev.get("type", "")) != "ShotFired":  # lasers come through on_shot (MatchView dispatch)
			_add_g6_list(G6Fx.from_event(ev, mv.snap, int(mv.player_fid), mv._ally_fids))


# ---------------------------------------------------------------- G7.1 DAMAGE71 effects (B2 / J3)
## Sim events -> fx61: Ricochet71 (glancing sparks + a streak away from the shooter), PlateShear71 (sparks, the plate
## tumbling off, a scrap mark), PartDestroyed71 (sparks + silver nanite fluid and a silver pool), CellCookoff71 (a small
## blast), NaniteRegrow71 (silver glints over the regrowing part). Presentation only; off-screen events are skipped.
const D71_FX := {"Ricochet71": 1, "PlateShear71": 1, "PartDestroyed71": 1, "CellCookoff71": 1, "NaniteRegrow71": 1, "Trampled71": 1}
func _fx71(ev: Dictionary) -> void:
	if not ev.has("pos"):
		return
	var wp := Vector2(ev.pos)
	var b := _w2s(wp)
	if not _vr().grow(64.0).has_point(b):
		return
	var e = _e()
	match String(ev.type):
		"Ricochet71":
			var fr := _w2s(Vector2(ev.get("from", wp - Vector2(1, 0))))
			e.ricochet71(b + Vector2(0, -6), b - fr)
		"PlateShear71":
			var f := Vector2.from_angle(float(ev.get("facing", 0.0)))
			var fc := String(ev.get("face", "all"))
			var dw := -f if fc == "rear" else (f.orthogonal() if fc == "side" else f)
			e.plate_shear71(b + Vector2(0, -6), _w2s(wp + dw) - b)
		"PartDestroyed71":
			e.part_down71(b + Vector2(0, -5), String(ev.get("kind", "")))
		"CellCookoff71":
			e.explosion(b, 10.0, "scorch")
		"NaniteRegrow71":
			e.silver71(b + Vector2(0, -5), false)
		"Trampled71":   # a tank / heavy Machine rolls over a body: a fresh smear of blood and a puff of churned dirt
			e.blood(b, 9.0, false)
			e.dust(b, Color(0.32, 0.27, 0.2, 0.7), false)


# ---------------------------------------------------------------- G6 (VIEW6) effects
# Specs from presentation/art/g6_fx.gd (world space) -> screen-space fx items of kind "g6".
const G6Fx = preload("res://presentation/art/g6_fx.gd")
var g6_made: Dictionary = {}   # kind -> effects started this session (probe / tests)
var _g6_smoke_tick := -1


var _laser_w: Dictionary = {}  # weapon id -> bool


## G6 (VIEW6, CR 822): world -> canvas on the drawn (raised) ground: ViewUtil.world_to_screen_h with the
## terrain layer's height map = iso(p) - (0, (ground_level - 1) * ViewUtil.level_px). Flat maps: exactly the old iso spot.
func _w2s(p: Vector2) -> Vector2:
	var tl = mv.get("terrain_layer") if mv != null else null
	if tl == null or not tl.has_method("height_map"):
		return ViewUtil.iso(p)
	return ViewUtil.world_to_screen_h(tl.height_map(), p)


func _is_laser(wid: String) -> bool:
	var v = _laser_w.get(wid)
	if v == null:
		v = G6Fx.is_laser(wid)
		_laser_w[wid] = v
	return v


## from_w / from_s (MUZZLE7-2): specs starting at the shooter (world point within 0.6 tiles of from_w) start at the
## drawn barrel tip from_s (screen px) instead.
func _add_g6_list(specs: Array, from_w = null, from_s := Vector2.ZERO) -> void:
	for sp in specs:
		if _fx.size() >= MAX_FX:
			return
		var a: Vector2 = sp.a
		var b: Vector2 = sp.b
		if not bool(sp.get("own_only", false)) and not (mv.cell_visible(Vector2i(floori(a.x), floori(a.y)))
				or mv.cell_visible(Vector2i(floori(b.x), floori(b.y)))):
			continue
		var kd := String(sp.g6)
		if lod >= 2 and kd in ["nanite", "shimmer", "train_smoke", "jam"]:
			continue
		g6_made[kd] = int(g6_made.get(kd, 0)) + 1
		var sa: Vector2 = from_s if from_w is Vector2 and a.distance_to(from_w) < 0.6 else _w2s(a)
		if from_w is Vector2 and sa == from_s:
			muzzle7["beam"] = int(muzzle7.get("beam", 0)) + 1
		_fx.append({"kind": "g6", "g6": kd, "t": -float(sp.get("delay", 0.0)), "life": float(sp.life),
			"a": sa, "b": _w2s(b), "size": float(sp.get("size", 1.0)), "color": sp.color})


## Once per sim tick: smoke puffs over moving armoured trains.
func _g6_tick() -> void:
	var sn: Dictionary = mv.snap if mv != null else {}
	if sn.is_empty() or int(sn.get("tick", -1)) == _g6_smoke_tick or lod >= 2:
		return
	_g6_smoke_tick = int(sn.tick)
	if _g6_smoke_tick % 4 == 0:
		_add_g6_list(G6Fx.train_smoke(sn))


func _draw_g6(f: Dictionary, k: float) -> void:
	var col: Color = f.color
	var a: Vector2 = f.a
	var b: Vector2 = f.b
	var fade := 1.0 - k
	match String(f.g6):
		"laser", "ciws":
			# beam: wide soft glow + bright core, flickering out; CIWS adds a short burst of dashes
			var wdt: float = 2.0 if String(f.g6) == "laser" else 1.0
			draw_line(a + Vector2(0, -6), b + Vector2(0, -4), Color(col.r, col.g, col.b, 0.35 * fade), wdt * 4.0)
			draw_line(a + Vector2(0, -6), b + Vector2(0, -4), Color(1, 1, 1, 0.9 * fade), wdt)
			draw_circle(b + Vector2(0, -4), 3.0 + 4.0 * k, Color(col.r, col.g, col.b, 0.6 * fade))
		"net":
			var at := a.lerp(b, clampf(k * 3.0, 0.0, 1.0))
			draw_line(a, at, Color(col.r, col.g, col.b, 0.7 * fade), 1.0)
			var r := 4.0 + 10.0 * minf(1.0, k * 2.0)
			for i in 8:
				var q := at + Vector2.from_angle(TAU * i / 8.0) * Vector2(r, r * 0.6)
				var q2 := at + Vector2.from_angle(TAU * (i + 1) / 8.0) * Vector2(r, r * 0.6)
				draw_line(at, q, Color(col.r, col.g, col.b, fade), 1.0)
				draw_line(q, q2, Color(col.r, col.g, col.b, fade), 1.0)
		"jam":
			for i in 6:
				var ang := TAU * i / 6.0 + k * 3.0
				var p0 := a + Vector2.from_angle(ang) * Vector2(8.0 + 14.0 * k, (8.0 + 14.0 * k) * 0.5)
				var p1 := p0 + Vector2.from_angle(ang + 1.2) * 5.0
				draw_polyline(PackedVector2Array([p0, p1, p1 + Vector2.from_angle(ang - 0.9) * 5.0]), Color(col.r, col.g, col.b, fade), 1.0)
			_draw_iso_ring(a, 10.0 + 22.0 * k, Color(col.r, col.g, col.b, 0.5 * fade), 1.0)
		"sonar":
			# CR 843: ART-G6b sonar_ping sheet (8-frame expanding ring, outer radius 30 px at the last frame),
			# scaled to the contact radius; procedural iso ring when the sheet is missing
			var sp6 := ArtCatalog.fx_g6("sonar_ping", int(k * 8.0))
			if not sp6.is_empty():
				var sc := maxf(0.5, ISO_R * float(f.size) / 30.0)
				var tex: Texture2D = sp6.texture
				draw_texture_rect(tex, Rect2(a + (sp6.offset as Vector2) * sc, tex.get_size() * sc), false, Color(1, 1, 1, minf(1.0, fade * 1.6)))
			else:
				_draw_iso_ring(a, ISO_R * float(f.size) * k, Color(col.r, col.g, col.b, 0.8 * fade), 1.5)
		"mine_blast", "strike":
			var big := float(f.size)
			if not _draw_frames("explosion_large" if big >= 1.2 else "explosion_small", a, k, 1.0):
				var rr := 10.0 * big * (0.4 + k)
				draw_circle(a, rr, Color(1.0, 0.7 - k * 0.5, 0.2, fade))
			_draw_iso_ring(a, 14.0 * big * (0.5 + k), Color(0.45, 0.36, 0.25, 0.6 * fade), 2.0)
		"line_charge":
			var head := a.lerp(b, clampf(k * 1.8, 0.0, 1.0))
			draw_line(a, head, Color(col.r, col.g, col.b, 0.9), 1.5)
			draw_circle(head, 2.5, Color(1, 0.9, 0.5, 1.0))
		"chute":
			var hgt := 70.0 * (1.0 - k)
			var p := a + Vector2(sin(k * 7.0) * 3.0, -hgt)
			draw_arc(p + Vector2(0, -10), 9.0, PI, TAU, 10, Color(col.r, col.g, col.b, minf(1.0, fade * 3.0)), 3.0)
			draw_line(p + Vector2(-9, -10), p, Color(0.2, 0.2, 0.2, fade), 1.0)
			draw_line(p + Vector2(9, -10), p, Color(0.2, 0.2, 0.2, fade), 1.0)
			draw_rect(Rect2(p - Vector2(2, 0), Vector2(4, 4)), Color(0.35, 0.33, 0.25, minf(1.0, fade * 3.0)))
		"shimmer":
			for i in 5:
				var x := -10.0 + 5.0 * i
				var y0 := -4.0 - 26.0 * fmod(k + i * 0.17, 1.0)
				draw_line(a + Vector2(x, y0), a + Vector2(x + 1.5, y0 - 7.0), Color(col.r, col.g, col.b, 0.55 * fade), 1.0)
			_draw_iso_ring(a, 12.0 * (0.6 + k * 0.6), Color(col.r, col.g, col.b, 0.5 * fade), 1.0)
		"nanite":
			for i in int(f.size) * 3:
				var ang2 := TAU * float(i) / (float(f.size) * 3.0) + k * 5.0
				var rad := 6.0 + 14.0 * (1.0 - k)
				draw_circle(a + Vector2(cos(ang2) * rad, sin(ang2) * rad * 0.5 - 10.0 - 12.0 * k), 1.5, Color(col.r, col.g, col.b, fade))
		"assimilate":
			for i in 8:
				var u := fmod(k * 2.0 + i / 8.0, 1.0)
				var p2 := a.lerp(b, u) + Vector2(0, -sin(u * PI) * 14.0 - 6.0)
				draw_circle(p2, 1.5 * float(f.size), Color(col.r, col.g, col.b, 0.85 * fade))
		"train_smoke":
			var p3 := a.lerp(b, k) + Vector2(0, -22.0 - 20.0 * k)
			if not _draw_frames("smoke", p3, k, 0.8 * fade):
				draw_circle(p3, 4.0 + 8.0 * k, Color(col.r, col.g, col.b, 0.5 * fade))


func on_air_strike(ev: Dictionary) -> void:
	var p: Vector2 = ev.get("pos", Vector2.ZERO)
	if mv == null or not mv.cell_visible(Vector2i(floori(p.x), floori(p.y))) or _fx.size() >= MAX_FX:
		return
	var s: Vector2 = _w2s(p)
	_fx.append({"kind": "bomb", "name": "g5_air_bomb", "t": 0.0, "life": 0.45, "a": s + Vector2(_rng.randf_range(-6, 6), -80.0),
		"b": s, "size": 3.0, "color": Color(0.3, 0.3, 0.3)})
	air_fx.bombs += 1


func _bomb_landed(f: Dictionary) -> void:
	var b: Vector2 = f.b
	_fx.append({"kind": "air_fx", "name": "g5_bomb_blast", "t": 0.0, "life": 0.9, "a": b, "b": b, "size": 26.0, "color": Color(1, 0.55, 0.15)})
	_fx.append({"kind": "blast", "t": 0.0, "life": 0.6, "a": b, "b": b, "size": 40.0, "color": Color(1.0, 0.6, 0.2)})
	_e().explosion(b, 16.0, "crater")
	for i in 3:
		var off := Vector2(_rng.randf_range(-14, 14), _rng.randf_range(-6, 4))
		_fx.append({"kind": "smoke", "t": -_rng.randf_range(0.2, 0.5), "life": 1.8 + _rng.randf(),
			"a": b + off, "b": b + off + Vector2(_rng.randf_range(-8, 8), -36), "size": 6.0, "color": Color(0.28, 0.26, 0.24)})
	air_fx.blasts += 1


func _add_crash(s: Vector2, crashed: bool) -> void:
	_fx.append({"kind": "air_fx", "name": "g5_air_crash", "t": 0.0, "life": 0.8, "a": s, "b": s, "size": 20.0, "color": Color(1, 0.55, 0.15)})
	_fx.append({"kind": "explosion_large", "t": 0.0, "life": 0.7, "a": s + Vector2(0, -8), "b": s, "size": 18.0, "color": Color(1, 0.55, 0.15)})
	for i in (4 if crashed else 3):
		var off := Vector2(_rng.randf_range(-10, 10), _rng.randf_range(-4, 4))
		_fx.append({"kind": "air_fx", "name": "g5_air_smoke", "t": -_rng.randf_range(0.0, 0.6), "life": 2.4 + _rng.randf(),
			"a": s + off, "b": s + off + Vector2(_rng.randf_range(-10, 10), -46), "size": 8.0, "color": Color(0.2, 0.2, 0.2), "fade": true})
	air_fx.crashes += 1


## Per frame: trail puffs behind flying missiles; every 0.15 s a smoke puff behind each visible
## airborne aircraft below half health (snapshot only).
func _air_trails(delta: float) -> void:
	var add: Array = []
	for f in _fx:
		if String(f.kind) != "missile" or f.t < 0.0:
			continue
		f.tr += delta
		if f.tr >= 0.035:
			f.tr = 0.0
			var p: Vector2 = (f.a as Vector2).lerp(f.b, clampf(f.t / f.life, 0.0, 1.0))
			add.append({"kind": "air_fx", "name": "g5_missile_trail", "t": 0.0, "life": 0.35, "a": p, "b": p + Vector2(0, -3),
				"size": 3.0, "color": Color(0.9, 0.9, 0.9), "fade": true})
	air_fx.trails += add.size()
	_smoke_t += delta
	if _smoke_t >= 0.15 and lod < 2:
		_smoke_t = 0.0
		var sn: Dictionary = mv.snap if mv != null and mv.get("snap") is Dictionary else {}
		var air: Dictionary = sn.get("air", {})
		if not air.is_empty():
			var ids: PackedInt32Array = sn.ids
			var hp: PackedFloat32Array = sn.hp
			var pos: PackedVector2Array = sn.pos
			var flg: PackedInt32Array = sn.flags
			for i in int(sn.n):
				if hp[i] >= 0.5 or (flg[i] & RenderSnap.FLAG_AIR) == 0 or flg[i] & RenderSnap.FLAG_LANDED or not air.has(ids[i]):
					continue
				var p: Vector2 = pos[i]
				if not mv.cell_visible(Vector2i(floori(p.x), floori(p.y))):
					continue
				var l := _snap_lift(ids[i])
				if not bool(l[1]):
					continue
				var sp: Vector2 = _w2s(p) + Vector2(0, -float(l[0]))
				add.append({"kind": "air_fx", "name": "g5_air_smoke", "t": 0.0, "life": 0.9, "a": sp, "b": sp + Vector2(0, -10),
					"size": 5.0, "color": Color(0.2, 0.2, 0.2), "fade": true})
				air_fx.smoke += 1
	for f in add:
		if _fx.size() >= MAX_FX:
			break
		_fx.append(f)


func _fx_pivot(name: String, t: Texture2D) -> Vector2:
	var v = _pivot.get(name)
	if v == null:
		var pv = ArtCatalog.manifest().get("effects", {}).get(name, {}).get("pivot")
		v = Vector2(float(pv[0]), float(pv[1])) if pv is Array and (pv as Array).size() >= 2 else t.get_size() * 0.5
		_pivot[name] = v
	return v


func _draw_air_fx(f: Dictionary, k: float) -> void:
	var name := String(f.name)
	var arr: Array = _frames.get(name, [])
	var kd := String(f.kind)
	var p: Vector2 = (f.a as Vector2).lerp(f.b, k * k if kd == "bomb" else k)
	var alpha := (1.0 - k) if bool(f.get("fade", false)) else 1.0
	if arr.is_empty():
		var col: Color = f.color
		if kd == "missile":
			draw_line(p, (f.a as Vector2).lerp(f.b, maxf(0.0, k - 0.1)), Color(1, 1, 1, 0.6), 1.5)
		draw_circle(p, float(f.size) * (0.5 + k * 0.5), Color(col.r, col.g, col.b, alpha))
		return
	var idx: int
	if kd == "missile":
		idx = int(f.fi) % arr.size()
	elif kd == "bomb":
		idx = int(f.t * 12.0) % arr.size()
	else:
		idx = clampi(int(k * arr.size()), 0, arr.size() - 1)
	var tx: Texture2D = arr[idx]
	draw_texture(tx, p - _fx_pivot(name, tx), Color(1, 1, 1, alpha))


# ---------------------------------------------------------------- G6.1 (VFX61) per-frame + ambient
## Per frame: quality refresh (every 2 s), ambient scan once per snapshot tick, engine step, child redraws.
## Returns true while the engine has anything to draw.
func _night_amt() -> float:
	# FacAtmo7 night amount (0 day .. 1 night); safe when match_view / atmo is missing (tests).
	if mv == null:
		return 0.0
	var atmo = mv.get("fac_atmo7")
	if atmo == null or not atmo.has_method("night_amount"):
		return 0.0
	return float(atmo.night_amount())


func _fx61_frame(delta: float) -> bool:
	var e = _e()
	e.lod = lod
	e.night = _night_amt()
	_q_t -= delta
	if _q_t <= 0.0:
		_q_t = 2.0
		e.set_quality(_q_forced if _q_forced != "" else Fx61Core.quality_setting())
	var t0 := Time.get_ticks_usec()
	_fx61_scan()
	ViewUtil.prof_add("p_fx61_scan", t0)
	var busy: bool = not (e.parts.is_empty() and e.fixed.is_empty() and e.lights.is_empty() and e.emitters.is_empty())
	if busy:
		var t1 := Time.get_ticks_usec()
		e.tick(delta, _vr())
		ViewUtil.prof_add("p_fx61_tick", t1)
	if busy or not e.decals.is_empty():
		_dec_node.queue_redraw()
		_lit_node.queue_redraw()
	return busy or e.heat > 0.0


## Once per snapshot tick (never the live world): dust trails behind moving ground vehicles in view (staggered;
## colour by terrain, spray on water), fire emitters on burning buildings (hp < 40%) and burning forest cells.
func _fx61_scan() -> void:
	var sn: Dictionary = mv.snap if mv != null and mv.get("snap") is Dictionary else {}
	if sn.is_empty() or int(sn.get("tick", -1)) == _fx61_tick or not sn.has("flags"):
		return
	_fx61_tick = int(sn.tick)
	if lod >= 2:
		return
	var e = fx61
	var vr := _vr()
	var stg := 6 if String(e.q) == "low" else 3
	var flg: PackedInt32Array = sn.flags
	var pos: PackedVector2Array = sn.pos
	var fac: PackedFloat32Array = sn.facing
	var sdefs: PackedStringArray = sn.defs
	var sdef: PackedInt32Array = sn.def
	var skip := RenderSnap.FLAG_AIR | RenderSnap.FLAG_SHIP | RenderSnap.FLAG_ABOARD
	var vdef := PackedByteArray()   # per def index: 1 = ground vehicle (the def table is small)
	vdef.resize(sdefs.size())
	for di in sdefs.size():
		vdef[di] = 1 if _is_vehicle(sdefs[di]) else 0
	for i in range(_fx61_tick % stg, int(sn.n), stg):
		var fl: int = flg[i]
		if (fl & RenderSnap.FLAG_MOVING) == 0 or (fl & skip) != 0 or vdef[sdef[i]] == 0:
			continue
		var p: Vector2 = pos[i]
		var bp: Vector2 = p - Vector2(cos(fac[i]), sin(fac[i])) * 0.45
		var sp: Vector2 = _w2s(bp)
		if not vr.has_point(sp) or not mv.cell_visible(Vector2i(floori(p.x), floori(p.y))):
			continue
		var code := _terrain_at(bp)
		e.dust(sp, Fx61Core.dust_color(code), Fx61Core.is_water(code))
	if _fx61_tick % 20 == 0:
		_g7_drips(sn, e, vr)
	if _fx61_tick % 4 != 0:   # fires: every 4th snapshot is enough (emitter ttl 1.5 s)
		return
	var st: Dictionary = sn.get("statics", {})
	for id in st:
		var s: Dictionary = st[id]
		if String(s.get("kind", "")) != "building" or float(s.get("hp", 1.0)) >= 0.4 or not bool(s.get("built", true)):
			continue
		var bpos: Vector2 = s.pos
		if mv.cell_visible(Vector2i(floori(bpos.x), floori(bpos.y))):
			e.fire("b%d" % int(id), _w2s(bpos) + Vector2(0, -10), 5.0 + 2.0 * float(s.get("size", 2)), 1.5)
	var fires = sn.get("fires")
	var mw := int(sn.get("map_w", 0))
	if fires is PackedInt32Array and mw > 0:
		for ci in fires:
			var c := Vector2i(ci % mw, ci / mw)
			if mv.cell_visible(c):
				var fp: Vector2 = _w2s(Vector2(c) + Vector2(0.5, 0.5))
				if vr.has_point(fp):
					e.fire("c%d" % ci, fp, 6.0, 1.5)



## G7 (LOOK7): bleeding (snap.g7u bleed) or dragged casualties leave a blood trail; once a second, visible ones only.
var g7_drips := 0
func _g7_drips(sn: Dictionary, e, vr: Rect2) -> void:
	var gu: Dictionary = sn.get("g7u", {})
	if gu.is_empty():
		return
	var ids: PackedInt32Array = sn.ids
	var pos: PackedVector2Array = sn.pos
	for id in gu:
		var gv: Dictionary = gu[id]
		if not bool(gv.get("bleed", false)) and String(gv.get("cared", "")) != "drag":
			continue
		var k := ids.bsearch(int(id))
		if k >= int(sn.n) or ids[k] != int(id):
			continue
		var p: Vector2 = pos[k]
		var sp: Vector2 = _w2s(p)
		if not vr.has_point(sp) or not mv.cell_visible(Vector2i(floori(p.x), floori(p.y))):
			continue
		e.blood(sp + Vector2(0, 2), _rng.randf_range(2.5, 4.0), true)
		g7_drips += 1



## G7 (LOOK7, DRONE7 change_request.drone_fx): a distinct blast per surface for DroneBlast {pos, surface, weapon} and a
## small release puff for DroneMunitionAway {pos}. Visible cells only (own side always).
var drone_fx: Dictionary = {}   # surface / "release" -> effects started (tests / playtest)
func _drone_fx(ev: Dictionary) -> void:
	var p = ev.get("pos")
	if not (p is Vector2):
		return
	var own: bool = int(ev.get("owner", -1)) == int(mv.player_fid)
	if not own and not mv.cell_visible(Vector2i(floori(p.x), floori(p.y))):
		return
	var e = _e()
	e.lod = lod
	var s: Vector2 = _w2s(p)
	var kind := "release" if String(ev.get("type", "")) == "DroneMunitionAway" else String(ev.get("surface", "ground"))
	drone_fx[kind] = int(drone_fx.get(kind, 0)) + 1
	match kind:
		"release":
			e.part("puff", s + Vector2(0, -26), Vector2(0, -6), 0.6, 2.0, 6.0, Color(0.8, 0.8, 0.78, 0.5))
		"soldier":
			e.impact("dirt", s, 1.2)
			e.part("puff", s + Vector2(0, -4), Vector2(0, -10), 1.6, 4.0, 12.0, Color(0.45, 0.4, 0.34, 0.5))
			e.blood(s + Vector2(0, 2), 6.0, false)
		"wall":
			e.impact("building", s, 1.6)
			e.debris(s, 10.0, 2)
		"roof":
			e.impact("building", s + Vector2(0, -14), 1.4)
			e.part("puff", s + Vector2(0, -16), Vector2(0, -14), 2.5, 6.0, 18.0, Color(0.5, 0.47, 0.42, 0.45))
			e.debris(s, 12.0, 2)
		"air":
			e.part("glow", s + Vector2(0, -40), Vector2.ZERO, 0.1, 10.0, 16.0, Color(1, 0.9, 0.7, 0.9))
			e.part("ring", s + Vector2(0, -40), Vector2.ZERO, 0.5, 4.0, 22.0, Color(0.7, 0.7, 0.7, 0.6))
			e.part("puff", s + Vector2(0, -40), Vector2(0, -4), 3.0, 6.0, 16.0, Color(0.3, 0.3, 0.3, 0.45))
		_:
			e.explosion(s, 9.0, "scorch")


# ---------------------------------------------------------------- G7 CIWS7-4 (13.9c-32a): the roof CIWS stream
## Owner: "shooting in a strait line wherever the barrel is point w realistic bullet spread the further they shoot".
## One ciws7 ShotFired = one sim fire tick (2-3 rounds) or one intercept burst (60 rounds). Its rounds leave the drawn
## barrel tip (muzzle7: the art state the mount shows) and fly STRAIGHT along the mount's bearing this tick (ev.brg,
## the Traverse7 lay the sim fires from), laid in elevation on the target's range (ev.d) and height, each round
## deflected inside the dispersion cone (half-angle ev.sp) by a pure hash of (ev.sd, round): tight close, wide far.
## A round inside the target's radius (ev.rt) at its range ends on it (spark); the rest fly past and run on along their
## own straight line until they strike the ground (dust kick) or fade out CIWS7_OVER x the range away. The stream never
## bends to the target: if the target moved off the bore since the lay, the rounds go where the barrel points.
## Display only (reads the event + snapshot, writes nothing back).
const CIWS7_HPX := 28.0           # screen px per tile of height (vertical scale of the iso view)
const CIWS7_OVER := 1.7           # misses run on to this multiple of the target range
const CIWS7_ANG_PXM := 6.0         # CIWS7-5: screen barrel-vs-stream angle only for barrels drawn >= 6 px/m (>= 15 px long)
const CIWS7_ICPT_DRAW := 24       # tracers drawn for a 60-round intercept burst (spread over its length)
var ciws7_fx := {"ticks": 0, "rounds": 0, "on": 0, "past": 0, "ground": 0, "n_ang": 0, "max_ang": 0.0, "max_ang3": 0.0}   # evidence (tests / playtest); CIWS7-5: max angle (deg) between the drawn barrel of the frame shown and the stream, on screen (barrels drawn >= 2 px/m long) and in 3D
## Last stream drawn: {sid, from, brg, d, sp, rt, a (muzzle px), bore (bore end px at the target's range), rounds:
## [[ground point at range (world), lateral dev (tiles), vertical dev (tiles), on target, end px, strike]]}.
var ciws7_last: Dictionary = {}


## CIWS7-5: the art state the mount shows for shooter sid right now (same picker call as _bld_tips) -> [name, state dict].
func _ciws7_shown(sid: int) -> Array:
	var se = _ent(sid)
	if se == null:
		return ["", {}]
	var sn: Dictionary = mv.snap if mv != null and mv.get("snap") is Dictionary else {}
	var st = (sn.get("statics", {}) as Dictionary).get(sid)
	if not (st is Dictionary):
		st = se
	var b: Dictionary = ArtCatalog.manifest().get("buildings", {}).get(String(se.def), {})
	var sts: Dictionary = b.get("states", {})
	var nm := G5Art.building_state(sts, {"facing_i": int(st.get("facing_i", 0)), "hp": 1.0, "built": true, "firing": 1,
		"tb": st.get("tb"), "def": String(se.def)}, "rot")
	return [nm, sts.get(nm, {})]


## CIWS7-5: angle (deg) between the drawn barrel of state sd and the stream from muzzle a to bore point bp (screen;
## -1 when the barrel is drawn shorter than CIWS7_ANG_PXM px per metre, i.e. seen almost end-on: a stub whose
## on-screen direction is not defined) and in 3D (the
## barrel's world bore vs the line from the frame's muzzle to the aim point at height ht px, from = mount point).
static func ciws7_angles(sd: Dictionary, a: Vector2, bp: Vector2, from: Vector2, aim: Vector2, ht: float, roof_m: float) -> Vector2:
	if not (sd.get("ax") is Array) or not (sd.get("ax3") is Array):
		return Vector2(-1, -1)
	var ax := Vector2(float(sd.ax[0]), float(sd.ax[1]))
	var sa := -1.0
	if ax.length() >= CIWS7_ANG_PXM and (bp - a).length() > 0.5:
		sa = absf(rad_to_deg(ax.angle_to(bp - a)))
	var m3 := Vector3(float(sd.mz3[0]), float(sd.mz3[1]), float(sd.mz3[2]))
	var a3 := Vector3(float(sd.ax3[0]), float(sd.ax3[1]), float(sd.ax3[2]))
	var mw := from + Vector2(m3.x, m3.y) / 4.0
	var v := Vector3((aim.x - mw.x) * 4.0, (aim.y - mw.y) * 4.0, ht / 9.8 - (roof_m + m3.z))
	return Vector2(sa, rad_to_deg(a3.angle_to(v)))


## Pure hash of n -> [0, 1) (display spread; never randf, so a replayed fire tick fans its rounds the same way).
static func _c7h(n: int) -> float:
	var x := (n * 1103515245 + 12345) & 0x7fffffff
	x = (((x >> 13) ^ x) * 1274126177) & 0x7fffffff
	x = (x >> 16) ^ x
	return float(x % 1000003) / 1000003.0


## Deflection (lateral, vertical) in radians of round i of seed sd: uniform over the cone's disc of half-angle sp.
static func ciws7_dev(sd: int, i: int, sp: float) -> Vector2:
	var rho := sp * sqrt(_c7h(sd * 7 + i * 2 + 1))
	var phi := TAU * _c7h(sd * 13 + i * 2 + 2)
	return Vector2(rho * cos(phi), rho * sin(phi))


func _ciws7_stream(ev: Dictionary, from: Vector2, to: Vector2) -> void:
	if lod >= 2:
		return
	var sid := int(ev.get("shooter", -1))
	var tid := int(ev.get("target", -1))
	var d := maxf(float(ev.get("d", from.distance_to(to))), 0.3)
	var brg := float(ev.get("brg", (to - from).angle()))
	var sp := float(ev.get("sp", 0.08))
	var rt := float(ev.get("rt", 0.4))
	var sd := int(ev.get("sd", 0))
	var dirw := Vector2.from_angle(brg)
	var perp := Vector2(-dirw.y, dirw.x)
	var aim := from + dirw * d                 # where the bore points at the target's range (NOT the target)
	var a: Vector2 = _fx61_muzzle(ev, from, aim, "autocannon")   # flash / casings / smoke at the drawn barrel tip
	var h0 := maxf(_w2s(from).y - a.y, 0.0)    # muzzle height above the mount's roof-corner ground point (px)
	var icpt := ev.has("icpt") or tid < 0
	var ht := 0.0                              # height of the aim point (px)
	var air_t := false
	var shown: Array = _ciws7_shown(sid)       # CIWS7-5: the frame drawn now (its barrel = where the stream goes)
	var sdct: Dictionary = shown[1]
	var c7: Dictionary = (Content.building("cn_ciws7").get("ciws7", {}) as Dictionary)
	var roof_m := float(c7.get("roof_z", 15.5))
	if icpt:
		# an incoming shell / rocket: the stream climbs along the drawn (high band) barrel to meet it (CIWS7-5)
		var pitch := deg_to_rad(32.0)
		if sdct.get("ax3") is Array:
			pitch = asin(clampf(float(sdct.ax3[2]), -1.0, 1.0))
		var mzh := h0
		var hz := d * 4.0
		if sdct.get("mz3") is Array:
			mzh = (roof_m + float(sdct.mz3[2])) * 9.8
			hz = maxf((aim - (from + Vector2(float(sdct.mz3[0]), float(sdct.mz3[1])) / 4.0)).length() * 4.0, 0.5)
		ht = mzh + hz * tan(pitch) * 9.8
	else:
		var lt := _snap_lift(tid)
		air_t = bool(lt[1])
		ht = (float(lt[0]) + 4.0) if air_t else _height_for(tid) * 0.55
	var n := int(ev.get("rounds", 1))
	var draw_n := mini(n, CIWS7_ICPT_DRAW) if icpt else clampi(n, 1, 4)
	var span := float(n) / 50.0                # 3000 rpm: the rounds of this event come out over n / 50 s
	var lay := float(ev.get("lay_ticks", 0)) / 20.0 if icpt else 0.0
	# a drone the sim shot down this tick is shown with at least one round on it (ground fire scores rounds x share)
	var forced_on := not (air_t and bool(ev.get("hit", false)))
	var rounds: Array = []
	var e = _e()
	for i in draw_n:
		var dv := ciws7_dev(sd, i, sp)
		var lo := d * tan(dv.x)                # lateral miss at the target's range (tiles)
		var vo := d * tan(dv.y)                # vertical miss (tiles)
		var dev := sqrt(lo * lo + vo * vo)
		if not forced_on and i == draw_n - 1 and dev > rt * 0.8:
			lo *= rt * 0.6 / dev               # the sim scored a hit: this round is one of the rounds on target
			vo *= rt * 0.6 / dev
			dev = rt * 0.6
		var on := dev <= rt
		forced_on = forced_on or on
		var g := aim + perp * lo
		var h := ht + vo * CIWS7_HPX
		var tip: Vector2 = _w2s(g) - Vector2(0, h)
		var lam := 1.0 if on else CIWS7_OVER
		var strike := false
		if h0 - h > 0.001 and h0 + (h - h0) * lam <= 0.0:   # a descending round that reaches the ground first
			lam = h0 / (h0 - h)
			strike = true
		var end: Vector2 = a + (tip - a) * lam
		var delay := lay + span * (float(i) + 0.5) / float(draw_n)
		var life := clampf(0.07 + 0.011 * d * lam, 0.08, 0.32)
		if _fx.size() < MAX_FX:
			_fx.append({"kind": "tracer", "t": -delay, "life": life, "a": a, "b": end, "size": 1.3,
				"color": Color(1.0, 0.7, 0.32), "glow": 0.55})
		var t_hit := delay + life * 0.625      # the tracer head reaches its end at k = 1 / 1.6
		if on and not icpt:
			e.part("spark", end, Vector2(0, -30) + perp * 20.0, 0.18, 2.5, 1.0, Color(1.0, 0.85, 0.45), 200.0, t_hit)
			ciws7_fx.on += 1
		elif strike:
			e.part("puff", end, Vector2(0, -14), 0.55, 2.0, 7.0, Color(0.6, 0.55, 0.47, 0.55), 0.0, t_hit)
			e.part("spark", end, Vector2(0, -40), 0.12, 2.0, 1.0, Color(1.0, 0.8, 0.4), 260.0, t_hit)
			ciws7_fx.ground += 1
		else:
			ciws7_fx.past += 1
		rounds.append([g, lo, vo, on, end, strike])
	if icpt and bool(ev.get("hit", false)) and _fx.size() < MAX_FX:   # the shell / rocket / missile bursts in the air
		var bp: Vector2 = _w2s(aim) - Vector2(0, ht)
		_fx.append({"kind": "explosion_small", "t": -(lay + span * 0.7), "life": 0.4, "a": bp, "b": bp, "size": 8.0,
			"color": Color(1, 0.6, 0.2)})
	ciws7_fx.ticks += 1
	ciws7_fx.rounds += draw_n
	var bp: Vector2 = _w2s(aim) - Vector2(0, ht)
	var ang := ciws7_angles(sdct, a, bp, from, aim, ht, roof_m)
	if ang.y >= 0.0:
		ciws7_fx.n_ang += 1
		ciws7_fx.max_ang3 = maxf(float(ciws7_fx.max_ang3), ang.y)
		if ang.x >= 0.0:
			ciws7_fx.max_ang = maxf(float(ciws7_fx.max_ang), ang.x)
	ciws7_last = {"sid": sid, "tid": tid, "from": from, "brg": brg, "d": d, "sp": sp, "rt": rt, "a": a,
		"bore": bp, "rounds": rounds, "icpt": icpt, "state": String(shown[0]), "ang": ang.x, "ang3": ang.y}
