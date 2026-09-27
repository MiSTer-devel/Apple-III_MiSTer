#!/usr/bin/env bash
# Build the SOS features test interpreter, sim/obj_dir/sosfeat/SOS.INTERP, and
# with a SOS 1.3 disk and AppleCommander, a test disk that runs it:
#   sim/sosfeat/build.sh [SOS13DISK.dsk AC.jar [OUTPUT.dsk]]
# The disk keeps its SOS.KERNEL and SOS.DRIVER (Apple's, not in this
# repository); its SOS.INTERP is replaced. Needs ca65 and ld65 (cc65).
set -euo pipefail
cd "$(dirname "$0")/../.."
out=sim/obj_dir/sosfeat
mkdir -p "$out"
ca65 -l "$out/sosfeat.lst" -o "$out/sosfeat.o" sim/sosfeat/sosfeat.s
ld65 -C sim/sosfeat/sosfeat.cfg -o "$out/SOS.INTERP" "$out/sosfeat.o"
echo "$out/SOS.INTERP"
if [[ $# -ge 2 ]]; then
	disk=${3:-$out/sosfeat.dsk}
	cp "$1" "$disk"
	java -jar "$2" -d "$disk" SOS.INTERP
	java -jar "$2" -p "$disk" SOS.INTERP SOS '$0000' < "$out/SOS.INTERP"
	echo "$disk"
fi
