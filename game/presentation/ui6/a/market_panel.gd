extends RefCounted
## UI6a (G6): Marketplace panel (CONTRACTS_G6 section 4 market_trade, section 13 / D27).
## Opened from the HQ's card ("Market" button) or the hub. One row per market resource: stock, live
## buy / sell price (Market.price), trades left this window (Market.limit_left), and Buy / Sell lots.
## Every button's enabled state and tooltip come from the sim's own validation (preview_command) and
## Market.quote, so the panel never offers a trade the sim would reject. Issues market_trade only.

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const U = preload("res://presentation/ui6/a/ui6a_util.gd")
const Market = preload("res://sim/systems/market.gd")

const LOTS := [10, 50]
const RES_NAMES := {"salvage": "Salvage", "ore": "Ore", "fuel": "Fuel", "ammo": "Ammo"}
const WANT_W := 760.0

var m: Dictionary = {}
var panel: PanelContainer = null
var issue: Callable = Callable()        # issue(cmd: Dictionary)
var on_close: Callable = Callable()
var rows: Dictionary = {}               # res -> {stock: Label, buy: Label, sell: Label, limit: Label, btns: {amount: Button}}
var note: Label
var _fid := 0


# ------------------------------------------------------------------ model (pure; tests use these)
## [{res, name, stock, buy, sell, limit}] in Market.resources() order.
static func model(w: SimWorld, fid: int) -> Array:
	var out := []
	if w == null or not w.factions.has(fid):
		return out
	for r in Market.resources():
		var res := String(r)
		out.append({"res": res, "name": String(RES_NAMES.get(res, res.capitalize())),
			"stock": int(w.factions[fid].stock.get(res, 0)), "buy": Market.price(w, res, "buy"),
			"sell": Market.price(w, res, "sell"), "limit": Market.limit_left(w, fid, res)})
	return out


static func trade_cmd(fid: int, res: String, amount: int) -> Dictionary:
	return {"type": "market_trade", "issuer": fid, "resource": res, "amount": amount}


## "" when the trade would be accepted now, else the sim's reason.
static func reason(w: SimWorld, fid: int, res: String, amount: int) -> String:
	return w.preview_command(trade_cmd(fid, res, amount))


static func quote_text(w: SimWorld, res: String, amount: int) -> String:
	var cr := Market.quote(w, res, amount)
	var nm := String(RES_NAMES.get(res, res))
	return ("Buy %d %s for %d credits" if amount > 0 else "Sell %d %s for %d credits") % [absi(amount), nm, cr]


# ------------------------------------------------------------------ view
func build(root: Control) -> PanelContainer:
	m = U.modal("MarketPanel", "MARKETPLACE", "Close the marketplace")
	panel = m.panel
	(m.close as Button).pressed.connect(func(): if on_close.is_valid(): on_close.call())
	var body: VBoxContainer = m.body
	var help := UiKit.label("Shared prices: every unit bought raises the price 1%, every unit sold lowers it 1%; prices drift back over 3 minutes. Selling pays 70% of the buy price.", "dim")
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(300, 0)
	body.add_child(help)
	var head := U.row(body)
	U.cell_label(head, "Resource", 96, "dim")
	U.cell_label(head, "Stock", 70, "dim")
	U.cell_label(head, "Buy", 64, "dim")
	U.cell_label(head, "Sell", 64, "dim")
	U.cell_label(head, "Limit", 64, "dim")
	for r in Market.resources():
		var res := String(r)
		var hb := U.row(body)
		hb.name = "Row_" + res
		var rec := {"btns": {}}
		U.cell_label(hb, String(RES_NAMES.get(res, res.capitalize())), 96, "header")
		rec.stock = U.cell_label(hb, "0", 70)
		rec.buy = U.cell_label(hb, "-", 64)
		rec.sell = U.cell_label(hb, "-", 64)
		rec.limit = U.cell_label(hb, "-", 64)
		for amt in LOTS:
			var b := U.small_button(hb, "Buy %d" % amt, "", 74)
			b.name = "Buy%d_%s" % [amt, res]
			b.pressed.connect(press.bind(res, int(amt)))
			rec.btns[int(amt)] = b
		for amt in LOTS:
			var b := U.small_button(hb, "Sell %d" % amt, "", 74)
			b.name = "Sell%d_%s" % [amt, res]
			b.pressed.connect(press.bind(res, -int(amt)))
			rec.btns[-int(amt)] = b
		rows[res] = rec
	note = UiKit.label("", "warn")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(300, 0)
	body.add_child(note)
	root.add_child(panel)
	return panel


func fit(canvas: Vector2) -> void:
	U.fit_modal(m, canvas, WANT_W)


func update(w: SimWorld, fid: int) -> void:
	if panel == null or w == null:
		return
	_fid = fid
	var hq_reason := ""
	for rec in model(w, fid):
		var r: Dictionary = rows.get(String(rec.res), {})
		if r.is_empty():
			continue
		(r.stock as Label).text = str(int(rec.stock))
		(r.buy as Label).text = "%d cr" % int(rec.buy)
		(r.sell as Label).text = "%d cr" % int(rec.sell)
		(r.limit as Label).text = str(int(rec.limit))
		for amt in r.btns:
			var b: Button = r.btns[amt]
			var why := reason(w, fid, String(rec.res), int(amt))
			b.disabled = why != ""
			b.tooltip_text = quote_text(w, String(rec.res), int(amt)) + ("\nUnavailable: " + why if why != "" else "")
			if why.contains("HQ"):
				hq_reason = why
	note.text = hq_reason
	note.visible = hq_reason != ""


## Buy (amount > 0) or sell (amount < 0) through the issue callable.
func press(res: String, amount: int) -> void:
	if issue.is_valid():
		issue.call(trade_cmd(_fid, res, amount))
