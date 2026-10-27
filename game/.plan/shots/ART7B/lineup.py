# ART7B scale lineup: python lineup.py <out.png> <ids...>  (facing row 1, frame 0, on one ground line, 3x)
import json, sys, os
from PIL import Image
A = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'assets')
base = json.load(open(os.path.join(A, 'generated', 'manifest.json')))
GR = ['g7_cn', 'g7_threats', 'g7_threats2', 'drone7', 'g7_rollout', 'g6_units', 'g5_units', 'g5_air']
def spec(uid):
    for g in GR:
        p = os.path.join(A, 'art', g, 'manifest.json')
        if not os.path.exists(p): continue
        m = json.load(open(p))
        for sec in ('vehicles', 'infantry'):
            if uid in m.get(sec, {}): e = m[sec][uid]; return os.path.join(A, 'art', g, e['file']), e
    for sec in ('vehicles', 'infantry'):
        if uid in base.get(sec, {}): e = base[sec][uid]; return os.path.join(A, 'generated', e['file']), e
cells = []
for u in sys.argv[2:]:
    r = spec(u)
    if not r: print('missing', u); continue
    f, e = r; im = Image.open(f).convert('RGBA'); fw, fh = e['fw'], e['fh']
    c = im.crop((0, fh, fw, 2 * fh)); bb = c.getbbox()
    print(u, 'frame', fw, fh, 'opaque w x h', (bb[2] - bb[0], bb[3] - bb[1]) if bb else 0)
    cells.append((u, c, e['pivot']))
W = sum(c.width for _, c, _ in cells) + 12 * len(cells) + 10; H = 170
out = Image.new('RGBA', (W, H), (74, 92, 58, 255)); x = 10
for u, c, pv in cells:
    out.alpha_composite(c, (x, 140 - pv[1])); x += c.width + 12
out.resize((W * 3, H * 3), Image.NEAREST).save(sys.argv[1])
