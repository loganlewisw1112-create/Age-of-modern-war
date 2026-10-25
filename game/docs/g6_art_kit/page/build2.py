import base64, json, os, glob, re
HERE = os.path.dirname(os.path.abspath(__file__))
GAME = r"D:\CODING\PROJECTS - CURRENTLY WORKING ON\RTS Age of Modern Warfare\game"
def uri(p):
    return "data:image/png;base64," + base64.b64encode(open(p, "rb").read()).decode()
def pngsize(p):
    d = open(p, "rb").read(24); return int.from_bytes(d[16:20], "big"), int.from_bytes(d[20:24], "big")
items = json.load(open(os.path.join(HERE, "items.json"), encoding="utf-8"))
meta = {}
for f in glob.glob(os.path.join(HERE, "art", "show", "*.json")):
    if os.path.basename(f) == "ex.json": continue
    meta.update(json.load(open(f, encoding="utf-8")))
missing = []
for o in items:
    a = o["art_id"]; m = meta.get(a)
    pl = os.path.join(HERE, "art", "show", a + ".png"); tu = os.path.join(HERE, "art", "turn", a + ".png")
    if m and os.path.exists(pl):
        o["plate"] = uri(pl); o["zoom"] = m["zoom"]; o["kind"] = m["kind"]
        if os.path.exists(tu):
            o["turn"] = uri(tu); o["th"] = pngsize(tu)[1]
    else:
        missing.append(a)
# G5 names from content
names = {}
for f in glob.glob(os.path.join(GAME, "content", "g5", "*.json")):
    d = json.load(open(f, encoding="utf-8"))
    for sec in ("units", "buildings"):
        for k, v in (d.get(sec) or {}).items():
            if isinstance(v, dict) and v.get("name"): names[k] = v["name"]
nowmeta = json.load(open(os.path.join(HERE, "art", "now", "now.json"), encoding="utf-8"))
order = sorted(nowmeta, key=lambda k: (nowmeta[k]["kind"] != "unit", k))
now = [{"id": k, "name": names.get(k, k), "src": uri(os.path.join(HERE, "art", "now", k + ".png"))} for k in order]
scen = json.load(open(os.path.join(HERE, "scenes.json"), encoding="utf-8")) if os.path.exists(os.path.join(HERE, "scenes.json")) else []
for sc in scen:
    p = os.path.join(HERE, "art", "scenes", sc["id"] + ".png")
    if os.path.exists(p): sc["img"] = uri(p)
tpl = open(os.path.join(HERE, "template2.html"), encoding="utf-8").read()
old = open(os.path.join(HERE, "template.html"), encoding="utf-8").read()
style = old[old.index("<style>") + 7: old.index("</style>")]
fr = base64.b64encode(open(os.path.join(GAME, "assets/fonts/rts_mil_regular.ttf"), "rb").read()).decode()
fb = base64.b64encode(open(os.path.join(GAME, "assets/fonts/rts_mil_bold.ttf"), "rb").read()).decode()
style = style.replace("__FONT_R__", fr).replace("__FONT_B__", fb)
out = tpl.replace("__STYLE__", style).replace("__DATA__", json.dumps({"items": items, "now": now, "scenes": scen}))
os.makedirs(os.path.join(HERE, "out"), exist_ok=True)
dst = os.path.join(HERE, "out", "g6_arsenal.html")
open(dst, "w", encoding="utf-8").write(out)
open(os.path.join(HERE, "out", "preview.html"), "w", encoding="utf-8").write('<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"></head><body>' + out + "</body></html>")
print("wrote", dst, round(len(out) / 1e6, 2), "MB; plates", len(items) - len(missing), "/", len(items), "; missing:", ",".join(missing) or "none")
