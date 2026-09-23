#!/bin/zsh
# FxSound for Mac — 30-minute soak test (plan9 §5 gate).
#
# Keeps test audio playing while the app processes, samples CPU/memory every minute,
# and reports the engine's overrun/underrun counters at the end.
#
# Prereqs: app built (Release), power on via --power=1, Audio Recording permission granted.
# Usage: Scripts/soak_test.sh [minutes]   (default 30)

set -euo pipefail
cd "$(dirname "$0")/.."

MINUTES="${1:-30}"
APP="build/derived/Build/Products/Release/fxsound.app"
[ -d "$APP" ] || APP=$(find ~/Library/Developer/Xcode/DerivedData /Volumes/essd/xcode/drivedata -name "fxsound.app" -path "*Release*" 2>/dev/null | head -1)
[ -d "$APP" ] || { echo "fxsound.app not found — build Release first"; exit 1; }

echo "==> Launching with --power=1"
pkill -9 -x fxsound 2>/dev/null || true; sleep 1
open -n "$APP" --args --power=1
sleep 5
PID=$(pgrep -x fxsound) || { echo "app did not start"; exit 1; }
echo "==> pid $PID — playing audio for ${MINUTES} minutes"

python3 - << 'EOF' > /tmp/fxsound-soak.wav
import wave, math, struct
sr = 44100
with wave.open("/dev/stdout", "w") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr)
    for i in range(sr * 20):  # 20s sweep-like looping tone
        t = i / sr
        f = 220 + 300 * (1 + math.sin(2 * math.pi * t / 4))
        s = int(0.3 * 32767 * math.sin(2 * math.pi * f * t))
        w.writeframesraw(struct.pack("<hh", s, s))
EOF

END=$((SECONDS + MINUTES * 60))
while [ $SECONDS -lt $END ]; do
  afplay /tmp/fxsound-soak.wav &
  sleep 15
  top -l 1 -pid "$PID" -stats pid,cpu,mem 2>/dev/null | tail -1
done

echo "==> Final engine stats (5s before quit):"
/usr/bin/log show --last 10s --predicate 'subsystem == "com.aliahad.fxsound"' --info 2>/dev/null | grep "stats" | tail -1
kill -TERM "$PID"
echo "==> Soak complete"
