#!/usr/bin/env python3
"""Generate a synthetic singing-lesson recording for end-to-end testing.

Produces, in Fixtures/:
  sample-lesson.m4a        ~1 min: teacher speech, student reply, piano cues and a sung
                           5-note scale (synthesised), with silences — the same mix a
                           real Voice Memos lesson has.
  sample-lesson-long.m4a   the same lesson eight times (~8 min), long enough to be split
                           into two transcription chunks.
  teacher-reference.wav    6 s of the "teacher" voice alone.
  student-reference.wav    4 s of the "student" voice alone.

Speech comes from the platform's TTS: `say` on macOS, SAPI (via PowerShell) on
Windows. Two clearly different voices are used so diarization has something to
separate. Needs ffmpeg on PATH. Standard library only.
"""
from __future__ import annotations

import math
import platform
import random
import shutil
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

RATE = 44_100
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Fixtures"

TEACHER_LINES = [
    "Okay, let's warm up with a five note scale on nay. We'll start on the F below middle C.",
    "Good. You're pushing chest voice too high around the C. Let it tip over into the mix earlier, and keep it light.",
    "Yes, keep the nay, and keep your jaw loose. I saw it clamp on the top note. Again, a half step up.",
    "Much better. Remember to keep your support all the way to the end of the phrase.",
]
STUDENT_LINES = [
    "Should I keep the nay vowel?",
]
TEACHER_REFERENCE = "The breath should feel low and wide, like you are filling a tyre around your waist."
STUDENT_REFERENCE = "I felt it flip a little on the way up, but honestly it was much easier than last week."


# --- speech -----------------------------------------------------------------

def tts(text: str, path: Path, voice: str) -> None:
    system = platform.system()
    if system == "Darwin":
        aiff = path.with_suffix(".aiff")
        subprocess.run(["say", "-v", voice, "-o", str(aiff), text], check=True)
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(aiff), "-ac", "1", "-ar", str(RATE), str(path)], check=True)
    elif system == "Windows":
        script = (
            "Add-Type -AssemblyName System.Speech;"
            "$s = New-Object System.Speech.Synthesis.SpeechSynthesizer;"
            f"$s.SelectVoice('{voice}');"
            f"$s.SetOutputToWaveFile('{path}');"
            f"$s.Speak(@'\n{text}\n'@);"
            "$s.Dispose()"
        )
        subprocess.run(["powershell", "-NoProfile", "-Command", script], check=True)
    else:
        sys.exit("Speech synthesis needs macOS (`say`) or Windows (SAPI).")


def voices() -> tuple[str, str, float]:
    """(teacher voice, student voice, student pitch factor)."""
    if platform.system() == "Darwin":
        return "Daniel", "Alex", 1.0
    # Windows ships two female voices; lower the student's pitch so the two
    # speakers are clearly distinct (and closer to a male student).
    return "Microsoft Hazel Desktop", "Microsoft Zira Desktop", 0.78


def read_wav(path: Path, pitch: float = 1.0) -> list[float]:
    """Load (and optionally pitch-shift) a WAV as mono floats at RATE via ffmpeg."""
    raw = path.with_suffix(".raw")
    filters = f"asetrate={RATE}*{pitch},aresample={RATE}" if pitch != 1.0 else f"aresample={RATE}"
    subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-y", "-i", str(path), "-af", filters,
         "-ac", "1", "-ar", str(RATE), "-f", "s16le", str(raw)],
        check=True,
    )
    data = raw.read_bytes()
    return [s / 32768 for s in struct.unpack(f"<{len(data) // 2}h", data)]


# --- music ------------------------------------------------------------------

def freq(midi: int) -> float:
    return 440 * 2 ** ((midi - 69) / 12)


def piano_note(midi: int, seconds: float, velocity: float = 0.35) -> list[float]:
    f = freq(midi)
    n = int(seconds * RATE)
    out = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-3.0 * t) * min(1.0, t * 200)
        s = sum(math.sin(2 * math.pi * f * k * t) / k ** 1.6 for k in range(1, 7))
        out.append(velocity * env * s)
    return out


