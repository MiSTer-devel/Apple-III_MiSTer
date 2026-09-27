#!/usr/bin/env python3
"""Make an Apple /// boot disk size memory up to 512K, so SOS uses it all.

SOS takes its memory size from the bank register its boot block leaves.
Apple's boot block ("SOS BOOT 1.1", "7.0") searches down from bank 6 and never
reports more than 256K; ON THREE's ("SOS BOOT 2.0", 1984, "2.2", 1985) checks
bank 14 against bank 6 first and hands SOS bank 14 on a 512K board. Putting it
on a disk is what ON THREE's upgrade did to the owner's disks
(docs/EXTERNAL_MEMORY.md).

--patch needs nothing else: it adds a 512K check of this repository's own to
the disk's Apple boot block in place, the same patch the SOS 512K update
disk (tools/sos512k) applies on the machine. Without --patch the tool copies
ON THREE's boot block from a donor image that has it, such as the "SOS 1.3
System Utilities" image (volume III.UTILS.01) that apple3.org and asimov
carry; that code is not in this repository.

The loader is block 0; the ROM loads nothing else, and the tool changes
nothing else. A hard-disk image made for soshdboot keeps its loader in block
1, and Rob Justice's loader already makes the check, so --check reports it and
the tool leaves such images alone. 140K DSK, DO and PO images in either sector
order and 2MG images work; WOZ does not (use the sector image).

  tools/onthree_boot.py --check DISK.dsk ...
  tools/onthree_boot.py --patch DISK.dsk [OUTPUT.dsk]
  tools/onthree_boot.py DONOR.dsk DISK.dsk [OUTPUT.dsk]
"""

import argparse
import os
import re
import struct
import sys

BLOCK = 512
FLOPPY = 143360
# DOS 3.3 sector holding each half of a ProDOS block within a track.
DOS_SECTOR = (0, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 15)


def is_volume(block):
    """A SOS/ProDOS volume directory key block (SOS 1.0's disks say 12 entries a block, later ones 13)."""
    return block[0:2] == b"\0\0" and block[4] >> 4 == 0xF and block[0x23] == 0x27 and block[0x24] in (0x0C, 0x0D)


class Image:
    """A sector image and where its ProDOS block 0 lives in the file."""

    def __init__(self, path):
        with open(path, "rb") as handle:
            self.data = bytearray(handle.read())
        self.path = path
        self.base = 0
        self.dos_order = False
        length = len(self.data)
        if self.data[:4] == b"2IMG":
            order, = struct.unpack_from("<I", self.data, 12)
            self.base, length = struct.unpack_from("<II", self.data, 24)
            if order not in (0, 1):
                raise ValueError(f"{path}: a nibble 2MG has no block 0 to replace")
            self.dos_order = order == 0
        elif length == FLOPPY:
            prodos = is_volume(self._raw_block(2, False))
            dos = is_volume(self._raw_block(2, True))
            if dos and not prodos:
                self.dos_order = True
            elif not prodos:
                # Not a SOS or ProDOS volume: guess from the extension.
                self.dos_order = os.path.splitext(path)[1].lower() in (".dsk", ".do")
        if length % BLOCK or length < 2 * BLOCK or self.data[:3] == b"WOZ":
            raise ValueError(f"{path}: not a sector image (WOZ and NIB are not supported)")
        self.length = length

    def _offsets(self, block, dos_order):
        if not dos_order:
            return [self.base + block * BLOCK, self.base + block * BLOCK + 256]
        track, index = divmod(block, 8)
        return [self.base + track * 4096 + DOS_SECTOR[2 * index + half] * 256 for half in (0, 1)]

    def _raw_block(self, block, dos_order):
        return b"".join(bytes(self.data[o:o + 256]) for o in self._offsets(block, dos_order))

    def block(self, block):
        return self._raw_block(block, self.dos_order)

    def write_block(self, block, data):
        for half, offset in enumerate(self._offsets(block, self.dos_order)):
            self.data[offset:offset + 256] = data[half * 256:half * 256 + 256]

    def volume(self):
        key = self.block(2)
        return key[5:5 + (key[4] & 0x0F)].decode("ascii", "replace") if is_volume(key) else None


# LDA #$0E, STA $FFEF, STA $2000, LDA #$06, STA $FFEF, STA $2000: mark bank
# 14, then bank 6, which is the same cell on Apple's 256K board. ON THREE's
# loaders and Rob Justice's soshdboot loader open their bank search with it.
PROBE_512K = bytes.fromhex("a90e8defff8d0020a9068defff8d0020")


