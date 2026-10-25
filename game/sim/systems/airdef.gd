extends RefCounted
## Airdef (owner: AIRDEF6). CONTRACTS_G6 §12: radar coverage, radar-gated SAMs, radar warnings, AWACS.
## Numbers: per-def flags (CONTENT6 defs) + rules.g6_airdef (content/g6/rules_airdef.json).
## Def flags read:
##   radar {radius, air_only?, own_only?}  radar source, building or unit (a_radar_station 28, a_awacs 24,
##       m_pulse_spire2 18). own_only: the radar serves only its own shots and the minimap picture; it never
##       covers another shooter (a SAM).
##   radar_required  building whose weapon fires only at a target a friendly radar covers (a_sam_site).
##       Gate: Status.can_fire(w, b) -> "NO_RADAR" (combat sets b.target before _fire).
##   awacs {radius, aa_acc_mult}  aircraft: enemy aircraft within radius are revealed to its team (e.marked_until /
##       e.marked_team, the G5 recon-mark rule Fog already honours) and friendly AA shots at air targets inside the
##       radius get x aa_acc_mult accuracy (acc_mult, a G6Hooks.accuracy_mult delegate).
##   stealth {radar_invisible, reveal_range}  target unseen by radar/AWACS unless within reveal_range of a source.
## A building source counts only when built, not EMP-disabled and (requires_power) powered; a unit source only
## while alive and airborne (not air_landed).
## State w.sys_state.airdef {contacts: {fid: {aid: last_seen_tick}}, picture: {fid: [aid]}, ver} - created only
## once a radar source exists (G5 matches never get it), refreshed every scan_every ticks, saved and hashed.
## picture is what the minimap draws (enemy aircraft fid's radar/AWACS sees).
## Events: RadarContact {fid, id, def, owner, pos} when an enemy aircraft enters fid's picture (a radar warning);
##   AwacsReveal {fid, awacs, ids} when an AWACS reveal pass marks at least one aircraft.
## Cache w.cache.airdef_sub (never saved): entity id lists by role (ascending id), shared with Counterdrone.
## Determinism: ascending ids, integer ticks, no rng. Never preload g6_hooks.gd, Damage or Movement here (cycle).

const SimIndex = preload("res://sim/systems/sim_index.gd")

const B_AIR := 1
const B_RADAR := 2
const B_AWACS := 4
const B_SAM := 8
const B_CIWS := 16
const B_NET := 32
const B_JAM := 64
const B_DRONE := 128
const B_DCC := 256
const LISTS := {"air": B_AIR, "radar": B_RADAR, "awacs": B_AWACS, "sam": B_SAM, "ciws": B_CIWS, "net": B_NET,
	"jam": B_JAM, "drone": B_DRONE, "dcc": B_DCC}
const VER := 1


static func tick(w: SimWorld) -> void:
	var sub := sub_state(w)
	if (sub.radar as Array).is_empty() and (sub.awacs as Array).is_empty():
		return
	var cfg := cfg()
	var every := maxi(int(cfg.get("scan_every", 10)), 1)
	if w.tick % every != int(cfg.get("scan_phase", 4)) % every:
		return
	var st := _state(w)
	if (sub.air as Array).is_empty() and (st.contacts as Dictionary).is_empty():
		return
	_awacs_pass(w, sub, cfg)
	var forget := every * maxi(int(cfg.get("contact_forget_scans", 6)), 1)
	var fids: Array = w.factions.keys()
	fids.sort()
	for fid in fids:
		var pic := _picture(w, int(fid))
		st.picture[int(fid)] = pic
		var known: Dictionary = st.contacts.get(int(fid), {})
		for aid in pic:
			if not known.has(aid) or w.tick - int(known[aid]) > forget:
				var a: Dictionary = w.entities[aid]
				w.emit("RadarContact", {"fid": int(fid), "id": int(aid), "def": String(a.def), "owner": int(a.owner), "pos": a.pos})
			known[aid] = w.tick
		var drop := []
		for aid in known:
			if w.tick - int(known[aid]) > forget or not w.entities.has(int(aid)):
				drop.append(aid)
		for aid in drop:
			known.erase(aid)
		st.contacts[int(fid)] = known


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	return "not_implemented"


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	pass


## True when friendly radar covers pos (SAM gating). own_only radars never cover for others.
static func radar_covers(w: SimWorld, fid: int, pos: Vector2) -> bool:
	for id in sub_list(w, "radar"):
		var src: Dictionary = w.entities[id]
		if not _friend(w, fid, int(src.owner)) or not source_active(w, src):
			continue
		var r := _radar(src)
		if bool(r.get("own_only", false)):
			continue
		if Vector2(src.pos).distance_to(pos) <= float(r.get("radius", 0.0)):
			return true
	return false


## Enemy aircraft ids revealed by fid's team radar/AWACS (ascending ids; the minimap radar picture).
## Computed live; w.sys_state.airdef.picture holds the copy from the last scan (for the render snapshot).
static func air_picture(w: SimWorld, fid: int) -> Array:
	return _picture(w, fid)


