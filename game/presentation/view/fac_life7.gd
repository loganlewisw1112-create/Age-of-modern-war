extends Node2D
## G7 LIFE7 (13.9c-7 "a living facility"): activity, moving parts and the ops room of the counter-nanite facility.
## DISPLAY ONLY: never writes the sim. Reads CnFacility.render_entries (every 15 frames, only while no sim step is in
## flight, like baseprops_layer), CnFacility.conf() (static content json: doors, towers), the render snapshot (unit
## positions for waiting / arrivals / tower aim / strike-team blips) and step events (CnTeamReady). Never reads
## mv.world per frame. A match without a facility costs one cheap check every 15 frames.
##  1. Staff on real routes (Dijkstra over the compound floor, lanes preferred): technicians between workshop,
##     garages, pads and ops; gate guards checking arrivals (halt sign, check, wave through; crouch on an enemy);
##     a handler and guard dog walking the inner wall route, stopping at every tower; an ops runner.
##  2. Vehicles at work: forklifts carrying ammo crates magazine -> garages / pads (loaded out, empty back), a fuel
##     bowser servicing the pads (hose run while parked), a tow tractor that hooks onto the dropship nose while one
##     sits on the helipad. Every actor waits while a sim unit is in its way (they never block sim units).
##  3. Range: drills with the strike-team kit (move up, fire, check targets), Machine-replica pop-up targets rising
##     and falling when hit, the kill house cleared by a pair with muzzle / bang flashes and a red LIVE FIRE lamp.
##     Only while the base is secure (as the sim's own drills).
##  4. A perimeter quadcopter orbiting outside the walls (shadow + camera footprint on the ground) that returns to the
##     drone bay every few minutes (bay door opens: light spill, lands, door shuts, relaunches); garage shutters roll
##     open when a vehicle comes to their door (sim APC or a forklift) and shut behind it.
##  5. Moving parts: the ops radar turning, blinking obstruction / comms lights, glowing ops-room windows, tower
##     cupolas tracking the nearest enemy from the snapshot (slow sector sweep when there is none).
##  6. (removed, owner 13.9c-19: no ops-room inset over the command centre; it reads as a building only: lit windows,
##     radome, mast lights. The live strike-team map is the F4 Ops Room panel.)
##  Alarm (lockdown / breached only, owner 13.9c-17): technicians and staff run for the nearest door, vehicles stop, the
##  range goes cold, guards crouch facing out, the dog handler runs the route, the drone tightens its orbit.
## Deterministic: actor clocks advance per sim tick (not per frame) and only while their way is clear, so the same
## tick sequence with the same snapshots gives the same picture. Wiring (ORCH change_request life7.wire, match_view):
## create after vis7_layer with z_index 2, setup(self), refresh(snap) every frame after entity_layer.refresh(),
## on_events(evs) in _on_step_events.
const ViewUtil = preload("res://presentation/view/view_util.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const ArtCat = preload("res://presentation/art/art_catalog.gd")
const FacAtmo7 = preload("res://presentation/view/fac_atmo7.gd")   # POLISH7-5: light anchors shared with ATMO7 (13.9c-24)
const Engineer7 = preload("res://sim/systems/engineer7.gd")   # POLISH7-4: BOWSER_BAY (13.9c-21), a static rect (no sim reads)
const ART := "res://assets/art/g7_life7/"
const TR := 20.0
const DT := 1.0 / 20.0
const WALK := ["walk_a", "walk_1", "walk_2", "walk_b", "walk_4", "walk_5"]
const RUN := ["run_0", "run_1", "run_2", "run_3", "run_4", "run_5"]
const TROT := ["trot_0", "trot_1", "trot_2", "trot_3"]
## Footprint heights (px at zoom 1) used to hide an actor that walks behind a building (no figure ever drawn over the
## building in front of it). PROVISIONAL estimates from the ART7F sprites; unknown (new) zones use DEFAULT_H.
const ZONE_H := {"planning": 152.0, "lab": 54.0, "drone_bay": 44.0, "workshop": 114.0, "decon_hall": 44.0,
	"gate_outer": 46.0, "gate_inner": 46.0, "apc_wash": 30.0,
	# POLISH7: FACB7-2 fact facb7.zone_heights (board seq 3875, metres x 9.8 px/m, the tallest roof of the zone):
	# magazine headwall 3.9 (mound 2.9; the box starts at the headwall, see MAG_FORECOURT), armory suit bay 5.4,
	# aid station quarantine roof 4.4; POLISH7-3: FACB7-4 board seq 4583: planning = the 4-storey command centre (roof brim
	# 15.5 m = 152 px), barracks = 3 storeys + roof pad (helideck 11.6 m = 114 px); POLISH7-4: FACB7-5 seq 4783 (13.9c-18):
	# barracks now [16,14,4,2] (same key, helideck 11.6 m), workshop [16,9,4,4] carries the drone-bay storey (deck rail
	# 11.6 m = 114 px; was the 6.5 m high bay = 58 px, so the tow tractor parked behind it was drawn on the launch deck);
	# the drone_bay zone is stacked on the workshop (no box / building of its own)
	"magazine": 38.0, "armory": 114.0, "aid_station": 43.0, "barracks": 114.0}
## POLISH7-3 (FACB7-4 seq 4583): the range zone [2,21,8,4] holds a 2-storey training building (world x 2.1..5.7,
## y 21.25..24.8, parapet 8.9 m = 87 px) west of the open range: covered firing line (canopy 2.9 m, x 6.05..6.9),
## 4 rifle lanes y 21.15..23.6 firing east, steel targets at x 9.1, berm x 9.5..10.0. Offsets from the zone origin.
const RANGE_BLD := Rect2(0.1, 0.25, 3.6, 3.55)
const RANGE_BLD_H := 87.0
const RANGE_LANE_Y0 := 0.15        # first rifle lane edge (y 21.15)
const RANGE_LANE_W := 0.6125       # (23.6 - 21.15) / 4
const RANGE_FIRE_X := 4.55         # firing point under the canopy (x 6.55)
const RANGE_READY_X := 3.95        # waiting line between the training building and the canopy (x 5.95)
const RANGE_TARGET_X := 7.1        # steel targets (x 9.1)
const RANGE_CANOPY_Z := 28.4       # canopy roof 2.9 m
## POLISH7: the magazine's door side is an open forecourt: the headwall stands 3.9 m (0.975 tile) inside the zone edge
## (facb7.zone_heights), so a forklift loading at the door is not hidden by a box over the whole zone.
const MAG_FORECOURT := 0.975
const DEFAULT_H := 46.0
const GARAGE_H := 46.0
const TOWER_H := 122.0
const WALL_H := 36.0
const FLOOR_ZONES := ["pad", "helipad", "staging", "range", "fuel_point", "runoff"]
## Anchors on FACB7's art (px above the footprint point; PROVISIONAL, calibrated on the pt7_life7 shots).
const TOWER_TOP := 112.0       # tower roof centre (above the 2x2 tower centre; measured on pt7_life7 z2.5)
## The tracking cupola sits on FACB7's armoured cupola ring (tower-local (0.6, -0.5, 10.84) m; FACB7-2 drops its static
## roof gun there, board 3776): px from the tower ground point at zoom 1, measured where the static gun stood.
const CUPOLA_OFF := Vector2(9, -104)
const RADAR_AT := Vector2(0.35, 0.78)  # radar on the clear front-left of the ops roof (FACB7's lattice mast + dish
                                       # stand at its centre, vents back-right), fraction of the planning rect
const ROOF_H_OPS := 152.0              # ops roof brim (POLISH7-3: 4-storey command centre, FACB7-4 seq 4583: 15.5 m)
## FACB7's three red-tipped comms poles on the ops roof (px from the planning-rect centre ground point, zoom 1,
## measured on life7_ops_z3): the comms-mast lights blink on their tips.
## LIGHT7-5 (CR 5927): the command centre roof (brim 15.52 m, FACB7-4) carries the EW mast (its red lamp at roof + 8.4 m = 23.92 m) and an
## antenna farm of 4 whips (tips roof + 2.6 + 0.6 k m): tools/art/g7_fac7f.gd planning(), metres from the zone centre (door side +x, f 0)
## -> px from _iso(zone centre): EW lamp (3.8, 4.3) m, whip k 3 (-0.98, -3.53) m 19.92 m, whip k 1 (1.22, -3.53) m 18.72 m.
const MAST_TIPS := [Vector2(-4, -202), Vector2(20, -213), Vector2(38, -193)]
const DOOR_W := 0.62           # garage shutter width (fraction of the face) and height (px)
const DOOR_HPX := 30.0   # LIGHT7-2 CR 5926: art door height (FacAtmo7.DOOR_Z)
## POLISH7-4 (FACB7-5 seq 4783): the drone bay is the workshop's 2nd storey; the drone lands on the launch deck
## (10.57 m) on the deck spot DECK_SPOT (fraction of the workshop rect: the north spot, local y -2.35 m).
const DECK_Z := 10.57
const DECK_SPOT := Vector2(0.5, 0.35)
const SPEED := {"walk": 0.36, "run": 0.85, "forklift": 0.55, "fuel": 0.6, "tug": 0.5, "dog": 0.36}
const LOD_MIN := 0.7           # below this zoom only the moving parts (radar, cupolas, drone) are drawn

var mv = null
var hm: Dictionary = {}
var sheets: Dictionary = {}     # id -> {tex, fw, fh, piv, fi {frame: col}, rows}
var glows: Node2D
var _glow_tex: Texture2D
var facs: Array = []            # CnFacility.render_entries (last read)
var life: Array = []            # per facility: layout, occluders, nav grid, actors, door state
var _fac_key := ""
var _frame := 0
var _fac_frame := 0
var _tick := -1
var _alpha := 0.0
var _near_cells: Dictionary = {}   # Vector2i -> true: cells holding a sim unit this tick (near any compound)
var _near: Array = []              # [Vector2 pos, owner] near the compounds (cupola aim, arrivals)
var _sentinels: Array = []         # [id, Vector2] Sentinel units near a compound this tick (the dog heels beside one)
var _sent_prev: Dictionary = {}    # id -> Vector2 last tick
var _eng_job: Dictionary = {}      # 13.9c-11 engineer hook: unit id -> "forklift" | "forklift_empty" | "fuel"
var _eng_pos: Dictionary = {}      # unit id -> Vector2 (this tick, from the snapshot)
var _eng_prev: Dictionary = {}     # unit id -> Vector2 (last tick)
var _sent_def: Dictionary = {}     # snapshot def index -> true for Sentinel defs (cached per snapshot defs size)
var _sent_defs_n := -1
var _veh_def: Dictionary = {}      # POLISH7-4: snapshot def index -> true for fuel-using ground / air vehicles (fuel_max > 0)
var _vehs: Array = []              # [Vector2 pos, owner] of those near a compound this tick (the bowser leaves its bay for one)
var on := true                     # A/B switch (tests / playtest): off = nothing drawn, nothing read
var zoom := 1.0
var _onscreen := false
# evidence (tests / playtest)
var drawn := {}
var occluded := 0
var waits := 0
var inset_shown := false   # 13.9c-19: always false (the ops-room inset is gone; tests assert it)
var scans := 0
var rebuilds := 0
var _gone := {}   # POLISH7-2: facility id -> the entry of a facility missing from the last rebuild (kept state if it comes back)


func setup(view) -> void:
	mv = view
	if OS.get_cmdline_user_args().has("--no-life7"):   # fps A/B (bench child args + --no-life7)
		on = false
	var map: Dictionary = view.world.map if view != null and view.get("world") != null else {}
	hm = ViewUtil.height_map_of(map) if not map.is_empty() else {}
	_load_art()
	glows = Node2D.new()
	glows.name = "Life7Glows"
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glows.material = mat
	glows.draw.connect(_draw_glows)
	add_child(glows)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	_glow_tex = gt
	visible = false


func _load_art() -> void:
	var mp := ART + "manifest.json"
	if not FileAccess.file_exists(mp):
		return
	var man = JSON.parse_string(FileAccess.get_file_as_string(mp))
	if not (man is Dictionary):
		return
	for id in (man.get("life7", {}) as Dictionary):
		var e: Dictionary = man.life7[id]
		_add_sheet(String(id), ART + String(e.file), e)
	# range trainees wear the approved strike-team kit (ARTCN7 sheets through the catalog manifest)
	var inf: Dictionary = ArtCat.manifest().get("infantry", {})
	for cid in ["g7_cn_gunner", "g7_cn_team_leader", "g7_cn_radio", "g7_cn_medic"]:
		if inf.has(cid):
			var e: Dictionary = inf[cid]
			_add_sheet(cid, String(e.file), {"fw": e.fw, "fh": e.fh, "pivot": e.pivot, "frames": e.frames, "rows": 8})


func _add_sheet(id: String, path: String, e: Dictionary) -> void:
	if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
		return
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null or img.is_empty():
		return
	var fi := {}
	var fr: Array = e.get("frames", [])
	for i in fr.size():
		fi[String(fr[i])] = i
	sheets[id] = {"tex": ImageTexture.create_from_image(img), "fw": int(e.fw), "fh": int(e.fh),
		"piv": Vector2(float(e.pivot[0]), float(e.pivot[1])), "fi": fi, "rows": int(e.get("rows", 8))}


# ================================================================ per frame
func refresh(snap: Dictionary) -> void:
	if mv == null or not on:
		if visible:
			visible = false
		return
	_frame += 1
	if _frame % 15 == 1 and mv.has_method("sim_busy") and mv.sim_busy() and _frame - _fac_frame < 60:
		_frame -= 1   # the world would join the in-flight sim step; retry next frame (<= 1 s late)
	elif _frame % 15 == 1:
		_fac_frame = _frame
		var w = mv.get("world")
		facs = CnFacility.render_entries(w) if w != null and CnFacility.active(w) else []
		var key := str(facs.size())
		for F in facs:
			key += "|%d,%s,%s,%d,%s" % [int(F.id), str(F.lock), str(F.state), int(F.heli), str(F.zones)]
		if key != _fac_key:
			_fac_key = key
			_rebuild()
	if life.is_empty():
		if visible:
			visible = false
		return
	visible = true
	var cam = mv.get("camera")
	zoom = float(cam.zoom.x) if cam != null and cam.get("zoom") != null else 1.0
	_onscreen = _compound_on_screen()
	var st := int(snap.get("tick", -1))
	if st != _tick and st >= 0:
		var steps := clampi(st - _tick, 1, 10) if _tick >= 0 else 1
		_tick = st
		_on_tick(snap, steps)
	_alpha = clampf(float(mv.get("_alpha")) if mv.get("_alpha") != null else 0.0, 0.0, 1.0)
	_update_doors()
	if _onscreen:
		queue_redraw()
		glows.queue_redraw()


func on_events(evs: Array) -> void:
	for ev in evs:
		var ty := String(ev.get("type", ""))
		if ty == "Eng7Job":   # 13.9c-11: a Facility Engineer starts / ends a driving job (ENG7 emits it)
			attach_engineer(int(ev.get("unit", -1)), String(ev.get("job", "")))
		elif ty == "EntityDestroyed" and _eng_job.has(int(ev.get("id", -1))):
			attach_engineer(int(ev.id), "")


## 13.9c-11 engineer hook (fact life7.engineer_hook). A Facility Engineer driving a facility vehicle: job "forklift"
## (carrying a load), "forklift_empty" (driving back), "fuel" (the fuel bowser), "" = the job ended (the vehicle goes
## back to its own display route). While attached, the k-th display forklift (by unit id order) / the fuel truck is
## drawn at that unit's snapshot position, facing its motion; the unit itself should not draw (ENG7: hide the figure
## while e.eng_drive or similar). Display only: nothing here reads or writes the sim.
func attach_engineer(unit_id: int, job: String) -> void:
	if unit_id < 0:
		return
	if job in ["forklift", "forklift_empty", "fuel"]:
		_eng_job[unit_id] = job
	else:
		_eng_job.erase(unit_id)
		_eng_pos.erase(unit_id)
		_eng_prev.erase(unit_id)


## The engineer driving display actor a (a forklift or the fuel truck) right now, else -1.
func _driver_of(Lf: Dictionary, a: Dictionary) -> int:
	if _eng_job.is_empty():
		return -1
	var kind := String(a.kind)
	var want := "fuel" if kind == "fuel" else "forklift"
	var ids := []
	for id in _eng_job:
		if String(_eng_job[id]).begins_with(want) and _eng_pos.has(id) and (Lf.cr as Rect2).grow(3.0).has_point(_eng_pos[id]):
			ids.append(int(id))
	if ids.is_empty():
		return -1
	ids.sort()
	var k := 0
	for b in Lf.actors:   # this actor's index among the facility's actors of its kind
		if b == a:
			break
		if String(b.kind) == kind:
			k += 1
	return int(ids[k]) if k < ids.size() else -1


func _drive_at(a: Dictionary, uid: int) -> void:
	var p: Vector2 = _eng_pos[uid]
	var pp: Vector2 = _eng_prev.get(uid, p)
	var moving := p.distance_to(pp) > 0.005
	if moving:
		a.face = (p - pp).angle()
	a.p = pp.lerp(p, _alpha)
	a.moving = moving
	a.hidden = false
	a.at = ""
	a.load = String(_eng_job[uid]) == "forklift"
	a.pose = "drive" if moving else "park"
	a.dwell_t = 0.0
	a.dwell_len = 1.0
	a.hose = null
	a.driver = uid


## Display time (s) of this frame: the sim tick plus the interpolation inside it.
## Evaluates every actor at the current display time; [{kind, p, face, pose, hidden}] (tests / playtest evidence).
func eval_all() -> Array:
	var out := []
	for Lf in life:
		for a in Lf.actors:
			_eval(Lf, a)
			out.append({"kind": String(a.kind), "p": a.p, "face": float(a.face), "pose": String(a.pose), "hidden": bool(a.hidden), "fac": int(Lf.id)})
	return out


func now() -> float:
	return (float(maxi(_tick, 0)) + _alpha) / TR


# ================================================================ layout
func _rebuild() -> void:
	rebuilds += 1
	var old := _gone.duplicate()   # POLISH7-2: a facility that drops out of render_entries for one rebuild keeps its state
	for Lf in life:
		old[int(Lf.id)] = Lf
	var seen := {}
	for F in facs:
		seen[int(F.id)] = true
	_gone = {}
	for id in old:
		if not seen.has(id):
			_gone[id] = old[id]
	life = []
	for F in facs:
		var Lf := _layout(F)
		if old.has(int(F.id)):   # keep the clocks / doors / alarm of a facility whose state only changed
			var o: Dictionary = old[int(F.id)]
			Lf.doors = o.doors
			Lf.alarm_t = o.alarm_t
			Lf.calm_t = o.calm_t
			Lf.aims = o.aims
			if (o.actors as Array).size() == (Lf.actors as Array).size():
				for i in (Lf.actors as Array).size():
					Lf.actors[i].clock = float(o.actors[i].clock)
					Lf.actors[i].face = float(o.actors[i].face)
		var alarm := bool(F.lock) or String(F.state) == "breached"   # POLISH7-2 (13.9c-17): under fire / contested = life goes on
		if alarm and not bool(Lf.get("alarm", false)) and (not old.has(int(F.id)) or not bool(old[int(F.id)].get("alarm", false))):
			Lf.alarm_t = now()
		if not alarm and old.has(int(F.id)) and bool(old[int(F.id)].get("alarm", false)):
			Lf.calm_t = now()
		Lf.alarm = alarm
		life.append(Lf)
	if life.is_empty():
		visible = false


func _r(a) -> Rect2:
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3])) if a is Array and (a as Array).size() == 4 else Rect2()


