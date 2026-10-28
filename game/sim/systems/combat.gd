extends RefCounted
## Combat (owner: agent B / sim-mil). Target acquisition, chasing, firing, damage, death.
## Commands: attack. Contract: docs/CONTRACTS.md section 5.
##
## Target choice is deterministic: nearest visible enemy (unit or building; distance to a building
## is measured to its footprint), ties go to the lower id. Scans are staggered: each shooter rescans
## every SCAN_EVERY ticks ((tick + id) % SCAN_EVERY == 0) and keeps a still-valid target in between.
## Stances by order type:
##   idle         aggressive: engage the nearest enemy within sight, chase it while it stays in sight.
##   attack_move  as idle, then resume the path to order.target; idle on arrival.
##   attack       chase target_id while visible; if it becomes non-visible go to its last-known
##                position, then idle. Destroyed target -> idle.
##   hold         fire at enemies within weapon range only, never move.
##   move/other   no auto-engage (forced move), but return fire (see engineers).
## ENGINEERS (units with can_build) ONLY RETURN FIRE: they never auto-acquire, whatever their order;
## they shoot back at the unit that hit them within the last RETURN_FIRE_TICKS if it is visible and
## in range, without moving. An explicit `attack` order is still obeyed.
## Buildings with a weapon (guard_tower) fire only when built, within weapon range.
## Randomness (hit roll, miss dispersion of the tracer end point) uses w.rng only.
## G3a (S3-sim, CONTRACTS_G3a section 3):
##   AIR: only weapons with `anti_air` may target units whose def has `is_air` (search, kept
##   targets, explicit attack orders and command validation all filter this).
##   ARTILLERY (`indirect` weapons): engages any visible enemy within range and beyond min_range
##   (search radius = max(sight, range)), ignores Damage.line_clear, and on firing applies splash to
##   every ground unit/building within `splash` of the impact point (allies too) with linear falloff
##   to 50% at the edge: one ShotFired {indirect:true} plus one Damage event per entity hit.
##   An explicit attack on a target inside min_range backs the shooter away.
## G5 (CORE10K, CONTRACTS_G5 section 3.6): weapon flags anti_air_low / anti_air_high / anti_drone go
##   into stats (aa_low, aa_high, anti_drone); `aa` = anti_air or either new flag. An air target must
##   also pass Air.can_target(s, t) (AIRSYS rule; s = these combat stats, s.weapon = weapon id), and a
##   Wounded unit (Medical, e.wounded) is never a direct-fire target (splash still hits it). Both are
##   no-ops for G4 content, so G4 results are unchanged. See _g5_ok.

