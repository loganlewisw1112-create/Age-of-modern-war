"""G7 sound + music generator (owner: AUDIO7). Same pipeline as G6.1 synth_sfx.py: procedural only (dsp.py),
nothing downloaded or sampled. Deterministic (every clip seeded from crc32 of its id).

Run (re-runnable):  py -3.13 tools/audio/synth_g7.py [id ...]      (then py -3.13 tools/audio/build_manifest_g7.py)
Writes assets/generated/audio7/sfx/<id>_<n>.wav and assets/generated/audio7/music/<stem>.wav
(16-bit PCM, 22.05 kHz, mono).
SFX ids keep the G6.1 prefix -> mixer category convention (shot_/impact_/explosion_/engine_/alert_/ui_) plus the G7
categories creep_ / threat_ / core_ (audio_catalog.gd CATEGORY, audio_mixer.gd MAX).
Music: four stems of exactly 8 bars at 96 BPM (20 s) that start together and stay sample-locked (ambient, tension,
pulse, drums: the adaptive layers), plus the Tide theme (own loop) and two stingers. Note tails wrap around the loop
end, so every stem loops seamlessly.
"""
import math
import os
import random
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dsp import *  # noqa: E402,F401,F403
import synth_sfx as s6  # noqa: E402  (crack, boom, tail, _lfo)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "generated", "audio7", "sfx")
MOUT = os.path.join(ROOT, "assets", "generated", "audio7", "music")


def place(buf, sig, t, g=1.0, wrap=False):
    st = int(t * SR)
    n = len(buf)
    for k, v in enumerate(sig):
        i = st + k
        if i >= n:
            if not wrap:
                break
            i %= n
        buf[i] += v * g
    return buf


def burst(r, sec, lo, hi, dec):
    return env_exp(bandpass(noise(sec, r), lo, hi), dec)


# ------------------------------------------------------------------ weapons (APC, turrets, counter-nanite kit)
def hmg50(r):
    n, gap = r.randint(3, 4), r.uniform(0.11, 0.13)
    out = silence(gap * n + 0.55)
    for i in range(n):
        place(out, s6.crack(r, 700, 0.07, 85), i * gap + r.uniform(-0.004, 0.004), r.uniform(0.8, 1.0))
    return mix(out, (0.35, offset(s6.tail(r, 0.6, 1200, 1.0), gap * n)))


def rocketpod(r):
    out = silence(1.3)
    for i in range(r.randint(4, 6)):
        wh = env_adsr(bandpass(noise(0.45, r), 900, 5000), 0.01, 0.1, 0.5, 0.25)
        pop = env_exp(lowpass(noise(0.08, r), 1200), 0.06)
        place(out, mix(pop, (0.6, wh)), i * r.uniform(0.07, 0.09))
    return out


def rail(r):
    charge = env_adsr(mix(sine(0.38, 300, 3200), (0.4, sine(0.38, 600, 6400))), 0.25, 0.05, 0.9, 0.02)
    hit = s6.crack(r, 400, 0.12, 60)
    ring = env_exp(mix(sine(0.9, 2100), (0.5, sine(0.9, 3170))), 0.8)
    return concat(gain(charge, 0.5), mix(drive(hit, 2.0), (0.25, ring), (0.5, s6.tail(r, 0.9, 900, 1.0))))


def thermite(r):
    roar = s6._lfo(bandpass(noise(1.3, r), 300, 4000), 7.0, 0.3)
    crackle = [0.0] * n_samples(1.3)
    for _ in range(40):
        i = r.randrange(0, len(crackle) - 120)
        for k in range(120):
            crackle[i + k] += r.uniform(-1, 1) * (1 - k / 120.0)
    return env_adsr(mix(roar, (0.5, highpass(crackle, 2000))), 0.05, 0.2, 0.8, 0.4)


def disruptor(r):
    f = r.uniform(180, 240)
    z = ringmod(square(0.35, f), r.uniform(900, 1300))
    return mix(env_exp(lowpass(z, 5000), 0.3), (0.4, burst(r, 0.2, 2000, 8000, 0.12)))


