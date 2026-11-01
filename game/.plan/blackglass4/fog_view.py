"""Mist + fog presentation views of Site Blackglass, composited from the rendered art layers (pieces.json).

The game renderer has no volumetric fog, so this is an offline grade: mist banks are inserted BETWEEN the mountain
layers and the compound layers (they wrap the cliffs and cove walls but sit behind the buildings), low valley fog and
side banks roll in over everything at the bottom / edges, cold haze swallows the distant peaks, light snowfall on top.
Output: fog_full.jpg (whole site) and fog_face.jpg (full-res close view of the face + airfield).
"""
import json, os, random
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, "art")
META = json.load(open(os.path.join(ART, "pieces.json")))
OUT = os.environ.get("FOG_OUT", HERE)
MIST = (226, 231, 238)


def keys_for(view):
    ks = [k for k, v in META.items() if v.get("view", "both") in ("both", view)]
    return sorted(ks, key=lambda k: float(META[k]["ord"]))


def bounds(ks):
    mnx = min(-META[k]["origin"][0] for k in ks); mny = min(-META[k]["origin"][1] for k in ks)
    mxx = max(-META[k]["origin"][0] + META[k]["w"] for k in ks); mxy = max(-META[k]["origin"][1] + META[k]["h"] for k in ks)
    return mnx, mny, mxx, mxy


def noise(w, h, cell, seed, blur):
    random.seed(seed)
    sw, sh = max(2, w // cell), max(2, h // cell)
    sm = Image.new("L", (sw, sh))
    sm.putdata([random.randint(0, 255) for _ in range(sw * sh)])
    return sm.resize((w, h), Image.BICUBIC).filter(ImageFilter.GaussianBlur(blur))


def clouds(w, h, seed, s):
    a = noise(w, h, int(260 * s), seed, 30 * s)
    b = noise(w, h, int(90 * s), seed + 1, 12 * s)
    c = ImageChops.add(a.point(lambda v: v * 0.7), b.point(lambda v: v * 0.3))
    return c.point(lambda v: max(0, min(255, int((v - 105) * 2.6))))   # contrast: patchy banks with clear gaps


def vgrad(w, h, y0, y1, invert=False):
    g = Image.new("L", (1, h))
    for y in range(h):
        t = 0.0 if y <= y0 else (1.0 if y >= y1 else (y - y0) / max(1, y1 - y0))
        g.putpixel((0, y), int(255 * ((1 - t) if invert else t)))
    return g.resize((w, h))


def compose(view, scale, crop=None):
    ks = keys_for(view)
    mnx, mny, mxx, mxy = bounds(ks)
    W, H = int((mxx - mnx) * scale), int((mxy - mny) * scale)
    cx0, cy0, cx1, cy1 = crop if crop else (0, 0, W, H)
    cw, ch = cx1 - cx0, cy1 - cy0
    back, front, mtn = Image.new("RGBA", (cw, ch), (0, 0, 0, 0)), Image.new("RGBA", (cw, ch), (0, 0, 0, 0)), Image.new("L", (cw, ch), 0)
    for k in ks:
        m = META[k]
        if k == "overlay":
            continue
        im = Image.open(os.path.join(ART, m["file"])).convert("RGBA")
        if scale != 1.0:
            im = im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))), Image.LANCZOS)
        at = (int((-m["origin"][0] - mnx) * scale) - cx0, int((-m["origin"][1] - mny) * scale) - cy0)
        if at[0] > cw or at[1] > ch or at[0] + im.width < 0 or at[1] + im.height < 0:
            continue
        layer = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
        layer.paste(im, at)
        if float(m["ord"]) < 0:            # terrain, summit, ground: the "back" stack (mist goes in front of it)
            back = Image.alpha_composite(back, layer)
            if not k.startswith("ground"):
                mtn = ImageChops.lighter(mtn, layer.getchannel("A"))
        else:
            front = Image.alpha_composite(front, layer)
    return back, front, mtn, (W, H, cx0, cy0)


