extends RefCounted
## Base for test files: `extends "res://tests/test_base.gd"`.

var failures: Array = []


func check(cond: bool, msg: String) -> bool:
	if not cond:
		failures.append(msg)
	return cond


func check_eq(a, b, msg: String) -> bool:
	if a != b:
		failures.append("%s (got %s, expected %s)" % [msg, str(a), str(b)])
		return false
	return true


## A fresh default 2-side match (player fid 0 vs AI fid 1) with optional overrides.
func make_world(overrides: Dictionary = {}) -> SimWorld:
	var c := SimWorld.default_config()
	c.merge(overrides, true)
	return SimWorld.new_match(c)


## Submit a command for fid and step once so it applies. Returns the apply-tick events.
func do_cmd(w: SimWorld, fid: int, cmd: Dictionary) -> Array:
	cmd.issuer = fid
	var r := w.submit(cmd)
	check(r.ok, "submit rejected: %s" % r.reason)
	w.step()
	return w.events


func rejected_reason(events: Array) -> String:
	for ev in events:
		if ev.type == "CommandRejected":
			return String(ev.reason)
	return ""