def sung_note(midi: int, seconds: float, amplitude: float = 0.3) -> list[float]:
    """A vowel-ish tone: harmonic stack, vibrato, soft attack and release."""
    f0 = freq(midi)
    n = int(seconds * RATE)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        vib = 1 + 0.012 * math.sin(2 * math.pi * 5.5 * t) * min(1.0, t * 3)
        phase += 2 * math.pi * f0 * vib / RATE
        # Formant-ish weighting for an "eh/ay" vowel.
        s = sum(math.sin(k * phase) * (1 / k) * (1.4 if 3 <= k <= 5 else 1.0) for k in range(1, 10))
        env = min(1.0, t / 0.06) * min(1.0, (seconds - t) / 0.08)
        out.append(amplitude * env * s / 3)
    return out


def mix_into(track: list[float], clip: list[float], at: float) -> None:
    start = int(at * RATE)
    end = start + len(clip)
    if end > len(track):
        track.extend([0.0] * (end - len(track)))
    for i, s in enumerate(clip):
        track[start + i] += s


def silence(seconds: float) -> list[float]:
    return [0.0] * int(seconds * RATE)


def exercise(root: int, beat: float = 0.55) -> list[float]:
    """Piano cue chord, then piano + singer on 1-2-3-4-5-4-3-2-1."""
    track = silence(0)
    for note in (root, root + 4, root + 7):
        mix_into(track, piano_note(note, 2 * beat, 0.22), 0)
    offsets = [0, 2, 4, 5, 7, 5, 4, 2, 0]
    t = 2 * beat
    for k, off in enumerate(offsets):
        length = beat * (2 if k == len(offsets) - 1 else 1)
        mix_into(track, piano_note(root + off, length, 0.12), t)
        mix_into(track, sung_note(root + off, length * 0.95), t)
        t += length
    track.extend(silence(0.6))
    return track


def room_noise(track: list[float], level: float = 0.003) -> None:
    rng = random.Random(7)
    for i in range(len(track)):
        track[i] += rng.uniform(-level, level)


def write_wav(path: Path, samples: list[float]) -> None:
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = min(1.0, 0.9 / peak)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * scale)) * 32767)) for s in samples))


def to_m4a(wav: Path, m4a: Path) -> None:
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(wav), "-c:a", "aac", "-b:a", "64k", str(m4a)], check=True)


def main() -> None:
    if not shutil.which("ffmpeg"):
        sys.exit("ffmpeg is required.")
    OUT.mkdir(exist_ok=True)
    teacher_voice, student_voice, student_pitch = voices()

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)

        def speech(text: str, voice: str, pitch: float, name: str) -> list[float]:
            path = tmp / f"{name}.wav"
            tts(text, path, voice)
            return read_wav(path, pitch)

        t = [speech(line, teacher_voice, 1.0, f"t{i}") for i, line in enumerate(TEACHER_LINES)]
        s = [speech(line, student_voice, student_pitch, f"s{i}") for i, line in enumerate(STUDENT_LINES)]

        f3, fsharp3 = 53, 54
        lesson: list[float] = []
        for part in (silence(1.0), t[0], silence(1.2), exercise(f3), silence(1.0), t[1],
                     silence(0.8), s[0], silence(0.6), t[2], silence(1.0), exercise(fsharp3),
                     silence(1.0), t[3], silence(2.0)):
            lesson.extend(part)
        room_noise(lesson)

        lesson_wav = tmp / "lesson.wav"
        write_wav(lesson_wav, lesson)
        to_m4a(lesson_wav, OUT / "sample-lesson.m4a")

        long_wav = tmp / "long.wav"
        write_wav(long_wav, (lesson + silence(3.0)) * 8)
        to_m4a(long_wav, OUT / "sample-lesson-long.m4a")

        write_wav(OUT / "teacher-reference.wav", speech(TEACHER_REFERENCE, teacher_voice, 1.0, "tref")[: int(8 * RATE)])
        write_wav(OUT / "student-reference.wav", speech(STUDENT_REFERENCE, student_voice, student_pitch, "sref")[: int(8 * RATE)])

    for name in ("sample-lesson.m4a", "sample-lesson-long.m4a", "teacher-reference.wav", "student-reference.wav"):
        path = OUT / name
        print(f"{path.relative_to(ROOT)}  {path.stat().st_size / 1024:.0f} KiB")


if __name__ == "__main__":
    main()
