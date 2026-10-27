# ART7B contact sheets: python sheet.py <group> <out.png> [scale] [ids...]
# Buildings: rot_0..3, fire, damaged, build_0..2, aim_* / extras (first 10) on a 64x32 tile grid, with a rev3
# soldier (18 px) for scale. Units: facing rows 0..7 x frames.
import json, sys, os
from PIL import Image, ImageDraw
ROOT = os.path.join(os.path.dirname(__file__), '..', '..', '..', 'assets', 'art')
grp, outp = sys.argv[1], sys.argv[2]
sc = int(sys.argv[3]) if len(sys.argv) > 3 else 2
only = sys.argv[4:]
man = json.load(open(os.path.join(ROOT, grp, 'manifest.json')))
sold = Image.open(os.path.join(ROOT, 'g7_cn', 'units', 'g7_cn_gunner.png')).crop((0, 32, 32, 64))
BG = (74, 92, 58, 255)
def grid(w, h, ox, oy):
    im = Image.new('RGBA', (w, h), BG); d = ImageDraw.Draw(im)
    for k in range(-40, 40):
        d.line([(ox + k * 32 - 400, oy - 200 + 0), (ox + k * 32 + 400, oy + 200)], fill=(84, 102, 66), width=1)
        d.line([(ox + k * 32 + 400, oy - 200), (ox + k * 32 - 400, oy + 200)], fill=(84, 102, 66), width=1)
    return im
rows = []
for sec in ('buildings',):
    for bid, e in sorted(man.get(sec, {}).items()):
        if only and bid not in only: continue
        st = e['states']; names = [n for n in ['rot_0', 'rot_1', 'rot_2', 'rot_3', 'rot_0_fire', 'rot_0_damaged', 'rot_0_build_0', 'rot_0_build_1', 'rot_0_build_2'] if n in st]
        names += [n for n in st if not n.startswith('rot_') and n not in ('built', 'damaged', 'fire', 'build_0', 'build_1', 'build_2')][:12]
        cells = []
        for n in names:
            im = Image.open(os.path.join(ROOT, grp, st[n]['file'])).convert('RGBA')
            px, py = e['pivot']
            bg = grid(im.width, im.height, px, py); bg.alpha_composite(im)
            if n == 'rot_0':
                bg.alpha_composite(sold, (min(im.width - 32, px + e['size'] * 32 - 20), py - 27 + e['size'] * 8))
            cells.append((n, bg.resize((im.width * sc, im.height * sc), Image.NEAREST)))
        rows.append((bid, cells))
for sec in ('vehicles', 'infantry'):
    for uid, e in sorted(man.get(sec, {}).items()):
        if only and uid not in only: continue
        if 'alias_of' in e: continue
        im = Image.open(os.path.join(ROOT, grp, e['file'])).convert('RGBA')
        bg = Image.new('RGBA', im.size, BG); bg.alpha_composite(im)
        rows.append((uid + ' ' + ','.join(e['frames']), [('sheet', bg.resize((im.width * sc, im.height * sc), Image.NEAREST))]))
W = max([sum(c[1].width + 6 for c in r[1]) for r in rows] + [400]) + 10
H = sum(max(c[1].height for c in r[1]) + 22 for r in rows) + 10
out = Image.new('RGBA', (W, H), (40, 46, 38, 255)); d = ImageDraw.Draw(out); y = 5
for name, cells in rows:
    d.text((5, y), name, fill=(240, 220, 120)); y += 12; x = 5
    for n, c in cells:
        out.paste(c, (x, y)); d.text((x + 2, y + 2), n, fill=(255, 255, 255)); x += c.width + 6
    y += max(c.height for _, c in cells) + 10
out.save(outp); print('sheet', outp, out.size)
