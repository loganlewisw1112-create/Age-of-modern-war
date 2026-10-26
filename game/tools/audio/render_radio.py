"""G6.1 radio line renderer (owner: AUDIO61).

Reads content/g6/audio_lines_g61.json (_audio.lines), renders each line with Windows SAPI through sapi_render.ps1
(installed voices only: Microsoft David Desktop / Microsoft Zira Desktop), then applies the radio chain in pure
Python: pitch shift, band-pass 300-3400 Hz, light distortion, static bed, squelch click in / out. Machine speakers get
the synthetic chain instead (ring modulation, bit crush, comb, data chirp).

Run (re-runnable; pass line ids to re-render only those):  py -3.13 tools/audio/render_radio.py [id ...]
Output: assets/generated/audio/radio/<id>.wav (16-bit PCM, 22.05 kHz, mono).
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

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
LINES = os.path.join(ROOT, "content", "g6", "audio_lines_g61.json")
OUT = os.path.join(ROOT, "assets", "generated", "audio", "radio")


def trim(x, thr=0.01):
    i = 0
    while i < len(x) and abs(x[i]) < thr:
        i += 1
    j = len(x)
    while j > i and abs(x[j - 1]) < thr:
        j -= 1
    return x[max(0, i - 200): min(len(x), j + 400)]


def squelch(r, sec, kind):
    if kind == "in":
        return gain(mix(env_exp(bandpass(noise(0.07, r), 500, 3000), 0.05, 0.001), (0.6, env_exp(square(0.02, 1250), 0.02))), 0.5)
    k = env_adsr(bandpass(noise(0.15, r), 700, 3200), 0.002, 0.03, 0.6, 0.06)
    return gain(k, 0.55)


def radio_chain(x, r):
    x = bandpass(bandpass(x, 300, 3400), 320, 3200)
    x = normalize(x, 0.9)
    x = drive(x, 2.6)
    x = crush(x, 12, 1)
    bed = gain(bandpass(noise(len(x) / SR, r), 400, 3000), 0.045)
    for _ in range(int(len(x) / SR * 6)):
        i = r.randrange(0, max(1, len(bed) - 40))
        for k in range(min(40, len(bed) - i)):
            bed[i + k] += r.uniform(-1, 1) * 0.12
    voice = mix(x, bed)
    return concat(squelch(r, 0.07, "in"), silence(0.03), voice, squelch(r, 0.15, "out"))


def machine_chain(x, r):
    x = normalize(x, 0.9)
    rm = ringmod(x, 55.0)
    x = mix((0.55, x), (0.6, rm))
    d = int(0.011 * SR)
    comb = list(x)
    for i in range(d, len(comb)):
        comb[i] += comb[i - d] * 0.45
    x = crush(bandpass(comb, 180, 5200), 6, 2)
    f = r.uniform(1100, 1400)
    chirp = gain(crush(env_exp(sine(0.09, f, f * 2.0), 0.08), 5, 3), 0.5)
    return concat(chirp, silence(0.04), normalize(x, 0.85), silence(0.05), gain(list(reversed(chirp)), 0.6))


def load_lib():
    with open(LINES, encoding="utf-8") as f:
        return json.load(f)["_audio"]


def prepare(tmp, only):
    """Write tmp/jobs.tsv (one SAPI job per line) and return the lines to render."""
    lib = load_lib()
    os.makedirs(tmp, exist_ok=True)
    todo = [ln for ln in lib["lines"] if not only or ln["id"] in only]
    jobs = []
    for ln in todo:
        sp = lib["speakers"][ln["speaker"]]
        raw = os.path.join(tmp, ln["id"] + ".wav")
        jobs.append("%s\t%s\t%d\t%s" % (raw, sp["voice"], int(sp.get("rate", 0)), ln["text"].replace("\t", " ")))
    with open(os.path.join(tmp, "jobs.tsv"), "w", encoding="utf-8") as f:
        f.write("\n".join(jobs) + "\n")
    return todo


def finish(tmp, only):
    """Apply the radio / machine chain to every raw SAPI wav in tmp and write the shipped files."""
    lib = load_lib()
    os.makedirs(OUT, exist_ok=True)
    n = 0
    for ln in lib["lines"]:
        if only and ln["id"] not in only:
            continue
        sp = lib["speakers"][ln["speaker"]]
        raw = os.path.join(tmp, ln["id"] + ".wav")
        if not os.path.exists(raw):
            print("MISSING SAPI output for", ln["id"])
            continue
        r = random.Random(zlib.crc32(ln["id"].encode()))
        x = trim(read_wav(raw))
        pitch = float(sp.get("pitch", 1.0))
        if abs(pitch - 1.0) > 1e-3:
            x = resample(x, pitch)
        x = machine_chain(x, r) if sp.get("fx") == "machine" else radio_chain(x, r)
        write_wav(os.path.join(OUT, ln["id"] + ".wav"), normalize(fade(x, 0.001, 0.02), 0.85))
        n += 1
    print("radio lines written:", n, "->", OUT)


def main():
    """No flag: prepare + SAPI (powershell -File sapi_render.ps1) + finish in one go.
    Split mode (when script execution is restricted): --prepare DIR, then run the SAPI loop of sapi_render.ps1 on
    DIR/jobs.tsv from any PowerShell, then --finish DIR."""
    args = sys.argv[1:]
    if args and args[0] in ("--prepare", "--finish"):
        only = set(args[2:])
        if args[0] == "--prepare":
            print("jobs:", len(prepare(args[1], only)), "->", os.path.join(args[1], "jobs.tsv"))
        else:
            finish(args[1], only)
        return
    only = set(args)
    tmp = tempfile.mkdtemp(prefix="audio61_sapi_")
    prepare(tmp, only)
    res = subprocess.run(["powershell", "-NoProfile", "-File", os.path.join(HERE, "sapi_render.ps1"),
                          os.path.join(tmp, "jobs.tsv")], capture_output=True, text=True)
    print(res.stdout.strip(), res.stderr.strip()[:500])
    finish(tmp, only)


if __name__ == "__main__":
    main()