def harpoon(r):
    thunk = env_exp(lowpass(noise(0.15, r), 600), 0.08)
    whizz = env_adsr(bandpass(noise(0.5, r), 2500, 7000), 0.005, 0.1, 0.4, 0.3)
    return mix(thunk, (0.5, offset(whizz, 0.03)), (0.6, env_exp(sine(0.2, 140, 70), 0.15)))


def microwave(r):
    hum = mix(sine(0.9, 120), (0.5, sine(0.9, 240)), (0.3, square(0.9, 60)))
    return env_adsr(lowpass(s6._lfo(hum, 11.0, 0.5), 1500), 0.08, 0.2, 0.7, 0.3)


def emp(r):
    zap = [0.0] * n_samples(1.6)
    for _ in range(60):
        i = r.randrange(0, int(0.6 * SR))
        for k in range(80):
            if i + k < len(zap):
                zap[i + k] += r.uniform(-1, 1)
    whomp = env_exp(sine(1.2, 90, 30), 0.9, 0.005)
    down = env_exp(sine(1.4, 2400, 180), 1.3)
    return mix((0.6, highpass(zap, 1500)), (1.0, whomp), (0.3, down))


def hero(r):
    return mix(s6.boom(r, 2.6, 900, 45, deb=14), (0.4, env_exp(sine(1.6, 3000, 500), 1.4)),
               (0.6, s6.crack(r, 500, 0.1, 70)))


def purge(r):
    hiss = env_adsr(bandpass(noise(1.6, r), 1500, 8000), 0.02, 0.3, 0.6, 0.8)
    shim = mix(*[(0.2, env_exp(sine(1.6, r.uniform(2400, 4200)), 1.4)) for _ in range(4)])
    return mix(hiss, shim, (0.5, env_exp(lowpass(noise(0.3, r), 500), 0.2)))


def aps(r):
    return mix(env_exp(highpass(noise(0.12, r), 2500), 0.05), (0.7, s6.crack(r, 1500, 0.04, 200)))


def limpet(r):
    return concat(env_exp(sine(0.07, 2200), 0.06), silence(0.08), env_exp(sine(0.07, 2200), 0.06),
                  silence(0.05), gain(env_exp(lowpass(noise(0.06, r), 1000), 0.04), 0.8))


def stomp(r):
    return mix(env_exp(sine(0.6, 70, 35), 0.45, 0.003), (0.6, env_exp(lowpass(noise(0.4, r), 300), 0.3)),
               (0.25, env_exp(highpass(noise(0.15, r), 2000), 0.06)))


# ------------------------------------------------------------------ engines / drones / dropships (loops)
def dropship(r):
    fan = s6._lfo(bandpass(noise(2.3, r), 250, 2500), r.uniform(9.0, 11.0), 0.3)
    whine = mix(sine(2.3, r.uniform(1100, 1300)), (0.5, sine(2.3, r.uniform(2300, 2500))))
    return normalize(loopable(mix(fan, (0.08, whine), (0.6, lowpass(brown(2.3, r), 200)))), 0.8)


def drone(r):
    f = r.uniform(170, 210)
    buzz = lowpass(mix(saw(2.3, f), (0.5, saw(2.3, f * 1.013)), (0.3, saw(2.3, f * 2.0))), 3000)
    return normalize(loopable(s6._lfo(buzz, r.uniform(3, 5), 0.15)), 0.7)


def drone_feed(r):
    st = bandpass(noise(2.3, r), 600, 4500)
    for _ in range(30):
        i = r.randrange(0, len(st) - 300)
        for k in range(300):
            st[i + k] *= 2.5
    hum = mix(sine(2.3, 60), (0.4, sine(2.3, 120)))
    return normalize(loopable(mix((0.35, st), (0.5, hum))), 0.45)


def ramp(r):
    whine = env_adsr(mix(sine(1.4, 300, 420), (0.4, sine(1.4, 900, 1250))), 0.1, 0.1, 0.8, 0.2)
    clunk = env_exp(lowpass(noise(0.3, r), 500), 0.2)
    return concat(gain(whine, 0.5), mix(clunk, (0.4, env_exp(sine(0.3, 90), 0.25))))