func _layout(F: Dictionary) -> Dictionary:
	var cr := _r(F.compound)
	var O := cr.position
	var cs := int(cr.size.x)
	var c := CnFacility.conf()
	var zs := {}
	for zn in (F.zones as Dictionary):
		zs[String(zn)] = _r(F.zones[zn])
	var Lf := {"id": int(F.id), "owner": int(F.owner), "O": O, "cs": cs, "cr": cr, "zones": zs, "F": F, "boxes": [],
		"doors": {}, "alarm": false, "alarm_t": -100.0, "calm_t": -100.0, "aims": {}, "actors": [], "garages": [],
		"towers": [], "heli": int(F.heli), "secure": String(F.state) == "secure" and not bool(F.lock),
		"lift": ViewUtil.ground_lift(hm, cr.get_center()) if not hm.is_empty() else 0.0}
	# occluders: wall strips, towers, garages, every non-floor zone
	var bx: Array = Lf.boxes
	bx.append(_box(Rect2(O, Vector2(cs, 2)), WALL_H))
	bx.append(_box(Rect2(O, Vector2(2, cs)), WALL_H))
	bx.append(_box(Rect2(O + Vector2(0, cs - 2), Vector2(cs, 2)), WALL_H))
	bx.append(_box(Rect2(O + Vector2(cs - 2, 0), Vector2(2, cs)), WALL_H))
	for t in c.get("towers", []):
		var tp := O + Vector2(float(t[0]), float(t[1]))
		bx.append(_box(Rect2(tp, Vector2(2, 2)), TOWER_H))
		(Lf.towers as Array).append(tp + Vector2(1, 1))
	for g in F.get("garage_rects", []):
		var gr := _r(g)
		bx.append(_box(gr, GARAGE_H))
		(Lf.garages as Array).append(gr)
	var stacked: Dictionary = F.get("stacked", c.get("stacked", {}))   # FACB7-5: {drone_bay: workshop} = an upper storey
	for zn in zs:
		if FLOOR_ZONES.has(zn) or (zs[zn] as Rect2).size == Vector2.ZERO or stacked.has(zn):
			continue
		var zb: Rect2 = zs[zn]
		if zn == "magazine":   # POLISH7: no box over the forecourt in front of the headwall
			match int((F.get("faces", {}) as Dictionary).get(zn, 3)):
				0: zb = zb.grow_individual(0, 0, -MAG_FORECOURT, 0)
				1: zb = zb.grow_individual(0, 0, 0, -MAG_FORECOURT)
				2: zb = zb.grow_individual(-MAG_FORECOURT, 0, 0, 0)
				_: zb = zb.grow_individual(0, -MAG_FORECOURT, 0, 0)
		bx.append(_box(zb, float(ZONE_H.get(zn, DEFAULT_H))))
	if zs.has("range") and (zs.range as Rect2).size != Vector2.ZERO:   # POLISH7-3: the 2-storey training building
		bx.append(_box(Rect2((zs.range as Rect2).position + RANGE_BLD.position, RANGE_BLD.size), RANGE_BLD_H))
	# nav grid over the compound floor: 0 blocked, else step cost (lanes 2, paved floors 3, gravel 5)
	var grid := PackedByteArray()
	grid.resize(cs * cs)
	grid.fill(0)
	for y in range(2, cs - 2):
		for x in range(2, cs - 2):
			grid[y * cs + x] = 5
	for zn in FLOOR_ZONES:
		if zs.has(zn):
			_paint(grid, cs, O, zs[zn], 3)
	for l in F.get("lanes", []):
		_paint(grid, cs, O, _r(l), 2)
	for gr in Lf.garages:
		_paint(grid, cs, O, gr, 0)
	for zn in zs:
		if not FLOOR_ZONES.has(zn):
			_paint(grid, cs, O, zs[zn], 0)
	if zs.has("range"):
		_paint(grid, cs, O, zs.range, 0)   # the range is fenced off: only the trainees use it
	# POLISH7-4 (13.9c-21): the fuel bowser's marked parking bay (Engineer7.BOWSER_BAY, the sim bowser parks there too):
	# no other actor walks or drives through it (cells whose centre lies in the bay are blocked)
	var bay := Rect2(O + Engineer7.bay_local().position, Engineer7.bay_local().size)
	Lf["fuel_bay"] = bay
	for y in range(int(floor(bay.position.y - O.y)), int(ceil(bay.end.y - O.y))):
		for x in range(int(floor(bay.position.x - O.x)), int(ceil(bay.end.x - O.x))):
			if x >= 0 and y >= 0 and x < cs and y < cs and bay.has_point(O + Vector2(x + 0.5, y + 0.5)):
				grid[y * cs + x] = 0
	Lf["grid"] = grid
	var host := String(stacked.get("drone_bay", ""))
	Lf["deck"] = zs.get(host, Rect2()) if host != "" else Rect2()
	# doors: content json doors (compound-relative cells just outside the building), else the nearest free cell
	var dr := {}
	var cd: Dictionary = c.get("doors", {})
	for zn in zs:
		if FLOOR_ZONES.has(zn):
			continue
		if cd.has(zn) and (cd[zn] as Array).size() > 0:
			var d0: Array = cd[zn][0]
			dr[zn] = O + Vector2(float(d0[0]) + 0.5, float(d0[1]) + 0.5)
		else:
			dr[zn] = _free_near(Lf, zs[zn])
	var gd := []
	for gr in Lf.garages:   # shutter on the face toward the compound centre
		var east: bool = (gr as Rect2).get_center().x < cr.get_center().x
		gd.append(Vector2((gr as Rect2).end.x + 0.45 if east else (gr as Rect2).position.x - 0.45, (gr as Rect2).get_center().y))
	Lf["door_pt"] = dr
	Lf["garage_door"] = gd
	for i in gd.size():
		Lf.doors["g%d" % i] = 0.0
	Lf.doors["drone_bay"] = 0.0
	_actors(Lf)
	return Lf


