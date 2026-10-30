extends RefCounted
## G7 CARDBAR8 (13.9c-51): playtest helpers for the facility cards now in the bottom command card. A card button
## lives in the command grid only while its tab is open, so a flow finds it through the HUD's cardbar host and, when
## its tab is closed, opens that tab with a real click on the tab strip first (click path only; every flow check stays).


## The card's node named nm wherever it is now (card info strip, command grid or the hidden stash).
static func node(pt, card, nm: String) -> Node:
	if card == null:
		return null
	var hud = pt.main.get("hud") if pt.main != null else null
	if hud != null and hud.get("cardbar") != null:
		return hud.cardbar.find(card, nm)
	return card.find_child(nm, true, false)


## The card button named btn_name, its tab opened by a real click when it is not on screen (null when missing).
static func reveal(pt, card, btn_name: String) -> Button:
	var b := node(pt, card, btn_name) as Button
	if b == null or b.is_visible_in_tree():
		return b
	var hud = pt.main.get("hud")
	if hud == null or hud.get("cardbar") == null:
		return b
	var cb = hud.cardbar
	var tab: String = cb.tab_for(card, btn_name)
	for i in 3:
		var tb: Button = cb.tab_button(tab)
		if tb == null or not tb.is_visible_in_tree():
			await pt._wait(0.3)
			continue
		await pt._click(tb.get_global_rect().get_center())
		await pt._wait(0.4)
		if b.is_visible_in_tree():
			break
	return b