def link_lost(r):
    st = env_adsr(bandpass(noise(0.6, r), 400, 5000), 0.005, 0.1, 0.7, 0.2)
    return concat(st, env_exp(square(0.25, 440), 0.25))


def lowbat(r):
    b = env_adsr(lowpass(square(0.09, 1760), 4000), 0.003, 0.02, 0.8, 0.02)
    return concat(b, silence(0.07), b, silence(0.07), b)


def klaxon(r):
    t = lowpass(mix(saw(0.5, 420, 520), (0.6, saw(0.5, 630, 780))), 2500)
    return env_adsr(concat(t, list(reversed(t))), 0.02, 0.05, 0.9, 0.08)


def dome_up(r):
    return env_adsr(mix(sine(0.9, 160, 420), (0.4, sine(0.9, 320, 840)), (0.15, ringmod(sine(0.9, 200), 37))),
                    0.05, 0.1, 0.8, 0.4)


def dome_down(r):
    return env_adsr(mix(sine(0.8, 420, 120), (0.4, burst(r, 0.8, 1500, 6000, 0.5))), 0.01, 0.1, 0.7, 0.4)


# ------------------------------------------------------------------ creep / fissures / growths
def creep_spread(r):
    out = silence(1.2)
    for _ in range(26):
        s = env_exp(bandpass(noise(0.05, r), r.uniform(1500, 3500), 7000), 0.03)
        place(out, s, r.uniform(0.0, 1.1), r.uniform(0.3, 1.0))
    return mix(out, (0.4, env_adsr(lowpass(noise(1.2, r), 300), 0.2, 0.2, 0.6, 0.5)))


def fissure(r):
    rumble = env_adsr(lowpass(lowpass(brown(2.6, r, 0.05), 160), 200), 0.3, 0.4, 0.8, 1.2)
    cr = [0.0] * n_samples(2.6)
    for _ in range(8):
        place(cr, env_exp(highpass(noise(0.12, r), 900), 0.08), r.uniform(0.3, 1.8), r.uniform(0.4, 1.0))
    return mix(rumble, (0.5, cr), (0.6, env_exp(sine(2.0, 45, 28), 1.8, 0.2)))


def growth(r):
    f = r.uniform(140, 200)
    groan = s6._lfo(lowpass(mix(saw(1.8, f, f * 0.7), (0.5, saw(1.8, f * 1.51, f * 1.02))), 1200), 6.0, 0.4)
    return env_adsr(mix(groan, (0.3, ringmod(sine(1.8, f * 2), 23))), 0.3, 0.3, 0.7, 0.6)


def creep_purged(r):
    return env_adsr(mix(bandpass(noise(1.4, r), 2500, 9000), (0.3, s6._lfo(bandpass(noise(1.4, r), 400, 1500), 13, 0.6))),
                    0.02, 0.3, 0.5, 0.9)


# ------------------------------------------------------------------ Machine threat units
def packhunter(r):
    f = r.uniform(700, 900)
    scr = env_adsr(ringmod(saw(0.5, f, f * 1.6), r.uniform(60, 90)), 0.02, 0.1, 0.6, 0.25)
    swipe = env_adsr(bandpass(noise(0.25, r), 1200, 6000), 0.03, 0.05, 0.5, 0.12)
    return mix(lowpass(scr, 5000), (0.7, offset(swipe, 0.25)))


def burrower(r):
    under = env_adsr(lowpass(brown(1.6, r, 0.04), 140), 0.4, 0.2, 0.8, 0.3)
    erupt = s6.boom(r, 0.9, 1200, 60, deb=10)
    return mix(under, (0.9, offset(erupt, 1.0)))


def leech(r):
    f = r.uniform(380, 460)
    d = s6._lfo(lowpass(mix(square(1.0, f), (0.5, saw(1.0, f * 2.02))), 4000), 23.0, 0.5)
    return env_adsr(d, 0.03, 0.1, 0.8, 0.2)


def weaver(r):
    out = silence(1.0)
    for i in range(r.randint(10, 14)):
        place(out, env_exp(highpass(noise(0.02, r), 3000), 0.012), i * r.uniform(0.035, 0.05), r.uniform(0.4, 1.0))
    spit = env_adsr(bandpass(noise(0.3, r), 300, 2500), 0.005, 0.05, 0.5, 0.2)
    return mix(out, (0.8, offset(spit, 0.62)), (0.4, offset(env_exp(sine(0.2, 400, 150), 0.15), 0.62)))