func _paint(grid: PackedByteArray, cs: int, O: Vector2, r: Rect2, v: int) -> void:
	for y in range(int(floor(r.position.y - O.y)), int(ceil(r.end.y - O.y))):
		for x in range(int(floor(r.position.x - O.x)), int(ceil(r.end.x - O.x))):
			if x >= 2 and y >= 2 and x < cs - 2 and y < cs - 2:
				if v == 0 or grid[y * cs + x] != 0:
					grid[y * cs + x] = v


func _walk(Lf: Dictionary, c: Vector2i) -> bool:
	var cs: int = Lf.cs
	return c.x >= 0 and c.y >= 0 and c.x < cs and c.y < cs and (Lf.grid as PackedByteArray)[c.y * cs + c.x] != 0


## Nearest walkable cell centre (world) around rect r, preferring the side facing the compound centre.
func _free_near(Lf: Dictionary, r: Rect2) -> Vector2:
	var O: Vector2 = Lf.O
	var ctr: Vector2 = (Lf.cr as Rect2).get_center()
	var best := ctr
	var bd := INF
	for y in range(int(floor(r.position.y - O.y)) - 1, int(ceil(r.end.y - O.y)) + 1):
		for x in range(int(floor(r.position.x - O.x)) - 1, int(ceil(r.end.x - O.x)) + 1):
			if not _walk(Lf, Vector2i(x, y)):
				continue
			var p := O + Vector2(x + 0.5, y + 0.5)
			var d := p.distance_to(ctr)
			if d < bd:
				bd = d
				best = p
	return best


## p when an actor standing there is drawn (not behind a building); else the nearest such walkable point within 3 tiles.
func _vis_spot(Lf: Dictionary, p: Vector2, hz: float) -> Vector2:
	if not _occluded(Lf, p, hz):
		return p
	var best := p
	var bd := INF
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var q := p + Vector2(dx, dy)
			var d := float(dx * dx + dy * dy)
			if d >= bd or d == 0.0 or not _walk(Lf, _cell(Lf, q)) or _occluded(Lf, q, hz):
				continue
			bd = d
			best = q
	return best


func _cell(Lf: Dictionary, p: Vector2) -> Vector2i:
	var q: Vector2 = p - (Lf.O as Vector2)
	return Vector2i(int(floor(q.x)), int(floor(q.y)))


## Nearest walkable cell to world point p (p itself when walkable).
func _snap(Lf: Dictionary, p: Vector2) -> Vector2i:
	var c := _cell(Lf, p)
	if _walk(Lf, c):
		return c
	for rad in range(1, 6):
		var best := Vector2i(-1, -1)
		var bd := INF
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				var q := c + Vector2i(dx, dy)
				if _walk(Lf, q) and Vector2(q - c).length() < bd:
					bd = Vector2(q - c).length()
					best = q
		if best.x >= 0:
			return best
	return c


## Cheapest 4-way route over the nav grid (bucket-queue Dijkstra), as world points from a to b (corners only).
func _path(Lf: Dictionary, a: Vector2, b: Vector2) -> PackedVector2Array:
	var cs: int = Lf.cs
	var grid: PackedByteArray = Lf.grid
	var O: Vector2 = Lf.O
	var s := _snap(Lf, a)
	var g := _snap(Lf, b)
	var out := PackedVector2Array([a])
	if s == g or not _walk(Lf, s) or not _walk(Lf, g):
		out.append(b)
		return out
	var n := cs * cs
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(1 << 29)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var buckets := {}
	var si := s.y * cs + s.x
	var gi := g.y * cs + g.x
	dist[si] = 0
	buckets[0] = [si]
	var d := 0
	var maxd := n * 6
	while d <= maxd:
		if not buckets.has(d):
			d += 1
			continue
		var bq: Array = buckets[d]
		buckets.erase(d)
		var done := false
		for i in bq:
			if dist[i] != d:
				continue
			if i == gi:
				done = true
				break
			var x: int = int(i) % cs
			var y: int = int(i) / cs
			for nb in [Vector2i(x + 1, y), Vector2i(x - 1, y), Vector2i(x, y + 1), Vector2i(x, y - 1)]:
				if nb.x < 0 or nb.y < 0 or nb.x >= cs or nb.y >= cs:
					continue
				var j: int = nb.y * cs + nb.x
				var cst := int(grid[j])
				if cst == 0:
					continue
				var nd := d + cst
				if nd < dist[j]:
					dist[j] = nd
					prev[j] = i
					if not buckets.has(nd):
						buckets[nd] = []
					(buckets[nd] as Array).append(j)
		if done:
			break
		d += 1
	if prev[gi] < 0:
		out.append(b)
		return out
	var cells := []
	var k := gi
	while k >= 0 and k != si:
		cells.append(k)
		k = prev[k]
	cells.reverse()
	var last_dir := Vector2i.ZERO
	var pc := s
	for ci in cells:
		var cc := Vector2i(ci % cs, ci / cs)
		var dv := cc - pc
		if dv != last_dir and pc != s:
			out.append(O + Vector2(pc) + Vector2(0.5, 0.5))
		last_dir = dv
		pc = cc
	out.append(b)
	return out


# ================================================================ actors
## Actor: a looping itinerary of stops {p, dwell, pose, face, load}; legs between stops are routed once here.
func _actor(Lf: Dictionary, kind: String, sheet: String, stops: Array, speed: float, phase: float, extra := {}) -> Dictionary:
	var segs := []
	var t := 0.0
	var n := stops.size()
	var hz := 40.0 if kind == "fuel" else (24.0 if kind in ["forklift", "tug"] else 18.0)
	for st in stops:   # a dwell (working, parked) happens where the camera can see it, never behind a building
		if String(st.get("pose", "")) != "hide" and kind != "gate" and not bool(st.get("fixed", false)):
			st.p = _vis_spot(Lf, st.p, hz)
	for i in n:
		var s: Dictionary = stops[i]
		var dw := float(s.get("dwell", 0.0))
		if dw > 0.0:
			segs.append({"t0": t, "t1": t + dw, "m": false, "p": s.p, "pose": String(s.get("pose", "idle")),
				"face": float(s.get("face", -99.0)), "load": bool(s.get("load", false)), "at": String(s.get("at", "")),
				"job": s.get("job", null)})
			t += dw
		if n < 2:
			continue
		var nx: Dictionary = stops[(i + 1) % n]
		var pts := _path(Lf, s.p, nx.p) if not bool(s.get("direct", false)) else PackedVector2Array([s.p, nx.p])
		var cum := PackedFloat32Array([0.0])
		for j in range(1, pts.size()):
			cum.append(cum[j - 1] + pts[j - 1].distance_to(pts[j]))
		var ln := cum[cum.size() - 1]
		if ln > 0.01:
			segs.append({"t0": t, "t1": t + ln / speed, "m": true, "pts": pts, "cum": cum, "len": ln,
				"load": bool(s.get("load_out", false)), "rev": bool(s.get("rev_out", false))})
			t += ln / speed
	var a := {"kind": kind, "sheet": sheet, "segs": segs, "T": maxf(t, 0.1), "clock": phase * maxf(t, 0.1), "face": 0.0,
		"civil": kind in ["tech", "staff", "forklift", "fuel", "tug"], "p": Vector2.ZERO, "moving": false, "pose": "idle",
		"hidden": false, "wait": false, "speed": speed}
	a.merge(extra)
	(Lf.actors as Array).append(a)
	return a


func _zone_c(Lf: Dictionary, zn: String, fx := 0.5, fy := 0.5) -> Vector2:
	var r: Rect2 = (Lf.zones as Dictionary).get(zn, Rect2())
	return r.position + r.size * Vector2(fx, fy)


func _door(Lf: Dictionary, zn: String) -> Vector2:
	if FLOOR_ZONES.has(zn) and (Lf.zones as Dictionary).has(zn):
		return _zone_c(Lf, zn)
	return (Lf.door_pt as Dictionary).get(zn, (Lf.cr as Rect2).get_center())


## First zone whose name contains one of keys (FACB7's new buildings: magazine, fuel point, armory, aid station).
func _find_zone(Lf: Dictionary, keys: Array, fallback: String) -> String:
	var names: Array = (Lf.zones as Dictionary).keys()
	names.sort()
	for k in keys:
		for zn in names:
			if String(zn).contains(k):
				return String(zn)
	return fallback


