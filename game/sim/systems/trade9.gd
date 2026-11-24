extends RefCounted
## Capturable trade posts pay credits plus a location-specific resource mix.

const KEY := "trade9"


static func R() -> Dictionary:
	return Content.rules().get("g71_econ9", {}).get("trade", {})


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {"posts": {}, "income": {}}
	return w.sys_state[KEY]


static func hold_post(w: SimWorld, fid: int, post_id: String) -> void:
	var posts: Dictionary = _st(w).posts
	if fid < 0:
		posts.erase(post_id)
	else:
		posts[post_id] = {"fid": fid, "last": w.tick}
	w.emit("Trade9Post", {"post": post_id, "fid": fid})


static func income_for(w: SimWorld, fid: int) -> Dictionary:
	return ((_st(w).income as Dictionary).get(str(fid), {}) as Dictionary).duplicate()


static func tick(w: SimWorld) -> void:
	var every := maxi(int(R().get("interval_ticks", 100)), 1)
	if not w.sys_state.has(KEY) or w.tick <= 0 or w.tick % every != 0:
		return
	var mixes: Dictionary = R().get("posts", {})
	for post_id in (_st(w).posts as Dictionary):
		var rec: Dictionary = _st(w).posts[post_id]
		var fid := int(rec.fid)
		if not w.factions.has(fid):
			continue
		var pay: Dictionary = (mixes.get(post_id, R().get("default_mix", {})) as Dictionary).duplicate()
		if pay.is_empty():
			continue
		w.credit(fid, pay, "trade9:%s" % post_id)
		var total: Dictionary = (_st(w).income as Dictionary).get(str(fid), {})
		for k in pay:
			total[k] = int(total.get(k, 0)) + int(pay[k])
		_st(w).income[str(fid)] = total
		w.emit("Trade9Income", {"post": post_id, "fid": fid, "mix": pay})