## True when shooter b (radar_required) may engage t: a friendly radar (or b's own radar) covers t.
static func covers_target(w: SimWorld, b: Dictionary, t: Dictionary) -> bool:
	var fid := int(b.owner)
	var tp: Vector2 = t.pos
	var inv := _stealth_range(t)
	for id in sub_list(w, "radar"):
		var src: Dictionary = w.entities[id]
		if not _friend(w, fid, int(src.owner)) or not source_active(w, src):
			continue
		var r := _radar(src)
		if bool(r.get("own_only", false)) and int(src.id) != int(b.id):
			continue
		var d := Vector2(src.pos).distance_to(tp)
		if d <= float(r.get("radius", 0.0)) and (inv < 0.0 or d <= inv):
			return true
	return false


## Status.can_fire gate for buildings: "" or "NO_RADAR" (a radar_required tower whose target is uncovered).
static func gate(w: SimWorld, b: Dictionary) -> String:
	if not _has_bit(w, b, B_SAM):
		return ""
	var t = w.entities.get(int(b.get("target", -1)))
	if t == null or covers_target(w, b, t):
		return ""
	return "NO_RADAR"


## Accuracy factor for src firing at t: x aa_acc_mult when t is airborne inside a friendly active AWACS radius
## and src's weapon can engage air (G6Hooks.accuracy_mult delegate). 1.0 otherwise (and with no AWACS).
static func acc_mult(w: SimWorld, src: Dictionary, s: Dictionary, t: Dictionary) -> float:
	var lst := sub_list(w, "awacs")
	if lst.is_empty() or not _airborne(w, t) or not bool(s.get("aa", false)):
		return 1.0
	var fid := int(src.owner)
	var best := 1.0
	for id in lst:
		var a: Dictionary = w.entities[id]
		if not _friend(w, fid, int(a.owner)) or not source_active(w, a):
			continue
		var ad: Dictionary = _def(a).get("awacs", {})
		if Vector2(a.pos).distance_to(Vector2(t.pos)) <= float(ad.get("radius", 0.0)):
			best = maxf(best, float(ad.get("aa_acc_mult", 1.0)))
	return best


## True when e is an airborne air unit (not landed / parked).
static func _airborne(w: SimWorld, e: Dictionary) -> bool:
	return e.get("kind", "") == "unit" and _has_bit(w, e, B_AIR) and not bool(e.get("air_landed", false))


## Building: built, not EMP-disabled, powered when it requires power. Unit: airborne if an aircraft.
static func source_active(w: SimWorld, e: Dictionary) -> bool:
	if e.kind == "building":
		if not bool(e.get("built", false)) or int(e.get("emp_until", -1)) > w.tick:
			return false
		if bool(Content.building(String(e.def)).get("requires_power", false)):
			var f = w.factions.get(int(e.owner))
			if f != null and int(f.get("power_use", 0)) > int(f.get("power_prod", 0)):
				return false
		return true
	if int(e.get("emp_until", -1)) > w.tick:
		return false
	return not bool(e.get("air_landed", false))


static func cfg() -> Dictionary:
	return Content.rules().get("g6_airdef", {})


static func _def(e: Dictionary) -> Dictionary:
	return Content.building(String(e.def)) if e.kind == "building" else Content.unit(String(e.def))


static func _radar(e: Dictionary) -> Dictionary:
	return _def(e).get("radar", {})


static func _friend(w: SimWorld, fid: int, owner: int) -> bool:
	return owner == fid or w.is_ally(fid, owner)


## reveal_range of a radar-invisible target, -1 for any normal target.
static func _stealth_range(t: Dictionary) -> float:
	if t.get("kind", "") != "unit":
		return -1.0
	var sd: Dictionary = Content.unit(String(t.def)).get("stealth", {})
	if not bool(sd.get("radar_invisible", false)):
		return -1.0
	return float(sd.get("reveal_range", 0.0))


static func _state(w: SimWorld) -> Dictionary:
	var st = w.sys_state.get("airdef")
	if st == null:
		st = {"contacts": {}, "picture": {}, "ver": VER}
		w.sys_state["airdef"] = st
	return st


## Enemy airborne aircraft inside any of fid's team radar / AWACS radii (radar_invisible: within reveal_range).
static func _picture(w: SimWorld, fid: int) -> Array:
	var srcs := []
	var seen := {}
	for lname in ["radar", "awacs"]:
		for id in sub_list(w, lname):
			if seen.has(id):
				continue   # an AWACS is in both lists
			seen[id] = true
			var src: Dictionary = w.entities[id]
			if _friend(w, fid, int(src.owner)) and source_active(w, src):
				srcs.append(src)
	var out := []
	if srcs.is_empty():
		return out
	for aid in sub_list(w, "air"):
		var a: Dictionary = w.entities[aid]
		if not w.is_enemy(fid, int(a.owner)) or bool(a.get("air_landed", false)):
			continue
		var inv := _stealth_range(a)
		for src in srcs:
			var d := _def(src)
			var rad := maxf(float(d.get("radar", {}).get("radius", 0.0)), float(d.get("awacs", {}).get("radius", 0.0)))
			var dd := Vector2(src.pos).distance_to(Vector2(a.pos))
			if dd <= rad and (inv < 0.0 or dd <= inv):
				out.append(int(aid))
				break
	return out