func _actors(Lf: Dictionary) -> void:
	var zs: Dictionary = Lf.zones
	var gd: Array = Lf.garage_door
	var cr: Rect2 = Lf.cr
	var ctr := cr.get_center()
	var shop := "workshop" if zs.has("workshop") else "planning"
	var ops := "planning" if zs.has("planning") else shop
	var mag := _find_zone(Lf, ["magazine", "ammo"], shop)
	var west := []
	var east := []
	for i in gd.size():
		if (gd[i] as Vector2).x < ctr.x:
			west.append(i)
		else:
			east.append(i)
	var pad := _zone_c(Lf, "pad") if zs.has("pad") else ctr
	var heli := _zone_c(Lf, "helipad") if zs.has("helipad") else ctr
	var padr: Rect2 = zs.get("pad", Rect2(ctr, Vector2.ONE))
	var hr: Rect2 = zs.get("helipad", Rect2(ctr, Vector2.ONE))
	var gp := func(i: int) -> Vector2:
		return gd[clampi(i, 0, gd.size() - 1)] if not gd.is_empty() else ctr
	var gw := func(k: int) -> int:
		return int(west[k % west.size()]) if not west.is_empty() else 0
	var ge := func(k: int) -> int:
		return int(east[k % east.size()]) if not east.is_empty() else 0
	# technicians
	_actor(Lf, "tech", "fig_tech", [{"p": _door(Lf, shop), "dwell": 6.0, "pose": "hide"},
		{"p": gp.call(gw.call(0)), "dwell": 11.0, "pose": "act", "at": "g%d" % gw.call(0)},
		{"p": gp.call(gw.call(2)), "dwell": 9.0, "pose": "act", "at": "g%d" % gw.call(2)},
		{"p": _door(Lf, ops), "dwell": 5.0, "pose": "hide"}], SPEED.walk, 0.0)
	_actor(Lf, "tech", "fig_tech", [{"p": _door(Lf, shop), "dwell": 5.0, "pose": "hide"},
		{"p": Vector2(padr.end.x - 0.6, padr.end.y - 0.7), "dwell": 13.0, "pose": "act"},
		{"p": Vector2(hr.position.x + 0.6, hr.end.y - 0.6), "dwell": 10.0, "pose": "act"},
		{"p": _door(Lf, "drone_bay"), "dwell": 6.0, "pose": "hide"}], SPEED.walk, 0.35)
	_actor(Lf, "tech", "fig_tech", [{"p": _door(Lf, "lab" if zs.has("lab") else shop), "dwell": 7.0, "pose": "hide"},
		{"p": gp.call(ge.call(1)), "dwell": 12.0, "pose": "act", "at": "g%d" % ge.call(1)},
		{"p": gp.call(ge.call(3)), "dwell": 8.0, "pose": "act", "at": "g%d" % ge.call(3)},
		{"p": _door(Lf, shop), "dwell": 6.0, "pose": "hide"}], SPEED.walk, 0.6)
	_actor(Lf, "tech", "fig_tech", [{"p": _door(Lf, "drone_bay"), "dwell": 8.0, "pose": "hide"},
		{"p": Vector2(hr.position.x + 0.7, hr.position.y + 0.8), "dwell": 9.0, "pose": "act"},
		{"p": Vector2(padr.position.x + 0.8, padr.end.y - 0.8), "dwell": 11.0, "pose": "act"}], SPEED.walk, 0.15)
	# ops runner (staff): ops -> lab -> aid / armory -> ops
	var aid := _find_zone(Lf, ["aid", "armory", "decon_hall"], ops)
	_actor(Lf, "staff", "fig_staff", [{"p": _door(Lf, ops), "dwell": 14.0, "pose": "hide"},
		{"p": _door(Lf, "lab" if zs.has("lab") else ops), "dwell": 7.0, "pose": "hide"},
		{"p": _door(Lf, aid), "dwell": 6.0, "pose": "hide"}], SPEED.walk * 1.15, 0.5)
	# forklifts: magazine -> garages / pad (loaded out), back empty
	_actor(Lf, "forklift", "forklift", [{"p": _door(Lf, mag), "dwell": 7.0, "pose": "load", "load_out": true},
		{"p": gp.call(gw.call(1)) + Vector2(0.9 if gp.call(gw.call(1)).x < ctr.x else -0.9, 0), "dwell": 6.0, "pose": "unload", "load": true, "at": "g%d" % gw.call(1)}],
		SPEED.forklift, 0.1)
	_actor(Lf, "forklift", "forklift", [{"p": _door(Lf, mag), "dwell": 8.0, "pose": "load", "load_out": true},
		{"p": Vector2(padr.position.x + padr.size.x * 0.5, padr.end.y + 0.6), "dwell": 7.0, "pose": "unload", "load": true},
		{"p": _door(Lf, mag), "dwell": 8.0, "pose": "load", "load_out": true},
		{"p": gp.call(ge.call(2)) + Vector2(-0.9 if gp.call(ge.call(2)).x > ctr.x else 0.9, 0), "dwell": 6.0, "pose": "unload", "load": true, "at": "g%d" % ge.call(2)}],
		SPEED.forklift, 0.55)
	# fuel bowser (POLISH7-4, owner 13.9c-21; POLISH7-5, 13.9c-21a): ONE marked parking bay (Engineer7.BOWSER_BAY, a
	# lay-by in the service alley between the workshop and the barracks' back wall, its mouth on the spine lane, nothing
	# opening onto it); it parks there nose out (Engineer7.bay_heading(), toward the mouth) and only leaves to refuel an
	# own vehicle actually standing on the pad / helipad (the bay dwell holds until one is there, see _on_tick): it
	# drives straight out onto the lane, hoses the vehicle from the fuel point's strip (POLISH7-2 / SEQ7-3 spots, clear of
	# the APC line-up), and reverses back into the bay from the mouth. An engineer's real refuelling run carries it
	# instead (13.9c-11 hook; the sim bowser parks in the same bay, engineer7.gd).
	var bay: Rect2 = Lf.fuel_bay
	var bpark := bay.get_center()
	var bdir := Vector2.from_angle(Engineer7.bay_heading())
	var bface := Engineer7.bay_heading()
	var mouth := bpark + bdir * (absf(bdir.x) * bay.size.x * 0.5 + absf(bdir.y) * bay.size.y * 0.5 + 0.65)
	_actor(Lf, "fuel", "fuel_truck", [{"p": bpark, "dwell": 30.0, "pose": "park", "face": bface, "fixed": true, "direct": true, "job": padr},
		{"p": mouth},
		{"p": Vector2(padr.end.x + 0.3, padr.position.y + 1.2), "dwell": 16.0, "pose": "hose", "hose": pad},
		{"p": mouth, "direct": true, "rev_out": true},
		{"p": bpark, "dwell": 30.0, "pose": "park", "face": bface, "fixed": true, "direct": true, "job": hr},
		{"p": mouth},
		{"p": Vector2(hr.position.x - 0.3, hr.position.y + 1.6), "dwell": 16.0, "pose": "hose", "hose": heli},
		{"p": mouth, "direct": true, "rev_out": true}],
		SPEED.fuel, 0.0, {"bay": bpark})
	# tow tractor: parks in the helipad's north-west corner, in plain sight (POLISH7-4: was (hr.x - 1, hr.end.y + 0.6) on
	# the y8 lane right behind the workshop, whose real 11.6 m drone-bay storey then drew it "on the launch deck"); hooks
	# onto the dropship nose while one is on the pad
	var park := hr.position + Vector2(0.6, 0.55)
	var nose := heli + Vector2(hr.size.x * 0.5 + 0.9, 0)
	if int(Lf.heli) > 0:
		_actor(Lf, "tug", "tow_tractor", [{"p": park, "dwell": 18.0, "pose": "park", "face": PI * 0.5},
			{"p": nose, "dwell": 22.0, "pose": "tow", "face": PI, "tow": heli + Vector2(hr.size.x * 0.32, 0)}], SPEED.tug, 0.0)
	else:   # nothing to tow: it stays parked (POLISH7-4: no idle shuttle to a second "park" spot behind the workshop)
		_actor(Lf, "tug", "tow_tractor", [{"p": park, "dwell": 24.0, "pose": "park", "face": PI * 0.5}], SPEED.tug, 0.0)
	# guard dog (13.9c-10: the wall guards and interior patrols are SENT7's real Sentinel units): the dog heels beside
	# the first Sentinel patrolling inside the compound (snapshot), else it waits at its kennel by the ready room.
	var kennel := _door(Lf, _find_zone(Lf, ["ready"], shop)) + Vector2(0.6, 0.4)
	if zs.has("barracks"):   # POLISH7-5 (13.9c-21a): against the barracks' back wall at the east end of the service alley
		var br: Rect2 = zs.barracks   # (POLISH7-2 had it at the front corner, which stood on the y16 lane), off every
		kennel = Vector2(br.end.x - 0.5, br.position.y - 0.5)   # lane, door front and the fuel bay (west end of the alley)
	_actor(Lf, "dog", "dog", [{"p": kennel, "dwell": 30.0, "pose": "kennel", "face": PI * 0.75}], SPEED.dog, 0.0,
		{"kennel": kennel, "dp": kennel, "civil": false})
	# gate guards: two outside the outer vehicle gate (facing the approach), one at the foot entry, one inside
	var go: Rect2 = zs.get("gate_outer", zs.get("gate", Rect2()))
	var posts := []
	if go.size != Vector2.ZERO:
		var out_y := go.end.y + 0.7 if go.get_center().y > ctr.y else go.position.y - 0.7
		var face := PI * 0.5 if go.get_center().y > ctr.y else -PI * 0.5
		posts.append([Vector2(go.position.x - 0.5, out_y), face])
		posts.append([Vector2(go.end.x + 0.5, out_y), face])
	# (the foot entry / scan point is garrisoned by real Sentinels, 13.9c-10: no display guards there)
	for i in posts.size():
		_actor(Lf, "gate", "fig_guard", [{"p": posts[i][0], "dwell": 30.0, "pose": "post", "face": posts[i][1]}], 0.1, 0.0,
			{"post": posts[i][0], "post_face": posts[i][1], "arr_t": -100.0, "arr_p": Vector2.ZERO, "foe": false})
	# perimeter drone (no route: an orbit evaluated in _drone_at)
	(Lf.actors as Array).append({"kind": "drone", "sheet": "drone", "segs": [], "T": 1.0, "clock": 0.0, "face": 0.0,
		"civil": false, "p": Vector2.ZERO, "moving": true, "pose": "fly", "hidden": false, "wait": false, "speed": 1.0})


# ================================================================ tick: snapshot reads, clocks
func _on_tick(snap: Dictionary, steps: int) -> void:
	var scan := _onscreen and zoom >= LOD_MIN * 0.85
	_near_cells.clear()
	_near.clear()
	_sent_prev.clear()
	for sx in _sentinels:
		_sent_prev[int(sx[0])] = sx[1]
	_sentinels.clear()
	_vehs.clear()
	_eng_prev = _eng_pos.duplicate()
	if scan or not _eng_job.is_empty():
		_scan(snap, scan)
	for Lf in life:
		var alarm: bool = Lf.alarm
		for a in Lf.actors:
			if String(a.kind) in ["gate", "drone"]:
				a.clock = float(a.clock) + DT * float(steps)
				continue
			if alarm and bool(a.civil):
				continue   # frozen where they were; drawn running for cover (see _eval)
			if String(a.kind) == "fuel" and _bay_hold(Lf, a, steps):
				continue   # POLISH7-4 (13.9c-21): parked in its bay, nothing to refuel
			var blocked := false
			if scan:
				blocked = _blocked(Lf, a)
			a.wait = blocked
			if blocked:
				waits += 1
				continue
			var k := 1.0
			a.clock = float(a.clock) + DT * float(steps) * k
		_gate_arrivals(Lf)
		_aim_towers(Lf, steps)


