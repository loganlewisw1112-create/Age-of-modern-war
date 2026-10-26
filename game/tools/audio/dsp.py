"""Tiny pure-Python DSP kit for the G6.1 audio generator (owner: AUDIO61).

No third-party packages: stdlib only (math, random, struct, wave). Signals are plain lists of floats in
[-1, 1] at SR Hz. Every generator takes an explicit random.Random so a re-run is byte-identical.
"""
import math
import random
import struct
import wave

SR = 22050


def n_samples(sec):
    return max(1, int(sec * SR))


def silence(sec):
    return [0.0] * n_samples(sec)


def noise(sec, rng):
    return [rng.uniform(-1.0, 1.0) for _ in range(n_samples(sec))]


def brown(sec, rng, k=0.02):
    out, v = [], 0.0
    for _ in range(n_samples(sec)):
        v = (v + rng.uniform(-1.0, 1.0) * k) * 0.998
        out.append(v)
    return normalize(out, 0.9)


def sine(sec, f0, f1=None, phase=0.0):
    """Sine with a linear (f0 -> f1) frequency glide."""
    f1 = f0 if f1 is None else f1
    n = n_samples(sec)
    out, ph = [], phase
    for i in range(n):
        f = f0 + (f1 - f0) * i / n
        ph += 2.0 * math.pi * f / SR
        out.append(math.sin(ph))
    return out


def saw(sec, f0, f1=None):
    f1 = f0 if f1 is None else f1
    n = n_samples(sec)
    out, ph = [], 0.0
    for i in range(n):
        f = f0 + (f1 - f0) * i / n
        ph = (ph + f / SR) % 1.0
        out.append(2.0 * ph - 1.0)
    return out


def square(sec, f, duty=0.5):
    n = n_samples(sec)
    return [1.0 if ((i * f / SR) % 1.0) < duty else -1.0 for i in range(n)]


def env_exp(x, decay, attack=0.002):
    """Exponential decay envelope (decay = seconds to -60 dB), short linear attack."""
    a = max(1, int(attack * SR))
    k = math.log(1000.0) / max(1e-4, decay * SR)
    return [s * (min(1.0, i / a) * math.exp(-k * i)) for i, s in enumerate(x)]


def env_adsr(x, a, d, s_lvl, r):
    n = len(x)
    ai, di, ri = int(a * SR), int(d * SR), int(r * SR)
    out = []
    for i, s in enumerate(x):
        if i < ai:
            g = i / max(1, ai)
        elif i < ai + di:
            g = 1.0 - (1.0 - s_lvl) * (i - ai) / max(1, di)
        elif i < n - ri:
            g = s_lvl
        else:
            g = s_lvl * max(0.0, (n - i) / max(1, ri))
        out.append(s * g)
    return out


def lowpass(x, fc):
    """One-pole low-pass."""
    a = math.exp(-2.0 * math.pi * fc / SR)
    out, y = [], 0.0
    for s in x:
        y = (1.0 - a) * s + a * y
        out.append(y)
    return out


def highpass(x, fc):
    lp = lowpass(x, fc)
    return [s - l for s, l in zip(x, lp)]


def biquad(x, kind, fc, q=0.707):
    """RBJ biquad: kind in lp, hp, bp."""
    w0 = 2.0 * math.pi * min(fc, SR * 0.45) / SR
    al = math.sin(w0) / (2.0 * q)
    c = math.cos(w0)
    if kind == "lp":
        b0, b1, b2 = (1 - c) / 2, 1 - c, (1 - c) / 2
    elif kind == "hp":
        b0, b1, b2 = (1 + c) / 2, -(1 + c), (1 + c) / 2
    else:
        b0, b1, b2 = al, 0.0, -al
    a0, a1, a2 = 1 + al, -2 * c, 1 - al
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    out = []
    x1 = x2 = y1 = y2 = 0.0
    for s in x:
        y = b0 * s + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, s, y1, y
        out.append(y)
    return out


def bandpass(x, lo, hi):
    return biquad(biquad(x, "hp", lo), "lp", hi)


def drive(x, k):
    """Soft clip (tanh) distortion; k = pre-gain."""
    t = math.tanh(k)
    return [math.tanh(s * k) / t for s in x]


def crush(x, bits, hold):
    q = float(2 ** (bits - 1))
    out, v = [], 0.0
    for i, s in enumerate(x):
        if i % hold == 0:
            v = round(s * q) / q
        out.append(v)
    return out


def ringmod(x, f):
    return [s * math.sin(2.0 * math.pi * f * i / SR) for i, s in enumerate(x)]


def mix(*parts):
    """Sum signals (pairs of (gain, signal) or bare signals), length = longest."""
    sigs = [(p if isinstance(p, tuple) else (1.0, p)) for p in parts]
    n = max(len(s) for _, s in sigs)
    out = [0.0] * n
    for g, s in sigs:
        for i, v in enumerate(s):
            out[i] += g * v
    return out


def concat(*parts):
    out = []
    for p in parts:
        out.extend(p)
    return out


def offset(x, sec):
    return silence(sec) + x


def gain(x, g):
    return [s * g for s in x]


def normalize(x, peak=0.89):
    m = max((abs(s) for s in x), default=0.0)
    return x if m < 1e-9 else [s * peak / m for s in x]


def fade(x, fin=0.003, fout=0.01):
    n = len(x)
    a, b = max(1, int(fin * SR)), max(1, int(fout * SR))
    return [s * min(1.0, i / a, (n - 1 - i) / b) for i, s in enumerate(x)]


def echo(x, delay, fb, n_taps=4, damp=2500.0):
    """Feedback echo tail (cheap 'space' for distant sounds)."""
    d = int(delay * SR)
    out = x + [0.0] * (d * n_taps)
    for t in range(1, n_taps + 1):
        tap = lowpass(x, damp / t)
        g = fb ** t
        for i, s in enumerate(tap):
            out[i + d * t] += s * g
    return out


def loopable(x, xfade=0.15):
    """Crossfade the tail into the head so the clip loops without a click."""
    k = int(xfade * SR)
    if k * 2 >= len(x):
        return x
    body = x[: len(x) - k]
    for i in range(k):
        t = i / k
        body[i] = body[i] * t + x[len(x) - k + i] * (1.0 - t)
    return body


def resample(x, ratio):
    """Linear-interpolation resample: ratio > 1 = higher pitch and shorter."""
    n = int(len(x) / ratio)
    out = []
    for i in range(n):
        p = i * ratio
        j = int(p)
        f = p - j
        a = x[j] if j < len(x) else 0.0
        b = x[j + 1] if j + 1 < len(x) else 0.0
        out.append(a + (b - a) * f)
    return out


def write_wav(path, x, sr=SR):
    data = bytearray()
    for s in x:
        data += struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(bytes(data))


def read_wav(path):
    with wave.open(path, "rb") as w:
        sr, ch, sw = w.getframerate(), w.getnchannels(), w.getsampwidth()
        raw = w.readframes(w.getnframes())
    if sw != 2:
        raise ValueError("16-bit wav expected: " + path)
    vals = struct.unpack("<%dh" % (len(raw) // 2), raw)
    if ch > 1:
        vals = vals[::ch]
    x = [v / 32768.0 for v in vals]
    if sr != SR:
        x = resample(x, sr / SR)
    return x
