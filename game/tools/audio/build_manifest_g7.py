"""Index the G7 generated audio (owner: AUDIO7): assets/generated/audio7/audio7_manifest.json.

Run after synth_g7.py / render_voice_g7.py:  py -3.13 tools/audio/build_manifest_g7.py
Same shape as the G6.1 manifest ({"sfx": {id: [res paths]}, "radio": {line_id: res path}, "dur", "rms"}) plus
"music": {stem: res path} and "peak": {res path: peak}. presentation/audio/audio_catalog.gd merges it into the
G6.1 manifest at load, so the runtime never lists directories (exported builds can't).
"""
import json
import math
import os
import re
import struct
import wave

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASE = os.path.join(ROOT, "assets", "generated", "audio7")
RES = "res://assets/generated/audio7/"


def stats(path):
    with wave.open(path, "rb") as w:
        n, sr = w.getnframes(), w.getframerate()
        raw = w.readframes(n)
    vals = struct.unpack("<%dh" % (len(raw) // 2), raw)
    rms = math.sqrt(sum(v * v for v in vals[::4]) / max(1, len(vals[::4]))) / 32768.0
    peak = max((abs(v) for v in vals), default=0) / 32768.0
    return round(n / float(sr), 3), round(rms, 4), round(peak, 4)


def main():
    man = {"sfx": {}, "radio": {}, "music": {}, "dur": {}, "rms": {}, "peak": {}}

    def add(res, path):
        man["dur"][res], man["rms"][res], man["peak"][res] = stats(path)

    sdir = os.path.join(BASE, "sfx")
    for fn in sorted(os.listdir(sdir)) if os.path.isdir(sdir) else []:
        m = re.match(r"^(.+)_(\d+)\.wav$", fn)
        if m:
            res = RES + "sfx/" + fn
            man["sfx"].setdefault(m.group(1), []).append(res)
            add(res, os.path.join(sdir, fn))
    for k in man["sfx"]:
        man["sfx"][k].sort(key=lambda p: int(re.search(r"_(\d+)\.wav$", p).group(1)))
    vdir = os.path.join(BASE, "voice")
    for fn in sorted(os.listdir(vdir)) if os.path.isdir(vdir) else []:
        if fn.endswith(".wav"):
            res = RES + "voice/" + fn
            man["radio"][fn[:-4]] = res
            add(res, os.path.join(vdir, fn))
    mdir = os.path.join(BASE, "music")
    for fn in sorted(os.listdir(mdir)) if os.path.isdir(mdir) else []:
        if fn.endswith(".wav"):
            res = RES + "music/" + fn
            man["music"][fn[:-4]] = res
            add(res, os.path.join(mdir, fn))
    with open(os.path.join(BASE, "audio7_manifest.json"), "w", encoding="utf-8") as f:
        json.dump(man, f, indent=1, sort_keys=True)
    silent = [p for p, r in man["rms"].items() if r < 0.005]
    clipped = [p for p, v in man["peak"].items() if v > 0.99]
    print("G7 manifest: %d sfx ids (%d files), %d voice lines, %d music stems, silent: %s, clipped: %s" % (
        len(man["sfx"]), sum(len(v) for v in man["sfx"].values()), len(man["radio"]), len(man["music"]),
        silent or "none", clipped or "none"))


if __name__ == "__main__":
    main()