def grade(view, scale, crop, name, strength=1.0):
    back, front, mtn, (W, H, cx0, cy0) = compose(view, scale, crop)
    w, h = back.size
    s = scale
    # sky: cold overcast gradient
    sky = Image.new("RGB", (w, h))
    dsky = ImageDraw.Draw(sky)
    for y in range(h):
        t = (y + cy0) / H
        dsky.line([(0, y), (w, y)], fill=(int(128 + 70 * t), int(138 + 68 * t), int(152 + 62 * t)))
    img = Image.alpha_composite(sky.convert("RGBA"), back)
    # mist banks on the mountain: stronger low on the cliffs, patchy, behind the compound
    full_low = vgrad(W, H, int(H * 0.12), int(H * 0.62)).crop((cx0, cy0, cx0 + w, cy0 + h)) if crop else vgrad(w, h, int(h * 0.12), int(h * 0.62))
    cl = clouds(w, h, 7, s)
    a = ImageChops.multiply(ImageChops.multiply(mtn, full_low), cl).point(lambda v: int(v * 0.85 * strength))
    img = Image.composite(Image.new("RGBA", (w, h), MIST + (255,)), img, a)
    # thin wisps drifting across the summit deck edge (in front of the deck, behind nothing on the ground)
    wisp = ImageChops.multiply(clouds(w, h, 11, s * 0.6), mtn).point(lambda v: int(v * 0.25 * strength))
    img = Image.composite(Image.new("RGBA", (w, h), MIST + (255,)), img, wisp)
    img = Image.alpha_composite(img, front)
    # valley fog rolling in at the base + side banks
    bot = vgrad(W, H, int(H * 0.70), int(H * 0.98)).crop((cx0, cy0, cx0 + w, cy0 + h)) if crop else vgrad(w, h, int(h * 0.70), int(h * 0.98))
    fogb = ImageChops.multiply(bot, clouds(w, h, 23, s)).point(lambda v: int(v * 0.8 * strength))
    img = Image.composite(Image.new("RGBA", (w, h), MIST + (255,)), img, fogb)
    side = Image.new("L", (w, h), 0)
    ds = ImageDraw.Draw(side)
    for x in range(w):
        gx = x + cx0
        t = max(0.0, 1.0 - min(gx, W - gx) / (W * 0.16))
        ds.line([(x, 0), (x, h)], fill=int(255 * t))
    img = Image.composite(Image.new("RGBA", (w, h), MIST + (255,)), img, ImageChops.multiply(side, clouds(w, h, 31, s)).point(lambda v: int(v * 0.7 * strength)))
    # cold haze over the distant peaks (top) + overall atmospheric grade
    top = vgrad(W, H, int(H * 0.02), int(H * 0.40), invert=True).crop((cx0, cy0, cx0 + w, cy0 + h)) if crop else vgrad(w, h, int(h * 0.02), int(h * 0.40), invert=True)
    img = Image.composite(Image.new("RGBA", (w, h), (200, 208, 220, 255)), img, top.point(lambda v: int(v * 0.42 * strength)))
    img = img.convert("RGB")
    img = ImageEnhance.Color(img).enhance(0.78)
    img = Image.blend(img, Image.new("RGB", (w, h), (178, 190, 206)), 0.10 * strength)
    img = ImageEnhance.Contrast(img).enhance(1.06)
    # light snowfall
    random.seed(5)
    d = ImageDraw.Draw(img, "RGBA")
    for _ in range(int(w * h / (900 / max(0.25, s)))):
        x, y = random.randint(0, w - 1), random.randint(0, h - 1)
        r = random.choice((1, 1, 1, 2)) * max(1, int(s * 2))
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, random.randint(90, 200)))
    img.save(os.path.join(OUT, name), quality=92)
    print(name, img.size)


if __name__ == "__main__":
    grade("full", 0.5, None, "fog_full.jpg")
    # full-res close view: the face, the core and the airfield (canvas window in full-scale pixels)
    ks = keys_for("full")
    mnx, mny, mxx, mxy = bounds(ks)
    Wf, Hf = int(mxx - mnx), int(mxy - mny)
    grade("full", 1.0, (int(Wf * 0.13), int(Hf * 0.20), int(Wf * 0.62), int(Hf * 0.66)), "fog_face.jpg")
