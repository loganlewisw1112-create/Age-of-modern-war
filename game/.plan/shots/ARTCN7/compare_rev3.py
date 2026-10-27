"""Look checkpoint side-by-side, rev3 (ARTCN7-4; same format as compare_rev2.py plus the scale strip).

    python -I compare_rev3.py <game dir> <out.png>

TODAY's shipped sprites vs the rev3 G7 DL7-3 samples, every sprite at the SAME pixel scale, team-tinted through its
own *_mask.png (player blue for Human, enemy red for Machine). Rev3 = the owner's rev2 decision: ONE real-world scale
(fact art.scale: 4 m per 64x32 tile, 9.8 px per metre of height): 1.8 m soldiers = 18 px, 8 m APC, 19.6 m VTOLs.
Top: the SCALE STRIP (tile diamonds, soldiers, both APCs, the stealth VTOL on the ground, the garage + a building
from today) at true size and 2x, everything standing on the same tile grid. Then the 3x rows and the true-size lineup.
"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont

root = sys.argv[1]; out = sys.argv[2]
TEAM = (0x4f, 0x7d, 0xb0); ENEMY = (0xb5, 0x58, 0x3a)
BASES = ['assets/art/g7_cn', 'assets/art/g7_turrets', 'assets/art/g7_threats', 'assets/generated', 'assets/art/g5_units',
         'assets/art/g5_air', 'assets/art/g6_units', 'assets/art/g5_bld', 'assets/art/g6_bld']
mans = {}; blds = {}
for base in BASES:
    p = os.path.join(root, base, 'manifest.json')
    if not os.path.exists(p):
        continue
    m = json.load(open(p, encoding='utf-8'))
    for sec in ('infantry', 'vehicles'):
        for k, e in m.get(sec, {}).items():
            if isinstance(e, dict) and 'file' in e and k not in mans:
                mans[k] = (base, e)
    for k, e in m.get('buildings', {}).items():
        if isinstance(e, dict) and k not in blds:
            blds[k] = (base, e)


def tint(im, mk, col):
    px = im.load(); mp = mk.load()
    for y in range(im.height):
        for x in range(im.width):
            if mp[x, y][3] > 0:
                r, g, b, a = px[x, y]
                k = 0.45 + (r / 255.0) * 0.9
                px[x, y] = tuple(min(255, int(c * k)) for c in col) + (a,)
    return im


def cell(k, fname, row=1):
    """Full cell (uncropped) + pivot."""
    base, e = mans[k]
    fw, fh = int(e['fw']), int(e['fh'])
    frames = e.get('frames', [])
    c = frames.index(fname) if fname in frames else 0
    def cut(f):
        im = Image.open(os.path.join(root, base, f)).convert('RGBA')
        r = min(row, im.height // fh - 1)
        return im.crop((c * fw, r * fh, c * fw + fw, r * fh + fh))
    im = cut(e['file'])
    if e.get('mask'):
        im = tint(im, cut(e['mask']), ENEMY if k.startswith('m_') or k.startswith('g7_m_') else TEAM)
    pv = e.get('pivot', [fw // 2, fh - 4])
    return im, (int(pv[0]), int(pv[1])), (frames[c] if frames else '-')


def frame(k, fname, row=1):
    im, pv, fn = cell(k, fname, row)
    bb = im.getbbox() or (0, 0, 1, 1)
    return im.crop(bb), fn


def bld(k, state='built'):
    base, e = blds[k]
    st = e['states'].get(state) or list(e['states'].values())[0]
    im = Image.open(os.path.join(root, base, st['file'])).convert('RGBA')
    if st.get('mask'):
        im = tint(im, Image.open(os.path.join(root, base, st['mask'])).convert('RGBA'), TEAM)
    return im, tuple(int(v) for v in e['pivot'])


try:
    f = ImageFont.truetype("arial.ttf", 22); fs = ImageFont.truetype("arial.ttf", 14); fb = ImageFont.truetype("arialbd.ttf", 26)
except Exception:
    f = fs = fb = ImageFont.load_default()

# ------------------------------------------------------------------ scale strip (true size, on one tile grid)
SW, SH = 1000, 250
strip = Image.new('RGBA', (SW, SH), (0, 0, 0, 255)); sp = strip.load()
for y in range(SH):
    for x in range(SW):
        u = ((x / 32.0) + (y / 16.0)) / 2.0; v = ((y / 16.0) - (x / 32.0)) / 2.0
        chk = (int(u // 1) + int(v // 1)) % 2
        sp[x, y] = (84, 98, 62, 255) if chk else (78, 92, 58, 255)
gy = 190   # ground row: units stand on tile centres along this line
def put(im, pv, gx, gyy):
    strip.alpha_composite(im, (int(gx - pv[0]), int(gyy - pv[1])))
items = []
gx = 40
for k in ['g7_cn_team_leader', 'g7_cn_gunner', 'g7_op_marksman']:
    if k in mans:
        im, pv, _ = cell(k, 'idle', 1); put(im, pv, gx, gy); gx += 14
items.append((40, "soldiers 1.8 m = 18 px"))
gx += 70
if 'g7_cn_strike_apc' in mans:
    im, pv, _ = cell('g7_cn_strike_apc', 'idle', 3); put(im, pv, gx, gy); items.append((gx - 40, "strike APC 8.0 m"))
gx += 110
if 'g7_op_tactical_apc' in mans:
    im, pv, _ = cell('g7_op_tactical_apc', 'idle', 3); put(im, pv, gx, gy); items.append((gx - 40, "tactical APC 7.0 m"))
gx += 170
if 'g7_cn_stealth_dropship' in mans:
    im, pv, _ = cell('g7_cn_stealth_dropship', 'landed', 3); put(im, pv, gx, gy - 6); items.append((gx - 90, "stealth VTOL 19.6 m (landed)"))
gx += 210
if 'g7_cn_garage' in blds:
    im, pv = bld('g7_cn_garage'); put(im, pv, gx, gy - 10); items.append((gx - 50, "APC garage 12 m"))
gx += 120
for k in ['a_barracks', 'barracks', 'a_hq']:
    if k in blds:
        im, pv = bld(k); put(im, pv, gx, gy - 10); items.append((gx - 40, "today: %s" % k)); break
sd = ImageDraw.Draw(strip)
for x0 in (8,):   # one tile diamond outlined = 4 m x 4 m
    cx, cy = 22, 222
    sd.polygon([(cx, cy - 16), (cx + 32, cy), (cx, cy + 16), (cx - 32, cy)], outline=(240, 220, 120, 255))
strip_lab = items

# ------------------------------------------------------------------ 3x comparison rows
ROWS = [
    ("Soldiers", [("rifleman", "idle"), ("a_special_forces", "idle"), ("a_captain", "idle"), ("a_hmg_team", "idle")],
     [("g7_cn_team_leader", "idle"), ("g7_cn_radio", "idle"), ("g7_cn_deploy", "idle"), ("g7_cn_scanner", "idle"),
      ("g7_cn_ew", "idle"), ("g7_cn_gunner", "idle"), ("g7_cn_medic", "idle"), ("g7_op_hunter", "idle", 3), ("g7_op_marksman", "idle", 3)]),
    ("APCs\n(rocket pod up /\nmoving)", [("ifv", "idle", 3), ("a_apc", "idle", 3)],
     [("g7_cn_strike_apc", "rockets_up", 3), ("g7_op_tactical_apc", "rockets_up", 3), ("g7_cn_strike_apc", "fire", 0), ("g7_op_tactical_apc", "move", 6)]),
    ("Dropships\n(hover, tilt, APC in\nbay / on ramp)", [("a_vtol_dropship", "idle")],
     [("g7_cn_stealth_dropship", "hover", 0), ("g7_cn_stealth_dropship", "transition", 2), ("g7_cn_stealth_dropship", "bay_open", 3),
      ("g7_a_vtol_dropship_xl", "landed", 2), ("g7_a_vtol_dropship_xl", "apc_ramp", 7)]),
    ("Machine", [("m_walker", "idle"), ("m_colossus", "idle")],
     [("g7_m_packhunter", "idle"), ("g7_m_weaver", "idle")]),
]
S = 3; GAP = 14; PAD = 18; LW = 230; LAB = 34
BG = (78, 92, 58); BG2 = (52, 66, 44)
rows = []
for name, olds, news in ROWS:
    side = []
    for lst in (olds, news):
        side.append([(t[0],) + frame(t[0], t[1], t[2] if len(t) > 2 else 1) for t in lst if t[0] in mans])
    rows.append((name, side))
CW = lambda im: max(im.width * S, 150)
colw = [max(sum(CW(im) + GAP for _, im, _ in r[1][i]) for r in rows) + PAD for i in (0, 1)]
# the dropship row is very wide at 3x: wrap it to two lines of two
rowh = [max(im.height * S for s in r[1] for _, im, _ in s) for r in rows]
true_old = [im for r in rows for _, im, _ in r[1][0]]; true_new = [im for r in rows for _, im, _ in r[1][1]]
th = max(im.height for im in true_old + true_new) + 40
W = max(LW + colw[0] + colw[1] + PAD * 2, SW * 2 + LW)
H = 70 + (SH * 3 + 60) + sum(h + LAB + PAD for h in rowh) + 50 + th * 2 + 30
img = Image.new('RGB', (W, H), BG2); d = ImageDraw.Draw(img)
d.text((LW, 14), "G7 REWORK rev3 (DL7-3): ONE real-world scale, 4 m per tile, 9.8 px per metre of height", fill=(255, 220, 120), font=fb)
d.text((LW, 46), "Scale strip: everything on the same 64x32 tile grid, true size (top) and 2x (below). Outlined diamond = one tile = 4 m x 4 m.", fill=(200, 200, 200), font=fs)
y = 70
d.text((PAD, y + 40), "Scale strip\n(1x)", fill=(255, 255, 255), font=f)
img.paste(strip.convert('RGB'), (LW, y))
for i, (x, t) in enumerate(strip_lab):
    d.text((LW + max(0, x), y + SH - 40 + (i % 2) * 18), t, fill=(255, 255, 255), font=fs)
y += SH + 10
d.text((PAD, y + 120), "Scale strip\n(2x)", fill=(255, 255, 255), font=f)
img.paste(strip.convert('RGB').resize((SW * 2, SH * 2), Image.NEAREST), (LW, y))
y += SH * 2 + 50
x0, x1 = LW, LW + colw[0] + PAD
d.text((x0, y - 36), "TODAY (in game now)", fill=(255, 255, 255), font=fb)
d.text((x1, y - 36), "G7 rev3 (DL7-3, proposed)  - same %dx pixel scale, facing row 1 unless noted" % S, fill=(255, 220, 120), font=fb)
for (name, side), h in zip(rows, rowh):
    d.text((PAD, y + h // 2 - 20), name, fill=(255, 255, 255), font=f)
    for i, xs in enumerate((x0, x1)):
        d.rectangle((xs - 6, y - 6, xs + colw[i] - PAD + 2, y + h + LAB - 4), fill=BG)
        x = xs
        for k, im, fn in side[i]:
            big = im.resize((im.width * S, im.height * S), Image.NEAREST)
            img.paste(big, (x, y + h - big.height), big)
            d.text((x, y + h + 3), k[3:] if k.startswith("g7_") else k, fill=(235, 235, 235), font=fs)
            d.text((x, y + h + 18), "%s  %dpx tall" % (fn, im.height), fill=(190, 190, 190), font=fs)
            x += CW(im) + GAP
    y += h + LAB + PAD
d.text((PAD, y + 10), "Same lineup at TRUE in-game size (zoom 1: 1 sprite px = 1 screen px)", fill=(255, 255, 255), font=f)
y += 46
for lab, lst, col in (("today", true_old, (255, 255, 255)), ("G7 rev3", true_new, (255, 220, 120))):
    d.rectangle((LW - 6, y, W - PAD, y + th - 6), fill=BG)
    d.text((PAD, y + th // 2 - 12), lab, fill=col, font=f)
    x = LW
    for im in lst:
        img.paste(im, (x, y + th - 16 - im.height), im)
        x += im.width + 10
    y += th
img.save(out)
print(out, img.size)