# The patch to Apple's SOS BOOT 1.1: offset in block 0, Apple's bytes, ours.
# It probes with bank registers 15 and 7, which Apple's boards (three bank
# register bits) take as the same byte and the 512K board does not, and
# leaves 15 or 7 where Apple's search starts. Like ON THREE's 2.2 it also
# puts an opcode at $2034 of bank 6: $AD, the LDA SOS 1.1-1.3 have there, in
# case a real board fetches the opcode after the loader's switch from bank 14
# to bank 0 from bank 6, as 2.2's own byte there suggests. The core latches
# all four bank bits, so it never does. The code lives in the header text, the spaces after the
# kernel's name and the unused tail, called from Apple's setup at $A078,
# rewritten with its search loop kept and two redundant loads dropped.
# tools/sos512k/sos512k.s carries the same table, and
# tools/test_onthree_boot.py checks that they agree.
PATCH = (
    # DEX, STX $FFEF (bank 6), STY $2034, STA $FFEF (15), LDA $2000, RTS
    (0x003, b"SOS BOOT  1.1 ", bytes.fromhex("ca 8eefff 8c3420 8defff ad0020 60")),
    # STX $2000 (bank 7), BNE $A003
    (0x01C, b"     ", bytes.fromhex("8e0020 d0e2")),
    # BIT $C010, LDA #$40, STA $FFCA, then LDY #$AD, LDA #$0F, JSR $A1F2,
    # STA $FFEF, Apple's search, and its block pointers from A=0, X=0
    (0x078, bytes.fromhex("2c10c0 a940 8dcaff a907 8defff a200 ceefff 8e0020 ad0020 d0f5"
                          " a901 85e0 a900 85e1 a900 8585 a9a2 8586"),
     bytes.fromhex("2c10c0 a940 8dcaff a0ad a90f 20f2a1 8defff a200 ceefff 8e0020 ad0020 d0f5"
                   " 85e1 8585 e8 86e0 a9a2 8586")),
    # STA $FFEF (15), STA $2000, LDX #$07, STX $FFEF, JMP $A01C
    (0x1F2, bytes(14), bytes.fromhex("8defff 8d0020 a207 8eefff 4c1ca0")),
)
# Apple's SOS BOOT 7.0 is 1.1's code with another header and two stray words
# in the tail, which nothing reads: its bytes where they differ from 1.1's.
APPLE_70 = {0x003: b"SOS BOOT  7.0 ", 0x1F2: bytes.fromhex("0000 0000 0000 0000 fa01 0000 0200")}


def patch_state(block0):
    """'apple' when the patch fits Apple's bytes, 'patched' when it is there."""
    def holds(regions):
        return all(block0[offset:offset + len(data)] == data for offset, data in regions)
    if holds((offset, new) for offset, _, new in PATCH):
        return "patched"
    if holds((offset, old) for offset, old, _ in PATCH):
        return "apple"
    if holds((offset, APPLE_70.get(offset, old)) for offset, old, _ in PATCH):
        return "apple"
    return None


# What SOS makes of the memory with a boot block.
MEMORY = {
    "512k": "sees 512K",
    "256k": "256K at most",
}


def describe(block0):
    """Name a boot block and say what SOS sees from it: a MEMORY key."""
    if patch_state(block0) == "patched":
        return "Apple's SOS boot block with the 512K patch", "512k"
    text = bytes(b & 0x7F for b in block0)
    memory = "512k" if PROBE_512K in block0 else "256k"
    version = re.search(rb"SOS BOOT\s+(\d+\.\d+)", text)
    if version:
        maker = "ON THREE" if b"ON THREE" in text else "Apple"
        return f"{maker} SOS BOOT {version.group(1).decode()}", memory
    if memory == "512k":
        return "a 512K-aware loader", memory
    return "no SOS boot block", memory


def check(paths):
    for path in paths:
        try:
            image = Image(path)
        except (OSError, ValueError) as error:
            print(f"{path}: {error}")
            continue
        name, memory = describe(image.block(0))
        if name == "no SOS boot block":
            name, memory = describe(image.block(1))
            if name != "no SOS boot block":
                name += " in block 1"
        volume = image.volume() or "?"
        print(f"{path}: /{volume}, {name}: {MEMORY[memory]}")


def install(donor_path, target_path, output_path):
    donor = Image(donor_path)
    boot, memory = describe(donor.block(0))
    if not (boot.startswith("ON THREE") and memory == "512k"):
        sys.exit(f"{donor_path}: its boot block is {boot}, not ON THREE's")
    target = Image(target_path)
    current, _ = describe(target.block(0))
    if current == "no SOS boot block":
        sys.exit(f"{target_path}: block 0 is not a SOS boot block; is it a SOS disk?")
    if current.startswith("ON THREE"):
        print(f"{target_path} already has {current}")
    target.write_block(0, donor.block(0))
    with open(output_path, "wb") as handle:
        handle.write(target.data)
    print(f"{output_path}: /{target.volume() or '?'} now boots with {boot} (was {current})")


def apply_patch(target_path, output_path):
    target = Image(target_path)
    block0 = bytearray(target.block(0))
    current, memory = describe(bytes(block0))
    state = patch_state(bytes(block0))
    if state != "apple":
        if memory == "512k":
            sys.exit(f"{target_path}: {current} already sees 512K")
        sys.exit(f"{target_path}: {current}, not Apple's SOS BOOT 1.1 or 7.0; left alone")
    for offset, _, new in PATCH:
        block0[offset:offset + len(new)] = new
    target.write_block(0, bytes(block0))
    with open(output_path, "wb") as handle:
        handle.write(target.data)
    print(f"{output_path}: /{target.volume() or '?'} now sizes memory up to 512K (was {current})")


def main():
    parser = argparse.ArgumentParser(description=(__doc__ or "").split("\n\n")[0])
    parser.add_argument("--check", action="store_true", help="report each image's boot block and exit")
    parser.add_argument("--patch", action="store_true", help="patch the disk's own Apple boot block; no donor")
    parser.add_argument("images", nargs="+", help="[DONOR] DISK [OUTPUT], or the images to check")
    args = parser.parse_args()
    if args.check:
        check(args.images)
        return
    if args.patch:
        if len(args.images) not in (1, 2):
            parser.error("--patch takes DISK and optionally OUTPUT")
        target = args.images[0]
        stem, ext = os.path.splitext(target)
        apply_patch(target, args.images[1] if len(args.images) == 2 else f"{stem}-512k{ext}")
        return
    if len(args.images) not in (2, 3):
        parser.error("give DONOR and DISK, and optionally OUTPUT")
    donor, target = args.images[:2]
    if len(args.images) == 3:
        output = args.images[2]
    else:
        stem, ext = os.path.splitext(target)
        output = f"{stem}-512k{ext}"
    if os.path.abspath(output) == os.path.abspath(donor):
        parser.error("OUTPUT must not be the donor")
    install(donor, target, output)


if __name__ == "__main__":
    main()
