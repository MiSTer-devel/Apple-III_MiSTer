#!/usr/bin/env bash
# Build the SOS 512K update disk: a 140K ProDOS-order image whose first four
# blocks are the program. Needs ca65 and ld65 (cc65).
#   tools/sos512k/build.sh [OUTPUT.po]   (default sim/obj_dir/sos512k/SOS512K.po)
set -euo pipefail
cd "$(dirname "$0")/../.."
out=sim/obj_dir/sos512k
mkdir -p "$out"
image=${1:-$out/SOS512K.po}
ca65 -l "$out/sos512k.lst" -o "$out/sos512k.o" tools/sos512k/sos512k.s
ld65 -C tools/sos512k/sos512k.cfg -o "$out/sos512k.bin" "$out/sos512k.o"
cp "$out/sos512k.bin" "$image"
truncate -s 143360 "$image"
echo "$image"
