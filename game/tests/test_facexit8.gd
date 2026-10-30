extends "res://tests/test_base.gd"
## G7 APCOUT8 regression (owner bug, packaged Last Protocol 23e0447: "i CANT send my apcs outside of the facility -- they
## just stop and cant make it through wash area"; "exact same thing with my strike team and other units inside facility").
## Cause: FacDrive7's convoy rule (the APC ordered earlier enters the gate lane first) deadlocked when every APC was sent
## out at once: g3 (closest to the lane) waited for g0, g0 stood behind g1 behind g2 (spacing), and g2, once in the lane,
## stood behind g3. Real LP start (768 map), plain player "move" orders (the right-click command), quiet and with the
## Machine at the gate (outer gate hardened: sally rules respected).

const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const FacDrive7 = preload("res://sim/systems/fac_drive7.gd")
const NOFIRE := 100000
const OUT_D := 33          # Chebyshev distance from the base centre beyond the outer wall (wall at 30)
const OUT_FAC := 17        # beyond the facility compound wall (compound half-size 14) + a body

const SALLY_S := 90.0     # FACFLOW8 (owner target): a hardened sally of all 8 APCs is out of the facility within 90 s
const MOVED := 0.75       # FACFLOW8: an APC that moved less than this in STALL_S while not out is stalled
const STALL_S := 20.0

static var _base: Dictionary = {}


## FACFLOW8: the Machine stays near (13.9c-22 hardened gate). A lone rifleman by the compound is shot by the base's
## guns within ~1 s (a head wound kills whatever its hp), and the gate stood down 20 s later: the old "machine near"
## cases ran almost unhardened, which hid the windowed flow's slow sally. Another one takes its place whenever it falls
## (the real game: the Machine keeps coming). Returns the live threat id.
static func keep_threat(w: SimWorld, fid: int, at: Vector2, en: int) -> int:
	if en >= 0 and w.entities.has(en):
		return en
	var mf := -1
	for f in w.factions.size():
		if w.is_enemy(fid, f):
			mf = f
			break
	var id := w.spawn_unit("rifleman", mf, at)
	var ee: Dictionary = w.entities[id]
	ee.order = {"type": "hold"}
	ee.cd_ticks = NOFIRE
	ee.hp = 1.0e9
	ee.max_hp = 1.0e9
	return id


func _lp() -> SimWorld:
	if not preload("res://sim/map_gen.gd").has_map("last_protocol"):
		return null
	if _base.is_empty():
		var w0 := SimWorld.new_match(LastProtocol.make_config(77, "last_protocol"))
		if w0 == null:
			return null
		w0.run_ticks(25)
		_base = w0.to_dict().duplicate(true)
	var w := SimWorld.from_dict(_base.duplicate(true))
	w.ai_state = {}
	return w


func _cheb(a: Vector2, c: Vector2) -> float:
	return maxf(absf(a.x - c.x), absf(a.y - c.y))


## APCs (with their strike teams / tactical squads aboard), some Sentinels and the facility engineers inside the compound.
func _groups(w: SimWorld, fid: int, cr: Rect2) -> Dictionary:
	var apcs := []
	var foot := []
	var ids: Array = []
	for e in w.units_of(fid):
		ids.append(int(e.id))
	ids.sort()
	for id in ids:
		var e: Dictionary = w.entities[id]
		if not cr.has_point(Vector2(e.pos)) or e.get("in_transport", false) or e.has("carrier"):
			continue
		var k := String(e.def)
		if k.contains("apc"):
			apcs.append(id)
		elif (k == "g7_fac_engineer" or k.begins_with("g7_sent_")) and foot.size() < 6:
			foot.append(id)
	return {"apcs": apcs, "foot": foot}


