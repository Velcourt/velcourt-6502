#!/usr/bin/env python3
"""ch26_wavscan.py - find the notes in a WAV recorded by sim_soc.

Usage: python3 ch26_wavscan.py FILE.wav [WINDOW_MS]
Cuts the recording into windows and, in each one, measures the strength of
every semitone from 98 Hz to 523 Hz with the Goertzel algorithm. It prints
the strongest note in each window, and a second one if it is at least a
quarter as strong and not a neighbour of the first. Equal windows are
joined into runs.
Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence."""
import sys, wave, struct, math

def load(path):
    w = wave.open(path)
    n = w.getnframes()
    return w.getframerate(), struct.unpack("<%dh" % n, w.readframes(n))

def goertzel(x, f, rate):
    """Amplitude of frequency f in the samples x (half the peak value)."""
    k = 2 * math.cos(2 * math.pi * f / rate)
    s1 = s2 = 0.0
    for v in x:
        s1, s2 = v + k * s1 - s2, s1
    return math.sqrt(max(s1 * s1 + s2 * s2 - k * s1 * s2, 0)) / len(x)

NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
NOTES = []                                    # (name, Hz) from G2 to C5
for m in range(43, 73):                       # MIDI note numbers
    NOTES.append((NAMES[m % 12] + str(m // 12 - 1), 440 * 2 ** ((m - 69) / 12)))

rate, data = load(sys.argv[1])
win = int(rate * (float(sys.argv[2]) if len(sys.argv) > 2 else 50) / 1000)
runs = []                                     # [start_s, end_s, label]
for start in range(0, len(data) - win + 1, win):
    x = data[start:start + win]
    if max(x) - min(x) == 0:
        label = "silence"
    else:
        amps = [goertzel(x, f, rate) for n, f in NOTES]
        best = max(range(len(NOTES)), key=lambda i: amps[i])
        top = [best] if amps[best] > 300 else []
        rest = [i for i in range(len(NOTES)) if abs(i - best) > 1]
        if top and rest:                      # a second note, not a neighbour
            second = max(rest, key=lambda i: amps[i])
            if amps[second] > 0.25 * amps[best]:
                top.append(second)
        label = " + ".join(NOTES[i][0] for i in sorted(top, reverse=True))
        label = label or "noise"
    t = start / rate
    if runs and runs[-1][2] == label:
        runs[-1][1] = t + win / rate
    else:
        runs.append([t, t + win / rate, label])
for a, b, label in runs:
    print("%6.3f - %6.3f s  %s" % (a, b, label))
