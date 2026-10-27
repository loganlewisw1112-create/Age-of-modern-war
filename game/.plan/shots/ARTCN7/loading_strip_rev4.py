"""Loading strip rev4 (ARTCN7-5): both VTOLs x 8 facings x key load frames, straight from the shipped sheets,
team-tinted, on grass, at 1x and 2x.   python -I loading_strip_rev4.py <game dir> <out_prefix>"""
import json, os, sys
from PIL import Image, ImageDraw
root, outp = sys.argv[1], sys.argv[2]
base = os.path.join(root, 'assets/art/g7_cn')
man = json.load(open(os.path.join(base, 'manifest.json')))['vehicles']
TEAM = (70, 130, 230)
COLS = [('_apcload', 'apc_load_0'), ('_apcload', 'apc_load_2'), ('_apcload', 'apc_load_3'), ('_apcload', 'apc_load_4'),
        ('_apcload', 'apc_load_5'), ('_squadload', 'squad_load_0'), ('_squadload', 'squad_load_2'), ('_squadunload', 'squad_unload_1')]
def cell(id_, fname, k):
    e = man[id_]; fw, fh = e['fw'], e['fh']; c = e['frames'].index(fname)
    im = Image.open(os.path.join(base, e['file'])).convert('RGBA').crop((c*fw, k*fh, c*fw+fw, k*fh+fh))
    mk = Image.open(os.path.join(base, e['mask'])).convert('RGBA').crop((c*fw, k*fh, c*fw+fw, k*fh+fh))
    px, mp = im.load(), mk.load()
    for y in range(fh):
        for x in range(fw):
            if mp[x, y][3] > 0 and px[x, y][3] > 0:
                l = px[x, y][0] / 255.0
                px[x, y] = tuple(min(255, int(t * l * 1.25)) for t in TEAM) + (px[x, y][3],)
    return im
W, H = 412, 256   # full load cell (pivot 206,144)
out = Image.new('RGB', (len(COLS) * W * 2 + 90, 8 * H + 40), (40, 52, 34))
d = ImageDraw.Draw(out)
for a, craft in enumerate(['g7_cn_stealth_dropship', 'g7_a_vtol_dropship_xl']):
    x0 = 90 + a * len(COLS) * W
    for j, (suf, fn) in enumerate(COLS):
        d.text((x0 + j * W + 6, 6), ('stealth ' if a == 0 else 'XL ') + fn, fill=(255, 220, 120))
        d.text((x0 + j * W + 6, 20), suf[1:], fill=(200, 200, 200))
        for k in range(8):
            bg = Image.new('RGBA', (W, H), (78, 92, 58, 255) if (j + k) % 2 == 0 else (72, 86, 52, 255))
            im = cell(craft + suf, fn, k)
            bg.alpha_composite(im)
            out.paste(bg.convert('RGB'), (x0 + j * W, 40 + k * H))
for k in range(8):
    d.text((8, 40 + k * H + H // 2), 'facing %d' % k, fill=(255, 255, 255))
out.save(outp + '.png')
out.resize((out.width * 2, out.height * 2), Image.NEAREST).save(outp + '_2x.png')
print(out.size)
