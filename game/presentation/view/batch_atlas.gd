extends RefCounted
## Dynamic texture atlas for batched drawing (owner: R4-render, G3b). Tinted unit sheets,
## building/resource/decor images and procedural fallbacks are blitted into a few 2048x2048
## RGBA8 pages, so almost every entity draw in a frame uses the same texture and the canvas
## renderer can batch them. Pages upload once per frame at most (flush()).
## No class_name: preload it.

const PAGE := 2048
const PAD := 2
const WIDE := 2560  # G6.1: shared page width for sheets wider than PAGE

var pages: Array = []        # Array of Dictionary {img: Image, tex: ImageTexture, x, y, row_h, dirty}
var _slots: Dictionary = {}  # key -> Rect2 (page index stored in _slot_page)
var _slot_page: Dictionary = {}
var uploads := 0
var _wide: Array = []        # G6.1: indices of shared WIDE pages
var _cur := -1               # G6.1: index of the regular page being filled


## G6.1 (ANIMA61): atlas memory evidence {pages, bytes}.
func stats() -> Dictionary:
	var b := 0
	for p in pages:
		b += (p.img as Image).get_width() * (p.img as Image).get_height() * 4
	return {"pages": pages.size(), "bytes": b}


func has(key) -> bool:
	return _slots.has(key)


## Page index of a slot (-1 when unknown).
func page_of(key) -> int:
	return int(_slot_page.get(key, -1))


## Source rect of a slot in its page (Rect2() when unknown).
func rect_of(key) -> Rect2:
	return _slots.get(key, Rect2())


func texture(page: int) -> Texture2D:
	return pages[page].tex


## Adds img under key (no-op when present). Returns the page index (-1 on a null image).
func add(key, img: Image) -> int:
	if _slots.has(key):
		return int(_slot_page[key])
	if img == null or img.is_empty():
		return -1
	if img.is_compressed():
		img = img.duplicate()
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
	var sz := img.get_size()
	var pi := -1
	var at := Vector2i.ZERO
	if sz.x + PAD > PAGE and sz.x + PAD <= WIDE and sz.y + PAD <= PAGE:
		# G6.1 (ANIMA61): sheets wider than a page (72 px walkers / 64 px squads x 33+ columns) stack in
		# shared WIDE x PAGE pages instead of one page (one texture, one batch break) each
		for wi in _wide:
			var wp: Dictionary = pages[wi]
			if int(wp.y) + sz.y + PAD <= PAGE:
				pi = wi
				break
		if pi < 0:
			pi = _new_page(Vector2i(WIDE, PAGE))
			pages[pi].x = WIDE
			_wide.append(pi)
		at = Vector2i(0, int(pages[pi].y))
		pages[pi].y = int(pages[pi].y) + sz.y + PAD
	elif sz.x + PAD > PAGE or sz.y + PAD > PAGE:
		pi = _new_page(Vector2i(sz.x + PAD, sz.y + PAD))
		pages[pi].x = PAGE  # an oversize page holds one image
	else:
		pi = _cur  # G6.1: the current regular page (oversize / wide pages never take small images)
		var ok := false
		if pi >= 0:
			var p: Dictionary = pages[pi]
			if int(p.x) + sz.x + PAD > int(p.img.get_width()):
				p.x = 0
				p.y = int(p.y) + int(p.row_h) + PAD
				p.row_h = 0
			ok = int(p.y) + sz.y + PAD <= int(p.img.get_height())
		if not ok:
			pi = _new_page(Vector2i(PAGE, PAGE))
			_cur = pi
		var q: Dictionary = pages[pi]
		at = Vector2i(int(q.x), int(q.y))
		q.x = int(q.x) + sz.x + PAD
		q.row_h = maxi(int(q.row_h), sz.y)
	var page: Dictionary = pages[pi]
	(page.img as Image).blit_rect(img, Rect2i(Vector2i.ZERO, sz), at)
	page.dirty = true
	_slots[key] = Rect2(Vector2(at), Vector2(sz))
	_slot_page[key] = pi
	return pi


func _new_page(size: Vector2i) -> int:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	pages.append({"img": img, "tex": null, "x": 0, "y": 0, "row_h": 0, "dirty": true})
	return pages.size() - 1


## Uploads dirty pages. Call once per frame before drawing.
func flush() -> void:
	for p in pages:
		if not bool(p.dirty):
			continue
		p.dirty = false
		uploads += 1
		if p.tex == null:
			p.tex = ImageTexture.create_from_image(p.img)
		else:
			(p.tex as ImageTexture).update(p.img)
