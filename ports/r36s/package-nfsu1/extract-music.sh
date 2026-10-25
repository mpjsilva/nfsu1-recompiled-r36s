#!/bin/bash
# extract-music.sh - fill the port's music player from your own NFSU1 soundtrack.
#
# The game's own EA Trax is one big EA stream bank, SNDSTREAMS/STRM_Music_UG0_MB.ast, with the songs
# concatenated (one SCHl..SCEl block each). The recompiled game opens it but does not play it here, so this
# script carves each song out of YOUR copy and decodes it to OGG into the music player's folders, where the
# port's own player picks it up (music/race, and a few copied to music/menu). It needs ffmpeg.
#
# Usage: extract-music.sh [GAMEDIR]   (default: the folder this script sits in)
# Run it once on a PC or on the device; it only reads files you already own and writes into music/.
set -e
GAMEDIR="${1:-$(cd "$(dirname "$0")" && pwd)}"
AST=$(find "$GAMEDIR/gamedata" -ipath '*SNDSTREAMS*STRM_Music_UG0_MB.ast' 2>/dev/null | head -1)
[ -n "$AST" ] || { echo "STRM_Music_UG0_MB.ast not found under $GAMEDIR/gamedata"; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg is required (install it, then re-run)"; exit 1; }

RACE="$GAMEDIR/music/race"; MENU="$GAMEDIR/music/menu"
mkdir -p "$RACE" "$MENU"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# Byte offset of every song header, plus the file size as the final boundary.
mapfile -t OFF < <(grep -abo 'SCHl' "$AST" | cut -d: -f1)
SIZE=$(stat -c%s "$AST")
OFF+=("$SIZE")
N=$(( ${#OFF[@]} - 1 ))
echo "Found $N songs in $(basename "$AST"); decoding to OGG (this takes a few minutes)..."

for ((i=0; i<N; i++)); do
  start=${OFF[i]}; len=$(( ${OFF[i+1]} - start ))
  piece="$TMP/song.ast"
  dd if="$AST" of="$piece" bs=1M iflag=skip_bytes,count_bytes skip="$start" count="$len" status=none
  out=$(printf "%s/track%02d.ogg" "$RACE" $((i+1)))
  ffmpeg -hide_banner -loglevel error -y -i "$piece" -ac 2 -c:a libvorbis -q:a 2 "$out" </dev/null || { echo "  track $((i+1)) failed, skipped"; continue; }
  printf "  track%02d.ogg\n" $((i+1))
done

# Give the menus a little music too (the player falls back to the race list when menu/ is empty, but a few
# dedicated tracks keep the menu quieter than a race mix).
for n in 01 02 03; do [ -f "$RACE/track$n.ogg" ] && cp -f "$RACE/track$n.ogg" "$MENU/track$n.ogg"; done
echo "Done: $(ls "$RACE"/*.ogg 2>/dev/null | wc -l) race tracks, $(ls "$MENU"/*.ogg 2>/dev/null | wc -l) menu tracks."
