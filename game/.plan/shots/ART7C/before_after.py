# ART7C before/after contact sheet: python before_after.py <before_art_root> <out.png>
# before = snapshot of assets/art taken before ART7C's pass; after = the live assets/art.
import json, os, sys
from PIL import Image, ImageDraw
HERE = os.path.dirname(os.path.abspath(__file__))
AFTER = os.path.join(HERE, '..', '..', '..', 'assets', 'art')
BEFORE, OUT = sys.argv[1], sys.argv[2]
BG = (74, 92, 58, 255)
def cell(root, spec, sc):
    p = spec.split(':'); grp, bid = p[0], p[1]; st = p[2] if len(p) > 2 else 'rot_0'
    man = json.load(open(os.path.join(root, grp, 'manifest.json')))
    if bid in man.get('buildings', {}):
        im = Image.open(os.path.join(root, grp, man['buildings'][bid]['states'][st]['file'])).convert('RGBA')
    else:
        e = man['vehicles'][bid]; im = Image.open(os.path.join(root, grp, e['file'])).convert('RGBA')
        fi = e['frames'].index(st); row = int(p[3]) if len(p) > 3 else 1
        im = im.crop((fi * e['fw'], row * e['fh'], fi * e['fw'] + e['fw'], row * e['fh'] + e['fh']))
    bb = im.getbbox() or (0, 0, im.width, im.height)
    im = im.crop((max(0, bb[0] - 3), max(0, bb[1] - 3), min(im.width, bb[2] + 3), min(im.height, bb[3] + 3)))
    bg = Image.new('RGBA', im.size, BG); bg.alpha_composite(im)
    return bg.resize((im.width * sc, im.height * sc), Image.NEAREST)
def strip(specs, sc):
    rows = []
    for root in (BEFORE, AFTER):
        cs = [cell(root, s, sc) for s in specs]
        w = sum(c.width + 6 for c in cs); h = max(c.height for c in cs)
        r = Image.new('RGBA', (w, h), (40, 46, 38, 255)); x = 0
        for c in cs:
            r.paste(c, (x, h - c.height)); x += c.width + 6
        rows.append(r)
    return rows
T = ['g7_turrets2:a_t7_' + n for n in ['hmg_nest', 'autocannon', 'hulldown', 'automortar', 'emp', 'thermite', 'microwave', 'railgun']]
SECTIONS = [
    ('Turrets rot_0 at zoom 1 (1 sprite px = 1 screen px): each silhouette now distinct, barrels shown 3/4 not end-on', T, 1),
    ('Turrets rot_0 at 3x', T, 3),
    ('Turret fire: thermite stream (aim_1 / aim_6 / aim_3), hull-down 120 mm, rail', ['g7_turrets2:a_t7_thermite:aim_1_fire', 'g7_turrets2:a_t7_thermite:aim_6_fire', 'g7_turrets2:a_t7_thermite:aim_3_fire', 'g7_turrets2:a_t7_hulldown:aim_6_fire', 'g7_turrets2:a_t7_railgun:aim_2_fire'], 2),
    ('CN facility (A rot_0, B rot_1), tower, checkpoint, blast wall, pop-up at 2x', ['g7_rollout:a_cn_facility', 'g7_rollout:b_cn_facility:rot_1', 'g7_rollout:cn_tower', 'g7_rollout:cn_checkpoint', 'g7_rollout:cn_blast_wall', 'g7_rollout:cn_popup:aim_1'], 2),
    ('CN barrier: edge-on facings 3 / 7 (was a flat line), facing 1, fire', ['g7_rollout:g7_cn_barrier:idle:3', 'g7_rollout:g7_cn_barrier:idle:7', 'g7_rollout:g7_cn_barrier:idle:1', 'g7_rollout:g7_cn_barrier:fire:0'], 4),
]
blocks = []
for title, specs, sc in SECTIONS:
    b, a = strip(specs, sc); blocks.append((title, b, a))
shots = [(os.path.join(HERE, '..', 'ART7B', 'ingame', n), os.path.join(HERE, 'ingame', n)) for n in ['art7b_compound_zoom3.png', 'art7b_turrets_zoom3.png', 'art7b_mixed_zoom1.png']]
W = max(max(b.width, a.width) for _, b, a in blocks) + 110
W = max(W, 1700)
H = sum(b.height + a.height + 40 for _, b, a in blocks) + len(shots) * 520 + 60
out = Image.new('RGBA', (W, H), (30, 34, 30, 255)); d = ImageDraw.Draw(out); y = 8
d.text((8, y), 'ART7C before (top of each pair, ART7B rev3 roll-out) / after (bottom): turret readability + CN facility detail pass', fill=(250, 230, 130)); y += 22
for title, b, a in blocks:
    d.text((8, y), title, fill=(240, 220, 120)); y += 14
    d.text((8, y + 4), 'BEFORE', fill=(220, 140, 120)); out.paste(b, (100, y)); y += b.height + 4
    d.text((8, y + 4), 'AFTER', fill=(140, 230, 140)); out.paste(a, (100, y)); y += a.height + 18
d.text((8, y), 'In game (windowed pt7_art7b flow): before | after', fill=(240, 220, 120)); y += 16
for bp, ap in shots:
    x = 8
    for p in (bp, ap):
        im = Image.open(p).convert('RGBA').crop((0, 40, 1600, 680)); im = im.resize((800, 320))
        out.paste(im, (x, y)); x += 810
    y += 330
out = out.crop((0, 0, W, y + 10)); out.save(OUT); print(OUT, out.size)
