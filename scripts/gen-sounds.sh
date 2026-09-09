#!/bin/bash
# Regenerates the three Sci-Fi chimes: plug.wav, unplug.wav, inject.wav.
# Fully synthesized with ffmpeg — no sampled/third-party audio is used.
# Requires: ffmpeg, python3.
set -euo pipefail
OUT="$(cd "$(dirname "$0")/.." && pwd)/sounds"
TMP=/tmp/sndplug-gen
rm -rf "$TMP"; mkdir -p "$TMP" "$OUT"

tone() { # 1=file 2=freq 3=dur 4=decay 5=harm 6=amp
  local file="$1" freq="$2" dur="$3" decay="$4" harm="${5:-0}" amp="${6:-0.35}"
  ffmpeg -y -v error -f lavfi \
    -i "aevalsrc=$amp*(sin(2*PI*$freq*t) + $harm*0.35*sin(2*PI*2*$freq*t))*exp(-$decay*t):s=44100:d=$dur" \
    -c:a pcm_s16le "$file"
}
gap() { ffmpeg -y -v error -f lavfi -i "anullsrc=r=44100:cl=mono:d=$2" -c:a pcm_s16le "$1"; }
concat() {
  local out="$1"; shift
  : > "$TMP/list.txt"
  for f in "$@"; do printf "file '%s'\n" "$f" >> "$TMP/list.txt"; done
  ffmpeg -y -v error -f concat -safe 0 -i "$TMP/list.txt" -c:a pcm_s16le "$out"
}
sweep() { # 1=file 2=start 3=end 4=steps 5=durEach
  local file="$1" start="$2" end="$3" steps="$4" dure="$5"
  local i f files=()
  for ((i=0;i<steps;i++)); do
    f=$(python3 -c "print(round($start + ($end-$start)*$i/($steps-1),1))")
    tone "$TMP/sw$i.wav" "$f" "$dure" 4.0
    files+=("$TMP/sw$i.wav")
  done
  concat "$file" "${files[@]}"
}

# plug:   rising sweep 320 -> 660 Hz
sweep "$OUT/plug.wav"   320 660 4 0.10
# unplug: falling sweep 660 -> 330 Hz
sweep "$OUT/unplug.wav" 660 330 4 0.12
# inject: 880 – 660 – 880 arpeggio with tail
tone "$TMP/a.wav" 880 0.12 4.0; gap "$TMP/g.wav" 0.06
tone "$TMP/b.wav" 660 0.12 4.0; gap "$TMP/h.wav" 0.06
tone "$TMP/c.wav" 880 0.22 3.5
concat "$OUT/inject.wav" "$TMP/a.wav" "$TMP/g.wav" "$TMP/b.wav" "$TMP/h.wav" "$TMP/c.wav"

echo "generated:"
ls -la "$OUT"