def slug(r):
    return mix(env_exp(lowpass(noise(0.4, r), 700), 0.3), (0.7, env_exp(sine(0.35, 220, 80), 0.3)),
               (0.3, env_exp(bandpass(noise(0.3, r), 2000, 6000), 0.15)))


def cocoon(r):
    out = silence(1.0)
    for _ in range(30):
        place(out, env_exp(bandpass(noise(0.03, r), 2500, 8000), 0.02), r.uniform(0, 0.95), r.uniform(0.2, 0.8))
    return mix(out, (0.4, env_adsr(lowpass(noise(1.0, r), 600), 0.2, 0.2, 0.5, 0.4)))


def spawn(r):
    f = r.uniform(55, 70)
    g = lowpass(mix(saw(1.2, f, f * 1.3), (0.6, ringmod(saw(1.2, f * 2), 31))), 900)
    return env_adsr(g, 0.15, 0.2, 0.7, 0.5)


# ------------------------------------------------------------------ cores
def core_scream(r):
    parts = []
    for k in range(5):
        f = r.uniform(300, 1400)
        parts.append((0.35, ringmod(saw(2.6, f, f * r.uniform(0.55, 1.6)), r.uniform(40, 140))))
    scream = env_adsr(lowpass(mix(*parts), 6000), 0.15, 0.4, 0.8, 1.2)
    return mix(scream, (0.6, env_adsr(lowpass(brown(2.6, r), 180), 0.3, 0.3, 0.7, 1.0)))


def core_pulse(r):
    return mix(env_exp(sine(1.1, 52, 40), 0.9, 0.08), (0.4, env_exp(sine(1.1, 104, 80), 0.6, 0.08)),
               (0.15, env_exp(ringmod(sine(1.1, 400), 7), 0.8)))


def core_hit(r):
    clang = mix(*[(0.3, env_exp(sine(0.9, r.uniform(500, 2600)), r.uniform(0.3, 0.8))) for _ in range(5)])
    return mix(clang, (0.6, s6.crack(r, 900, 0.06, 140)), (0.3, burst(r, 0.3, 2000, 7000, 0.2)))


def core_destroyed(r):
    return mix(s6.boom(r, 3.2, 700, 38, deb=18), (0.5, env_adsr(core_scream(r), 0.0, 0.5, 0.6, 1.5)))


# ------------------------------------------------------------------ CIWS7-4 rotary cannon (G7_REFERENCE 13.9c-32a)
# Owner: "that signatture phlanx BBRRRRTTTTTTTTTT shooting sound". Original synthesis (no recording): a train of
# CIWS_RATE short reports a second (each its own noise crack + low thump + mechanism tick, timing / level jitter) so
# close together they fuse into one tearing buzz whose fundamental IS the rate (70 Hz), a sawtooth body on the same
# fundamental for the "BRRRT" tone, the drive motor whine and belt rattle underneath, soft-clipped for harsh upper
# harmonics, plus a short slap echo. brrt is a seamless 1.0 s loop (the reports and the echo wrap round the loop end):
# the audio layer starts it at the burst's first round and stops it at its last. spinup / spindown are the barrel
# cluster's electric-hydraulic whine and rotation clicks before and after the rounds.
CIWS_RATE = 70.0      # reports per second (~4200 rpm): the buzz fundamental
CIWS_LOOP = 1.0       # loop length, s (exactly CIWS_RATE reports: the loop point falls between two reports)
CIWS_SPINUP = 0.55    # s
CIWS_SPINDOWN = 1.8   # s


def _ciws_report(r, far=False):
    crack = env_exp(highpass(noise(0.014, r), 900 if far else 1700), 0.011, 0.0003)
    body = env_exp(sine(0.024, r.uniform(140, 165), 85), 0.02, 0.0005)
    mech = env_exp(bandpass(noise(0.01, r), 2400, 6500), 0.006)
    if far:
        return mix((0.5, lowpass(crack, 700)), (1.0, body))
    return mix((0.9, crack), (0.75, body), (0.3, mech))