## POLISH7-4 (owner 13.9c-21): the bowser's bay dwell does not run out while its next job (the pad / helipad rect in
## the dwell's "job") has no own fuel-using vehicle on it: it stays parked in the bay until there is one to refuel.
func _bay_hold(Lf: Dictionary, a: Dictionary, steps: int) -> bool:
	var tt := fposmod(float(a.clock), float(a.T))
	for sg in a.segs:
		if tt >= float(sg.t0) and tt < float(sg.t1):
			if bool(sg.m) or not (sg.get("job") is Rect2) or tt + DT * float(steps) < float(sg.t1) - 0.05:
				return false
			var jr: Rect2 = (sg.job as Rect2).grow(0.5)
			for v in _vehs:
				if int(v[1]) == int(Lf.owner) and jr.has_point(v[0]):
					return false
			return true
	return false


## One pass over the snapshot units: cells near a compound (+ positions for aim / arrivals) and strike-team APCs.
func _scan(snap: Dictionary, near: bool) -> void:
	scans += 1
	var n := int(snap.get("n", 0))
	var ids: PackedInt32Array = snap.get("ids", PackedInt32Array())
	var pos: PackedVector2Array = snap.get("pos", PackedVector2Array())
	var own: PackedInt32Array = snap.get("owner", PackedInt32Array())
	var dfi: PackedInt32Array = snap.get("def", PackedInt32Array())
	var defs: PackedStringArray = snap.get("defs", PackedStringArray())
	if defs.size() != _sent_defs_n:   # SENT7 units carry a content "sentinel" type field (g7_sent_*); bearers excluded
		_sent_defs_n = defs.size()
		_sent_def = {}
		_veh_def = {}
		for di in defs.size():
			var ud: Dictionary = Content.unit(String(defs[di]))
			if ud.has("sentinel") and String(ud.sentinel) != "bearer":
				_sent_def[di] = true
			if float(ud.get("fuel_max", 0.0)) > 0.0:
				_veh_def[di] = true
	var sent_def: Dictionary = _sent_def
	n = mini(n, mini(ids.size(), pos.size()))
	var rects := []
	for Lf in life:
		rects.append((Lf.cr as Rect2).grow(16.0))
	var engs := not _eng_job.is_empty()
	for i in n:
		if engs and _eng_job.has(ids[i]):
			_eng_pos[ids[i]] = pos[i]
		var p: Vector2 = pos[i]
		if near:
			for r in rects:
				if (r as Rect2).has_point(p):
					_near_cells[Vector2i(int(floor(p.x)), int(floor(p.y)))] = true
					_near.append([p, own[i] if i < own.size() else -1])
					if not sent_def.is_empty() and i < dfi.size() and sent_def.has(dfi[i]):
						_sentinels.append([ids[i], p, own[i] if i < own.size() else -1])
					if i < dfi.size() and _veh_def.has(dfi[i]):
						_vehs.append([p, own[i] if i < own.size() else -1])
					break


## A moving actor waits while a sim unit stands on or just ahead of its next step (they never block sim units).
func _blocked(Lf: Dictionary, a: Dictionary) -> bool:
	if not bool(a.moving) or _near_cells.is_empty():
		return false
	var p: Vector2 = a.p
	var reach := 1.3 if String(a.kind) in ["forklift", "fuel", "tug"] else 0.7
	var ahead := p + Vector2.from_angle(float(a.face)) * reach
	for q in [p, ahead, p.lerp(ahead, 0.5)]:
		if _near_cells.has(Vector2i(int(floor(q.x)), int(floor(q.y)))):
			return true
	return false


func _gate_arrivals(Lf: Dictionary) -> void:
	for a in Lf.actors:
		if String(a.kind) != "gate":
			continue
		var post: Vector2 = a.post
		var best := INF
		var bp := Vector2.ZERO
		var foe := false
		for u in _near:
			var p: Vector2 = u[0]
			var d := p.distance_to(post)
			if d < 4.5 and d > 0.4 and d < best and not (Lf.cr as Rect2).grow(-1.5).has_point(p):
				best = d
				bp = p
				foe = int(u[1]) != int(Lf.owner) and int(u[1]) >= 0
		if best < INF:
			if now() - float(a.arr_t) > 9.0 or (a.arr_p as Vector2).distance_to(bp) > 3.0:
				a.arr_t = now()
			a.arr_p = bp
			a.foe = foe
		elif now() - float(a.arr_t) > 9.0:
			a.foe = false


func _aim_towers(Lf: Dictionary, steps: int) -> void:
	var ctr: Vector2 = (Lf.cr as Rect2).get_center()
	var aims: Dictionary = Lf.aims
	for i in (Lf.towers as Array).size():
		var tp: Vector2 = Lf.towers[i]
		var out := (tp - ctr).angle()
		var tgt := INF
		var best := 14.0
		for u in _near:
			if int(u[1]) == int(Lf.owner) or int(u[1]) < 0:
				continue
			var d := (u[0] as Vector2).distance_to(tp)
			if d < best:
				best = d
				tgt = ((u[0] as Vector2) - tp).angle()
		var cur := float(aims.get(i, out))
		var want := tgt
		var rate := PI * 0.9
		if tgt == INF:   # slow sector sweep, +-40 deg about the outward normal, each tower out of phase
			want = out + sin(float(_tick) / TR * 0.35 + float(i) * 1.7) * 0.7
			rate = PI * 0.25
		var dd := wrapf(want - cur, -PI, PI)
		cur += clampf(dd, -rate * DT * steps, rate * DT * steps)
		aims[i] = wrapf(cur, -PI, PI)
		aims["t%d" % i] = tgt != INF


# ================================================================ evaluation
## Where actor a is at display time: sets a.p, a.face, a.moving, a.pose, a.hidden, a.frame, a.load.
func _eval(Lf: Dictionary, a: Dictionary) -> void:
	var kind := String(a.kind)
	if kind == "drone":
		_drone_at(Lf, a)
		return
	if kind == "gate":
		_gate_at(Lf, a)
		return
	if kind == "dog":
		_dog_at(Lf, a)
		return
	if kind in ["forklift", "fuel"]:
		a.driver = -1
		var uid := _driver_of(Lf, a)
		if uid >= 0:
			_drive_at(a, uid)
			return
	var clk := float(a.clock)
	if not bool(a.wait) and not (bool(Lf.alarm) and bool(a.civil)):
		clk += _alpha * DT * (2.0 if bool(Lf.alarm) and kind in ["guard", "dog"] else 1.0)
	if kind == "dog":
		clk += float(a.get("lead", 0.0))
	var tt := fposmod(clk, float(a.T))
	var seg: Dictionary = {}
	for s in a.segs:
		if tt >= float(s.t0) and tt < float(s.t1):
			seg = s
			break
	if seg.is_empty() and not (a.segs as Array).is_empty():
		seg = a.segs[0]
		tt = float(seg.t0)
	a.load = bool(seg.get("load", false))
	a.at = String(seg.get("at", ""))
	if bool(seg.get("m", false)):
		var d := (tt - float(seg.t0)) / maxf(float(seg.t1) - float(seg.t0), 0.001) * float(seg.len)
		var pts: PackedVector2Array = seg.pts
		var cum: PackedFloat32Array = seg.cum
		var j := 1
		while j < pts.size() - 1 and cum[j] < d:
			j += 1
		var l0 := cum[j - 1]
		var l1 := cum[j]
		var p := pts[j - 1].lerp(pts[j], clampf((d - l0) / maxf(l1 - l0, 0.0001), 0.0, 1.0))
		if pts[j].distance_to(pts[j - 1]) > 0.01:   # rev: reversing into the bowser bay (faces away from its travel)
			a.face = (pts[j] - pts[j - 1]).angle() + (PI if bool(seg.get("rev", false)) else 0.0)
		a.p = p
		a.moving = not bool(a.wait)
		a.pose = "run" if bool(Lf.alarm) and kind in ["guard", "dog"] else ("walk" if not bool(a.wait) else "idle")
		a.dist = d + float(seg.t0) * float(a.speed)
	else:
		a.p = seg.get("p", (Lf.cr as Rect2).get_center())
		a.moving = false
		if float(seg.get("face", -99.0)) > -9.0:
			a.face = float(seg.face)
		a.pose = String(seg.get("pose", "idle"))
		a.dwell_t = tt - float(seg.get("t0", 0.0))
		a.dwell_len = float(seg.get("t1", 1.0)) - float(seg.get("t0", 0.0))
		a.hose = seg.get("hose", null)
		a.tow = seg.get("tow", null)
	a.hidden = String(a.pose) == "hide"
	# alarm: civilians run for the nearest door and stay inside; after the all-clear they come back out
	if bool(a.civil):
		var since := now() - float(Lf.alarm_t)
		if bool(Lf.alarm) and kind in ["tech", "staff"]:
			var door := _nearest_door(Lf, a.p)
			var dd := (a.p as Vector2).distance_to(door)
			var run_t := dd / SPEED.run
			if since >= run_t:
				a.hidden = true
			else:
				a.face = (door - (a.p as Vector2)).angle()
				a.p = (a.p as Vector2).lerp(door, since / maxf(run_t, 0.01))
				a.moving = true
				a.pose = "run"
				a.hidden = false
		elif bool(Lf.alarm):
			a.moving = false
			a.pose = "park"
		else:
			var back := now() - float(Lf.calm_t)
			if back < 2.5 and kind in ["tech", "staff"]:
				var door := _nearest_door(Lf, a.p)
				a.p = door.lerp(a.p, back / 2.5)
				a.face = ((a.p as Vector2) - door).angle()
				a.moving = true
				a.pose = "walk"


## The dog heels 0.7 tiles to the left-rear of the lowest-id friendly Sentinel inside the compound; trots while it moves,
## sits / sniffs while it stands; with no Sentinel inside it lies at its kennel. Smoothed per frame (display only).
func _dog_at(Lf: Dictionary, a: Dictionary, step_dt := -1.0) -> void:
	var inner: Rect2 = (Lf.cr as Rect2).grow(-1.5)
	var lead = null
	for sx in _sentinels:
		if int(sx[2]) == int(Lf.owner) and inner.has_point(sx[1]) and (lead == null or int(sx[0]) < int(lead[0])):
			lead = sx
	var want: Vector2 = a.kennel
	var moving := false
	var hd := float(a.face)
	if lead != null:
		var lp: Vector2 = lead[1]
		var pp: Vector2 = _sent_prev.get(int(lead[0]), lp)
		if lp.distance_to(pp) > 0.005:
			hd = (lp - pp).angle()
			moving = true
		want = lp + Vector2.from_angle(hd + PI * 0.75) * 0.7
	var dp: Vector2 = a.dp
	var dt := clampf(get_process_delta_time() if step_dt < 0.0 else step_dt, 0.0, 0.1)   # step_dt: a fixed step (tests)
	var d := dp.distance_to(want)
	if d > 6.0:
		dp = want
	elif d > 0.02:
		dp = dp.move_toward(want, maxf(d * 3.0, 0.9) * dt)
		if d > 0.15:
			hd = (want - dp).angle()
			moving = true
	a.dp = dp
	a.p = dp
	a.face = hd
	a.moving = moving
	a.hidden = false
	a.pose = "walk" if moving else ("watch" if lead != null else "kennel")
	a.dwell_t = fposmod(now(), 6.0)


