#!/usr/bin/env python3
"""Generate the game's 8 bit sound effects and music into assets/sounds.

Everything is synthesized from square, pulse and LFSR noise sources at 22050 Hz
and written as 8 bit unsigned mono WAV, which is what the era actually sounded
like and what miniaudio decodes without any extra dependency. Output is
deterministic: the noise generator is a fixed seed LFSR, so rerunning this
produces byte identical files and an unchanged git diff.

    python3 tools/gen-sounds.py [outdir]
"""

import math
import os
import struct
import sys

RATE = 22050

# Half steps above C, the only note names this file needs.
NOTES = {
    "C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6,
    "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11,
}


def hz(name, octave=4):
    """Scientific pitch note name to frequency, tuned to A4 = 440."""
    semis = NOTES[name] - NOTES["A"] + (octave - 4) * 12
    return 440.0 * (2.0 ** (semis / 12.0))


class Noise:
    """15 bit LFSR, the NES noise channel. Seeded, so output is reproducible."""

    def __init__(self, seed=0x7F1D):
        self.reg = seed & 0x7FFF or 1

    def next(self):
        bit = (self.reg ^ (self.reg >> 1)) & 1
        self.reg = (self.reg >> 1) | (bit << 14)
        return 1.0 if self.reg & 1 else -1.0


class Buffer:
    """Mono float buffer that voices mix into, addressed in seconds."""

    def __init__(self, seconds):
        self.data = [0.0] * int(seconds * RATE)

    def add(self, index, value):
        if 0 <= index < len(self.data):
            self.data[index] += value

    def __len__(self):
        return len(self.data)


def env_decay(t, dur, curve=3.0):
    """1 at the attack, 0 at the end, curved so the tail is short and snappy."""
    if t >= dur:
        return 0.0
    return (1.0 - t / dur) ** curve


def pulse(buf, start, dur, f0, f1, amp, duty=0.5, curve=3.0, levels=8, vibrato=0.0):
    """Pulse wave with an exponential frequency glide from f0 to f1.

    levels quantizes the amplitude the way a 4 bit APU register would, which is
    what keeps these from sounding like a modern synth.
    """
    n = int(dur * RATE)
    i0 = int(start * RATE)
    phase = 0.0
    for i in range(n):
        t = i / RATE
        k = i / max(1, n - 1)
        f = f0 * (f1 / f0) ** k
        if vibrato:
            f *= 1.0 + vibrato * math.sin(t * 38.0)
        phase += f / RATE
        v = 1.0 if (phase % 1.0) < duty else -1.0
        a = amp * env_decay(t, dur, curve)
        a = round(a * levels) / levels
        buf.add(i0 + i, v * a)


def noiseburst(buf, start, dur, amp, curve=3.0, step=1, rng=None):
    """LFSR noise. step holds each sample for a few frames to darken the tone."""
    n = int(dur * RATE)
    i0 = int(start * RATE)
    rng = rng or Noise()
    v = rng.next()
    for i in range(n):
        if i % step == 0:
            v = rng.next()
        buf.add(i0 + i, v * amp * env_decay(i / RATE, dur, curve))


def write_wav(path, buf, headroom=0.92):
    """Normalize and write 8 bit unsigned mono PCM."""
    peak = max((abs(v) for v in buf.data), default=0.0)
    gain = headroom / peak if peak > 0.0 else 0.0
    frames = bytearray(len(buf.data))
    for i, v in enumerate(buf.data):
        s = int(round(v * gain * 127.0)) + 128
        frames[i] = 0 if s < 0 else (255 if s > 255 else s)

    with open(path, "wb") as f:
        f.write(b"RIFF")
        f.write(struct.pack("<I", 36 + len(frames)))
        f.write(b"WAVEfmt ")
        f.write(struct.pack("<IHHIIHH", 16, 1, 1, RATE, RATE, 1, 8))
        f.write(b"data")
        f.write(struct.pack("<I", len(frames)))
        f.write(frames)

    rms = math.sqrt(sum(v * v for v in buf.data) / max(1, len(buf.data))) * gain
    print("%-14s %5.2fs  peak %.2f  rms %.2f  %6d bytes"
          % (os.path.basename(path), len(buf) / RATE, headroom, rms,
             44 + len(frames)))


def shoot(variant):
    """Short descending pulse zap. Three variants so held fire is not a drone."""
    top, bottom, duty = [
        (1180.0, 430.0, 0.25),
        (1320.0, 500.0, 0.125),
        (1010.0, 380.0, 0.375),
    ][variant]
    b = Buffer(0.10)
    pulse(b, 0.0, 0.09, top, bottom, 0.8, duty=duty, curve=2.2)
    noiseburst(b, 0.0, 0.015, 0.25, curve=1.5, step=2)
    return b


