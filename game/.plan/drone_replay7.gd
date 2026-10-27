extends SceneTree
## INTEG7 Done-when 2 evidence: a recorded player drone flight (command log) replayed in a fresh world.
func _init() -> void:
	var T = load("res://tests/test_drone7.gd").new()
	var a: Array = T._flight([])
	var b: Array = T._flight(a[1])
	print("DRONE_REPLAY recorded=%s replayed=%s commands=%d flight=%s same=%s" % [String(a[0]).left(24), String(b[0]).left(24), (a[1] as Array).size(), str(a[2]), str(a[0] == b[0])])
	quit()
