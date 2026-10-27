"""G7 voice renderer (owner: AUDIO7). Same pipeline as G6.1 render_radio.py: Windows SAPI (installed desktop voices
only, sapi_render.ps1) + pure-Python processing. Nothing is downloaded or sampled.

Library: presentation/audio/audio_lines_g7.json
  - barks: {pers: {kind: [texts]}} -> one file per text per voice: b7_<pers>_<kind>_<i>_v<voice>.wav
    (speaker <pers>_<voice>, radio chain: operators are heard over the team net)
  - lines: command acks / HQ / PROTOCOL (speaker fx "radio" or "protocol": clean synthetic facility-AI chain)
Run (re-runnable, deterministic chains):  py -3.13 tools/audio/render_voice_g7.py [id ...]
Split mode: --prepare DIR / --finish DIR (as render_radio.py). Output: assets/generated/audio7/voice/<id>.wav
"""
import json
import os
import random
import subprocess
import sys
import tempfile
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dsp import *  # noqa: E402,F401,F403
import render_radio as rr  # noqa: E402  (trim, radio_chain)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
LIB = os.path.join(ROOT, "presentation", "audio", "audio_lines_g7.json")
OUT = os.path.join(ROOT, "assets", "generated", "audio7", "voice")


def load_lib():
    with open(LIB, encoding="utf-8") as f:
        return json.load(f)


def expand(lib):
    """Every renderable line: [{id, speaker, text}] (barks expanded per voice)."""
    out = []
    nv = int(lib.get("voices_per_pers", 2))
    for pers, kinds in sorted(lib["barks"].items()):
        for kind, texts in sorted(kinds.items()):
            for i, t in enumerate(texts):
                for v in range(nv):
                    out.append({"id": "b7_%s_%s_%d_v%d" % (pers, kind, i, v), "speaker": "%s_%d" % (pers, v), "text": t})
    for ln in lib["lines"]:
        out.append({"id": ln["id"], "speaker": ln["speaker"], "text": ln["text"]})
    return out


def protocol_chain(x, r):
    """Facility AI: clean (no static), slight detune chorus + soft ring mod shimmer, a two-tone chime in front."""
    x = normalize(x, 0.9)
    d = int(0.017 * SR)
    ch = list(x)
    for i in range(d, len(ch)):
        ch[i] = ch[i] * 0.8 + x[i - d] * 0.35
    rm = ringmod(x, 30.0)
    x = mix((1.0, highpass(ch, 140)), (0.12, rm))
    x = lowpass(x, 6500)
    chime = concat(env_exp(sine(0.11, 1046.5), 0.1), env_exp(sine(0.16, 1568.0), 0.15))
    return concat(gain(chime, 0.35), silence(0.06), normalize(x, 0.85), silence(0.05))


def prepare(tmp, only):
    lib = load_lib()
    os.makedirs(tmp, exist_ok=True)
    todo = [ln for ln in expand(lib) if not only or ln["id"] in only]
    jobs = []
    for ln in todo:
        sp = lib["speakers"][ln["speaker"]]
        raw = os.path.join(tmp, ln["id"] + ".wav")
        jobs.append("%s\t%s\t%d\t%s" % (raw, sp["voice"], int(sp.get("rate", 0)), ln["text"].replace("\t", " ")))
    with open(os.path.join(tmp, "jobs.tsv"), "w", encoding="utf-8") as f:
        f.write("\n".join(jobs) + "\n")
    return todo


def finish(tmp, only):
    lib = load_lib()
    os.makedirs(OUT, exist_ok=True)
    n = 0
    for ln in expand(lib):
        if only and ln["id"] not in only:
            continue
        sp = lib["speakers"][ln["speaker"]]
        raw = os.path.join(tmp, ln["id"] + ".wav")
        if not os.path.exists(raw):
            print("MISSING SAPI output for", ln["id"])
            continue
        r = random.Random(zlib.crc32(("g7:" + ln["id"]).encode()))
        x = rr.trim(read_wav(raw))
        pitch = float(sp.get("pitch", 1.0))
        if abs(pitch - 1.0) > 1e-3:
            x = resample(x, pitch)
        x = protocol_chain(x, r) if sp.get("fx") == "protocol" else rr.radio_chain(x, r)
        write_wav(os.path.join(OUT, ln["id"] + ".wav"), normalize(fade(x, 0.001, 0.02), 0.85))
        n += 1
    print("G7 voice lines written:", n, "->", OUT)


def main():
    args = sys.argv[1:]
    if args and args[0] in ("--prepare", "--finish"):
        only = set(args[2:])
        if args[0] == "--prepare":
            print("jobs:", len(prepare(args[1], only)), "->", os.path.join(args[1], "jobs.tsv"))
        else:
            finish(args[1], only)
        return
    only = set(args)
    tmp = tempfile.mkdtemp(prefix="audio7_sapi_")
    prepare(tmp, only)
    res = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                          os.path.join(HERE, "sapi_render.ps1"), os.path.join(tmp, "jobs.tsv")],
                         capture_output=True, text=True)
    print(res.stdout.strip(), res.stderr.strip()[:500])
    finish(tmp, only)


if __name__ == "__main__":
    main()
