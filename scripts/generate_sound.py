#!/usr/bin/env python3
"""Generate a short notification OGG sound file."""
import struct
import math
import wave
import os

# Generate a simple alarm-like tone
sample_rate = 22050
duration = 2.0  # seconds
frequency = 880  # Hz - A5, pleasant alarm tone

frames = []
for i in range(int(sample_rate * duration)):
    t = i / sample_rate
    # Two alternating tones for alarm effect
    tone = (math.sin(2 * math.pi * 880 * t) * 0.5 +
            math.sin(2 * math.pi * 1320 * t) * 0.3) * 0.5
    # Amplitude envelope - fade in/out
    env = min(1.0, t * 10) * min(1.0, (duration - t) * 10)
    tone *= env
    # Convert to 16-bit PCM
    sample = int(tone * 32767)
    frames.append(struct.pack('<h', sample))

# Write WAV
os.makedirs('/root/hermes/deep_focus/android/app/src/main/res/raw', exist_ok=True)
with wave.open('/tmp/alarm.wav', 'w') as wf:
    wf.setnchannels(1)
    wf.setsampwidth(2)
    wf.setframerate(sample_rate)
    wf.writeframes(b''.join(frames))

print("WAV generated.")

# Try to convert to OGG for Android
try:
    import subprocess
    subprocess.run(['ffmpeg', '-y', '-i', '/tmp/alarm.wav', 
                    '-codec:a', 'libvorbis', 
                    '-qscale:a', '3',
                    '/root/hermes/deep_focus/android/app/src/main/res/raw/alarm.ogg'], 
                   check=True, capture_output=True)
    print("OGG generated via ffmpeg.")
except (subprocess.CalledProcessError, FileNotFoundError):
    # Fallback: Android accepts WAV in res/raw
    import shutil
    shutil.copy('/tmp/alarm.wav', '/root/hermes/deep_focus/android/app/src/main/res/raw/alarm.wav')
    print("ffmpeg not found, copied WAV instead.")
