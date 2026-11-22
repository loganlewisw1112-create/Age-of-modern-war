extends RefCounted
## G7.1 ARMY71 D4 RADIO CALLOUTS (docs/G71_SCOPE.md D4; roster 5A Q13: text now, voiced in the wave-5 sound pass).
## Sim code says a line; the view shows it as a radio subtitle through presentation/audio/radio_queue.gd
## (presentation/ui71/radio_feed.gd rate-limits: one voice per event cluster, per-category cooldown).
##   say(w_or_view, key, pos, team) -> void
##       SimWorld: emits event "radio71" {key, pos [x,y], team} (no saved state, not hashed, display only)
##       a view object with radio71_say(key, pos, team): calls it directly (view-side callouts)
##   lines() -> Dictionary   key -> {text, cat, prio, cd}; merged from presentation/audio/lines71_<agent>.json in file
##                           name order; a key already loaded is kept (first file wins; agents prefix their keys)
##   line(key) -> Dictionary {} = unknown key
## Line fragment format: {"lines": {"<key>": {"text": "Contact front!", "cat": "contact", "prio": 60, "cd": 4.0}}}

const DIR := "res://presentation/audio/"

static var _lines = null


static func say(w_or_view, key: String, pos: Vector2, team: int) -> void:
	if w_or_view is SimWorld:
		(w_or_view as SimWorld).emit("radio71", {"key": key, "pos": [pos.x, pos.y], "team": team})
	elif w_or_view != null and w_or_view.has_method("radio71_say"):
		w_or_view.radio71_say(key, pos, team)


static func lines() -> Dictionary:
	if _lines != null:
		return _lines
	var out := {}
	var names: Array = []
	var d := DirAccess.open(DIR)
	if d != null:
		for f in d.get_files():
			var fn := String(f).trim_suffix(".remap")
			if fn.begins_with("lines71_") and fn.ends_with(".json") and not names.has(fn):
				names.append(fn)
	names.sort()
	for fn in names:
		var txt := FileAccess.get_file_as_string(DIR + String(fn))
		var j = JSON.parse_string(txt) if txt != "" else null
		if j is Dictionary:
			var ls: Dictionary = (j as Dictionary).get("lines", {})
			for k in ls:
				if not out.has(k) and ls[k] is Dictionary:
					out[k] = ls[k]
	_lines = out
	return out


static func line(key: String) -> Dictionary:
	return lines().get(key, {})
