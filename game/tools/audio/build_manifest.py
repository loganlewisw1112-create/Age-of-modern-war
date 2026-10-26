"""Index the generated audio (owner: AUDIO61): assets/generated/audio/audio_manifest.json.

Run after synth_sfx.py / render_radio.py:  py -3.13 tools/audio/build_manifest.py
{"sfx": {sound_id: [res paths of its variants]}, "radio": {line_id: res path}, "dur": {res path: seconds},
 "rms": {res path: rms}}. The runtime (presentation/audio/audio_catalog.gd) reads only this file + the line library,
so it never lists directories (exported builds can't).
"""
import json
import math
import os
import re
import wave
import struct

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASE = os.path.join(ROOT, "assets", "generated", "audio")


def stats(path):
    with wave.open(path, "rb") as w:
        n, sr = w.getnframes(), w.getframerate()
        raw = w.readframes(n)
    vals = struct.unpack("<%dh" % (len(raw) // 2), raw)
    rms = math.sqrt(sum(v * v for v in vals[::4]) / max(1, len(vals[::4]))) / 32768.0
    return round(n / float(sr), 3), round(rms, 4)


def main():
    man = {"sfx": {}, "radio": {}, "dur": {}, "rms": {}}
    sdir = os.path.join(BASE, "sfx")
    for fn in sorted(os.listdir(sdir)):
        m = re.match(r"^(.+)_(\d+)\.wav$", fn)
        if not m:
            continue
        res = "res://assets/generated/audio/sfx/" + fn
        man["sfx"].setdefault(m.group(1), []).append(res)
        man["dur"][res], man["rms"][res] = stats(os.path.join(sdir, fn))
    rdir = os.path.join(BASE, "radio")
    for fn in sorted(os.listdir(rdir)):
        if fn.endswith(".wav"):
            res = "res://assets/generated/audio/radio/" + fn
            man["radio"][fn[:-4]] = res
            man["dur"][res], man["rms"][res] = stats(os.path.join(rdir, fn))
    for k in man["sfx"]:
        man["sfx"][k].sort(key=lambda p: int(re.search(r"_(\d+)\.wav$", p).group(1)))
    with open(os.path.join(BASE, "audio_manifest.json"), "w", encoding="utf-8") as f:
        json.dump(man, f, indent=1, sort_keys=True)
    silent = [p for p, r in man["rms"].items() if r < 0.005]
    print("manifest: %d sfx ids (%d files), %d radio lines, silent: %s" % (
        len(man["sfx"]), sum(len(v) for v in man["sfx"].values()), len(man["radio"]), silent or "none"))


if __name__ == "__main__":
    main()
