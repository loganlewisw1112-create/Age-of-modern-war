import sys
p=sys.argv[1]
s=open(p,encoding="utf-8",newline="").read()
crlf="\r\n" in s
s=s.replace("\r\n","\n")
R=[
# 1 load: 6 fields = foot-only gate
("""		gates[int(g[0])] = [int(g[1]), int(g[2])] if (g as Array).size() < 4 else ([int(g[1]), int(g[2]), int(g[3])] if (g as Array).size() < 5 else [int(g[1]), int(g[2]), int(g[3]), int(g[4])])   # G7 APCMOV7-3: 5 fields = vehicle-only gate
""",
"""		gates[int(g[0])] = [int(g[1]), int(g[2])] if (g as Array).size() < 4 else ([int(g[1]), int(g[2]), int(g[3])] if (g as Array).size() < 5 else ([int(g[1]), int(g[2]), int(g[3]), int(g[4])] if (g as Array).size() < 6 else [int(g[1]), int(g[2]), int(g[3]), int(g[4]), int(g[5])]))   # G7 APCMOV7-3: 5 fields = vehicle-only gate; FACB7-7: 6 fields = foot-only gate
"""),
# 2 _solid_view
("""		out[i] = 0 if _gate_open(gates[i], team) and _cell_sm(w, mc, i) > 0.0 and (mc == "foot" or not _is_ww(gates[i])) and not (mc == "foot" and _is_vg(gates[i])) else 1
""",
"""		out[i] = 0 if _gate_open(gates[i], team) and _cell_sm(w, mc, i) > 0.0 and (mc == "foot" or not _is_ww(gates[i])) and not (mc == "foot" and _is_vg(gates[i])) and (mc == "foot" or not _is_fo(gates[i])) else 1
"""),
# 3 is_passable
("""			return _gate_open(gates[i], team) and _cell_sm(w, mc, i) > 0.0 and (mc == "foot" or not _is_ww(gates[i])) and not (mc == "foot" and _is_vg(gates[i]))
""",
"""			return _gate_open(gates[i], team) and _cell_sm(w, mc, i) > 0.0 and (mc == "foot" or not _is_ww(gates[i])) and not (mc == "foot" and _is_vg(gates[i])) and (mc == "foot" or not _is_fo(gates[i]))
"""),
# 4 set_gate doc + signature + entry + native allow
("""## saved as [idx, team, locked, 0, 1]; native: the foot class gets allow 0 on those cells, _vg_native_allow).
static func set_gate(w: SimWorld, cells: Array, owner_team: int, locked: bool, vonly := false) -> void:
""",
"""## saved as [idx, team, locked, 0, 1]; native: the foot class gets allow 0 on those cells, _vg_native_allow).
## G7 FACB7-7 (13.9c-20c): fonly = a foot-only gate (the facility's mantrap doors and decon hall): open only for the owner
## team's foot class while unlocked, solid for every non-foot ground class of any team (CN suits, vehicles)
## (gates[i] = [team, locked, 0, 0, 1], saved as [idx, team, locked, 0, 0, 1]; native: non-foot classes get allow 0).
static func set_gate(w: SimWorld, cells: Array, owner_team: int, locked: bool, vonly := false, fonly := false) -> void:
"""),
("""	var vg_changed := false
	for c in cells:
""",
"""	var vg_changed := false
	var fo_changed := false
	for c in cells:
"""),
("""		var was_vg := _is_vg(gates.get(i))
""",
"""		var was_vg := _is_vg(gates.get(i))
		var was_fo := _is_fo(gates.get(i))
"""),
("""			gates[i] = [owner_team, 1 if locked else 0, 0, 1] if vonly else [owner_team, 1 if locked else 0]
		vg_changed = vg_changed or was_vg != (vonly and owner_team >= 0)
""",
"""			gates[i] = [owner_team, 1 if locked else 0, 0, 0, 1] if fonly else ([owner_team, 1 if locked else 0, 0, 1] if vonly else [owner_team, 1 if locked else 0])
		vg_changed = vg_changed or was_vg != (vonly and not fonly and owner_team >= 0)
		fo_changed = fo_changed or was_fo != (fonly and owner_team >= 0)
"""),
("""		if vg_changed:
			_vg_native_allow(w, native)
""",
"""		if vg_changed:
			_vg_native_allow(w, native)
		if fo_changed:
			_fo_native_allow(w, native)
"""),
# 5 _is_fo + helpers after _is_vg
("""static func _is_vg(g) -> bool:
	return g != null and (g as Array).size() > 3 and int(g[3]) != 0
""",
"""static func _is_vg(g) -> bool:
	return g != null and (g as Array).size() > 3 and int(g[3]) != 0


## G7 FACB7-7 (13.9c-20c): foot-only gate entry (5th field 1): see set_gate.
static func _is_fo(g) -> bool:
	return g != null and (g as Array).size() > 4 and int(g[4]) != 0


static func _fo_any(w: SimWorld) -> bool:
	var gates: Dictionary = w.nav.gates
	for i in gates:
		if _is_fo(gates[i]):
			return true
	return false


## Native: every non-foot ground class gets the wall-walk + foot-only allow mask again (foot-only cells changed).
static func _fo_native_allow(w: SimWorld, nav) -> void:
	if nav == null or not nav.has_method("add_class"):
		return
	for mc in w.nav.solid.keys():
		var ms := String(mc)
		if ms != "foot" and not is_air(ms):
			nav.add_class(NativeCore.mc_index(ms), PackedFloat32Array(_lut(ms)), _ww_allow(w, ms, _base_allow(w, ms)))
			w.nav.solid[mc] = nav.solid_bytes(_key(ms, -1))
"""),
# 6 _ww_allow
("""static func _ww_allow(w: SimWorld, mc: String, base: PackedByteArray) -> PackedByteArray:
	if mc == "foot" or is_air(mc) or not wallwalk_any(w):
		return base
""",
"""static func _ww_allow(w: SimWorld, mc: String, base: PackedByteArray) -> PackedByteArray:
	if mc == "foot" or is_air(mc) or (not wallwalk_any(w) and not _fo_any(w)):   # FACB7-7: + foot-only gate cells
		return base
"""),
("""	for i in gates:
		if _is_ww(gates[i]):
			out[i] = 0
	return out
""",
"""	for i in gates:
		if _is_ww(gates[i]) or _is_fo(gates[i]):
			out[i] = 0
	return out
"""),
# 7 _ww_native_allow
("""static func _ww_native_allow(w: SimWorld, nav) -> void:
	if not wallwalk_any(w) or not nav.has_method("add_class"):
		return
""",
"""static func _ww_native_allow(w: SimWorld, nav) -> void:
	if (not wallwalk_any(w) and not _fo_any(w)) or not nav.has_method("add_class"):
		return
"""),
# 8 _save_gates
("""		elif _is_vg(g):   # G7 APCMOV7-3: vehicle-only gate
			arr.append([int(i), int(g[0]), int(g[1]), 0, 1])
""",
"""		elif _is_vg(g):   # G7 APCMOV7-3: vehicle-only gate
			arr.append([int(i), int(g[0]), int(g[1]), 0, 1])
		elif _is_fo(g):   # G7 FACB7-7: foot-only gate
			arr.append([int(i), int(g[0]), int(g[1]), 0, 0, 1])
"""),
]
for i,(a,b) in enumerate(R):
    n=s.count(a)
    if n!=1:
        print("HUNK",i,"count",n); sys.exit(1)
    s=s.replace(a,b)
if crlf: s=s.replace("\n","\r\n")
open(p,"w",encoding="utf-8",newline="").write(s)
print("patched",len(R),"hunks")
