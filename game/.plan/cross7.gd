extends SceneTree
const F7 = preload("res://sim/systems/formations7.gd")
func _cnt(mem, pts, perm) -> int:
	var c := 0
	for a in mem.size():
		for b in range(a + 1, mem.size()):
			if F7._crosses(mem[a].pos, pts[perm[a]], mem[b].pos, pts[perm[b]]): c += 1
	return c
func _init() -> void:
	var mem := []
	var pts := []
	var roles := []
	for k in 400:
		mem.append({"id": 1000 + k, "pos": Vector2(float(k % 20) * 1.1 + 10.0, float(k / 20) * 1.1 + 10.0), "rank_role": "lead" if k == 37 else "", "def": "rifleman"})
		pts.append(Vector2(float(k % 25) * 1.1 + 60.0, float(k / 25) * 1.1 + 40.0))
		roles.append(F7.ROLE_RIFLE)
	var t := Time.get_ticks_usec()
	var pe := F7._assign_exact(mem, pts, roles, true)
	var te := (Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	var ps := F7.assign(mem, pts, roles)
	var ts := (Time.get_ticks_usec() - t) / 1000.0
	var ce := _cnt(mem, pts, pe); var cs := _cnt(mem, pts, ps)
	var se := 0.0; var ss := 0.0
	for j in 400:
		se += Vector2(mem[j].pos).distance_squared_to(pts[pe[j]]); ss += Vector2(mem[j].pos).distance_squared_to(pts[ps[j]])
	print("CROSS7 exact: %d crossings %.0f ms cost %.0f | split: %d crossings %.0f ms cost %.0f" % [ce, te, se, cs, ts, ss])
	quit(0)