func _nearest_door(Lf: Dictionary, p: Vector2) -> Vector2:
	var best := p
	var bd := INF
	for zn in Lf.door_pt:
		var d: float = (Lf.door_pt[zn] as Vector2).distance_to(p)
		if d < bd:
			bd = d
			best = Lf.door_pt[zn]
	for g in Lf.garage_door:
		var d: float = (g as Vector2).distance_to(p)
		if d < bd:
			bd = d
			best = g
	return best


func _gate_at(Lf: Dictionary, a: Dictionary) -> void:
	var post: Vector2 = a.post
	a.p = post
	a.moving = false
	a.hidden = false
	var since := now() - float(a.arr_t)
	if bool(Lf.alarm) or bool(a.foe) and since < 9.0:
		a.pose = "crouch"
		if since < 9.0:
			a.face = ((a.arr_p as Vector2) - post).angle()
		else:
			a.face = float(a.post_face)
		return
	if since < 9.0:   # arrival: halt sign, check papers / vehicle, wave through
		a.face = ((a.arr_p as Vector2) - post).angle()
		if since < 1.8:
			a.pose = "halt"
		elif since < 4.8:
			a.pose = "idle"
			a.p = post.lerp(a.arr_p, 0.18)
		elif since < 6.0:
			a.pose = "wave"
		else:
			a.pose = "idle"
		return
	# no arrival: a short beat by the post, then a look along the approach
	var c := fposmod(float(a.clock) + float(hash(Vector2i(int(post.x * 4.0), int(post.y * 4.0))) % 97), 24.0)
	a.face = float(a.post_face)
	a.pose = "idle"
	if c < 3.0:
		a.p = post + Vector2.from_angle(float(a.post_face) + PI * 0.5) * (c / 3.0) * 0.8
		a.face = float(a.post_face) + PI * 0.5
		a.pose = "walk"
		a.moving = true
	elif c < 12.0:
		a.p = post + Vector2.from_angle(float(a.post_face) + PI * 0.5) * 0.8
	elif c < 15.0:
		a.p = post + Vector2.from_angle(float(a.post_face) + PI * 0.5) * (1.0 - (c - 12.0) / 3.0) * 0.8
		a.face = float(a.post_face) - PI * 0.5
		a.pose = "walk"
		a.moving = true


## Perimeter drone: an orbit 4 tiles outside the walls at 9 m; every 160 s it returns to the drone bay for 24 s.
## POLISH7-4: the orbit (radius half the compound + 4) crosses the corner towers (12.4 m) and the wall ring: it flies at
## 14 m (was 9 m: through the towers); to / from the launch deck it climbs to DRONE_CRUISE, clear of the 15.5 m command
## centre, and only descends onto the deck over the last part of the leg.
const DRONE_ALT := 14.0
const DRONE_CRUISE := 18.0
const DRONE_CYCLE := 160.0
const DRONE_HOME := 24.0
func _drone_at(Lf: Dictionary, a: Dictionary) -> void:
	var cr: Rect2 = Lf.cr
	var ctr := cr.get_center()
	var t := float(a.clock) + _alpha * DT
	var rad := cr.size.x * 0.5 + (2.0 if bool(Lf.alarm) else 4.0)
	var w := (0.05 if bool(Lf.alarm) else 0.035)
	var ang := t * w
	var orbit := ctr + Vector2(cos(ang), sin(ang)) * rad
	# POLISH7-4 (FACB7-5): the drone bay is the workshop's 2nd storey: it recovers on the launch-deck spot (10.57 m)
	var dk: Rect2 = Lf.get("deck", Rect2())
	var home: Vector2 = dk.position + dk.size * DECK_SPOT if dk.size != Vector2.ZERO else _door(Lf, "drone_bay")
	var home_z := DECK_Z if dk.size != Vector2.ZERO else 0.0
	a.floor = 0.0
	var c := fposmod(t, DRONE_CYCLE)
	var alt := DRONE_ALT
	var p := orbit
	a.face = ang + PI * 0.5
	a.hidden = false
	a.home = false
	var t_out := DRONE_CYCLE - DRONE_HOME - 16.0
	if c > t_out and not bool(Lf.alarm):   # fly home (8 s), land / door (24 s), launch back (8 s)
		var k := c - t_out
		var ang_out := (t - k) * w
		var orb0 := ctr + Vector2(cos(ang_out), sin(ang_out)) * rad
		var ang_back := (t - k + 16.0 + DRONE_HOME) * w
		var orb1 := ctr + Vector2(cos(ang_back), sin(ang_back)) * rad
		if k < 8.0:
			var u := k / 8.0
			p = orb0.lerp(home, smoothstep(0.0, 1.0, u))
			alt = lerpf(DRONE_ALT, DRONE_CRUISE, smoothstep(0.0, 0.3, u)) if u < 0.65 else lerpf(DRONE_CRUISE, home_z + 1.2, smoothstep(0.65, 1.0, u))
			a.face = (home - orb0).angle()
		elif k < 8.0 + DRONE_HOME:
			p = home
			alt = home_z + 0.3   # sits on its deck spot (the lift hatch opens / shuts: door "drone_bay")
			a.hidden = home_z <= 0.0 and k > 10.0 and k < 6.0 + DRONE_HOME
			a.home = true
		else:
			var q := (k - 8.0 - DRONE_HOME) / 8.0
			p = home.lerp(orb1, smoothstep(0.0, 1.0, q))
			alt = lerpf(home_z + 1.2, DRONE_CRUISE, smoothstep(0.0, 0.35, q)) if q < 0.7 else lerpf(DRONE_CRUISE, DRONE_ALT, smoothstep(0.7, 1.0, q))
			a.face = (orb1 - home).angle()
		a.home_k = k
		if dk.size != Vector2.ZERO and dk.grow(0.3).has_point(p):
			a.floor = home_z   # over the workshop: its shadow falls on the deck, not on the ground under the building
	a.p = p
	a.alt = alt
	a.moving = true


## Door targets: open while a sim unit or a vehicle actor is at the door (or a technician works there); shutters roll at
## ~0.8 m/s (1.4 s full travel). Per frame, display only.
func _update_doors(dt := -1.0) -> void:
	if dt < 0.0:
		dt = clampf(get_process_delta_time(), 0.0, 0.1)
	for Lf in life:
		var gd: Array = Lf.garage_door
		var want := {}
		for i in gd.size():
			var dp: Vector2 = gd[i]
			var o := false
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					if _near_cells.has(Vector2i(int(floor(dp.x)) + dx, int(floor(dp.y)) + dy)):
						o = true
			want["g%d" % i] = o
		for a in Lf.actors:
			if String(a.get("at", "")) != "" and not bool(a.moving) and String(a.kind) in ["forklift", "tech"]:
				want[String(a.at)] = true
			if String(a.kind) == "drone" and bool(a.get("home", false)):
				var k := float(a.get("home_k", 0.0))
				want["drone_bay"] = (k > 6.0 and k < 12.0) or (k > 4.0 + DRONE_HOME and k < 10.0 + DRONE_HOME)
		if bool(Lf.alarm):
			for k in want:
				want[k] = false
		for k in Lf.doors:
			var tgt := 1.0 if bool(want.get(k, false)) else 0.0
			Lf.doors[k] = move_toward(float(Lf.doors[k]), tgt, dt / 1.4)


## 0..1 open fraction of a facility door ("g0".."g7" garages, "drone_bay"). ATMO7 / SEQ7 may read it.
func door_open(fac_id: int, name: String) -> float:
	for Lf in life:
		if int(Lf.id) == fac_id:
			return float((Lf.doors as Dictionary).get(name, 0.0))
	return 0.0


## Tile rects the actors of facility fac_id occupy this frame (SEQ7 may keep its runners clear of them).
func busy_cells(fac_id: int) -> Array:
	var out := []
	for Lf in life:
		if int(Lf.id) != fac_id:
			continue
		for a in Lf.actors:
			if not bool(a.get("hidden", false)) and String(a.kind) != "drone":
				out.append(Rect2((a.p as Vector2) - Vector2(0.5, 0.5), Vector2.ONE))
	return out


# ================================================================ drawing helpers
func _iso(Lf: Dictionary, p: Vector2) -> Vector2:
	return ViewUtil.iso(p) - Vector2(0, float(Lf.lift))


func _box(r: Rect2, h: float) -> Dictionary:
	var q := [ViewUtil.iso(r.position), ViewUtil.iso(Vector2(r.end.x, r.position.y)), ViewUtil.iso(r.end), ViewUtil.iso(Vector2(r.position.x, r.end.y))]
	var up := Vector2(0, -h)
	# screen silhouette of the box: left corner, its top, the back top corner, right top, right corner, front bottom
	var poly := PackedVector2Array([q[3], q[3] + up, q[0] + up, q[1] + up, q[1], q[2]])
	var bb := Rect2(poly[0], Vector2.ZERO)
	for v in poly:
		bb = bb.expand(v)
	return {"r": r, "h": h, "poly": poly, "bb": bb}


## True when world point p (with a figure top hz px above it) is behind a building whose silhouette covers it.
func _occluded(Lf: Dictionary, p: Vector2, hz: float) -> bool:
	var s := ViewUtil.iso(p) + Vector2(0, -hz * 0.5)
	for b in Lf.boxes:
		var r: Rect2 = b.r
		if r.has_point(p):
			return true   # inside a building (door threshold): hidden
		if p.x >= r.end.x or p.y >= r.end.y:
			continue      # south / east of it: in front
		if not (b.bb as Rect2).has_point(s):
			continue
		if Geometry2D.is_point_in_polygon(s, b.poly):
			return true
	return false


func _row(a: float) -> int:
	return posmod(int(round(a / (PI / 4.0))), 8)


func _spr(id: String, frame: String, row: int, at: Vector2, mod := Color.WHITE) -> bool:
	var s = sheets.get(id)
	if s == null:
		return false
	var fi: int = int(s.fi.get(frame, s.fi.get("idle", 0)))
	row = clampi(row, 0, int(s.rows) - 1)
	var o: Vector2 = (at - (s.piv as Vector2)).round()
	draw_texture_rect_region(s.tex, Rect2(o, Vector2(s.fw, s.fh)), Rect2(fi * int(s.fw), row * int(s.fh), int(s.fw), int(s.fh)), mod)
	drawn[id] = int(drawn.get(id, 0)) + 1
	return true


func _compound_on_screen() -> bool:
	if not is_inside_tree():
		return true   # headless tests: treat as on screen
	var vr := get_viewport_rect()
	var inv := get_global_transform_with_canvas().affine_inverse()
	var view := Rect2(inv * vr.position, Vector2.ZERO).expand(inv * vr.end)
	for Lf in life:
		var cr: Rect2 = Lf.cr
		var a := ViewUtil.iso(cr.position)
		var bb := Rect2(a, Vector2.ZERO).expand(ViewUtil.iso(Vector2(cr.end.x, cr.position.y))).expand(ViewUtil.iso(cr.end)).expand(ViewUtil.iso(Vector2(cr.position.x, cr.end.y)))
		bb = bb.grow(220.0)
		if bb.intersects(view):
			return true
	return false


