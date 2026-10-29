extends "res://tests/test_base.gd"
## G7 ICONS7: no unit or building def (any faction, G5 to G7) may resolve to ArtCatalog's magenta placeholder icon.
## ArtCatalog.icon(id) returns the placeholder when the id has no entry in any manifest `icons` section, or its PNG
## is missing/unreadable. The check is on the resolved texture itself, so a manifest entry that points at a missing
## file fails too.


func _missing(table: String) -> Array:
	var out: Array = []
	var ids: Array = Content.ids(table)
	ids.sort()
	for id in ids:
		var tex: Texture2D = ArtCatalog.icon(String(id))
		var img: Image = tex.get_image() if tex != null else null
		var is_ph := tex == null or img == null or img.is_empty()
		if not is_ph:
			# the placeholder is a flat 16x16 magenta; a real icon is never one flat magenta colour
			var c := img.get_pixel(0, 0)
			is_ph = img.get_width() == 16 and img.get_height() == 16 and c.is_equal_approx(Color.MAGENTA)
			if is_ph:
				for y in 16:
					for x in 16:
						if not img.get_pixel(x, y).is_equal_approx(Color.MAGENTA):
							is_ph = false
		if is_ph:
			out.append(String(id))
	return out


func test_no_def_uses_placeholder_icon() -> void:
	Content.load_all()
	ArtCatalog.load_all()
	var mu := _missing("units")
	var mb := _missing("buildings")
	print("ICONS7 units=%d buildings=%d missing_units=%s missing_buildings=%s" % [Content.ids("units").size(), Content.ids("buildings").size(), str(mu), str(mb)])
	check(mu.is_empty(), "units with placeholder icon: %s" % str(mu))
	check(mb.is_empty(), "buildings with placeholder icon: %s" % str(mb))