def hit(variant):
    """Bullet landing on an enemy that survives it."""
    b = Buffer(0.09)
    top = 1700.0 if variant == 0 else 1450.0
    pulse(b, 0.0, 0.06, top, 900.0, 0.55, duty=0.5, curve=3.5)
    noiseburst(b, 0.0, 0.05, 0.5, curve=3.0, step=2, rng=Noise(0x2A19 + variant))
    return b


def explode():
    """Enemy destroyed: noise body over a falling square, with a chip stutter."""
    b = Buffer(0.45)
    noiseburst(b, 0.0, 0.40, 0.9, curve=2.4, step=3, rng=Noise(0x51C3))
    pulse(b, 0.0, 0.34, 300.0, 55.0, 0.5, duty=0.5, curve=2.0)
    # retriggered ticks, the classic APU way of faking a longer envelope
    for k, t in enumerate((0.06, 0.12, 0.2)):
        pulse(b, t, 0.05, 420.0 - k * 90.0, 120.0, 0.3, duty=0.125, curve=2.0)
    return b


def death():
    """Player wrecked: long vibrato dive with a noise wash and a low thud."""
    b = Buffer(1.15)
    pulse(b, 0.0, 1.0, 620.0, 70.0, 0.75, duty=0.5, curve=1.6, vibrato=0.05)
    pulse(b, 0.0, 0.9, 310.0, 45.0, 0.4, duty=0.25, curve=1.4)
    noiseburst(b, 0.0, 0.7, 0.45, curve=1.8, step=4, rng=Noise(0x1B77))
    noiseburst(b, 0.86, 0.28, 0.5, curve=2.0, step=9, rng=Noise(0x6D05))
    return b


def start():
    """Rising arpeggio for starting a run."""
    b = Buffer(0.34)
    for i, (name, octv) in enumerate((("A", 3), ("C", 4), ("E", 4), ("A", 4))):
        f = hz(name, octv)
        pulse(b, i * 0.065, 0.09, f, f, 0.7, duty=0.25, curve=2.0)
    return b


def music():
    """Four bar loop at 140 BPM: Am F C G, bass, arpeggio and noise percussion.

    The length is an exact multiple of the bar so the file loops without a seam,
    and every voice decays inside its own slot so there is no click at the wrap.
    """
    bpm = 140.0
    beat = 60.0 / bpm
    step = beat / 4.0          # sixteenth
    bars = 4
    b = Buffer(bars * 4 * beat)

    chords = [
        ("A", 2, ["A", "C", "E", "A"], [3, 4, 4, 4]),
        ("F", 2, ["F", "A", "C", "F"], [3, 3, 4, 4]),
        ("C", 2, ["C", "E", "G", "C"], [4, 4, 4, 5]),
        ("G", 2, ["G", "B", "D", "G"], [3, 3, 4, 4]),
    ]
    hatrng = Noise(0x3EA5)
    snarerng = Noise(0x0C4B)

    for bar, (root, rootoct, arp, arpocts) in enumerate(chords):
        t0 = bar * 4 * beat
        rootf = hz(root, rootoct)

        # bass on 1 and 3, with a pickup on the last eighth
        for k in (0, 8):
            pulse(b, t0 + k * step, beat * 0.55, rootf, rootf, 0.40,
                  duty=0.5, curve=1.2)
        pulse(b, t0 + 14 * step, step * 1.6, rootf * 2.0, rootf * 2.0, 0.32,
              duty=0.5, curve=1.4)

        # sixteenth arpeggio over the chord
        for k in range(16):
            name = arp[k % 4]
            octv = arpocts[k % 4]
            f = hz(name, octv)
            amp = 0.34 if k % 4 == 0 else 0.24
            pulse(b, t0 + k * step, step * 0.9, f, f, amp, duty=0.25, curve=1.8)

        # percussion: hat on every eighth, snare on 2 and 4
        for k in range(0, 16, 2):
            noiseburst(b, t0 + k * step, 0.03, 0.12 if k % 4 else 0.18,
                       curve=3.0, step=1, rng=hatrng)
        for k in (4, 12):
            noiseburst(b, t0 + k * step, 0.12, 0.34, curve=2.6, step=2,
                       rng=snarerng)

    return b


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "assets", "sounds")
    os.makedirs(outdir, exist_ok=True)

    tracks = [("shoot%d.wav" % (i + 1), shoot(i)) for i in range(3)]
    tracks += [("hit%d.wav" % (i + 1), hit(i)) for i in range(2)]
    tracks += [
        ("explode.wav", explode()),
        ("death.wav", death()),
        ("start.wav", start()),
        ("music.wav", music()),
    ]

    for name, buf in tracks:
        write_wav(os.path.join(outdir, name), buf)
    print("wrote %d files to %s" % (len(tracks), outdir))


if __name__ == "__main__":
    main()
