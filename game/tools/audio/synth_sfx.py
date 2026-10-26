"""G6.1 battle-sound generator (owner: AUDIO61). Procedural only: nothing is downloaded or sampled.

Run (re-runnable, deterministic):  py -3.13 tools/audio/synth_sfx.py
Writes assets/generated/audio/sfx/<id>_<n>.wav (16-bit PCM, 22.05 kHz, mono). build_manifest.py then indexes them.
"""
import os
import random
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dsp import *  # noqa: E402,F401,F403

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "generated", "audio", "sfx")


def crack(r, hp=900.0, dec=0.07, body=110.0):
    """Muzzle crack: bright noise transient + a short low body thump."""
    t = env_exp(highpass(noise(0.25, r), hp), dec * r.uniform(0.8, 1.2), 0.0005)
    b = env_exp(sine(0.2, body * r.uniform(0.9, 1.1), body * 0.45), 0.09)
    return drive(mix((1.0, t), (0.7, b)), 2.2)


def tail(r, sec, lp, level):
    return gain(env_exp(lowpass(noise(sec, r), lp), sec, 0.01), level)


def boom(r, sec, lp, f0, deb=0.0):
    base = env_exp(lowpass(lowpass(noise(sec, r), lp), lp * 1.4), sec * 0.85, 0.004)
    sub = env_exp(sine(sec, f0 * r.uniform(0.9, 1.1), f0 * 0.5), sec * 0.6, 0.003)
    parts = [(1.0, base), (0.9, sub)]
    if deb > 0.0:
        d = [0.0] * n_samples(sec)
        for _ in range(int(deb)):
            i = r.randrange(int(0.08 * SR), len(d) - 400)
            for k in range(300):
                d[i + k] += r.uniform(-1, 1) * (1.0 - k / 300.0) * r.uniform(0.2, 0.6)
        parts.append((0.35, highpass(d, 1500)))
    return drive(mix(*parts), 1.6)


def rifle(r):
    return mix(crack(r), offset(tail(r, 0.35, 1800, 0.25), 0.02))


def mg(r):
    out = silence(0.0)
    n, gap = r.randint(4, 6), r.uniform(0.07, 0.085)
    out = silence(gap * n + 0.4)
    for i in range(n):
        s = crack(r, 1000, 0.05, 130)
        st = int((i * gap + r.uniform(-0.004, 0.004)) * SR) if i else 0
        for k, v in enumerate(s):
            if st + k < len(out):
                out[st + k] += v * r.uniform(0.75, 1.0)
    return mix(out, (0.3, offset(tail(r, 0.5, 1500, 1.0), gap * n)))


def sniper(r):
    return mix(crack(r, 700, 0.1, 90), offset(echo(tail(r, 0.3, 1400, 0.5), 0.18, 0.45), 0.03))


def cannon(r):
    return mix(gain(crack(r, 500, 0.06, 70), 0.8), boom(r, 1.1, 500, 70), (0.4, offset(tail(r, 0.8, 600, 1.0), 0.1)))


def autocannon(r):
    gap = r.uniform(0.13, 0.16)
    out = silence(gap * 3 + 0.5)
    for i in range(3):
        s = mix(crack(r, 600, 0.06, 90), (0.6, boom(r, 0.25, 900, 90)))
        st = int(i * gap * SR)
        for k, v in enumerate(s):
            if st + k < len(out):
                out[st + k] += v
    return out


def rocket(r):
    whoosh = env_adsr(bandpass(noise(1.1, r), 400, 3500), 0.02, 0.12, 0.55, 0.6)
    pop = env_exp(lowpass(noise(0.15, r), 1500), 0.1)
    hiss = env_adsr(highpass(noise(1.1, r), 3000), 0.05, 0.2, 0.3, 0.6)
    return drive(mix((0.9, pop), (1.0, whoosh), (0.3, hiss)), 1.4)


def artillery(r):
    return mix(boom(r, 1.8, 380, 55), (0.35, offset(echo(tail(r, 0.7, 400, 1.0), 0.25, 0.4, 3, 500), 0.2)))


def artillery_far(r):
    t = env_adsr(lowpass(lowpass(noise(1.4, r), 160), 200), 0.03, 0.2, 0.35, 1.0)
    return echo(mix(t, (0.6, env_exp(sine(1.4, 45, 30), 1.0, 0.02))), 0.3, 0.35, 3, 250)


def energy(r):
    f0 = r.uniform(1800, 2800)
    z = env_exp(sine(0.32, f0, f0 * 0.12), 0.28, 0.001)
    sq = env_exp(lowpass(square(0.32, f0 * 0.25), 3000), 0.2)
    return mix(ringmod(z, r.uniform(90, 160)), (0.5, z), (0.25, sq), (0.2, env_exp(highpass(noise(0.1, r), 4000), 0.05)))