## AWACS reveal: enemy airborne aircraft within awacs.radius are marked for the AWACS team.
static func _awacs_pass(w: SimWorld, sub: Dictionary, c: Dictionary) -> void:
	var until := w.tick + int(c.get("awacs_mark_ticks", 30))
	for id in sub_list(w, "awacs"):
		var a: Dictionary = w.entities[id]
		if not source_active(w, a):
			continue
		var fid := int(a.owner)
		var team := int(w.factions[fid].get("team", fid)) if w.factions.has(fid) else fid
		var rad := float(_def(a).get("awacs", {}).get("radius", 0.0))
		var ids := []
		for aid in sub_list(w, "air"):
			var t: Dictionary = w.entities[aid]
			if not w.is_enemy(fid, int(t.owner)) or bool(t.get("air_landed", false)):
				continue
			var inv := _stealth_range(t)
			var dd := Vector2(a.pos).distance_to(Vector2(t.pos))
			if dd <= rad and (inv < 0.0 or dd <= inv):
				t.marked_until = until
				t.marked_team = team
				ids.append(int(aid))
		if not ids.is_empty():
			w.emit("AwacsReveal", {"fid": fid, "awacs": int(id), "ids": ids})


# ================================================================ role subsets (cache, never saved)
## Role bits of an entity's def (cached per world in the subset state).
static func _mask_of(st: Dictionary, e: Dictionary) -> int:
	var key := ("b:" if e.kind == "building" else "u:") + String(e.def)
	var m = st.defs.get(key)
	if m != null:
		return int(m)
	var bits := 0
	var cd: Dictionary = cfg().get("counter_drone", {})
	if e.kind == "building":
		var d := Content.building(String(e.def))
		if d.has("radar"):
			bits |= B_RADAR
		if bool(d.get("radar_required", false)):
			bits |= B_SAM
		if d.has("ciws"):
			bits |= B_CIWS
		if d.has("net_capture"):
			bits |= B_NET
		if d.has("jammer"):
			bits |= B_JAM
		if d.has("drone_cc"):
			bits |= B_DCC
	elif e.kind == "unit":
		var d := Content.unit(String(e.def))
		var air := bool(d.get("is_air", false)) or String(d.get("move_class", "")).begins_with("air")
		if air:
			bits |= B_AIR
			var drone := false
			for f in cd.get("drone_flags", ["launched_drone"]):
				drone = drone or bool(d.get(String(f), false))
			drone = drone or (cd.get("drone_roles", []) as Array).has(String(d.get("role", ""))) \
				or (cd.get("drone_aircraft", []) as Array).has(String(d.get("aircraft", "")))
			if drone:
				bits |= B_DRONE
		if d.has("radar"):
			bits |= B_RADAR
		if d.has("awacs"):
			bits |= B_AWACS
		if d.has("jammer"):
			bits |= B_JAM
	st.defs[key] = bits
	return bits


static func _has_bit(w: SimWorld, e: Dictionary, bit: int) -> bool:
	return _mask_of(sub_state(w), e) & bit != 0


static func _add(st: Dictionary, e: Dictionary) -> void:
	var m := _mask_of(st, e)
	if m == 0:
		return
	for lname in LISTS:
		if m & int(LISTS[lname]):
			(st[lname] as Array).append(int(e.id))


## {defs, next_id, <list>: [ids ascending]}; incremental on new ids; full rebuild when missing.
static func sub_state(w: SimWorld) -> Dictionary:
	var st = w.cache.get("airdef_sub")
	var nid := int(w.next_id)
	if st == null:
		st = {"defs": {}, "next_id": nid}
		for lname in LISTS:
			st[lname] = []
		var ids: Array = w.entities.keys()
		ids.sort()
		for id in ids:
			_add(st, w.entities[id])
		w.cache["airdef_sub"] = st
		return st
	if nid > int(st.next_id):
		for id in range(int(st.next_id), nid):
			var e = w.entities.get(id)
			if e != null:
				_add(st, e)
		st.next_id = nid
	return st


## Live ids of one role list (dead ids are dropped in place).
static func sub_list(w: SimWorld, lname: String) -> Array:
	var st := sub_state(w)
	var arr: Array = st[lname]
	var dead := false
	for id in arr:
		if not w.entities.has(id):
			dead = true
			break
	if dead:
		var keep := []
		for id in arr:
			if w.entities.has(id):
				keep.append(id)
		st[lname] = keep
		return keep
	return arr
