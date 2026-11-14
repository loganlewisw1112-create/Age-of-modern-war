extends "res://tests/test_base.gd"
## G7.1 SWARMNAT71: native swarm drawing (docs/SWARM_NATIVE71.md) + the render_snap g71 provider hook (ORCH task for
## wave 2).
const RenderSnap = preload("res://sim/render_snap.gd")


## RenderSnap.register_g71: nothing registered = no snap.g71 and no calls; each provider runs once per build, in
## registration order, gets (w, snap) with the built-in fields final, and its return lands at snap.g71[key];
## re-registering replaces; unregister removes; building snapshots never moves the sim hash.
func test_g71_hook() -> void:
	for k in RenderSnap.g71_keys():   # a test that died half-way must not leak providers into this one
		RenderSnap.unregister_g71(k)
	var w := make_world()
	w.spawn_unit("rifleman", 0, Vector2(30, 30))
	w.step()
	var h0 := w.state_hash()
	RenderSnap.build(w)
	var s0: Dictionary = RenderSnap.latest(w)
	check(not s0.has("g71"), "empty registry: snapshot has no g71 key")
	var calls := [0, 0]
	var order: Array = []
	RenderSnap.register_g71("t_a", func(ww, sn):
		calls[0] += 1
		order.append("a")
		return {"n": int(sn.n), "ids": (sn.ids as PackedInt32Array).size(), "tick": int(ww.tick)})
	RenderSnap.register_g71("t_b", func(_ww, _sn):
		calls[1] += 1
		order.append("b")
		return PackedInt32Array([7, 1]))
	check_eq(Array(RenderSnap.g71_keys()), ["t_a", "t_b"], "g71_keys in registration order")
	RenderSnap.build(w)
	var s1: Dictionary = RenderSnap.latest(w)
	var g: Dictionary = s1.get("g71", {})
	check_eq(calls, [1, 1], "each provider called once per build")
	check_eq(order, ["a", "b"], "providers run in registration order")
	check_eq(g.get("t_a"), {"n": int(s1.n), "ids": int(s1.n), "tick": int(w.tick)}, "provider sees the final ids / n of this snapshot")
	check_eq(g.get("t_b"), PackedInt32Array([7, 1]), "return value stored at snap.g71[key]")
	RenderSnap.register_g71("t_b", func(_ww, _sn): return "replaced")
	RenderSnap.build(w)
	check_eq((RenderSnap.latest(w).get("g71", {}) as Dictionary).get("t_b"), "replaced", "re-registering a key replaces its provider")
	check_eq(calls, [2, 1], "the replaced provider is no longer called")
	RenderSnap.unregister_g71("t_a")
	RenderSnap.unregister_g71("t_b")
	RenderSnap.unregister_g71("t_none")   # unknown key: no-op
	RenderSnap.build(w)
	check(not RenderSnap.latest(w).has("g71"), "after unregistering every key the snapshot has no g71 key again")
	check_eq(RenderSnap.g71_keys().size(), 0, "registry empty")
	check_eq(w.state_hash(), h0, "snapshot builds with providers never change the sim hash")