# ================================================================ draw
func _draw() -> void:
	drawn = {}
	occluded = 0
	inset_shown = false
	if not on or not _onscreen:
		return
	var t := now()
	for Lf in life:
		var items := []   # [depth, kind, data]
		for a in Lf.actors:
			_eval(Lf, a)
			if bool(a.hidden):
				continue
			var kind := String(a.kind)
			if zoom < LOD_MIN and kind != "drone":
				continue
			var p: Vector2 = a.p
			var hz := 40.0 if kind == "fuel" else (24.0 if kind in ["forklift", "tug"] else 18.0)
			if kind != "drone" and _occluded(Lf, p, hz):
				occluded += 1
				continue
			items.append([p.x + p.y + (40.0 if kind == "drone" else 0.0), "actor", a])
		_range_items(Lf, items, t)
		items.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		_draw_doors(Lf)
		for it in items:
			if String(it[1]) == "actor":
				_draw_actor(Lf, it[2], t)
			else:
				_draw_range_item(Lf, it, t)
		_draw_parts(Lf, t)
		# POLISH7-5: the LIVE FIRE lamp's housing on the range canopy roof is drawn here, on this node (it used to be
		# drawn from _draw_glows, the Life7Glows child's draw callback: ~1,500 "Drawing is only allowed inside this
		# node's _draw()" errors per windowed run); its glow stays in _draw_glows
		var rr: Rect2 = (Lf.zones as Dictionary).get("range", Rect2())
		if rr.size != Vector2.ZERO and bool(Lf.get("live_fire", false)) and zoom >= LOD_MIN:
			draw_rect(Rect2(_range_lamp(Lf, rr) + Vector2(-1.5, 0.0), Vector2(3, 3)), Color(0.16, 0.16, 0.17))


## Screen point of the range's LIVE FIRE lamp (POLISH7-3: on the firing-line canopy roof, north end).
func _range_lamp(Lf: Dictionary, r: Rect2) -> Vector2:
	return _iso(Lf, r.position + Vector2(RANGE_FIRE_X - 0.1, RANGE_LANE_Y0 + 0.1)) - Vector2(0, RANGE_CANOPY_Z + 3.0)


func _draw_actor(Lf: Dictionary, a: Dictionary, t: float) -> void:
	var kind := String(a.kind)
	var s := _iso(Lf, a.p)
	var row := _row(float(a.face))
	var ph := float(a.get("dist", t * float(a.speed))) / maxf(float(a.speed), 0.01)
	match kind:
		"tech", "staff", "guard":
			var fr := "idle"
			match String(a.pose):
				"walk":
					fr = WALK[int(ph * 7.0) % 6]
				"run":
					fr = RUN[int(t * 11.0) % 6]
				"act":
					fr = "act_0" if int(t * 2.2 + float(row)) % 2 == 0 else "act_1"
				"watch":
					fr = "idle_1" if int(t * 0.8) % 2 == 0 else "idle"
				_:
					fr = "idle_1" if int(t * 0.6 + s.x * 0.01) % 2 == 0 else "idle"
			_spr("fig_" + kind if kind != "guard" else "fig_guard", fr, row, s)
		"gate":
			var fr2 := "idle"
			match String(a.pose):
				"walk":
					fr2 = WALK[int(t * 7.0) % 6]
				"halt":
					fr2 = "act_0"
				"wave":
					fr2 = "act_1" if int(t * 4.0) % 2 == 0 else "act_0"
				"crouch":
					fr2 = "crouch"
			_spr("fig_guard", fr2, row, s)
		"dog":
			var fd := "idle"
			if String(a.pose) in ["walk", "run"]:
				fd = TROT[int(ph * (8.0 if String(a.pose) == "walk" else 13.0)) % 4]
			elif String(a.pose) == "watch":
				fd = "sniff" if fmod(float(a.get("dwell_t", 0.0)), 3.0) < 1.6 else "sit"
			elif String(a.pose) == "kennel":
				fd = "sit" if fmod(float(a.get("dwell_t", 0.0)), 6.0) < 4.5 else "idle"
			_spr("dog", fd, row, s)
		"forklift":
			var ld := bool(a.get("load", false)) or (String(a.pose) == "unload" and float(a.get("dwell_t", 0.0)) < float(a.get("dwell_len", 1.0)) * 0.5) \
				or (String(a.pose) == "load" and float(a.get("dwell_t", 0.0)) > float(a.get("dwell_len", 1.0)) * 0.5)
			var bk := int(t * 2.5) % 2 == 1 and (bool(a.moving) or String(a.pose) in ["load", "unload"])
			_spr("forklift", ("l" if ld else "e") + ("1" if bk else "0"), row, s)
		"fuel":
			_spr("fuel_truck", "b1" if int(t * 2.0) % 2 == 1 else "b0", row, s)
			if String(a.pose) == "hose" and a.get("hose") != null and float(a.get("dwell_t", 0.0)) > 1.5 and float(a.get("dwell_t", 0.0)) < float(a.get("dwell_len", 1.0)) - 1.5:
				var back := s + ViewUtil.iso(Vector2.from_angle(float(a.face)) * -0.85)
				var tgt := _iso(Lf, (a.p as Vector2).lerp(a.hose, 0.35))
				var mid := back.lerp(tgt, 0.5) + Vector2(0, 5)
				draw_polyline(PackedVector2Array([back + Vector2(0, -10), mid, tgt + Vector2(0, -3)]), Color(0.10, 0.10, 0.10), 1.6)
		"tug":
			_spr("tow_tractor", "b1" if int(t * 2.0) % 2 == 1 and String(a.pose) != "park" else "b0", row, s)
			if String(a.pose) == "tow" and a.get("tow") != null:
				var hitch := s + ViewUtil.iso(Vector2.from_angle(float(a.face)) * 0.45) + Vector2(0, -5)
				draw_line(hitch, _iso(Lf, a.tow) + Vector2(0, -6), Color(0.15, 0.15, 0.13), 2.0)
				draw_line(hitch, _iso(Lf, a.tow) + Vector2(0, -6), Color(0.85, 0.72, 0.22), 1.0)
		"drone":
			var g := s
			var ar := Vector2(1.0, 0.5) * 3.0
			var fl := float(a.get("floor", 0.0)) * 9.8   # POLISH7-4: on / over the launch deck the shadow sits on the deck
			draw_set_transform(g - Vector2(0, fl), 0.0, Vector2(1, 1))
			draw_circle(Vector2.ZERO, 3.0, Color(0.03, 0.04, 0.03, 0.30))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			if not bool(Lf.alarm) and zoom >= LOD_MIN and float(a.alt) > 4.0:   # camera footprint swept on the ground
				# (POLISH7) the old quad [g, fp-left, fp-down, fp+right] went collinear / self-crossing whenever the drone
				# faced along the screen's x axis (g level with fp's left/right points): ~450 "triangulation failed"
				# per run. Now a cone (triangle across the view axis, never degenerate since |fp - g| >= 1.6 tiles)
				# plus an elliptical spot on the ground.
				var fp := g + ViewUtil.iso(Vector2.from_angle(float(a.face)) * 1.6)
				var ax := fp - g
				if ax.length_squared() > 4.0:
					var perp := Vector2(-ax.y, ax.x).normalized() * ar.x * 2.4
					draw_colored_polygon(PackedVector2Array([g, fp + perp, fp - perp]), Color(0.6, 0.9, 1.0, 0.05))
					draw_set_transform(fp, 0.0, Vector2(1.0, 0.5))
					draw_circle(Vector2.ZERO, ar.x * 2.6, Color(0.6, 0.9, 1.0, 0.06))
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			_spr("drone", "r1" if int(t * 20.0) % 2 == 1 else "r0", row, g - Vector2(0, float(a.alt) * 9.8))


# ---------------------------------------------------------------- range
const LANES := 4
const DRILL := 44.0
func _range_items(Lf: Dictionary, items: Array, t: float) -> void:
	var r: Rect2 = (Lf.zones as Dictionary).get("range", Rect2())
	if r.size == Vector2.ZERO or zoom < LOD_MIN:
		return
	var live := bool(Lf.secure) and not bool(Lf.alarm)
	var c := fposmod(t, DRILL)
	Lf.live_fire = live and c >= 6.0 and c < 28.0
	for i in LANES:
		var ly := r.position.y + RANGE_LANE_Y0 + RANGE_LANE_W * (float(i) + 0.5)
		var tp := Vector2(r.position.x + RANGE_TARGET_X, ly)
		var st := "up"
		if live:
			var up0 := 6.5 + fmod(float(i) * 5.3, 15.0)
			var hit := up0 + 2.2 + fmod(float(i) * 1.9, 1.4)
			if c < up0 or c > 30.0:
				st = "down"
			elif c > hit:
				st = "half" if c < hit + 0.25 else "down"
			elif c < up0 + 0.25:
				st = "half"
		else:
			st = "down"
		items.append([tp.x + tp.y, "target", tp, st])
		if not live:
			continue
		var fire := Vector2(r.position.x + RANGE_FIRE_X, ly)   # POLISH7-3: firing line under the canopy, firing east
		var ready := Vector2(r.position.x + RANGE_READY_X, ly)
		var p := fire
		var pose := "fire_c"
		var face := 0.0
		if c < 6.0:
			p = ready.lerp(fire, c / 6.0)
			pose = "walk"
			face = (fire - ready).angle()
		elif c >= 28.0 and c < 36.0:   # walk forward and check the targets
			var k := (c - 28.0) / 8.0
			var chk := tp - Vector2(0.45, 0.0)
			p = fire.lerp(chk, minf(k * 2.0, 1.0)) if k < 0.5 else chk.lerp(fire, (k - 0.5) * 2.0)
			pose = "walk" if absf(k - 0.5) > 0.12 else "idle"
			face = 0.0 if k < 0.5 else PI
		elif c >= 36.0:
			var k2 := (c - 36.0) / 8.0
			p = fire.lerp(ready, k2)
			pose = "walk"
			face = (ready - fire).angle()
		else:
			var up0 := 6.5 + fmod(float(i) * 5.3, 15.0)
			var hit := up0 + 2.2 + fmod(float(i) * 1.9, 1.4)
			pose = "fire_s" if c > up0 + 0.4 and c < hit and int(t * 9.0) % 3 == 0 else ("fire_c" if i % 2 == 0 else "prone")
		items.append([p.x + p.y, "trainee", p, pose, face, i])
	# kill house: a pair stacking and clearing the rooms of the west half (bang / muzzle flashes, lamp)
	if live and c >= 6.0 and c < 28.0:
		# POLISH7-3: the kill house is FACB7-4's 2-storey training building (door N at [5,20]): the pair stacks at the
		# door, goes in (hidden by the building, 13.9c-18: no cut-away) and comes back out
		var bo2 := r.position + RANGE_BLD.position
		var dr := Vector2(r.position.x + 3.5, r.position.y - 0.45)
		var route := [dr + Vector2(0.6, -0.2), dr, Vector2(dr.x, bo2.y + 0.6), Vector2(bo2.x + 1.0, bo2.y + 1.2),
			Vector2(bo2.x + 1.0, bo2.y + 2.8), Vector2(dr.x, bo2.y + 0.6), dr, dr + Vector2(0.6, -0.2)]
		var k3 := (c - 6.0) / 22.0 * float(route.size() - 1)
		for m in 2:
			var kk := clampf(k3 - float(m) * 0.18, 0.0, float(route.size() - 1) - 0.001)
			var j := int(kk)
			var p2: Vector2 = (route[j] as Vector2).lerp(route[j + 1], kk - float(j))
			items.append([p2.x + p2.y, "kh", p2, (route[j + 1] - route[j]).angle(), m, fmod(kk, 1.0) > 0.7])


