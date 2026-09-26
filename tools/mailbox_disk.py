#!/usr/bin/env python3
"""Build the Mailbox floppy: a Business BASIC disk that boots into MAILBOX.BAS.

The Apple /// answers MiSTer's modem and keeps messages for one caller, who
reaches it with any telnet program. The disk takes the boot blocks, SOS.KERNEL,
SOS.DRIVER (with .RS232), SOS.INTERP and REQUEST.INV from Apple's Business
BASIC 1.23 disk, and adds the program as HELLO, which Business BASIC runs at
boot.

  tools/mailbox_disk.py Apple3BusBasic1.23.dsk Mailbox.dsk
  tools/mailbox_disk.py Apple3BusBasic1.23.dsk New.dsk --messages-from Mailbox.dsk
"""

import argparse
import datetime
import os
import sys

import blank_hd as volume
import business_basic

KEEP = ("SOS.KERNEL", "SOS.DRIVER", "SOS.INTERP", "REQUEST.INV")
MESSAGES = ("INBOX", "OUTBOX", "PARTYLOG")
SOURCE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mailbox", "MAILBOX.BAS")
BA3 = 0x09


def new_entry(name, file_type, data):
    """A file entry for build(), which fills in the storage type and blocks."""
    entry = bytearray(volume.ENTRY)
    entry[0] = len(name)
    entry[1:1 + len(name)] = name.encode("ascii")
    entry[0x10] = file_type
    entry[0x15:0x18] = len(data).to_bytes(3, "little")
    stamp = volume.prodos_date(datetime.datetime.now().astimezone())
    entry[0x18:0x1C] = stamp
    entry[0x1E] = 0xC3  # destroy, rename, write, read
    entry[0x21:0x25] = stamp
    return entry


def dos_order(image):
    """Reorder a 140K ProDOS-order image into DOS 3.3 sector order."""
    out = bytearray(len(image))
    for block in range(len(image) // volume.BLOCK):
        track, index = divmod(block, 8)
        for half in (0, 1):
            sector = volume.DOS_SECTOR[2 * index + half]
            out[(track * 16 + sector) * 256:(track * 16 + sector + 1) * 256] = \
                image[block * volume.BLOCK + half * 256:block * volume.BLOCK + half * 256 + 256]
    return bytes(out)


def main():
    parser = argparse.ArgumentParser(description="Build the Mailbox floppy from Business BASIC 1.23.")
    parser.add_argument("basic", help="Apple's Business BASIC 1.23 disk (Apple3BusBasic1.23.dsk)")
    parser.add_argument("output", help="disk image to write (.dsk, DOS order)")
    parser.add_argument("--source", default=SOURCE, help="program to put on the disk as HELLO")
    parser.add_argument("--messages-from", metavar="IMAGE",
                        help="an older Mailbox disk whose INBOX, OUTBOX and PARTYLOG to keep")
    args = parser.parse_args()

    basic = volume.Volume(args.basic)
    root = dict(basic.root())
    files = []
    for name in KEEP:
        if name not in root:
            sys.exit(f"{args.basic}: no {name}; is this Business BASIC 1.23?")
        files.append((root[name], basic.contents(root[name])))
    with open(args.source, encoding="latin-1") as source:
        try:
            program = business_basic.tokenize(source.read())
        except ValueError as error:
            sys.exit(f"{args.source}: {error}")
    blocks = [program[i:i + volume.BLOCK].ljust(volume.BLOCK, b"\0")
              for i in range(0, len(program), volume.BLOCK)]
    files.append((new_entry("HELLO", BA3, program), blocks))
    if args.messages_from:
        previous = volume.Volume(args.messages_from)
        old = dict(previous.root())
        files += [(old[name], previous.contents(old[name])) for name in MESSAGES if name in old]

    image = volume.build(280, "MAILBOX", files, basic.data[:2 * volume.BLOCK])
    with open(args.output, "wb") as out:
        out.write(dos_order(image))
    free = sum(byte.bit_count() for byte in image[volume.BITMAP * volume.BLOCK:][:35])
    print(f"{args.output}: /MAILBOX, HELLO is {len(program):,} bytes, {free} blocks free for messages")


if __name__ == "__main__":
    main()