const Movement = preload("res://sim/systems/movement.gd")
const Fog = preload("res://sim/systems/fog.gd")
const Status = preload("res://sim/systems/status.gd")
const Damage = preload("res://sim/systems/damage.gd")
const Shrapnel = preload("res://sim/systems/shrapnel.gd")  # G7 (WOUND7): fragments
const Supply = preload("res://sim/systems/supply.gd")
const NativeCore = preload("res://sim/native_core.gd")
const Tiers = preload("res://sim/systems/tiers.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const Inert7 = preload("res://sim/systems/inert7.gd")   # G7 LPPERF7: def-filtered building lists
const Fortify = preload("res://sim/systems/fortify.gd")
const G4bMech = preload("res://sim/systems/g4b_mech.gd")  # G4b UNITS: concealment, ignite
## G6 PERF6 (CONTRACTS_G6 section 5.1): hit/splash damage_mult (next to _g4_mult), hit-roll accuracy_mult,
## acquisition + fire range_mult (_rm: hold/indirect scan radii, _pick, _engage, _return_fire, towers; the
## native scan radii are rescaled in _scan_rm), height LOS los_ok (_hlos, after the terrain line of fire;
## air shooters/targets and indirect fire skip it), visible_to in _cand_ok (Fog.entity_visible covers _seen).
## Each hook is called only when its bit is set in SimIndex.g6m(w).
const G6Hooks = preload("res://sim/systems/g6_hooks.gd")
const Elevation = preload("res://sim/systems/elevation.gd")   # G6: MAX_LEVEL for the native height LOS
const WallWalk7 = preload("res://sim/systems/wallwalk7.gd")   # G7 WALL7-3 CR 5500: idle defenders hold the wall-walk
const CnRole7 = preload("res://sim/systems/cn_role7.gd")   # G7 CNROLE7 CR 6046 (13.9c-29): CN teams parked at home never chase
const Traverse7 = preload("res://sim/systems/traverse7.gd")   # G7 TURRET7B CR 6354 (13.9c-30): turret / mount traverse before fire
## G6 PERF6: height LOS through RtsCombat.height_los (rts_core >= 0.5.0, exact port of Elevation.los_map) while
## G6Hooks.los_ok == Elevation.los (its only delegate) and no test spy is set. Off = the GDScript hook.
static var native_elev := true

const BUCKET := 2.0
const GRID_STRIDE := 1024
const SCAN_EVERY := 4
const SCAN_EVERY_ENGAGED := 32
const CHASE_REPATH_TICKS := 10
const RETURN_FIRE_TICKS := 60
const FIRING_HINT_TICKS := 3
const Q := 1.0 / 1024.0          # quantum for saved floats (exact in decimal text)

static var _stats: Dictionary = {}
static var _no_search := false   # REDUCED pass: searches return null (Tiers contact bound)
## PERF4-4: with the native core live, line-of-fire checks run in RtsCombat.line_clear (an exact port
## of Damage.line_clear). false forces the GDScript walk (parity test / bench); outcomes are identical.
static var native_los := true
static var prof_units := false   # bench: time each _unit_tick by order type (adds overhead)
## SIM10K: act_skip = do not call _unit_tick when its result is a no-op by construction (prep skip
## codes + null-search skip); native_prep = run the prep loop as RtsCombat.prep_units (needs
## act_skip and rts_core >= 0.3.1). Both exact (tests/test_perf_systems.gd); false = PERF10K-2 path.
static var act_skip := true
## CORE10K-2: native prep with the list's ids (rts_core >= 0.4.2; dict-free pass 1, act by index). Off = 0.3.1 call.
static var prep_ids := true
static var native_prep := true


## Cached combat stats for an entity def.
static func stats(e: Dictionary) -> Dictionary:
	var key = e.def   # unit and building def ids are disjoint
	if _stats.has(key):
		return _stats[key]
	var d: Dictionary = Content.unit(e.def) if e.kind == "unit" else Content.building(e.def)
	var wid := String(d.get("weapon", ""))
	var wd: Dictionary = Content.weapon(wid) if wid != "" else {}
	var s := {
		"weapon": wid if not wd.is_empty() else "",
		"range": float(wd.get("range", 0)),
		"cooldown": float(wd.get("cooldown", 1)),
		"accuracy": float(wd.get("accuracy", 0)),
		"damage": float(wd.get("damage", 0)),
		"cls": String(wd.get("class", "")),
		"armor": String(d.get("armor", "infantry")),
		"sight": float(d.get("sight", 0)),
		"builder": bool(d.get("can_build", false)),
		"aa": bool(wd.get("anti_air", false)) or bool(wd.get("anti_air_low", false)) or bool(wd.get("anti_air_high", false)),
		"aa_low": bool(wd.get("anti_air_low", false)) or bool(wd.get("anti_air", false)),   # G5 section 3.6
		"aa_high": bool(wd.get("anti_air_high", false)),
		"naval_only": bool(wd.get("naval_only", false)),   # G6 NAVAL6: torpedoes hit naval ships only
		"anti_drone": bool(wd.get("anti_drone", false)),
		"indirect": bool(wd.get("indirect", false)),
		"min_range": 0.0 if bool(wd.get("guided", false)) else float(wd.get("min_range", 0)),  # G3b STG4: guided
		"guided": bool(wd.get("guided", false)),  # G3b STG4: indirect, no friendly splash, no scatter
		"splash": float(wd.get("splash", 0)),
		"is_air": bool(d.get("is_air", false)),
		# G4b UNITS (CONTRACTS_G4 section 8): mortar set-up, flamer, sniper cover, salvo, mech front armor
		"setup": int(d.get("setup_ticks", 0)),
		"ignite": bool(wd.get("ignite", false)),
		"ignore_cover": bool(wd.get("ignore_cover", false)),
		"cover_mult": float(wd.get("cover_mult", 1.0)),
		"salvo": int(wd.get("salvo", 1)),
		"salvo_gap": float(wd.get("salvo_gap", 0.25)),
		"front_mult": float(d.get("front_armor_mult", 1.0)),
	}
	_stats[key] = s
	return s


## Damage one hit from shooter e would do to target t (weapon damage x armor table).
static func shot_damage(e: Dictionary, t: Dictionary) -> float:
	var s := stats(e)
	return s.damage * Content.armor_mult(s.cls, stats(t).armor)


## Distance from p to target t (footprint rectangle for buildings, centre for units).
static func dist_to(p: Vector2, t: Dictionary) -> float:
	if t.kind == "building":
		var o: Vector2i = t.cell
		var sz := float(t.size)
		var q := Vector2(clampf(p.x, float(o.x), float(o.x) + sz), clampf(p.y, float(o.y), float(o.y) + sz))
		return p.distance_to(q)
	var tp: Vector2 = t.pos
	return p.distance_to(tp)


# ================================================================ tick
## Cooldown is authoritative in whole ticks (e.cd_ticks); e.cooldown (seconds) mirrors it as
## cd_ticks / 20. Integer state keeps the var_to_str save round trip exact.
static func _cd(e: Dictionary) -> int:
	if e.has("cd_ticks"):
		return int(e.cd_ticks)
	return maxi(ceili(float(e.get("cooldown", 0.0)) * SimWorld.TICK_RATE - 1e-6), 0)


## G3b PERF4/PERF4-2 (fidelity tiers + native search). FULL units come from the Tiers lists
## (Tiers.lists(w).full: one shared index, no per-tick pass over every unit) and run every tick.
## A REDUCED unit (Tiers: no enemy unit or building anywhere near) runs only on its stride tick
## ((tick + id) % Tiers.SCAN_STRIDE == 0), after the FULL units, with its cooldown and firing hint
## caught up by SCAN_STRIDE. It never searches: by the Tiers contact bound no enemy can be inside
## any search radius of it (and it is inside none), so the search result is null by construction
## and REDUCED units are left out of the per-tick grids altogether.
## With the native core live, target search asks RtsGrid.nearest_enemy_batch for the nearest
## enemy candidate (one batched call for every FULL unit on its scan slot, single calls otherwise)
## and verifies it (visible, not concealed, min_range); if it fails the check, an exact scan of
## RtsGrid.query_radius runs instead, so the result equals find_target().
static func tick(w: SimWorld) -> void:
	var t0 := Time.get_ticks_usec() if SimIndex.profiling else 0
	var tiers_on := Tiers.enabled(w)
	var idx := Tiers.lists(w)
	var units: Array = idx.full if tiers_on else idx.kinds.get("unit", [])
	var all_blds: Array = idx.kinds.get("building", [])
	var native := NativeCore.enabled(w)
	var ents: Dictionary = w.entities
	var grid := {}   # owner -> {bucket key -> [unit dicts]} (GDScript search, splash, Damage.near_miss)
	var blds := []
	var act := []    # FULL units that act this tick, ascending id
	var askip := PackedByteArray()   # SIM10K: per act entry, 0 = call _unit_tick, else a no-op class
	var atg := PackedInt32Array()    # SIM10K: per act entry, its target id at prep
	var act_ix := PackedInt32Array()  # CORE10K-2 (rts_core >= 0.4.2): act entries as indices into units
	var act_id := PackedInt32Array()  # and their ids (when set, act stays empty)
	var nids := PackedInt32Array()
	var npos := PackedVector2Array()
	var nteam := PackedInt32Array()
	var nflags := PackedInt32Array()
	# id -> index in this tick's RtsGrid (-1: not in it). A packed array over ids (one memset)
	# instead of a Dictionary insert per unit (PERF4-3)
	var nidx := PackedInt32Array()
	if native:
		nidx.resize(int(w.next_id) + 1)
		nidx.fill(-1)
	var teams := {}
	for fid in w.factions:
		teams[int(fid)] = int(w.factions[fid].get("team", fid))
	var scan_src := PackedInt32Array()   # native pre-batch: FULL units on their scan slot
	var scan_r := PackedFloat32Array()
	var scan_need := PackedInt32Array()
	var scan_ids := PackedInt32Array()
	var tick := w.tick
	# the GDScript grid serves the non-native search/splash and Damage.near_miss; with native live
	# it is skipped once damage.gd declares NEAR_MISS_NG (near_miss reads w.cache.combat_ng then)
	var need_grid := not native or not _dmg_uses_ng()
	# PERF4-4: per-id runtime table (owner and def never change after spawn; rebuilt when the team
	# map changes; never saved): 0 = not filled, -1 = no faction team (not in the RtsGrid), else
	# ((team + 1) << 3) | 4 if it can auto-scan (armed, not a builder) | 2 air / 1 ground.
	var tf := PackedInt32Array()
	if native:
		var tabs = w.cache.get("cmb_tabs")
		if tabs == null or tabs.teams != teams:
			tabs = {"teams": teams.duplicate(), "tf": PackedInt32Array()}
			w.cache["cmb_tabs"] = tabs
		tf = tabs.tf
		if tf.size() < nidx.size():
			tf.resize(nidx.size())
			tabs.tf = tf
	# SIM10K: with rts_core >= 0.3.1 the whole prep loop below (grid inputs, scan pre-batch, firing /
	# cooldown countdown writes, act-skip codes) runs as one RtsCombat.prep_units call (exact port;
	# the GDScript loop stays the fallback and the hash oracle).
	var trf := float(SimWorld.TICK_RATE)
	var np_done := false
	var nores := PackedByteArray()   # SIM10K: per id, 1 = this tick's search is null by construction
	if native and not need_grid and native_prep and act_skip:
		var cobj = _combat_obj(w)
		if cobj != null and cobj.has_method("prep_units"):
			var tabs: Dictionary = w.cache["cmb_tabs"]
			if not tabs.has("dx"):
				tabs["dx"] = PackedInt32Array()
				tabs["dmap"] = {}
				tabs["dr"] = PackedFloat32Array()
				tabs["ds"] = PackedFloat32Array()
				tabs["df"] = PackedInt32Array()
			var dxa: PackedInt32Array = tabs.dx
			if dxa.size() < tf.size():
				dxa.resize(tf.size())
				tabs.dx = dxa
			if SimIndex.profiling:
				t0 = SimIndex.pt("cmb.pre_np", t0)
			# CORE10K-2: rts_core >= 0.4.2 takes the FULL list's ids (cached per list) so its pass 1 reads
			# no unit dict, and returns act_ids so a skipped act entry is never read either
			var pids := _list_ids(idx, units) if prep_ids and tiers_on and cobj.has_method("prep_units_ids") else PackedInt32Array()
			var r: Array
			if not pids.is_empty():
				r = cobj.prep_units_ids(units, ents, pids, tick, [tf, dxa, tabs.dr, tabs.ds, tabs.df], int(w.next_id), trf, SCAN_EVERY, RETURN_FIRE_TICKS)
			else:
				r = cobj.prep_units(units, ents, tick, tf, dxa, tabs.dr, tabs.ds, tabs.df, int(w.next_id), trf, SCAN_EVERY, RETURN_FIRE_TICKS)
			if SimIndex.profiling:
				t0 = SimIndex.pt("cmb.np", t0)
			if r.size() == 1:
				for nid in r[0]:
					var ne: Dictionary = ents[nid]
					if tf[nid] == 0:
						tf[nid] = _tf_of(ne, teams)
					dxa[nid] = _dx_of(ne, tabs)
				if not pids.is_empty():
					r = cobj.prep_units_ids(units, ents, pids, tick, [tf, dxa, tabs.dr, tabs.ds, tabs.df], int(w.next_id), trf, SCAN_EVERY, RETURN_FIRE_TICKS)
				else:
					r = cobj.prep_units(units, ents, tick, tf, dxa, tabs.dr, tabs.ds, tabs.df, int(w.next_id), trf, SCAN_EVERY, RETURN_FIRE_TICKS)
			if r.size() == 12 or r.size() == 13:
				nids = r[0]
				npos = r[1]
				nteam = r[2]
				nflags = r[3]
				nidx = r[4]
				scan_src = r[5]
				scan_r = r[6]
				scan_need = r[7]
				scan_ids = r[8]
				var aix: PackedInt32Array = r[9]
				askip = r[10]
				atg = r[11]
				if r.size() == 13:
					act_ix = aix          # CORE10K-2: act entries by index into units, ids alongside
					act_id = r[12]
				else:
					for k in aix:
						act.append(units[k])
				np_done = true
				if SimIndex.profiling:
					var nz := 0
					for c in askip:
						if c == 0:
							nz += 1
					SimIndex.prof["n.act_listed"] = [aix.size() * 1000, 1]
					SimIndex.prof["n.act_code0"] = [nz * 1000, 1]
					t0 = SimIndex.pt("cmb.np_unpack", t0)
	if not np_done:
		var nn := 0   # RtsGrid entries written (arrays pre-sized, trimmed after the loop)
		if native:
			nids.resize(units.size())
			npos.resize(units.size())
			nteam.resize(units.size())
			nflags.resize(units.size())
		for e: Dictionary in units:
			var id: int = e.id
			if not ents.has(id):
				continue
			var p: Vector2 = e.pos
			if need_grid:
				var o: int = e.owner
				var g = grid.get(o)
				if g == null:
					g = {}
					grid[o] = g
				var key := floori(p.x / BUCKET) + floori(p.y / BUCKET) * GRID_STRIDE
				var cell = g.get(key)
				if cell == null:
					g[key] = [e]
				else:
					cell.append(e)
			if native:
				var tfv := tf[id]
				if tfv == 0:
					tfv = _tf_of(e, teams)
					tf[id] = tfv
				if tfv > 0:
					var si := nn
					nn += 1
					nidx[id] = si
					nids[si] = id
					npos[si] = p
					nteam[si] = (tfv >> 3) - 1
					# CORE10K-2: a landed aircraft is a ground target too (AIRSYS CR 2831): air|ground, so the
					# native nearest-enemy search offers it to non-AA shooters exactly like find_target does
					nflags[si] = 3 if tfv & 2 and _landed(e) else tfv & 3
					if tfv & 4 and (tick + id) % SCAN_EVERY == 0:
						var ot = e.order.get("type", "idle")
						if ot == "idle" or ot == "attack_move" or ot == "hold":
							var sv = _stats.get(e.def)
							var s: Dictionary = sv if sv != null else stats(e)
							scan_src.append(si)
							scan_r.append(float(s.range) if ot == "hold" else _search_r(s))
							scan_need.append(0 if s.aa else 1)
							scan_ids.append(id)
			var fr := int(e.firing)
			if fr > 0:
				e.firing = fr - 1
			var cdv = e.get("cd_ticks")
			var cd: int = int(cdv) if cdv != null else _cd(e)
			if cd > 0:
				cd -= 1
				e.cd_ticks = cd
				e.cooldown = float(cd) / trf
			act.append(e)
			# SIM10K: act-phase skip code, computed from the values _unit_tick would read (see _act_skip)
			var tg := int(e.target)
			var code := 0
			if e.get("broken", false):
				code = 1 if tg < 0 else 0   # broken: _unit_tick only writes target = -1
			elif tg >= 0:
				if not e.moving and cd > 1 and ents.has(tg):
					code = 2                 # reloading at a live target: no-op unless the target is hit
			else:
				var mv: bool = e.moving
				var slot := (tick + id) % SCAN_EVERY == 0
				var ot = e.order.get("type", "idle")
				if not mv and not slot and (ot == "idle" or ot == "hold"):
					code = 1
				else:
					var sv2 = _stats.get(e.def)
					var s2: Dictionary = sv2 if sv2 != null else stats(e)
					if s2.weapon == "":
						code = 1
					elif ot != "attack" and ot != "idle" and ot != "hold" and ot != "attack_move":
						if tick - int(e.get("last_hit_tick", -100000)) > RETURN_FIRE_TICKS:
							code = 3         # move/other order, not hit recently: no-op unless hit this tick
					elif ot == "attack_move" and mv and not s2.builder and not slot and not e.order.get("engaged", false):
						code = 1
			askip.append(code if act_skip else 0)
			atg.append(tg)
		if native:
			nids.resize(nn)
			npos.resize(nn)
			nteam.resize(nn)
			nflags.resize(nn)
	var red := []    # REDUCED units on their stride tick
	if tiers_on:
		var dec := Tiers.SCAN_STRIDE
		for e: Dictionary in Tiers.due_reduced(w, Tiers.SCAN_STRIDE):
			if not ents.has(int(e.id)) or int(e.get("tier", 0)) != Tiers.REDUCED:
				continue
			var fr := int(e.firing)
			if fr > 0:
				e.firing = maxi(fr - dec, 0)
			var cdv = e.get("cd_ticks")
			var cd: int = int(cdv) if cdv != null else _cd(e)
			if cd > 0:
				cd = maxi(cd - dec, 0)
				e.cd_ticks = cd
				e.cooldown = float(cd) / trf
			red.append(e)
	for b in all_blds:
		if not ents.has(int(b.id)):
			continue
		blds.append(b)
		var cd := _cd(b)
		if cd > 0:
			cd -= 1
			b.cd_ticks = cd
			b.cooldown = float(cd) / SimWorld.TICK_RATE
	# G7 LPPERF7: only armed buildings act (_bld_act -> _tower_tick returns at once for a def without a weapon,
	# writing nothing); every alive building stays in blds (targets, splash, scan bounds, cooldown countdown above)
	var ablds := []
	for b in Inert7.blds(w, Inert7.ARMED):
		if ents.has(int(b.id)):
			ablds.append(b)
	if SimIndex.profiling:
		t0 = SimIndex.pt("cmb.prep", t0)
	w.cache["combat_grid"] = grid
	w.cache["combat_blds"] = blds
	if native:
		var ng = w.cache.get("combat_rgrid")
		if ng == null:
			ng = NativeCore.make_grid(w)
			ng.setup(int(w.map.w), int(w.map.h), 4.0)
			w.cache["combat_rgrid"] = ng
		var zr := PackedFloat32Array()
		zr.resize(nids.size())
		zr.fill(0.0)
		ng.rebuild(nids, npos, nteam, zr)
		ng.set_flags(nflags)
		var pre := {}
		if not scan_src.is_empty():
			if SimIndex.g6m(w) & SimIndex.G6_RANGE:
				_scan_rm(w, scan_ids, scan_r)
			var res: PackedInt32Array = ng.nearest_enemy_batch(scan_src, scan_r, scan_need)
			for i in scan_ids.size():
				pre[scan_ids[i]] = Vector2(float(res[i]), scan_r[i])
			if np_done:
				# SIM10K: a scan-slot shooter with no RtsGrid candidate (res -1) and no building of ANY
				# owner within its scan radius gets null from _find (the unit search is skipped on -1;
				# positions, fog and the building list are fixed for the tick; deaths only remove).
				var brs := PackedFloat32Array()
				brs.resize(blds.size() * 4)   # G7 LPPERF7: indexed writes (same values) instead of a temp array per building
				var bj := 0
				for b in blds:
					var o: Vector2i = b.cell
					var bsz := float(b.size)
					brs[bj] = float(o.x)
					brs[bj + 1] = float(o.y)
					brs[bj + 2] = float(o.x) + bsz
					brs[bj + 3] = float(o.y) + bsz
					bj += 4
				nores.resize(nidx.size())
				var nb := brs.size()
				if bscan_bucket and nb > BSCAN_BUCKET_MIN * 4:
					_nores_bucketed(scan_ids, scan_src, scan_r, res, npos, brs, nores)
					if bscan_debug:
						var chk := PackedByteArray()
						chk.resize(nidx.size())
						for i in scan_ids.size():
							if res[i] != -1:
								continue
							var sp: Vector2 = npos[scan_src[i]]
							var rr := float(scan_r[i]) + 0.01
							rr *= rr
							var near := false
							var j := 0
							while j < nb:
								var dx := sp.x - clampf(sp.x, brs[j], brs[j + 2])
								var dy := sp.y - clampf(sp.y, brs[j + 1], brs[j + 3])
								if dx * dx + dy * dy <= rr:
									near = true
									break
								j += 4
							if not near:
								chk[scan_ids[i]] = 1
						var bad := 0
						for q in chk.size():
							if chk[q] != nores[q]:
								bad += 1
						if bad > 0:
							print("BSCAN mismatch tick=%d bad=%d nores_sum=%d chk_sum=%d" % [w.tick, bad, Array(nores).count(1), Array(chk).count(1)])
				else:
					for i in scan_ids.size():
						if res[i] != -1:
							continue
						var sp: Vector2 = npos[scan_src[i]]
						var rr := float(scan_r[i]) + 0.01
						rr *= rr
						var near := false
						var j := 0
						while j < nb:
							var dx := sp.x - clampf(sp.x, brs[j], brs[j + 2])
							var dy := sp.y - clampf(sp.y, brs[j + 1], brs[j + 3])
							if dx * dx + dy * dy <= rr:
								near = true
								break
							j += 4
						if not near:
							nores[scan_ids[i]] = 1
		var lc = null
		if native_los:
			lc = w.cache.get("combat_lc")
			if lc == null:
				lc = NativeCore.new_combat(w)
				w.cache["combat_lc"] = lc if lc != null else false
			elif not lc is Object:
				lc = null   # older DLL without RtsCombat: GDScript line_clear
		w.cache["combat_ng"] = {"grid": ng, "idx": nidx, "pre": pre, "eb": {}, "lc": lc,
			"hl": lc != null and lc.has_method("height_los"),
			"mw": int(w.map.w), "mh": int(w.map.h), "teams": teams, "npos": npos, "nteam": nteam}
	else:
		w.cache.erase("combat_ng")
	if SimIndex.profiling:
		t0 = SimIndex.pt("cmb.ngrid", t0)
	# act in ascending id order, FULL units and buildings interleaved as in w.entities.
	# SIM10K: a unit whose prep skip code says _unit_tick is a no-op is not called. The only state an
	# earlier actor can change that those exits read is a hit (last_hit_tick) or the death of the
	# tracked target, both of which go through Damage.apply_hit, which records the hit entity id in
	# w.cache.cmb_ev: code 2 (reloading at target) wakes when its target is in it, code 3 (move/other
	# order, return fire only) wakes when it is itself in it; code 1 exits read nothing others write.
	var ev := {}
	w.cache["cmb_ev"] = ev
	var bkr = w.sys_state.get("combat_bk")
	if bkr != null:
		_bk_wake(w, bkr, ev)   # G7: fire-on-the-move units are never act-skipped (code 3 wakes on ev)
	var use_nr := not nores.is_empty()
	var bi := 0
	var by_ix := not act_id.is_empty()
	for i in (act_id.size() if by_ix else act.size()):
		var eid: int = act_id[i] if by_ix else int(act[i].id)
		while bi < ablds.size() and int(ablds[bi].id) < eid:
			_bld_act(w, ablds[bi], grid, blds)
			bi += 1
		if not ents.has(eid):
			continue  # destroyed earlier this tick: dead entities never act
		var sk := askip[i]
		if sk != 0:
			if sk == 1 or ev.is_empty():
				continue
			if sk == 2 and not ev.has(atg[i]):
				continue
			if sk == 3 and not ev.has(eid):
				continue
		var e: Dictionary = units[act_ix[i]] if by_ix else act[i]
		if by_ix and int(e.id) != eid:
			e = ents[eid]   # the list was re-sorted mid-act (an append + Tiers.lists): same dict by id
		if sk == 0 and use_nr and nores[eid] == 1 and atg[i] < 0:
			# SIM10K: untargeted scan-slot shooter whose search is null by construction (see above):
			# _unit_tick is then a no-op for idle / hold, and for an attack-move that is moving and
			# not engaged (it only rewrites target = -1). Anything else still calls.
			var ot2 = e.order.get("type", "idle")
			if ot2 == "idle" or ot2 == "hold":
				continue
			if ot2 == "attack_move" and e.moving and not e.order.get("engaged", false):
				continue
		if prof_units and SimIndex.profiling:
			var lab := "u." + String(e.order.get("type", "idle")) + (".t" if int(e.target) >= 0 else "") + (".mv" if e.moving else "")
			var tu := Time.get_ticks_usec()
			_unit_tick(w, e, grid, blds)
			SimIndex.pt(lab, tu)
		else:
			_unit_tick(w, e, grid, blds)
	while bi < ablds.size():
		_bld_act(w, ablds[bi], grid, blds)
		bi += 1
	if SimIndex.profiling:
		t0 = SimIndex.pt("cmb.act", t0)
	_no_search = true
	for e in red:
		var rid: int = e.id
		if not ents.has(rid):
			continue
		# PERF4-4: with searches returning null, an armed non-builder that tracks nothing is a no-op
		# in _unit_tick unless it has an attack order, an attack-move that is stopped or engaged, or a
		# move/other order with a recent hit (return fire): skip the call for the rest.
		if native and int(e.target) == -1:
			var tfv := tf[rid]
			if tfv == 0:
				tfv = _tf_of(e, teams)
				tf[rid] = tfv
			if tfv > 0 and tfv & 4:
				var ot1 = e.order.get("type", "idle")
				if ot1 == "idle" or ot1 == "hold":
					continue
				if ot1 == "attack_move":
					if e.moving and not e.order.get("engaged", false):
						continue
				elif ot1 != "attack" and tick - int(e.get("last_hit_tick", -100000)) > RETURN_FIRE_TICKS:
					continue
		_unit_tick(w, e, grid, blds)
	_no_search = false
	w.cache.erase("cmb_ev")
	if SimIndex.profiling:
		SimIndex.pt("cmb.reduced", t0)


## cmb_tabs entry for unit e: -1 = owner has no faction team, else
## ((team + 1) << 3) | 4 if armed and not a builder | 2 air / 1 ground.
static func _tf_of(e: Dictionary, teams: Dictionary) -> int:
	var tv = teams.get(int(e.owner))
	if tv == null:
		return -1
	var s0 := stats(e)
	return ((int(tv) + 1) << 3) | (4 if s0.weapon != "" and not s0.builder else 0) | (2 if s0.is_air else 1)


## SIM10K: this world's RtsCombat (cached in w.cache.combat_lc; false = DLL without it) or null.
static func _combat_obj(w: SimWorld):
	var lc = w.cache.get("combat_lc")
	if lc == null:
		lc = NativeCore.new_combat(w)
		w.cache["combat_lc"] = lc if lc != null else false
	return lc if lc is Object else null


## CORE10K-2: ids parallel to a Tiers list (runtime cache in the tier index, never saved), rebuilt
## when the list is a new Array or changed size (the same rule as Supply._full_buckets: Tiers only
## appends to a list, and re-sorts it only after an append).
static func _list_ids(idx: Dictionary, units: Array) -> PackedInt32Array:
	var c = idx.get("cmb_ids")
	if c != null and is_same(c.src, units) and int(c.n) == units.size():
		return c.ids
	var ids := PackedInt32Array()
	ids.resize(units.size())
	for i in units.size():
		ids[i] = int(units[i].id)
	idx["cmb_ids"] = {"src": units, "n": units.size(), "ids": ids}
	return ids


## SIM10K: def-table index of e for RtsCombat.prep_units (cmb_tabs: dmap def -> index; dr range,
## ds search radius, df flags 1 anti_air | 2 armed | 4 builder).
static func _dx_of(e: Dictionary, tabs: Dictionary) -> int:
	var dm: Dictionary = tabs.dmap
	var di = dm.get(e.def)
	if di != null:
		return int(di)
	var s := stats(e)
	var n: int = dm.size()
	dm[e.def] = n
	var dr: PackedFloat32Array = tabs.dr
	var ds: PackedFloat32Array = tabs.ds
	var df: PackedInt32Array = tabs.df
	dr.append(float(s.range))
	ds.append(_search_r(s))
	df.append((1 if s.aa else 0) | (2 if s.weapon != "" else 0) | (4 if s.builder else 0))
	tabs.dr = dr
	tabs.ds = ds
	tabs.df = df
	return n


static var _dmg_ng := -1


static func _dmg_uses_ng() -> bool:
	if _dmg_ng < 0:
		_dmg_ng = 1 if (Damage as Script).get_script_constant_map().has("NEAR_MISS_NG") else 0
	return _dmg_ng == 1


## Line of fire a -> b: RtsCombat.line_clear when this tick's native state holds one, else
## Damage.line_clear (same answer bit for bit: N1-core's exact port, see native/rts_core/src/combat.rs).
static func _los(w: SimWorld, a: Vector2, b: Vector2) -> bool:
	var ng = w.cache.get("combat_ng")
	var lc = ng.lc if ng != null else null
	if SimIndex.profiling:
		var t0 := Time.get_ticks_usec()
		var r: bool = lc.line_clear(ng.mw, ng.mh, w.map.terrain, Damage.RIDGE, a, b) if lc != null else Damage.line_clear(w, a, b)
		SimIndex.pt("cmb.los", t0)
		return r
	if lc != null:
		return lc.line_clear(ng.mw, ng.mh, w.map.terrain, Damage.RIDGE, a, b)
	return Damage.line_clear(w, a, b)


static func _bld_act(w: SimWorld, b: Dictionary, grid: Dictionary, blds: Array) -> void:
	if w.entities.has(int(b.id)) and b.get("built", false):
		_tower_tick(w, b, grid, blds)


## Fog.entity_visible plus the G4b sniper conceal_still rule (G4bMech.hidden_from).
static func _seen(w: SimWorld, fid: int, t: Dictionary) -> bool:
	return Fog.entity_visible(w, fid, t) and not (t.has("hid") and G4bMech.hidden_from(w, fid, t))


## G6: true when G6Hooks.visible_to hides candidate c from fid (search filters next to Fog.concealed).
static func _g6_hidden(w: SimWorld, fid: int, c: Dictionary) -> bool:
	return SimIndex.g6m(w) & SimIndex.G6_VIS != 0 and not SimIndex.g6h().visible_to(w, fid, c)


## G6: weapon range factor of shooter e (G6Hooks.range_mult; 1.0 while the hook is off).
static func _rm(w: SimWorld, e: Dictionary, s: Dictionary) -> float:
	if SimIndex.g6m(w) & SimIndex.G6_RANGE == 0:
		return 1.0
	return SimIndex.g6h().range_mult(w, e, s)


## G6: auto-acquisition radius with the range factor (sight, or max(sight, range x rm) for indirect).
static func _search_rm(w: SimWorld, e: Dictionary, s: Dictionary) -> float:
	if not bool(s.indirect):
		return float(s.sight)
	return maxf(float(s.sight), float(s.range) * _rm(w, e, s))


## G6: rescales this tick's scan radii (hold: range x rm, indirect: max(sight, range x rm)), the
## values _unit_tick passes to _pick, so the native nearest-enemy pre-batch searches the same circle.
## G7 PERF7F: the SIM10K "no building within the scan radius" pre-scan above, with the building rects (the same
## float32 brs values) bucketed by BSCAN_BK tiles, so a shooter tests only the buildings around it instead of every
## building (a counter-nanite facility adds ~115). Same distance test; "any building near" does not depend on the
## order the buildings are tested in, so the result (nores) is identical. Used above BSCAN_BUCKET_MIN buildings.
const BSCAN_BK := 8.0
const BSCAN_BUCKET_MIN := 16
static var bscan_bucket := true
static var bscan_debug := false   # bench / tests: false = the plain loop over every building (A/B proof)


static func _nores_bucketed(scan_ids: PackedInt32Array, scan_src: PackedInt32Array, scan_r: PackedFloat32Array, res: PackedInt32Array, npos: PackedVector2Array, brs: PackedFloat32Array, nores: PackedByteArray) -> void:
	var nb := brs.size()
	var bk := {}
	var j := 0
	while j < nb:
		for by in range(floori(brs[j + 1] / BSCAN_BK), floori(brs[j + 3] / BSCAN_BK) + 1):
			for bx in range(floori(brs[j] / BSCAN_BK), floori(brs[j + 2] / BSCAN_BK) + 1):
				var key := (bx + 8) + (by + 8) * 8192
				var arr = bk.get(key)
				if arr == null:
					bk[key] = [j]
				else:
					arr.append(j)
		j += 4
	for i in scan_ids.size():
		if res[i] != -1:
			continue
		var sp: Vector2 = npos[scan_src[i]]
		var r0 := float(scan_r[i]) + 0.01
		var rr := r0 * r0
		var near := false
		# every building within r0 of sp overlaps the square sp +- r0; one extra bucket each side covers rounding
		for by in range(floori((sp.y - r0) / BSCAN_BK) - 1, floori((sp.y + r0) / BSCAN_BK) + 2):
			for bx in range(floori((sp.x - r0) / BSCAN_BK) - 1, floori((sp.x + r0) / BSCAN_BK) + 2):
				var arr = bk.get((bx + 8) + (by + 8) * 8192)
				if arr == null:
					continue
				for q: int in arr:
					var dx := sp.x - clampf(sp.x, brs[q], brs[q + 2])
					var dy := sp.y - clampf(sp.y, brs[q + 1], brs[q + 3])
					if dx * dx + dy * dy <= rr:
						near = true
						break
				if near:
					break
			if near:
				break
		if not near:
			nores[scan_ids[i]] = 1


static func _scan_rm(w: SimWorld, ids: PackedInt32Array, rr: PackedFloat32Array) -> void:
	var ents: Dictionary = w.entities
	for k in ids.size():
		var e = ents.get(ids[k])
		if e == null:
			continue
		var sv = _stats.get(e.def)
		var s: Dictionary = sv if sv != null else stats(e)
		if e.order.get("type", "idle") == "hold":
			rr[k] = float(s.range) * _rm(w, e, s)
		elif bool(s.indirect):
			rr[k] = _search_rm(w, e, s)


## G6: height line of sight (G6Hooks.los_ok -> Elevation.los) for direct fire e -> t, on top of the
## terrain line of fire. Air shooters and airborne targets ignore it (CONTRACTS_G6 section 7.2).
static func _hlos(w: SimWorld, e: Dictionary, t: Dictionary) -> bool:
	if SimIndex.g6m(w) & SimIndex.G6_LOS == 0:
		return true
	if e.kind == "unit" and bool(stats(e).is_air):
		return true
	if t.kind == "unit" and bool(stats(t).is_air) and not _landed(t):
		return true
	if native_elev and SimIndex.g6_spy == null:
		var ng = w.cache.get("combat_ng")
		if ng != null and bool(ng.get("hl", false)):
			var m: Dictionary = w.map
			if not m.has("height"):
				return true
			return ng.lc.height_los(ng.mw, ng.mh, m.height, Elevation.MAX_LEVEL, e.pos, t.pos)
	return SimIndex.g6h().los_ok(w, e.pos, t.pos)


## G4b UNITS: target-side damage factor for a direct hit / splash victim: scrap-mech front armor
## (front_armor_mult divides front hits), foot infantry cover on HILL (Terrain.cover_mult, NAT) and the
## weapon's cover_mult vs infantry in cover. ignore_cover weapons (flamer) skip both cover terms.
static func _g4_mult(w: SimWorld, e: Dictionary, s: Dictionary, t: Dictionary) -> float:
	if t.kind != "unit":
		return 1.0
	var ts := stats(t)
	var m := 1.0
	if float(ts.front_mult) != 1.0 and Damage.hit_side(e.pos, t) == "front":
		m /= float(ts.front_mult)
	if t.has("morale") and not bool(s.get("ignore_cover", false)):
		var p: Vector2 = t.pos
		m *= Terrain.cover_mult(w.terrain_at(Vector2i(floori(p.x), floori(p.y))), "foot")
		if float(s.get("cover_mult", 1.0)) != 1.0 and Damage.in_cover(w, t):
			m *= float(s.cover_mult)
	return m


## True if a shooter with stats s may engage t at all (air targets need an anti_air weapon).
static func can_target(s: Dictionary, t: Dictionary) -> bool:
	return (bool(s.aa) or t.kind != "unit" or not bool(stats(t).is_air) or _landed(t)) and _g5_ok(s, t)


## G5 (AIRSYS CR 2831): a landed / parked aircraft (e.air_landed) is a ground target: no anti_air needed.
static func _landed(t: Dictionary) -> bool:
	return t.has("air_landed") and bool(t.air_landed)


## G5 (CORE10K): the AIRSYS air rule for air targets + no direct fire at Wounded units. Call only
## after the G3a anti_air filter passed. True for every G4 target (no is_air rule change, no wounded).
static func _g5_ok(s: Dictionary, t: Dictionary) -> bool:
	# G6 (NAVAL6 CR naval6_torpedo_submerged, CONTRACTS_G6 section 11): naval_only weapons (torpedoes) hit
	# naval ships only (same rule as Sonar.naval_target_ok). Only g6_torpedo carries the flag.
	if s.get("naval_only", false) and not (t.kind == "unit" and bool(Content.unit(String(t.def)).get("naval_ship", false))):
		return false
	if t.kind != "unit":
		return true
	if t.has("wounded") and bool(t.wounded):
		return false
	if bool(stats(t).is_air):
		return SimWorld.Air.can_target(s, t)
	return true


## Search radius for auto-acquisition: sight, or the full range for indirect fire.
static func _search_r(s: Dictionary) -> float:
	return maxf(float(s.sight), float(s.range)) if bool(s.indirect) else float(s.sight)


static func _valid_target(w: SimWorld, fid: int, tid: int, s = null):
	if tid < 0:
		return null
	var t = w.entities.get(tid)
	if t != null and t.kind == "structure":
		return t if String(t.get("state", "")) != "ruined" and Fog.is_visible(w, fid, t.pos) else null  # explicit attack on the bridge only (C2: a ruin is never a target)
	if t == null or (t.kind != "unit" and t.kind != "building") or not w.is_enemy(fid, int(t.owner)):
		return null
	if not _seen(w, fid, t):
		return null
	if s != null and not can_target(s, t):
		return null
	return t


## Nearest visible enemy within radius of e (ties -> lower id). Returns the entity dict or null.
## Searches enemy-owner buckets in rings around e and stops once no closer bucket can exist.
static func find_target(w: SimWorld, e: Dictionary, radius: float, grid: Dictionary, blds: Array):
	var fid := int(e.owner)
	var p: Vector2 = e.pos
	var r2 := radius * radius
	var best = null
	var best_d := INF
	var best_id := 0
	var s := stats(e)
	var aa: bool = s.aa
	var mr: float = s.min_range
	var mr2 := mr * mr
	var vis := PackedByteArray()
	if w.fog.has(fid):
		vis = w.fog[fid].visible
	var mw := int(w.map.w)
	var nvis := vis.size()
	var enemy_grids := []
	for o in grid:
		if w.is_enemy(fid, int(o)):
			enemy_grids.append(grid[o])
	if not enemy_grids.is_empty():
		var bx := int(floor(p.x / BUCKET))
		var by := int(floor(p.y / BUCKET))
		var kmax := int(ceil(radius / BUCKET)) + 1
		for k in range(0, kmax + 1):
			if k >= 2:
				var lim := float(k - 1) * BUCKET
				if lim * lim > best_d or lim * lim > r2:
					break
			for yy in range(by - k, by + k + 1):
				var edge_row := yy == by - k or yy == by + k
				var step := 1 if edge_row else 2 * k
				var xx := bx - k
				while xx <= bx + k:
					var key := xx + yy * GRID_STRIDE
					for g in enemy_grids:
						var arr = g.get(key)
						if arr == null:
							continue
						for c in arr:
							var cp: Vector2 = c.pos
							var d2 := p.distance_squared_to(cp)
							if d2 > r2:
								continue
							var cid := int(c.id)
							if d2 > best_d or (d2 == best_d and cid > best_id):
								continue
							var vi := floori(cp.y) * mw + floori(cp.x)
							if vi < 0 or vi >= nvis or vis[vi] != 1 or not w.entities.has(cid):
								continue
							if Fog.concealed(w, fid, c) or (c.has("hid") and G4bMech.hidden_from(w, fid, c)) or _g6_hidden(w, fid, c):
								continue  # G2: infantry hidden in forest (A2)
							if (not aa and bool(stats(c).is_air) and not _landed(c)) or d2 < mr2 or not _g5_ok(s, c):
								continue  # G3a: air needs anti_air; artillery min_range; G5 air rule / wounded
							best = c
							best_d = d2
							best_id = cid
					if k == 0:
						break
					xx += step
	for b in blds:
		if not w.is_enemy(fid, int(b.owner)):
			continue
		var d := dist_to(p, b)
		var d2 := d * d
		if d2 > r2 or d2 < mr2:
			continue
		var bid := int(b.id)
		if d2 > best_d or (d2 == best_d and bid > best_id):
			continue
		if not w.entities.has(bid) or not Fog.entity_visible(w, fid, b):
			continue
		best = b
		best_d = d2
		best_id = bid
	return best


## Target search dispatch: native-backed when this tick's RtsGrid holds e, else find_target().
static var _scan_vis := -1   # G7 INTEG7: 1 = RtsGrid.scan_vis available (rts_core >= 0.5.3)


static func _find(w: SimWorld, e: Dictionary, radius: float, grid: Dictionary, blds: Array):
	var tq0 := Time.get_ticks_usec() if SimIndex.profiling else 0
	var ng = w.cache.get("combat_ng")
	if ng == null:
		return find_target(w, e, radius, grid, blds)
	var nix: PackedInt32Array = ng.idx
	var eid := int(e.id)
	var si := nix[eid] if eid >= 0 and eid < nix.size() else -1   # -1: outside the grid (towers): exact scan below
	var sv = _stats.get(e.def)
	var s: Dictionary = sv if sv != null else stats(e)
	var aa: bool = s.aa
	var fid := int(e.owner)
	var p: Vector2 = e.pos
	var r2 := radius * radius
	var mr: float = s.min_range
	var mr2 := mr * mr
	var mw := int(w.map.w)
	var best = null
	var best_d := INF
	var best_id := 0
	var rg = ng.grid
	var cand := -1
	var pv = ng.pre.get(int(e.id))
	if si < 0:
		cand = -2          # not in the grid: no nearest query, go straight to the exact scan
	elif pv != null and is_equal_approx(float(pv.y), radius):
		cand = int(pv.x)   # this tick's batched answer (same grid, same query)
	else:
		var res: PackedInt32Array = rg.nearest_enemy_batch(PackedInt32Array([int(si)]), PackedFloat32Array([radius]), PackedInt32Array([0 if aa else 1]))
		cand = res[0]
	if cand >= 0 or cand == -2:
		var vis := PackedByteArray()   # fid's visible cells (only needed for unit candidates)
		if w.fog.has(fid):
			vis = w.fog[fid].visible
		var c = w.entities.get(cand) if cand >= 0 else null
		var d2 := INF
		if c != null:
			d2 = p.distance_squared_to(Vector2(c.pos))
		if c != null and _cand_ok(w, fid, c, d2, r2, mr2, aa, vis, mw, s):
			best = c
			best_d = d2
			best_id = cand
		else:
			# the nearest raw candidate is not a legal target: exact scan of everything in range.
			# PERF4-4: team, position and the visible-cell test read this tick's packed RtsGrid
			# inputs (positions are fixed during Combat.tick) before any Dictionary access; the
			# legal set and the (distance, id) argmin are unchanged.
			var tsc := Time.get_ticks_usec() if SimIndex.profiling else 0
			var myt = ng.teams.get(fid)
			if myt != null:
				var npos: PackedVector2Array = ng.npos
				var nteam: PackedInt32Array = ng.nteam
				var nsz := nix.size()
				var nvis := vis.size()
				var ents: Dictionary = w.entities
				var mt := int(myt)
				# G7 INTEG7 (perf): rts_core >= 0.5.3 pre-filters to visible items of another team (the tests below
				# repeat, so the legal set and the (distance, id) argmin are the same as with query_radius)
				if _scan_vis == -1:
					_scan_vis = 1 if rg.has_method("scan_vis") else 0
				for cid in (rg.scan_vis(p, radius, mt, vis, mw) if _scan_vis == 1 else rg.query_radius(p, radius)):
					var ci := nix[cid] if cid < nsz else -1
					if ci < 0 or nteam[ci] == mt:
						continue
					var cp: Vector2 = npos[ci]
					var dd := p.distance_squared_to(cp)
					if dd > best_d or (dd == best_d and cid > best_id) or dd > r2 or dd < mr2:
						continue
					var vi := floori(cp.y) * mw + floori(cp.x)
					if vi < 0 or vi >= nvis or vis[vi] != 1:
						continue
					var c3 = ents.get(cid)
					if c3 == null or Fog.concealed(w, fid, c3) or (c3.has("hid") and G4bMech.hidden_from(w, fid, c3)) or _g6_hidden(w, fid, c3) or (not aa and bool(stats(c3).is_air) and not _landed(c3)) or not _g5_ok(s, c3):
						continue
					best = c3
					best_d = dd
					best_id = cid
				cand = -3   # scanned
			if SimIndex.profiling:
				SimIndex.pt("f.scan", tsc)
			for cid in (rg.query_radius(p, radius) if cand != -3 else PackedInt32Array()):
				var c2 = w.entities.get(cid)
				if c2 == null or not w.is_enemy(fid, int(c2.owner)):
					continue
				var dd := p.distance_squared_to(Vector2(c2.pos))
				if dd > best_d or (dd == best_d and cid > best_id):
					continue
				if _cand_ok(w, fid, c2, dd, r2, mr2, aa, vis, mw, s):
					best = c2
					best_d = dd
					best_id = cid
	var tq := 0
	if SimIndex.profiling:
		tq = SimIndex.pt("f.units", tq0)
	# enemy buildings of fid, filtered once per tick (PERF4-2): [b, x0, y0, x1, y1]
	# G7 LPPERF7: bucketed by EB_CS-tile cells (an entry sits in every cell its rect touches); a query walks only
	# the cells of its radius box (+1 tile margin), which hold every building with d <= radius. The pick is the
	# (distance, id) minimum over the same legal set, independent of visit order (a repeat visit changes nothing).
	var ebs: Dictionary = ng.eb
	var eb = ebs.get(fid)
	if eb == null:
		eb = _eb_grid(w, fid, blds, int(ng.mw), int(ng.mh))
		ebs[fid] = eb
	var ebc: Array = eb.c
	var egw: int = eb.gw
	var egh: int = eb.gh
	var cx0 := clampi(floori((p.x - radius - 1.0) / EB_CS), 0, egw - 1)
	var cx1 := clampi(floori((p.x + radius + 1.0) / EB_CS), 0, egw - 1)
	var cy0 := clampi(floori((p.y - radius - 1.0) / EB_CS), 0, egh - 1)
	var cy1 := clampi(floori((p.y + radius + 1.0) / EB_CS), 0, egh - 1)
	if not is_finite(radius) or radius > 65536.0 or not Inert7.enabled:   # Inert7 off (tests): every cell
		cx0 = 0
		cy0 = 0
		cx1 = egw - 1
		cy1 = egh - 1
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			var cell = ebc[cy * egw + cx]
			if cell == null:
				continue
			for q in cell:
				var b: Dictionary = q[0]
				var qx := clampf(p.x, q[1], q[3])
				var qy := clampf(p.y, q[2], q[4])
				var d := p.distance_to(Vector2(qx, qy))
				var d2b := d * d
				if d2b > r2 or d2b < mr2:
					continue
				var bid := int(b.id)
				if d2b > best_d or (d2b == best_d and bid > best_id):
					continue
				if not w.entities.has(bid) or not Fog.entity_visible(w, fid, b):
					continue
				best = b
				best_d = d2b
				best_id = bid
	if SimIndex.profiling:
		SimIndex.pt("f.eb%d" % int(eb.n), tq)
	return best


const EB_CS := 16.0   # G7 LPPERF7: enemy-building bucket size (tiles)


## G7 LPPERF7: fid's enemy buildings of this tick's blds as [b, x0, y0, x1, y1] entries in a bucket grid
## ({c: Array of cells (null or [entries] in blds order), gw, gh, n}); an entry is in every cell its rect touches.
static func _eb_grid(w: SimWorld, fid: int, blds: Array, mw: int, mh: int) -> Dictionary:
	var gw := maxi(1, ceili(float(mw) / EB_CS) + 1)
	var gh := maxi(1, ceili(float(mh) / EB_CS) + 1)
	var c := []
	c.resize(gw * gh)
	var n := 0
	for b in blds:
		if w.is_enemy(fid, int(b.owner)):
			var o: Vector2i = b.cell
			var sz := float(b.size)
			var q := [b, float(o.x), float(o.y), float(o.x) + sz, float(o.y) + sz]
			n += 1
			var bx0 := clampi(floori(float(o.x) / EB_CS), 0, gw - 1)
			var bx1 := clampi(floori((float(o.x) + sz) / EB_CS), 0, gw - 1)
			var by0 := clampi(floori(float(o.y) / EB_CS), 0, gh - 1)
			var by1 := clampi(floori((float(o.y) + sz) / EB_CS), 0, gh - 1)
			for by in range(by0, by1 + 1):
				for bx in range(bx0, bx1 + 1):
					var k := by * gw + bx
					if c[k] == null:
						c[k] = [q]
					else:
						c[k].append(q)
	return {"c": c, "gw": gw, "gh": gh, "n": n}


## The per-candidate filters of find_target (range, visible cell, alive, concealment, air, min_range).
static func _cand_ok(w: SimWorld, fid: int, c: Dictionary, d2: float, r2: float, mr2: float, aa: bool, vis: PackedByteArray, mw: int, s: Dictionary = {}) -> bool:
	if d2 > r2 or d2 < mr2:
		return false
	var cp: Vector2 = c.pos
	var vi := floori(cp.y) * mw + floori(cp.x)
	if vi < 0 or vi >= vis.size() or vis[vi] != 1 or not w.entities.has(int(c.id)):
		return false
	if Fog.concealed(w, fid, c) or (c.has("hid") and G4bMech.hidden_from(w, fid, c)) or _g6_hidden(w, fid, c):
		return false
	return (aa or not bool(stats(c).is_air) or _landed(c)) and _g5_ok(s, c)


static func _scan_due(w: SimWorld, e: Dictionary, period: int) -> bool:
	return (w.tick + int(e.id)) % period == 0


## Keeps the current target if still valid within radius. Rescans on this shooter's stagger slot
## (every SCAN_EVERY ticks; every SCAN_EVERY_ENGAGED while the target is already in weapon range),
## or immediately when the tracked target just became invalid.
static func _pick(w: SimWorld, e: Dictionary, radius: float, grid: Dictionary, blds: Array):
	if _no_search:
		return null  # REDUCED unit: no enemy can be within radius (Tiers contact bound)
	var s := stats(e)
	var cur = _valid_target(w, int(e.owner), int(e.target), s)
	if cur != null:
		var d := dist_to(e.pos, cur)
		if d > radius or d < float(s.min_range):
			cur = null
		elif d <= float(stats(e).range) * _rm(w, e, s):
			if not _scan_due(w, e, SCAN_EVERY_ENGAGED):
				return cur
		elif not _scan_due(w, e, SCAN_EVERY):
			return cur
	elif int(e.target) < 0 and not _scan_due(w, e, SCAN_EVERY):
		return null  # nothing tracked: wait for this shooter's scan slot
	if SimIndex.profiling:
		var t0 := Time.get_ticks_usec()
		var r = _find(w, e, radius, grid, blds)
		SimIndex.pt("cmb.find", t0)
		return r
	return _find(w, e, radius, grid, blds)


static func _unit_tick(w: SimWorld, e: Dictionary, grid: Dictionary, blds: Array) -> void:
	if e.get("broken", false):
		e.target = -1  # G2 (A2): broken units never acquire, chase or fire (morale.gd rallies them)
		return
	var tgt := int(e.target)
	# fast paths (perf): a stationary shooter that is reloading at a live target has nothing to
	# decide until its reload is nearly done; an untargeted idle/hold unit waits for its scan slot.
	if tgt >= 0:
		if not e.moving and int(e.get("cd_ticks", 0)) > 1 and w.entities.has(tgt):
			return
	elif not e.moving and (w.tick + int(e.id)) % SCAN_EVERY != 0:
		var ot0 = e.order.type
		if ot0 == "idle" or ot0 == "hold":
			return
	var sv = _stats.get(e.def)
	var s: Dictionary = sv if sv != null else stats(e)
	if s.weapon == "":
		return
	var ot := String(e.order.get("type", "idle"))
	# PERF4-2 fast paths (exact: they skip only calls that cannot change anything)
	if tgt < 0 and ot != "attack" and ot != "idle" and ot != "hold" and ot != "attack_move" 			and w.tick - int(e.get("last_hit_tick", -100000)) > RETURN_FIRE_TICKS and not bool(e.order.get("bk", false)):
		return  # move/other orders only return fire, and nothing hit it recently (G7: bk moves fire on the move)
	if tgt < 0 and ot == "attack_move" and e.moving and not s.builder and (w.tick + int(e.id)) % SCAN_EVERY != 0 			and not e.order.get("engaged", false):
		return  # marching, nothing tracked, not its scan slot: _pick would return null and change nothing
	if ot == "attack":
		_attack_order(w, e, s)
		return
	if s.builder:
		_return_fire(w, e, s)
		if ot == "attack_move" and not e.moving:
			e.order = {"type": "idle"}
		return
	match ot:
		"idle":
			if (w.sys_state.has("wallwalk7") and WallWalk7.on_wall(w, e)) or CnRole7.parked(w, e):   # + CNROLE7 CR 6046: CN teams at home hold   # G7 WALL7-3 CR 5500 (owner 13.9c-23): an idle soldier on the wall-walk holds the wall: fires at what is in range, never chases off it
				var th = _pick(w, e, float(s.range) * _rm(w, e, s), grid, blds)
				if th == null:
					e.target = -1
					return
				e.target = int(th.id)
				_fire(w, e, s, th)
				return
			var t = _pick(w, e, _search_rm(w, e, s), grid, blds)
			if t == null:
				if int(e.target) >= 0:
					e.target = -1
					if e.moving:
						Movement.stop_path(e)  # was chasing, lost it
				return
			_engage(w, e, s, t, true)
		"hold":
			var t = _pick(w, e, float(s.range) * _rm(w, e, s), grid, blds)
			if t == null:
				e.target = -1
				return
			e.target = int(t.id)
			_fire(w, e, s, t)
		"attack_move":
			var t = _pick(w, e, _search_rm(w, e, s), grid, blds)
			if t != null:
				e.order.engaged = true
				_engage(w, e, s, t, true)
				return
			e.target = -1
			if e.order.get("engaged", false):
				e.order.engaged = false
				if not Movement.order_path(w, e, e.order.target):
					e.order = {"type": "idle"}
			elif not e.moving:
				e.order = {"type": "idle"}  # arrived
		_:
			if bool(e.order.get("bk", false)):
				_fire_on_move(w, e, s, grid, blds)
			else:
				_return_fire(w, e, s)


## G7: registry of units on a move order with order.bk (SquadAI ordered fall-back), w.sys_state.combat_bk {id: 1}
## (saved + hashed; absent until the first bk order). Morale's realism pass registers them (staggered, within one
## fatigue update period); an order writer may call note_bk at once. Combat.tick puts the live ones into the
## act-skip wake set each tick and drops ids whose order lost bk or that died.
static func note_bk(w: SimWorld, id: int) -> void:
	var r = w.sys_state.get("combat_bk")
	if r == null:
		r = {}
		w.sys_state["combat_bk"] = r
	r[id] = 1


static func _bk_wake(w: SimWorld, r: Dictionary, ev: Dictionary) -> void:
	for id in r.keys():
		var e = w.entities.get(id)
		if e == null or not bool(e.order.get("bk", false)):
			r.erase(id)
		else:
			ev[id] = true
	if r.is_empty():
		w.sys_state.erase("combat_bk")


## G7 (SQUAD7 ask, WOUND7): a move order with order.bk (ordered fall-back: walk backwards facing the enemy) keeps
## firing at the nearest valid target in range without stopping or replacing the path (never chases). Keeps a live
## tracked target; re-picks only on its scan slot, so the cost is the same cadence as an idle unit's scan.
static func _fire_on_move(w: SimWorld, e: Dictionary, s: Dictionary, grid: Dictionary, blds: Array) -> void:
	var rng_t := float(s.range) * _rm(w, e, s)
	var t = null
	var tgt := int(e.target)
	if tgt >= 0:
		t = _valid_target(w, int(e.owner), tgt, s)
		if t != null and dist_to(e.pos, t) > rng_t:
			t = null
	if t == null:
		if (w.tick + int(e.id)) % SCAN_EVERY != 0:
			if tgt >= 0:
				e.target = -1
			return
		t = _pick(w, e, rng_t, grid, blds)
	if t == null:
		e.target = -1
		return
	e.target = int(t.id)
	_fire(w, e, s, t)


static func _return_fire(w: SimWorld, e: Dictionary, s: Dictionary) -> void:
	var att := int(e.get("last_attacker", -1))
	if att < 0 or w.tick - int(e.get("last_hit_tick", -100000)) > RETURN_FIRE_TICKS:
		return
	var t = _valid_target(w, int(e.owner), att, s)
	if t == null or dist_to(e.pos, t) > float(s.range) * _rm(w, e, s):
		return
	_fire(w, e, s, t)


static func _attack_order(w: SimWorld, e: Dictionary, s: Dictionary) -> void:
	var tid := int(e.order.get("target_id", -1))
	var t = w.entities.get(tid)
	if t == null:
		e.order = {"type": "idle"}
		e.target = -1
		Movement.stop_path(e)
		return
	if not can_target(s, t):
		e.order = {"type": "idle"}  # G3a: e.g. an AT team ordered onto a drone
		e.target = -1
		Movement.stop_path(e)
		return
	if _seen(w, int(e.owner), t):
		e.order.last_pos = t.pos
		e.order.lost = false
		_engage(w, e, s, t, true)
		return
	e.target = -1
	if not e.order.get("lost", false):
		e.order.lost = true
		var lp: Vector2 = e.order.get("last_pos", e.pos)
		if not Movement.order_path(w, e, lp):
			e.order = {"type": "idle"}
	elif not e.moving:
		e.order = {"type": "idle"}


static func _engage(w: SimWorld, e: Dictionary, s: Dictionary, t: Dictionary, can_chase: bool) -> void:
	e.target = int(t.id)
	var d := dist_to(e.pos, t)
	var mr: float = s.min_range
	# G2 (A2): in range but the line of fire crosses a ridge -> keep closing (chase) instead.
	# G3a: indirect fire ignores the ridge check but needs d >= min_range.
	if d <= float(s.range) * _rm(w, e, s) and d >= mr and (bool(s.indirect) or (_los(w, e.pos, t.pos) and not Fortify.fire_blocked(w, e, t) and _hlos(w, e, t))):
		if e.moving:
			Movement.stop_path(e)
		_fire(w, e, s, t, true)  # line of fire just checked (positions unchanged since)
	elif can_chase:
		var tp: Vector2 = t.pos
		if d < mr:
			# too close for indirect fire: back away along target -> shooter
			var away: Vector2 = Vector2(e.pos) - tp
			if away.length() < 0.01:
				away = Vector2(1, 0)
			tp = tp + away.normalized() * (mr + 1.0)
		var last_goal: Vector2 = e.get("chase_goal", Vector2(-1000, -1000))
		var need: bool = not e.moving or (w.tick - int(e.get("chase_tick", -100000)) >= CHASE_REPATH_TICKS and tp.distance_to(last_goal) > 1.0)
		if need:
			e.chase_tick = w.tick
			e.chase_goal = tp
			var tcp := Time.get_ticks_usec() if SimIndex.profiling else 0
			Movement.order_path(w, e, tp)
			if SimIndex.profiling:
				SimIndex.pt("eng.chase_path", tcp)


static func _tower_tick(w: SimWorld, b: Dictionary, grid: Dictionary, blds: Array) -> void:
	var s := stats(b)
	if s.weapon == "":
		return
	var t = _pick(w, b, float(s.range) * _rm(w, b, s), grid, blds)
	if t == null:
		b.target = -1
		return
	b.target = int(t.id)
	_fire(w, b, s, t)


## G6 AIRDEF6 (CR 492): G6Hooks.shot_blocked under the SHOT bit (set only while a CIWS / jammer exists). A
## test spy without shot_blocked never blocks.
static func _g6_shot_blocked(w: SimWorld, e: Dictionary, s: Dictionary, t: Dictionary, to: Vector2) -> bool:
	var h = SimIndex.g6h()
	if SimIndex.g6_spy != null and not SimIndex.g6_spy.has_method("shot_blocked"):
		return false
	return bool(h.shot_blocked(w, e, s, t, to))


static func _fire(w: SimWorld, e: Dictionary, s: Dictionary, t: Dictionary, los_ok := false) -> void:
	if _cd(e) > 0:
		return
	if Status.can_fire(w, e) != "":
		return
	if int(s.get("setup", 0)) > 0 and (not bool(e.get("deployed", false)) or bool(e.get("moving", false))):
		return  # G4b UNITS: mortar fires only deployed (G4bMech set-up)
	if not Traverse7.lay(w, e, t.pos, float(s.cooldown), bool(s.indirect), int(t.id)):   # + TURRET7B CR 6480: no free swing onto a new target
		return   # G7 TURRET7B CR 6354 (13.9c-30): the turret / mount traverses onto the target first (holds fire until laid)
	var indirect: bool = s.indirect
	if not indirect and not los_ok and (not _los(w, e.pos, t.pos) or Fortify.fire_blocked(w, e, t) or not _hlos(w, e, t)):
		return
	if float(s.min_range) > 0.0 and dist_to(e.pos, t) < float(s.min_range):
		return
	var tfr := Time.get_ticks_usec() if SimIndex.profiling else 0   # SIM10K sub-timer: fire resolution
	# --- G3b STG4 EW hook: jammed shooters deal Status.damage_mult x damage (s is a shared cache: copy)
	var dm := Status.damage_mult(w, e)
	if dm != 1.0:
		s = s.duplicate()
		s.damage = float(s.damage) * dm
	# --- end G3b STG4 hook
	if not indirect:
		var gm := _g4_mult(w, e, s, t)
		if SimIndex.g6m(w) & SimIndex.G6_DMG:
			gm *= SimIndex.g6h().damage_mult(w, e, s, t)  # G6 (x 1.0 when neutral: bit-identical)
		if gm != 1.0:
			s = s.duplicate()
			s.damage = float(s.damage) * gm
	var rlm := SimWorld.Morale.reload_mult(e)
	if e.has("wz"):
		rlm *= SimWorld.Wounds.reload_mult(e)   # G7 (WOUND7): arm wounds reload slower
	var cd := maxi(roundi(float(s.cooldown) * rlm * SimWorld.TICK_RATE), 1)  # G6.1 rank reload
	if int(s.get("salvo", 1)) > 1:   # G4b UNITS: rocket salvo, salvo_gap between rockets, then reload
		var left := int(e.get("salvo_left", 0))
		if left <= 0:
			left = int(s.salvo)
		left -= 1
		e.salvo_left = left
		if left > 0:
			cd = maxi(roundi(float(s.salvo_gap) * SimWorld.TICK_RATE), 1)
	e.cd_ticks = cd
	e.cooldown = float(cd) / SimWorld.TICK_RATE
	var acc := float(s.accuracy) * Status.accuracy_mult(w, e)
	if SimIndex.g6m(w) & SimIndex.G6_ACC:
		acc *= SimIndex.g6h().accuracy_mult(w, e, s, t)  # G6: same single rng draw
	if e.has("wz"):
		acc *= SimWorld.Wounds.acc_mult(e)   # G7 (WOUND7): arm wounds aim worse (same single rng draw)
	var hit := w.rng.chance(acc)
	var from: Vector2 = e.pos
	var to: Vector2 = t.pos
	if not hit and not bool(s.get("guided", false)):  # G3b STG4: guided fire never scatters
		var disp := 1.5 if indirect else 0.6
		to += Vector2(w.rng.randf_range(-disp, disp), w.rng.randf_range(-disp, disp))
	if e.kind == "unit":
		e.firing = FIRING_HINT_TICKS
		e.facing = Traverse7.face(e, snappedf((to - from).angle(), Q))   # G7 TURRET7B CR 6354 (ORCH ruling): a mounted weapon never swings the hull
	w.emit("ShotFired", {"shooter": int(e.id), "target": int(t.id), "weapon": s.weapon, "hit": hit, "from": from, "to": to, "indirect": indirect})
	if bool(s.get("ignite", false)):
		G4bMech.ignite(w, w.cell_of(to), int(e.owner))  # G4b UNITS: flame landing on FOREST starts a fire
	if e.kind == "unit":
		e.last_fired_tick = w.tick  # G2 (A2): firing reveals forest-concealed infantry for 60 ticks
		Supply.on_shot(w, e)
	if SimIndex.profiling:
		tfr = SimIndex.pt("fire.resolve", tfr)
	if SimIndex.g6m(w) & SimIndex.G6_SHOT and _g6_shot_blocked(w, e, s, t, to):
		return  # G6 AIRDEF6: CIWS intercept / guided shot jammed (Counterdrone emits CiwsIntercept / GuidedJammed); cooldown + ammo spent
	if indirect:
		_splash(w, e, s, to)
		if SimIndex.profiling:
			SimIndex.pt("fire.splash", tfr)
		return
	if SimIndex.profiling:
		var tdm := Time.get_ticks_usec()
		Damage.apply_hit(w, e, t, s, hit)
		SimIndex.pt("fire.dmg", tdm)
		return
	Damage.apply_hit(w, e, t, s, hit)  # G2 pipeline: armor facing, cover, components, suppression


## G3a artillery impact: every ground unit and building within s.splash of `at` (any owner, the
## shooter's allies included) takes damage x (1 - 0.5 * d / splash) through the G2 pipeline, in id
## order. Nothing in the radius: near-miss suppression only.
## G6 (MECH6a CR change_request.garrison_movement_skip, optional part): ground splash damages rail tiles
## through Rail.on_splash(w, at, splash, damage, owner) when the world has rail (w.sys_state.rail, or RAIL
## tiles on the map: scanned once per world into w.cache.rail_any, derived from state, so loads agree).
## Called before the entity hits; maps without rail never call it (G5 results unchanged).
static var _rail_script = null   # loaded lazily (rail.gd preloads Movement / Construction)
const RAIL_CODE := 14            # Terrain.RAIL


static func _rail_splash(w: SimWorld, e: Dictionary, s: Dictionary, at: Vector2, rad: float) -> void:
	if not w.sys_state.has("rail"):
		var ra = w.cache.get("rail_any")
		if ra == null:
			var t = w.map.get("terrain")
			ra = t is PackedByteArray and (t as PackedByteArray).has(RAIL_CODE)
			w.cache["rail_any"] = ra
		if not bool(ra):
			return
	if _rail_script == null:
		_rail_script = load("res://sim/systems/rail.gd")
	_rail_script.on_splash(w, at, rad, float(s.damage), int(e.get("owner", -1)))


static func _splash(w: SimWorld, e: Dictionary, s: Dictionary, at: Vector2) -> void:
	var rad: float = maxf(float(s.splash), 0.01)
	_rail_splash(w, e, s, at, rad)
	var hits := {}   # id -> distance
	var ng = w.cache.get("combat_ng")
	if ng != null:
		for cid in ng.grid.query_radius(at, rad):
			var c = w.entities.get(cid)
			if c == null or bool(stats(c).is_air):
				continue
			if bool(s.get("guided", false)) and w.is_ally(int(e.owner), int(c.owner)):
				continue  # G3b STG4: guided splash spares friendlies
			hits[int(cid)] = at.distance_to(Vector2(c.pos))
	var grid: Dictionary = {} if ng != null else w.cache.get("combat_grid", {})
	var x0 := floori((at.x - rad) / BUCKET)
	var x1 := floori((at.x + rad) / BUCKET)
	var y0 := floori((at.y - rad) / BUCKET)
	var y1 := floori((at.y + rad) / BUCKET)
	for o in grid:
		var g: Dictionary = grid[o]
		for yy in range(y0, y1 + 1):
			for xx in range(x0, x1 + 1):
				var arr = g.get(xx + yy * GRID_STRIDE)
				if arr == null:
					continue
				for c in arr:
					if bool(stats(c).is_air):
						continue
					if bool(s.get("guided", false)) and w.is_ally(int(e.owner), int(c.owner)):
						continue  # G3b STG4: guided splash spares friendlies
					var d := at.distance_to(Vector2(c.pos))
					if d <= rad:
						hits[int(c.id)] = d
	for b in w.cache.get("combat_blds", []):
		if bool(s.get("guided", false)) and w.is_ally(int(e.owner), int(b.owner)):
			continue  # G3b STG4: guided splash spares friendlies
		var d := dist_to(at, b)
		if d <= rad:
			hits[int(b.id)] = d
	if hits.is_empty():
		var sup: Dictionary = Content.rules().get("suppression", {})
		Damage.near_miss(w, int(e.owner), at, float(sup.get("per_near_miss", 8)), SimWorld.Morale.weapon_supp(s))
		if _frag_near(w, at, rad):
			Shrapnel.burst(w, at, Shrapnel.from_weapon(s), e, false, true)   # G7: fragments reach past the splash
		return
	var ids := hits.keys()
	ids.sort()
	var frag := false   # G7 (WOUND7): hit-zone soldiers take fragments (Shrapnel, walls / cover block) instead of splash
	for id in ids:
		var v = w.entities.get(id)
		if v == null:
			continue
		if v.kind == "unit" and v.has("morale") and SimWorld.Wounds.applies(v):
			frag = true
			continue
		var s2 := s.duplicate()
		s2.damage = float(s.damage) * (1.0 - 0.5 * float(hits[id]) / rad) * _g4_mult(w, e, s, v)
		if SimIndex.g6m(w) & SimIndex.G6_DMG:
			s2.damage = float(s2.damage) * SimIndex.g6h().damage_mult(w, e, s, v)  # G6 splash
		Damage.apply_hit(w, e, v, s2, true)
	if frag or _frag_near(w, at, rad):
		Shrapnel.burst(w, at, Shrapnel.from_weapon(s), e, false, true)


## G7: a zone soldier inside the fragment reach (1.5 x splash) but outside the splash radius still gets a burst.
static func _frag_near(w: SimWorld, at: Vector2, rad: float) -> bool:
	var st = w.sys_state.get("wounds")
	if st == null and not bool(SimWorld.Wounds.cfg().get("enabled", false)):
		return false
	var r := rad * float((SimWorld.Wounds.shrapnel_cfg().get("shell_scale", {}) as Dictionary).get("radius_mult", 1.5))
	for c in Shrapnel._near(w, at, r, true):
		var u = w.entities.get(c)
		if u != null and SimWorld.Wounds.applies(u):
			return true
	return false


# ================================================================ commands
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if String(cmd.type) != "attack":
		return "Unknown combat command."
	var fid := int(cmd.issuer)
	var t = w.entities.get(int(cmd.get("target_id", -1)))
	if t == null:
		return "Target not visible."
	if t.kind == "structure":
		if String(t.get("state", "")) == "ruined":
			return "The bridge is already destroyed."
		return "" if Fog.is_visible(w, fid, t.pos) else "Target not visible."
	if t.kind != "unit" and t.kind != "building":
		return "That is not a valid attack target."
	if int(t.owner) == fid:
		return "Cannot attack your own forces."
	if not w.is_enemy(fid, int(t.owner)):
		return "That is not a valid attack target."
	if not _seen(w, fid, t) and not Fog.Senses7.seen_now(w, fid, t):   # REGRESS7-2: exact sight for an explicit order
		return "Target not visible."
	var armed := false
	for id in cmd.get("unit_ids", []):
		var e = w.entities.get(int(id))
		if e != null and stats(e).weapon != "":
			armed = true
			if can_target(stats(e), t):
				return ""
	return "Selected units cannot engage aircraft." if armed else "Selected units have no weapons."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var tid := int(cmd.target_id)
	var t: Dictionary = w.entities[tid]
	for id in cmd.get("unit_ids", []):
		var e = w.entities.get(int(id))
		if e == null or stats(e).weapon == "" or not can_target(stats(e), t):
			continue
		Tiers.promote(e, w)  # G3b PERF4: an explicit attack order is always FULL tier (joins the FULL list now)
		e.order = {"type": "attack", "target_id": tid, "last_pos": t.pos, "lost": false}
		e.target = tid
		e.chase_tick = -100000
