#!/usr/bin/env bash
# Rebuild clip_ar.mp4: a 45.5 s excerpt of "A Conversation with Bertrand Russell (1952)"
# (https://youtu.be/xL_sMXfzzyA) covering 26:40.0 -> 27:25.5, with Arabic subtitles
# burned into the picture.
#
# The video has no Arabic subtitle track; subs.ar.srt is a hand-made Arabic translation
# of the English subtitle track, timed on the ORIGINAL video timeline.
#
# Usage: ./build_clip.sh [path/to/cookies.txt]
set -euo pipefail

URL="https://youtu.be/xL_sMXfzzyA"
COOKIES="${1:-}"

# --- prerequisites -----------------------------------------------------------
command -v yt-dlp >/dev/null || { echo "yt-dlp missing: pip install yt-dlp" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg missing: apt-get install ffmpeg" >&2; exit 1; }

# libass must be linked against fribidi + harfbuzz or Arabic renders unshaped and LTR.
libass=$(ldconfig -p | grep -oE '/[^ ]*libass\.so[^ ]*' | head -1)
for lib in libfribidi libharfbuzz; do
  ldd "$libass" | grep -q "$lib" || { echo "libass lacks $lib - Arabic would render broken" >&2; exit 1; }
done

fc-list :lang=ar | grep -q . || { echo "no Arabic font: apt-get install fonts-noto-core" >&2; exit 1; }

# --- download ----------------------------------------------------------------
# YouTube requires an authenticated session here; without cookies every media
# request returns HTTP 403. deno provides the JS runtime yt-dlp needs.
if [ ! -f vid.mp4 ]; then
  yt-dlp ${COOKIES:+--cookies "$COOKIES"} --remote-components ejs:github \
    -f "bv*+ba/b" --merge-output-format mp4 \
    --retries 20 --fragment-retries 20 \
    -o "vid.%(ext)s" "$URL"
fi

# --- cut + burn in a single pass ---------------------------------------------
# -copyts keeps the source timeline so the SRT's 00:26:40-based cues line up;
# -start_at_zero / -avoid_negative_ts rebase the output to zero.
ffmpeg -y -ss 26:40 -to 27:25.5 -copyts -i vid.mp4 \
  -vf "subtitles=subs.ar.srt:force_style='FontName=Noto Naskh Arabic,Fontsize=22,Outline=1,Shadow=0,MarginV=30'" \
  -start_at_zero -avoid_negative_ts make_zero \
  -c:v libx264 -crf 18 -preset medium -c:a aac -b:a 192k clip_ar.mp4

ffprobe -v error -show_entries format=duration -of csv=p=0 clip_ar.mp4