func _draw_range_item(Lf: Dictionary, it: Array, t: float) -> void:
	if String(it[1]) != "target" and _occluded(Lf, it[2], 18.0):   # POLISH7-3: inside / behind the training building
		occluded += 1
		return
	match String(it[1]):
		"target":
			_spr("target", String(it[3]), 0, _iso(Lf, it[2]))
		"trainee":
			var sid: String = ["g7_cn_gunner", "g7_cn_team_leader", "g7_cn_radio", "g7_cn_medic"][int(it[5]) % 4]
			if not sheets.has(sid):
				sid = "fig_guard"
			var fr := String(it[3])
			if fr == "walk":
				fr = WALK[int(t * 7.0) % 6]
			if not _occluded(Lf, it[2], 18.0) or true:
				_spr(sid, fr, _row(float(it[4])), _iso(Lf, it[2]))
		"kh":
			var sid2 := "g7_cn_gunner" if int(it[4]) == 0 else "g7_cn_team_leader"
			if not sheets.has(sid2):
				sid2 = "fig_guard"
			_spr(sid2, "fire_s" if bool(it[5]) else WALK[int(t * 8.0 + float(it[4]) * 3.0) % 6], _row(float(it[3])), _iso(Lf, it[2]))


# ---------------------------------------------------------------- doors, moving parts
func _draw_doors(Lf: Dictionary) -> void:
	if zoom < LOD_MIN:
		return
	var gd: Array = Lf.garage_door
	var ctr: Vector2 = (Lf.cr as Rect2).get_center()
	for i in gd.size():
		var f := float((Lf.doors as Dictionary).get("g%d" % i, 0.0))
		if f <= 0.01:
			continue
		var gr: Rect2 = Lf.garages[i]
		if gr.get_center().x > ctr.x:
			continue   # shutter on the west face (away from the camera): only its light spill shows (glows)
		var x := gr.end.x - 0.42   # LIGHT7-2 CR 5926: FacAtmo7.INSET, the art facade (was a slab 0.42 tile in front of it)
		var y0 := gr.get_center().y - 0.56
		var y1 := gr.get_center().y + 0.56   # the art garage door is 1.12 tiles wide (FacAtmo7 _shutter hw 0.56)
		var b0 := _iso(Lf, Vector2(x, y0))
		var b1 := _iso(Lf, Vector2(x, y1))
		var hh := DOOR_HPX * f
		# opening grows from the floor up as the shutter rolls into its drum: dark bay, lit floor, a vehicle shape
		draw_colored_polygon(PackedVector2Array([b0, b1, b1 + Vector2(0, -hh), b0 + Vector2(0, -hh)]), Color(0.06, 0.07, 0.07, 1.0))   # opaque (13.9c-18)
		draw_colored_polygon(PackedVector2Array([b0, b1, b1 + Vector2(-4, -3), b0 + Vector2(-4, -3)]), Color(0.55, 0.50, 0.36, 0.55 * f))
		draw_line(b0 + Vector2(0, -hh), b1 + Vector2(0, -hh), Color(0.28, 0.30, 0.30), 1.0)   # shutter bottom rail


func _draw_parts(Lf: Dictionary, t: float) -> void:
	var zs: Dictionary = Lf.zones
	# radar on the ops roof
	var pr: Rect2 = zs.get("planning", Rect2())
	if pr.size != Vector2.ZERO and sheets.has("radar"):
		var rp := pr.position + pr.size * RADAR_AT
		var step := int(fposmod(t * 0.42 / TAU * 16.0, 16.0))   # one turn every ~15 s
		_spr("radar", "a%d" % step, 0, _iso(Lf, rp) - Vector2(0, ROOF_H_OPS))
	# tower cupolas
	var aims: Dictionary = Lf.aims
	for i in (Lf.towers as Array).size():
		var tp: Vector2 = Lf.towers[i]
		var a := float(aims.get(i, ((tp - (Lf.cr as Rect2).get_center()).angle())))
		var st := posmod(int(round(a / (TAU / 16.0))), 16)
		_spr("cupola", "a%d" % st, 0, _iso(Lf, tp) + CUPOLA_OFF)


func _draw_glows() -> void:
	if not on or not _onscreen:
		return
	var t := now()
	for Lf in life:
		var zs: Dictionary = Lf.zones
		# obstruction lights on every tower top: 1 s period, 0.25 s on, staggered pairs
		for i in (Lf.towers as Array).size():
			if fposmod(t + float(i % 2) * 0.5, 1.6) < 0.3:
				_glow(obstruction_lamp(Lf, i), 12.0, Color(1.0, 0.15, 0.08, 0.85))
			if bool((Lf.aims as Dictionary).get("t%d" % i, false)) and fposmod(t * 3.0, 1.0) < 0.5:   # tracking: amber lamp
				_glow(_iso(Lf, Lf.towers[i]) + CUPOLA_OFF + Vector2(6, -12), 8.0, Color(1.0, 0.65, 0.1, 0.8))
		var pr: Rect2 = zs.get("planning", Rect2())
		if pr.size != Vector2.ZERO:
			# comms mast blink (double flash) and the ops windows glowing with the screens (flicker per pane)
			for m in MAST_TIPS.size():   # double flash running pole to pole
				var ph := fposmod(t - float(m) * 0.18, 2.0)
				if ph < 0.12 or (ph > 0.3 and ph < 0.42):
					_glow(_iso(Lf, pr.get_center()) + MAST_TIPS[m], 6.0, Color(1.0, 0.2, 0.1, 0.9))
			if zoom >= LOD_MIN:
				for k in 6:
					var u := (float(k) + 0.5) / 6.0
					var on_e := k < 3
					var wp := Vector2(pr.end.x, pr.position.y + pr.size.y * u * 2.0) if on_e else Vector2(pr.position.x + pr.size.x * (u - 0.5) * 2.0, pr.end.y)
					var fl := 0.55 + 0.45 * sin(t * (2.0 + float(k) * 0.7) + float(k) * 2.1)
					glows.draw_texture_rect(_glow_tex, Rect2(_iso(Lf, wp) - Vector2(9, 22), Vector2(18, 10)), false, Color(0.35, 0.75, 1.0, 0.22 * fl))
		# garage / drone bay light spill on the apron while a door is open
		var gd: Array = Lf.garage_door
		# LIGHT7-2 CR 5926: the garage door spill is drawn (clipped) by fac_atmo7._draw_glow only; this one doubled it
		var fdb := float((Lf.doors as Dictionary).get("drone_bay", 0.0))
		if fdb > 0.02:
			var dk: Rect2 = Lf.get("deck", Rect2())   # POLISH7-4: the lift hatch on the launch deck (drone bay = workshop 2nd storey)
			if dk.size != Vector2.ZERO:
				glows.draw_texture_rect(_glow_tex, Rect2(_iso(Lf, dk.position + dk.size * DECK_SPOT) - Vector2(16, 6 + DECK_Z * 9.8), Vector2(32, 12)), false, Color(0.7, 0.9, 1.0, 0.45 * fdb))
			else:
				glows.draw_texture_rect(_glow_tex, Rect2(_iso(Lf, _door(Lf, "drone_bay")) - Vector2(30, 12), Vector2(60, 24)), false, Color(0.7, 0.9, 1.0, 0.35 * fdb))
		# vehicle beacons, drone nav strobe
		for a in Lf.actors:
			if bool(a.get("hidden", false)) or zoom < LOD_MIN and String(a.kind) != "drone":
				continue
			match String(a.kind):
				"forklift", "fuel", "tug":
					if int(t * 2.5) % 2 == 1 and (bool(a.moving) or String(a.pose) != "park"):
						_glow(_iso(Lf, a.p) - Vector2(0, 26.0 if String(a.kind) == "fuel" else 22.0), 9.0, Color(1.0, 0.62, 0.12, 0.6))
				"drone":
					if fposmod(t, 1.0) < 0.1:
						_glow(_iso(Lf, a.p) - Vector2(0, float(a.get("alt", 0.0)) * 9.8), 7.0, Color(1.0, 1.0, 1.0, 0.9))
		# range: red LIVE FIRE lamp on the range tower, muzzle flashes, kill-house bangs
		var r: Rect2 = zs.get("range", Rect2())
		if r.size != Vector2.ZERO and bool(Lf.get("live_fire", false)) and zoom >= LOD_MIN:
			# POLISH7-3: the LIVE FIRE lamp sits on the firing-line canopy roof (north end), not floating over the berm
			var lamp := _range_lamp(Lf, r)   # (its dark housing is drawn by _draw: only glows.draw_* may run in here)
			if fposmod(t, 0.8) < 0.45:
				_glow(lamp, 14.0, Color(1.0, 0.1, 0.05, 0.9))
			var c := fposmod(t, DRILL)
			for i in LANES:
				var up0 := 6.5 + fmod(float(i) * 5.3, 15.0)
				var hit := up0 + 2.2 + fmod(float(i) * 1.9, 1.4)
				if c > up0 + 0.4 and c < hit and int(t * 9.0) % 3 == 0:
					var ly := r.position.y + RANGE_LANE_Y0 + RANGE_LANE_W * (float(i) + 0.5)
					_glow(_iso(Lf, Vector2(r.position.x + RANGE_FIRE_X + 0.3, ly)) - Vector2(0, 10), 7.0, Color(1.0, 0.85, 0.4, 0.9))
			# the pair clearing the training building: flashes in its windows (east / south faces, both storeys);
			# never a cut-away (13.9c-18): only the window light shows
			var bo := r.position + RANGE_BLD.position
			var wins := [[Vector2(bo.x + RANGE_BLD.size.x, bo.y + 1.0), 18.0], [Vector2(bo.x + 1.4, bo.y + RANGE_BLD.size.y), 18.0],
				[Vector2(bo.x + RANGE_BLD.size.x, bo.y + 2.6), 58.0]]
			for m in 3:
				if fposmod(t * 1.7 + float(m) * 0.9, 3.0) < 0.12:
					_glow(_iso(Lf, wins[m][0]) - Vector2(0, float(wins[m][1])), 9.0, Color(1.0, 0.95, 0.85, 0.75))


## POLISH7-5 (owner 13.9c-24 "nothing floating"): tower i's red obstruction lamp, on the tip of the mast ATMO7 draws on
## the tower roof (FacAtmo7.MAST_OFF / MAST_TOP_Z; was the tower centre + 124 px, beside the mast in the air).
func obstruction_lamp(Lf: Dictionary, i: int) -> Vector2:
	return _iso(Lf, (Lf.towers[i] as Vector2) + FacAtmo7.MAST_OFF) - Vector2(0, FacAtmo7.MAST_TOP_Z)


func _glow(at: Vector2, rad: float, col: Color) -> void:
	glows.draw_texture_rect(_glow_tex, Rect2(at - Vector2(rad, rad * 0.75), Vector2(rad * 2.0, rad * 1.5)), false, col)