func _run_out(w: SimWorld, label: String, enemy_near: bool, tgt_a := Vector2(0, 44), tgt_f := Vector2(0, 40)) -> void:
	var s: Dictionary = w.sys_state.lp
	var fid := int(s.fid)
	var facs: Array = CnFacility.facilities(w, fid)
	if not check(not facs.is_empty(), "%s: LP facility raised" % label):
		return
	var F := CnFacility.fac(w, int(facs[0]))
	var cr := CnFacility.compound_rect(F)
	var C := Vector2(w.map.lp.base.center)
	var g := _groups(w, fid, cr)
	var apcs: Array = g.apcs
	var foot: Array = g.foot
	check_eq(apcs.size(), 8, "%s: 8 APCs parked in the facility (2 strike teams + 4 tactical squads)" % label)
	check(foot.size() >= 4, "%s: foot units inside the facility (%d)" % [label, foot.size()])
	for id in apcs + foot:
		w.entities[id].cd_ticks = NOFIRE
		for u in w.entities[id].get("cargo", []):
			u.cd_ticks = NOFIRE
	var en := -1
	var at := cr.end + Vector2(6, 8)   # inside THREAT_PAD of the compound, off the exit road
	if enemy_near:
		for i in CnFacility.secs(FacDrive7.GATE_S) + 80:
			en = keep_threat(w, fid, at, en)
			w.step()
		var GT: Dictionary = F.get("gate", {})
		check(not GT.is_empty() and bool(GT.get("hard", false)), "%s: the Machine near: the outer gate is hardened (%s)" % [label, GT])
	var tgt := C + tgt_a
	var r := w.submit({"type": "move", "unit_ids": apcs, "target": tgt, "issuer": fid})
	check(r.ok, "%s: APC move accepted (%s)" % [label, r.reason])
	r = w.submit({"type": "move", "unit_ids": foot, "target": C + tgt_f, "issuer": fid})
	check(r.ok, "%s: foot move accepted (%s)" % [label, r.reason])
	var out_at := {}
	var fac_at := {}
	var both_open := false
	var unhard := 0
	var lim := 3600
	var seen := {}
	var stalls := []
	for t in lim:
		if enemy_near:
			en = keep_threat(w, fid, at, en)
		w.step()
		var GT: Dictionary = F.get("gate", {})
		if enemy_near and not bool(GT.get("hard", false)):
			unhard += 1
		if enemy_near and bool(GT.get("hard", false)) and String(GT.get("o", "")) == "open" and String(GT.get("i", "")) == "open":
			both_open = true
		if t % 10 == 0:
			for id in apcs + foot:
				var e = w.entities.get(id)
				if e != null and not out_at.has(id) and _cheb(Vector2(e.pos), C) >= OUT_D:
					out_at[id] = t
				if e != null and apcs.has(id) and not fac_at.has(id) and _cheb(Vector2(e.pos), C) >= OUT_FAC:
					fac_at[id] = t
			if out_at.size() == apcs.size() + foot.size():
				break
		# FACFLOW8 diagnostics only (an APC waiting its turn for the sally port legitimately stands still for cycles)
		if t % CnFacility.secs(STALL_S) == 0:
			for id in apcs:
				var e = w.entities.get(id)
				if e == null or fac_at.has(id):
					continue
				if seen.has(id) and Vector2(e.pos).distance_to(seen[id]) < MOVED and FacDrive7.vstate(w, id).get("st", "") == "drive":
					stalls.append([t, id, (Vector2(e.pos) - cr.position).snapped(Vector2(0.1, 0.1))])
				seen[id] = Vector2(e.pos)
	var na := 0
	var nf := 0
	var last := 0
	for id in out_at:
		last = maxi(last, int(out_at[id]))
		if apcs.has(id):
			na += 1
		else:
			nf += 1
	var stuck := []
	for id in apcs + foot:
		if not out_at.has(id):
			var e = w.entities.get(id)
			stuck.append([id, String(e.def), Vector2(e.pos).snapped(Vector2(0.1, 0.1)), FacDrive7.vstate(w, id).get("st", "")] if e != null else [id, "dead"])
	print("  FACEXIT8 %s: APCs out %d/%d, foot out %d/%d, last out at +%d ticks; stuck %s" % [label, na, apcs.size(), nf, foot.size(), last, stuck])
	var lastf := 0
	for id in fac_at:
		lastf = maxi(lastf, int(fac_at[id]))
	print("  FACEXIT8 %s: APCs out of the facility %d/%d, last at +%d ticks (%.1f s); unhardened ticks %d; still >%d s %s" % [label, fac_at.size(), apcs.size(), lastf, lastf / float(SimWorld.TICK_RATE), unhard, int(STALL_S), stalls])
	check_eq(na, apcs.size(), "%s: every APC ordered out drove past the outer wall (no deadlock at the wash / gate lane)" % label)
	if enemy_near:
		check_eq(unhard, 0, "%s: the outer gate stayed hardened through the whole sally (the Machine stays near)" % label)
		check(fac_at.size() == apcs.size() and lastf <= CnFacility.secs(SALLY_S), "%s: all %d APCs out of the facility through the sally port within %d s (last +%.1f s)" % [label, apcs.size(), int(SALLY_S), lastf / float(SimWorld.TICK_RATE)])
	check_eq(nf, foot.size(), "%s: every foot unit ordered out walked past the outer wall" % label)
	if enemy_near:
		check(not both_open, "%s: outer and inner gates never open together while hardened (sally port)" % label)
	if na < apcs.size():
		return
	# APCOUT8B: the APCs stay out (no automatic duty pulls a player-ordered APC back in; Sentinels and engineers do
	# return after own_timeout_s by design, 13.9c-12, so they are not checked here)
	for t in 60 * SimWorld.TICK_RATE:
		w.step()
	var back := []
	for id in apcs:
		var e = w.entities.get(id)
		if e != null and _cheb(Vector2(e.pos), C) < OUT_D:
			back.append(id)
	check(back.is_empty(), "%s: no APC ordered out drove back inside within 60 s (%s)" % [label, back])


func test_all_apcs_and_foot_ordered_out_quiet() -> void:
	var w := _lp()
	if w == null:
		check(true, "last_protocol map not registered: skipped")
		return
	_run_out(w, "quiet", false)