def _ciws_train(r, far=False):
    """CIWS_LOOP seconds of reports at CIWS_RATE (wrapped: loops seamlessly)."""
    out = silence(CIWS_LOOP)
    n = int(round(CIWS_RATE * CIWS_LOOP))
    for i in range(n):
        t = i / CIWS_RATE + r.uniform(-0.00035, 0.00035)
        place(out, _ciws_report(r, far), t % CIWS_LOOP, r.uniform(0.82, 1.0), wrap=True)
    return out


def _echo2(x, delay, g, damp):
    """Slap echo (no feedback) over a two-period buffer: the second period carries the first period's tail."""
    tap = lowpass(x, damp)
    d = int(delay * SR)
    out = list(x)
    for i in range(len(x) - d):
        out[i + d] += tap[i] * g
    return out


def ciws_brrt(r):
    # every input is periodic in CIWS_LOOP (wrapped reports, whole cycles of the 70 Hz saw and the whine sines, a
    # repeated noise block); the filters, drive and echo run over two periods and the second (steady-state) period is
    # kept, so the loop point is seamless
    sec = CIWS_LOOP
    n = n_samples(sec)
    train = _ciws_train(r)
    tone = lowpass(saw(sec, CIWS_RATE) * 2, 2200)                  # the fused buzz on the rate fundamental
    whine = mix(sine(sec, 1180), (0.4, sine(sec, 2360)), (0.15, sine(sec, 3540))) * 2
    rattle = bandpass(noise(sec, r) * 2, 3000, 8000)                # belt feed / links / spent cases
    x = mix((1.0, train * 2), (0.32, tone), (0.05, whine), (0.07, rattle))
    x = drive(x, 2.6)                                               # harsh upper harmonics (soft clip)
    x = _echo2(x, 0.047, 0.22, 2600)                                # slap off the roof / walls
    return x[n:]


def ciws_brrt_far(r):
    sec = CIWS_LOOP
    n = n_samples(sec)
    train = _ciws_train(r, True)
    tone = lowpass(saw(sec, CIWS_RATE) * 2, 450)
    rumble = lowpass(noise(sec, r) * 2, 260)
    x = mix((1.0, train * 2), (0.45, tone), (0.25, rumble))
    x = drive(lowpass(x, 900), 1.6)
    x = _echo2(x, 0.13, 0.38, 900)
    x = _echo2(x, 0.29, 0.22, 600)
    return x[n:]


def _clicks(r, sec, f0, f1, g0, g1, shape=1.0):
    """Barrel-cluster rotation clicks whose rate glides f0 -> f1 (Hz) and level g0 -> g1."""
    out = silence(sec)
    ph, n = 0.0, n_samples(sec)
    step = 64
    for i in range(0, n, step):
        u = i / float(n)
        f = f0 + (f1 - f0) * (u ** shape)
        ph += f * step / SR
        if ph >= 1.0:
            ph -= 1.0
            clk = env_exp(bandpass(noise(0.004, r), 1800, 5200), 0.004, 0.0002)
            place(out, clk, i / SR, (g0 + (g1 - g0) * u) * r.uniform(0.8, 1.0))
    return out


def ciws_spinup(r):
    sec = CIWS_SPINUP
    whine = mix(sine(sec, 180, 1180), (0.4, sine(sec, 360, 2360)), (0.12, sine(sec, 540, 3540)))
    whine = env_adsr(whine, sec * 0.8, 0.01, 1.0, 0.03)            # rises with the motor speed
    hiss = env_adsr(bandpass(noise(sec, r), 700, 3200), sec * 0.7, 0.05, 0.8, 0.05)
    clunk = env_exp(lowpass(noise(0.08, r), 400), 0.07)              # clutch / hydraulics engage
    return mix((0.55, whine), (0.25, hiss), (0.5, clunk), (0.7, _clicks(r, sec, 6.0, CIWS_RATE, 0.3, 0.8, 1.6)))


