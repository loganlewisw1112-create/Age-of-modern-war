extends SceneTree
## G7 (MUZZLE7): writes assets/art/muzzle7.json (barrel tips of every firing sprite, see tools/art/muzzle7.gd).
## Run: godot --headless --path . -s tools/art/muzzle7_gen.gd   (re-run after any art regeneration)

const M7 = preload("res://tools/art/muzzle7.gd")
const OUT := "res://assets/art/muzzle7.json"


func _init() -> void:
	Content.load_all()
	var t0 := Time.get_ticks_msec()
	var tb: Dictionary = M7.build_table()
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(tb, "", true) + "\n")
	f.close()
	var nf := 0
	var ne := 0
	for k in tb.u:
		for p in (tb.u[k].s as Dictionary):
			nf += String(tb.u[k].s[p]).count("f")
			ne += String(tb.u[k].s[p]).count("e")
	var bf := 0
	var be := 0
	for k in tb.b:
		bf += String(tb.b[k].s).count("f")
		be += String(tb.b[k].s).count("e")
	print("MUZZLE7 GEN units=%d buildings=%d unit_rows flash=%d edge=%d bld_states flash=%d edge=%d ms=%d" % [
		(tb.u as Dictionary).size(), (tb.b as Dictionary).size(), nf, ne, bf, be, Time.get_ticks_msec() - t0])
	quit()