def flame(r):
    roar = env_adsr(bandpass(noise(0.9, r), 250, 1800), 0.05, 0.1, 0.8, 0.35)
    return drive(mix(roar, (0.5, env_adsr(lowpass(brown(0.9, r), 200), 0.05, 0.1, 0.8, 0.35))), 1.5)


def far_fire(r):
    """Distant small-arms crackle (fog-hidden / off-screen firefight)."""
    out = silence(0.9)
    for _ in range(r.randint(3, 6)):
        s = env_exp(lowpass(noise(0.12, r), 900), 0.06)
        st = r.randrange(0, len(out) - len(s))
        for k, v in enumerate(s):
            out[st + k] += v * r.uniform(0.4, 1.0)
    return echo(out, 0.2, 0.3, 2, 600)


def impact_bullet(r):
    thud = env_exp(bandpass(noise(0.12, r), 1200, 6000), 0.04, 0.0005)
    parts = [thud]
    if r.random() < 0.5:
        f = r.uniform(2400, 3600)
        parts.append((0.25, env_exp(sine(0.25, f, f * 0.55), 0.22)))
    return mix(*parts)


def impact_heavy(r):
    fs = [r.uniform(300, 340), r.uniform(440, 480), r.uniform(760, 820), r.uniform(1300, 1400)]
    ring = mix(*[(1.0 / (i + 1), env_exp(sine(0.6, f), 0.5 / (i + 1))) for i, f in enumerate(fs)])
    return drive(mix(ring, (0.8, env_exp(lowpass(noise(0.2, r), 2500), 0.08))), 1.8)


def explosion_near(r):
    return boom(r, 1.9, 1100, 50, deb=r.randint(10, 18))


def explosion_far(r):
    return echo(boom(r, 1.6, 260, 40), 0.28, 0.4, 3, 300)


def explosion_small(r):
    return mix(boom(r, 0.8, 1600, 80, deb=6), (0.6, crack(r, 1200, 0.04, 120)))


def _lfo(x, rate, depth):
    return [s * (1.0 - depth + depth * (0.5 + 0.5 * math.sin(2 * math.pi * rate * i / SR))) for i, s in enumerate(x)]


def engine_tank(r):
    f = r.uniform(34, 42)
    eng = lowpass(mix(saw(2.3, f), (0.6, saw(2.3, f * 2.01)), (0.4, square(2.3, f * 0.5))), 380)
    clank = [0.0] * n_samples(2.3)
    rate = r.uniform(8.5, 10.0)
    for j in range(int(2.3 * rate)):
        i = int(j * SR / rate) + r.randrange(0, 200)
        for k in range(min(500, len(clank) - i)):
            clank[i + k] += r.uniform(-1, 1) * (1 - k / 500.0)
    return normalize(loopable(mix(_lfo(eng, 3.1, 0.25), (0.25, bandpass(clank, 600, 3000)), (0.3, lowpass(noise(2.3, r), 250)))), 0.8)


def engine_truck(r):
    f = r.uniform(50, 60)
    eng = lowpass(mix(saw(2.3, f), (0.5, saw(2.3, f * 1.5))), 650)
    return normalize(loopable(mix(_lfo(eng, 4.3, 0.2), (0.25, lowpass(noise(2.3, r), 500)))), 0.75)


def engine_jet(r):
    roar = bandpass(noise(2.3, r), 500, 5000)
    whine = sine(2.3, r.uniform(2900, 3400))
    return normalize(loopable(mix(_lfo(roar, 0.7, 0.15), (0.12, whine), (0.5, lowpass(brown(2.3, r), 300)))), 0.8)


def engine_heli(r):
    rate = r.uniform(5.0, 6.0)
    thump = [s * max(0.0, math.sin(2 * math.pi * rate * i / SR)) ** 6 for i, s in enumerate(lowpass(noise(2.3, r), 380))]
    return normalize(loopable(mix((1.6, thump), (0.08, sine(2.3, 1750)), (0.25, bandpass(noise(2.3, r), 800, 3000)))), 0.8)


def engine_ship(r):
    diesel = lowpass(saw(2.3, r.uniform(26, 31)), 220)
    water = _lfo(bandpass(noise(2.3, r), 200, 900), 0.4, 0.5)
    return normalize(loopable(mix(diesel, (0.6, water), (0.7, lowpass(brown(2.3, r), 120)))), 0.75)


def footstep(r):
    return mix(env_exp(lowpass(noise(0.12, r), 400), 0.06), (0.4, env_exp(highpass(noise(0.1, r), 2500), 0.04)))


def gear(r):
    out = silence(0.35)
    for _ in range(r.randint(3, 5)):
        f = r.uniform(2500, 5000)
        s = env_exp(sine(0.06, f), 0.04)
        st = r.randrange(0, len(out) - len(s))
        for k, v in enumerate(s):
            out[st + k] += v * r.uniform(0.3, 1.0)
    return out