def ciws_spindown(r):
    sec = CIWS_SPINDOWN
    tail = silence(0.3)                                              # the last rounds ringing out
    for i in range(4):
        place(tail, _ciws_report(r), i / CIWS_RATE, 0.9 * (0.55 ** i))
    tail = echo(tail, 0.047, 0.3, 3, 2600)
    whine = mix(sine(sec, 1180, 120), (0.35, sine(sec, 2360, 240)))
    whine = env_exp(whine, sec * 1.1, 0.002)
    clicks = _clicks(r, sec, CIWS_RATE * 0.85, 4.0, 0.7, 0.1, 0.55)
    stop = offset(env_exp(lowpass(noise(0.12, r), 700), 0.1), sec * 0.82)   # cluster brake / stop clack
    return mix((0.8, tail), (0.4, whine), (0.6, clicks), (0.25, stop))


# id -> (recipe, variants, peak)
RECIPES = {
    "shot_hmg50": (hmg50, 3, 0.88), "shot_rocketpod": (rocketpod, 2, 0.85), "shot_rail": (rail, 2, 0.92),
    "shot_thermite": (thermite, 2, 0.8), "shot_disruptor": (disruptor, 3, 0.8), "shot_harpoon": (harpoon, 2, 0.8),
    "shot_microwave": (microwave, 1, 0.7),
    "explosion_emp": (emp, 2, 0.9), "explosion_hero": (hero, 2, 0.97), "explosion_purge": (purge, 2, 0.85),
    "impact_aps": (aps, 2, 0.75), "impact_stomp": (stomp, 3, 0.85),
    "engine_dropship": (dropship, 1, 0.8), "engine_drone": (drone, 2, 0.7),
    "ui_drone_feed": (drone_feed, 1, 0.45),
    "alert_ramp": (ramp, 1, 0.7), "alert_link_lost": (link_lost, 2, 0.6), "alert_lowbat": (lowbat, 1, 0.5),
    "alert_klaxon": (klaxon, 1, 0.6), "alert_dome_up": (dome_up, 1, 0.6), "alert_dome_down": (dome_down, 1, 0.6),
    "alert_limpet": (limpet, 1, 0.55),
    "creep_spread": (creep_spread, 3, 0.6), "creep_fissure": (fissure, 2, 0.9), "creep_growth": (growth, 3, 0.7),
    "creep_purged": (creep_purged, 2, 0.7),
    "threat_packhunter": (packhunter, 3, 0.8), "threat_burrower": (burrower, 2, 0.9), "threat_leech": (leech, 2, 0.7),
    "threat_weaver": (weaver, 3, 0.75), "threat_slug": (slug, 2, 0.75), "threat_cocoon": (cocoon, 2, 0.6),
    "threat_spawn": (spawn, 2, 0.75),
    "core_scream": (core_scream, 3, 0.95), "core_pulse": (core_pulse, 2, 0.85), "core_hit": (core_hit, 3, 0.8),
    "core_destroyed": (core_destroyed, 1, 0.97),
    "shot_ciws7_brrt": (ciws_brrt, 2, 0.9), "shot_ciws7_brrt_far": (ciws_brrt_far, 1, 0.8),   # CIWS7-4 13.9c-32a
    "shot_ciws7_spinup": (ciws_spinup, 1, 0.7), "shot_ciws7_spindown": (ciws_spindown, 2, 0.75),
}
LOOPS = ("engine_", "ui_drone_feed", "shot_ciws7_brrt")


# ------------------------------------------------------------------ adaptive music (D minor, 96 BPM, 8 bars)
BPM = 96.0
BEAT = 60.0 / BPM
BAR = BEAT * 4
LOOP_S = BAR * 8
N = {"D1": 36.71, "A1": 55.0, "D2": 73.42, "F2": 87.31, "A2": 110.0, "Bb2": 116.54, "C3": 130.81, "D3": 146.83,
     "E3": 164.81, "F3": 174.61, "G3": 196.0, "A3": 220.0, "Bb3": 233.08, "C4": 261.63, "D4": 293.66, "E4": 329.63,
     "F4": 349.23, "G4": 392.0, "A4": 440.0, "Bb4": 466.16, "C5": 523.25, "D5": 587.33}
CHORDS = [("D3", "F3", "A3"), ("Bb2", "D3", "F3"), ("F2", "A3", "C4"), ("C3", "E3", "G3")]