func test_all_apcs_and_foot_ordered_out_machine_at_the_gate() -> void:
	if not FacDrive7.GATES_ON:
		print("  FACEXIT8 hardened case NOT EXECUTED: FacDrive7.GATES_ON is false")
		return
	var w := _lp()
	if w == null:
		check(true, "last_protocol map not registered: skipped")
		return
	_run_out(w, "machine near", true)


## FACFLOW8 (owner, windowed LP: "i CANT send my apcs outside of the facility"; 6 of 8 out after ~5 min): the real
## Last Protocol start as the facexit8 flow plays it: AI kept running, a 150-tick warm-up (staff, Sentinels on their
## posts), the Machine near (hardened), the flow's clicked points.
func test_real_lp_start_hardened_sally() -> void:
	if not FacDrive7.GATES_ON:
		print("  FACEXIT8 real-start case NOT EXECUTED: FacDrive7.GATES_ON is false")
		return
	if not preload("res://sim/map_gen.gd").has_map("last_protocol"):
		check(true, "last_protocol map not registered: skipped")
		return
	var w := SimWorld.new_match(LastProtocol.make_config(77, "last_protocol"))
	w.run_ticks(150)
	_run_out(w, "real start", true, Vector2(0.5, 54.5), Vector2(0.5, 40.5))


## APCOUT8B (owner: "exact same thing with my strike team and other units inside facility"): a strike team and a
## tactical squad dismounted inside the compound and ordered out on foot (plain player move) walk past the outer wall
## (out of the compound: an 18-man group ends in a column reaching back into the outer-wall gateway) and are STILL out a full minute later (longer than the Sentinels' / engineers' 45 s own_timeout_s, 13.9c-12: only
## those return to automatic duty by design); the APCs that drove out stay out too.
func test_dismounted_strike_team_and_squad_ordered_out_stay_out() -> void:
	var w := _lp()
	if w == null:
		check(true, "last_protocol map not registered: skipped")
		return
	var fid := int(w.sys_state.lp.fid)
	var facs: Array = CnFacility.facilities(w, fid)
	if not check(not facs.is_empty(), "dismount: LP facility raised"):
		return
	var F := CnFacility.fac(w, int(facs[0]))
	var cr := CnFacility.compound_rect(F)
	var C := Vector2(w.map.lp.base.center)
	var g := _groups(w, fid, cr)
	var strike := -1
	var tact := -1
	for id in g.apcs:
		var k := String(w.entities[id].def)
		if strike < 0 and k == "g7_cn_strike_apc":
			strike = id
		elif tact < 0 and k == "g7_op_tactical_apc":
			tact = id
	if not check(strike >= 0 and tact >= 0, "dismount: a strike-team APC and a tactical-squad APC in the facility"):
		return
	var inf := []
	for c in [strike, tact]:
		for u in w.entities[c].get("cargo", []):
			inf.append(int(u.id))
		var r := w.submit({"type": "unload_all", "carrier": c, "issuer": fid})
		check(r.ok, "dismount: unload_all accepted (%s)" % r.reason)
	for t in 600:
		w.step()
	inf.sort()
	var foot := []
	for id in inf:
		var e = w.entities.get(id)
		if e != null and not e.get("in_transport", false) and cr.has_point(Vector2(e.pos)):
			e.cd_ticks = NOFIRE
			foot.append(id)
	check(foot.size() >= 10, "dismount: strike team + tactical squad standing inside the compound (%d of %d)" % [foot.size(), inf.size()])
	var r2 := w.submit({"type": "move", "unit_ids": foot, "target": C + Vector2(0, 40), "issuer": fid})
	check(r2.ok, "dismount: foot move accepted (%s)" % r2.reason)
	var out_at := {}
	for t in 3600:
		w.step()
		if t % 10 == 0:
			for id in foot:
				var e = w.entities.get(id)
				if e != null and not out_at.has(id) and _cheb(Vector2(e.pos), C) >= OUT_FAC:
					out_at[id] = t
			if out_at.size() == foot.size():
				break
	print("  FACEXIT8 dismounted: out %d/%d" % [out_at.size(), foot.size()])
	check_eq(out_at.size(), foot.size(), "dismount: every strike-team / tactical-squad soldier ordered out walked out of the facility compound (an 18-man group ends in a column whose tail stands in the outer-wall gateway, so the compound wall is the line)")
	for t in 60 * SimWorld.TICK_RATE:
		w.step()
	var back := []
	for id in foot:
		var e = w.entities.get(id)
		if e != null and _cheb(Vector2(e.pos), C) < OUT_FAC:
			back.append([id, String(e.def), Vector2(e.pos).snapped(Vector2(0.1, 0.1)), String(e.order.get("type", ""))])
	print("  FACEXIT8 dismounted: back inside after 60 s %s" % [back])
	check(back.is_empty(), "dismount: no soldier ordered out walked back into the facility within 60 s (%s)" % [back])