def ui_click(r):
    return mix(env_exp(sine(0.05, r.uniform(1600, 2000)), 0.03), (0.3, env_exp(highpass(noise(0.03, r), 3000), 0.01)))


def ui_confirm(r):
    return concat(env_exp(sine(0.08, 880), 0.08), env_exp(sine(0.14, 1320), 0.13))


def ui_error(r):
    return concat(env_exp(lowpass(square(0.12, 220), 2000), 0.12), env_exp(lowpass(square(0.16, 185), 2000), 0.15))


def alert_attack(r):
    a, b = (660, 440) if r.random() < 0.5 else (700, 470)
    t = concat(lowpass(square(0.14, a), 2500), lowpass(square(0.14, b), 2500))
    return env_adsr(concat(t, t), 0.005, 0.05, 0.8, 0.05)


def alert_ready(r):
    base = r.choice([523.25, 587.33])
    return mix(*[(1.0, offset(env_exp(sine(0.35, base * m), 0.3), i * 0.09)) for i, m in enumerate((1.0, 1.26, 1.5))])


def construct(r):
    out = silence(0.6)
    for i in range(r.randint(2, 3)):
        s = mix(env_exp(lowpass(noise(0.1, r), 900), 0.05), (0.4, env_exp(sine(0.15, r.uniform(700, 900)), 0.1)))
        st = int(i * r.uniform(0.17, 0.22) * SR)
        for k, v in enumerate(s):
            if st + k < len(out):
                out[st + k] += v
    return out


def squelch_in(r):
    return mix(env_exp(bandpass(noise(0.08, r), 500, 3000), 0.06, 0.001), (0.5, env_exp(square(0.02, 1200), 0.02)))


def squelch_out(r):
    k = env_adsr(bandpass(noise(0.16, r), 700, 3200), 0.002, 0.04, 0.6, 0.06)
    return mix(k, (0.3, env_exp(sine(0.16, 1500, 900), 0.12)))


def radio_static(r):
    s = bandpass(noise(2.3, r), 400, 3000)
    for _ in range(40):
        i = r.randrange(0, len(s) - 60)
        for k in range(60):
            s[i + k] += r.uniform(-1, 1) * 2.0
    return normalize(loopable(s), 0.5)


def machine_chirp(r):
    f = r.uniform(1100, 1400)
    return crush(env_exp(sine(0.1, f, f * 2.0), 0.09), 5, 3)


# id -> (recipe, variants, peak)
RECIPES = {
    "shot_rifle": (rifle, 5, 0.85), "shot_mg": (mg, 4, 0.85), "shot_sniper": (sniper, 3, 0.9),
    "shot_cannon": (cannon, 4, 0.92), "shot_autocannon": (autocannon, 3, 0.88), "shot_rocket": (rocket, 3, 0.85),
    "shot_artillery": (artillery, 3, 0.95), "shot_artillery_far": (artillery_far, 3, 0.7),
    "shot_energy": (energy, 4, 0.8), "shot_flame": (flame, 2, 0.8), "shot_far": (far_fire, 3, 0.55),
    "impact_bullet": (impact_bullet, 4, 0.6), "impact_heavy": (impact_heavy, 3, 0.8),
    "explosion_near": (explosion_near, 4, 0.95), "explosion_far": (explosion_far, 3, 0.7),
    "explosion_small": (explosion_small, 3, 0.85),
    "engine_tank": (engine_tank, 2, 0.8), "engine_truck": (engine_truck, 2, 0.75), "engine_jet": (engine_jet, 1, 0.8),
    "engine_heli": (engine_heli, 1, 0.8), "engine_ship": (engine_ship, 1, 0.75),
    "foot_step": (footstep, 4, 0.5), "gear_rattle": (gear, 3, 0.4),
    "ui_click": (ui_click, 3, 0.5), "ui_confirm": (ui_confirm, 2, 0.5), "ui_error": (ui_error, 1, 0.5),
    "alert_attack": (alert_attack, 2, 0.6), "alert_ready": (alert_ready, 2, 0.55), "alert_build": (construct, 3, 0.6),
    "radio_squelch_in": (squelch_in, 2, 0.6), "radio_squelch_out": (squelch_out, 2, 0.6),
    "radio_static": (radio_static, 1, 0.5), "machine_chirp": (machine_chirp, 2, 0.55),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    only = set(sys.argv[1:])
    count = 0
    for sid, (fn, nv, peak) in sorted(RECIPES.items()):
        if only and sid not in only:
            continue
        for v in range(nv):
            r = random.Random(zlib.crc32(("%s#%d" % (sid, v)).encode()))
            x = fn(r)
            if not sid.startswith("engine_") and sid != "radio_static":
                x = fade(x, 0.0005, 0.02)
            write_wav(os.path.join(OUT, "%s_%d.wav" % (sid, v)), normalize(x, peak))
            count += 1
    print("SFX written:", count, "->", OUT)


if __name__ == "__main__":
    main()