def loopbuf():
    return [0.0] * n_samples(LOOP_S)


def pad(sec, notes, lp=800.0, att=1.2, rel=1.5):
    v = mix(*[(0.5, saw(sec + rel, N[n] * d)) for n in notes for d in (0.996, 1.004)])
    return env_adsr(lowpass(lowpass(v, lp), lp * 1.3), att, 0.3, 0.8, rel)


def kick(r):
    return mix(env_exp(sine(0.4, 120, 42), 0.35, 0.002), (0.3, env_exp(lowpass(noise(0.03, r), 2000), 0.02)))


def snare(r):
    return mix(env_exp(bandpass(noise(0.25, r), 1200, 6000), 0.16), (0.6, env_exp(sine(0.12, 190, 160), 0.1)))


def hat(r, dec=0.03):
    return env_exp(highpass(noise(0.06, r), 6000), dec)


def taiko(r, f=82.0):
    return mix(env_exp(sine(0.9, f * 1.4, f * 0.8), 0.7, 0.003), (0.5, env_exp(lowpass(noise(0.15, r), 600), 0.1)))


def m_ambient(r):
    b = loopbuf()
    for i, ch in enumerate(CHORDS):
        place(b, pad(BAR * 2, ch), i * BAR * 2, 0.5, wrap=True)
    scale = ["D4", "F4", "G4", "A4", "C5", "D5"]
    plucks = loopbuf()
    for k in range(14):
        t = r.randrange(0, 64) * BEAT / 2
        place(plucks, env_exp(mix(sine(1.4, N[r.choice(scale)]), (0.2, sine(1.4, N["D5"] * 2))), 1.2), t, 0.25, wrap=True)
    wind = lowpass(brown(LOOP_S, r, 0.01), 400)
    return mix(b, echo(plucks, BEAT * 0.75, 0.4, 3)[:len(b)], (0.12, wind))


def m_tension(r):
    b = loopbuf()
    drone = lowpass(mix(saw(LOOP_S, N["D2"]), (0.6, saw(LOOP_S, N["A2"] * 1.002))), 320)
    e8 = BEAT / 2
    for k in range(int(LOOP_S / e8)):
        g = 1.0 if k % 8 == 0 else (0.7 if k % 2 == 0 else 0.5)
        place(b, env_exp(drone[int(k * e8 * SR): int((k + 1) * e8 * SR)], e8 * 1.6, 0.004), k * e8, g)
    trem = loopbuf()
    for i in range(4):
        n = "A4" if i % 2 == 0 else "Bb4"
        s = s6._lfo(lowpass(saw(BAR * 2 + 0.5, N[n]), 2200), 12.0, 0.6)
        place(trem, env_adsr(s, 0.6, 0.2, 0.8, 0.5), i * BAR * 2, 0.18, wrap=True)
    return mix(b, trem)


def m_pulse(r):
    b = loopbuf()
    arp = ["D3", "F3", "A3", "D4", "A3", "F3", "A3", "E4"]
    s16 = BEAT / 4
    for k in range(int(LOOP_S / s16)):
        bar = int(k * s16 / BAR) % 8
        root = 0.0 if bar < 4 else -2.0  # second half down a whole tone: rising unease when it comes back
        f = N[arp[k % len(arp)]] * (2.0 ** (root / 12.0))
        place(b, env_exp(lowpass(square(s16 * 1.5, f, 0.3), 1800), 0.12), k * s16, 0.35 if k % 4 else 0.5, wrap=True)
        if k % 2 == 0:
            place(b, hat(r, 0.02), k * s16, 0.18, wrap=True)
    return b


def m_drums(r):
    b = loopbuf()
    for bar in range(8):
        t0 = bar * BAR
        for bt in (0.0, 1.5, 2.0):
            place(b, kick(r), t0 + bt * BEAT, 0.9, wrap=True)
        for bt in (1.0, 3.0):
            place(b, snare(r), t0 + bt * BEAT, 0.55, wrap=True)
        for e in range(8):
            place(b, hat(r), t0 + e * BEAT / 2, 0.22 if e % 2 else 0.3, wrap=True)
        if bar % 4 == 3:
            for k, bt in enumerate((2.0, 2.5, 3.0, 3.25, 3.5, 3.75)):
                place(b, taiko(r, 70.0 + 12.0 * (k % 3)), t0 + bt * BEAT, 0.6, wrap=True)
    return b


def m_tide(r):
    b = loopbuf()
    motif = [("D2", 0, 2), ("F2", 2, 1), ("E3", 3, 1), ("C3", 4, 2), ("D2", 6, 1), ("A1", 7, 1)]
    for nm, at, ln in motif:
        f = N[nm]
        s = lowpass(mix(saw(BAR * ln + 0.6, f), (0.7, saw(BAR * ln + 0.6, f * 2.003)), (0.4, saw(BAR * ln + 0.6, f * 1.498))), 700)
        place(b, env_adsr(s, 0.25, 0.3, 0.85, 0.6), at * BAR, 0.45, wrap=True)
    for i, ch in enumerate([("D3", "F3", "A3"), ("Bb2", "D3", "F3"), ("C3", "E3", "G3"), ("D3", "F3", "A3")]):
        choir = bandpass(pad(BAR * 2, ch, lp=2400, att=0.6, rel=1.0), 300, 2400)
        place(b, s6._lfo(choir, 5.5, 0.12), i * BAR * 2, 0.35, wrap=True)
    for bar in range(8):
        t0 = bar * BAR
        for e in range(8):
            place(b, taiko(r, 64.0 if e % 2 == 0 else 88.0), t0 + e * BEAT / 2, 0.75 if e % 4 == 0 else 0.45, wrap=True)
        for bt in (1.0, 3.0):
            place(b, snare(r), t0 + bt * BEAT, 0.5, wrap=True)
        place(b, kick(r), t0, 1.0, wrap=True)
    hi = s6._lfo(lowpass(mix(saw(LOOP_S, N["D5"]), (0.8, saw(LOOP_S, N["D5"] * 1.059))), 3000), 14.0, 0.7)
    return mix(b, (0.06, hi))


def sting_tide(r):
    hit = s6.boom(r, 3.5, 600, 36, deb=10)
    horn = env_adsr(lowpass(mix(saw(4.0, N["D1"] * 2), (0.8, saw(4.0, N["A1"] * 2.004)), (0.5, saw(4.0, N["D2"] * 2.0))), 500),
                    0.5, 0.5, 0.8, 1.5)
    return mix(hit, (0.7, horn))


def sting_core(r):
    sw = env_adsr(mix(*[(0.3, saw(3.0, N[n])) for n in ("D3", "F3", "A3", "D4")]), 1.2, 0.3, 0.8, 1.2)
    return mix(lowpass(sw, 1500), (0.4, env_exp(sine(3.0, N["A4"]), 2.5, 1.0)))


MUSIC = {"ambient": (m_ambient, 0.8), "tension": (m_tension, 0.8), "pulse": (m_pulse, 0.7), "drums": (m_drums, 0.85),
         "tide": (m_tide, 0.9), "sting_tide": (sting_tide, 0.95), "sting_core": (sting_core, 0.8)}


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(MOUT, exist_ok=True)
    only = set(sys.argv[1:])
    count = 0
    for sid, (fn, nv, peak) in sorted(RECIPES.items()):
        if only and sid not in only:
            continue
        for v in range(nv):
            r = random.Random(zlib.crc32(("g7:%s#%d" % (sid, v)).encode()))
            x = fn(r)
            if not sid.startswith(LOOPS):
                x = fade(x, 0.0005, 0.02)
            write_wav(os.path.join(OUT, "%s_%d.wav" % (sid, v)), normalize(x, peak))
            count += 1
    for mid, (fn, peak) in sorted(MUSIC.items()):
        if only and ("music_" + mid) not in only:
            continue
        r = random.Random(zlib.crc32(("g7music:" + mid).encode()))
        x = fn(r)
        if mid.startswith("sting"):
            x = fade(x, 0.001, 0.3)
        write_wav(os.path.join(MOUT, "%s.wav" % mid), normalize(x, peak))
        count += 1
    print("G7 audio written:", count, "->", OUT, "+", MOUT)


if __name__ == "__main__":
    main()
