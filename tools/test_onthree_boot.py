#!/usr/bin/env python3
"""tools/onthree_boot.py on made-up images: no Apple or ON THREE code needed.

A donor carries a stand-in ON THREE boot block (the 512K probe and a version
string), the target a stand-in Apple one holding just the bytes the patch
expects. Each is built in ProDOS order, DOS order and as a 2MG; the donor copy
and --patch must change exactly block 0 and report the result. With ca65, the
patch table in tools/sos512k/sos512k.s must match the tool's.
"""

import os
import shutil
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "onthree_boot.py")
sys.path.insert(0, HERE)
import onthree_boot

BLOCK = 512
DOS_SECTOR = onthree_boot.DOS_SECTOR


def tool(*args, check=True):
    return subprocess.run([sys.executable, TOOL, *args], capture_output=True, text=True, check=check)


def boot_block(text, probe):
    block = bytearray(BLOCK)
    block[0:3] = b"\x4c\x6e\xa0"
    block[3:3 + len(text)] = text
    if probe:
        block[0x80:0x90] = onthree_boot.PROBE_512K
    return bytes(block)


def apple_patch_target(release):
    """Block 0 with Apple's bytes where the patch goes and filler elsewhere."""
    block = bytearray(boot_block(b"", False))
    block[0x20:0x70] = bytes(range(0x20, 0x70))
    for offset, old, _ in onthree_boot.PATCH:
        if release == "7.0":
            old = onthree_boot.APPLE_70.get(offset, old)
        block[offset:offset + len(old)] = old
    return bytes(block)


def check_assembly_table():
    """The update disk's table: offsets, lengths, Apple's bytes, then ours."""
    if not shutil.which("ca65") or not shutil.which("ld65"):
        print("SKIP sos512k table comparison: needs ca65 and ld65")
        return 0
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run([os.path.join(HERE, "sos512k", "build.sh"), os.path.join(tmp, "SOS512K.po")], check=True,
                       capture_output=True)
        with open(os.path.join(tmp, "SOS512K.po"), "rb") as handle:
            program = handle.read(2048)
    patch = onthree_boot.PATCH
    table = b"".join(struct.pack("<H", offset) for offset, _, _ in patch)
    table += bytes(len(old) for _, old, _ in patch)
    table += b"".join(old for _, old, _ in patch) + b"".join(new for _, _, new in patch)
    table += b"".join(onthree_boot.APPLE_70.get(offset, old) for offset, old, _ in patch)
    assert table in program, "tools/sos512k/sos512k.s and onthree_boot.PATCH differ"
    return 1


def volume(name, boot):
    blocks = [bytearray(BLOCK) for _ in range(280)]
    blocks[0][:] = boot
    blocks[1][:] = bytes([0xB1]) * BLOCK  # must survive
    key = blocks[2]
    key[4] = 0xF0 | len(name)
    key[5:5 + len(name)] = name
    key[0x23], key[0x24] = 0x27, 0x0D
    for n in range(3, 280):
        blocks[n][:] = bytes([n & 0xFF]) * BLOCK
    return blocks


def image(blocks, form):
    if form == "po":
        return b"".join(blocks)
    data = bytearray(280 * BLOCK)
    for n, block in enumerate(blocks):
        track, index = divmod(n, 8)
        for half in (0, 1):
            offset = track * 4096 + DOS_SECTOR[2 * index + half] * 256
            data[offset:offset + 256] = block[half * 256:half * 256 + 256]
    if form == "dsk":
        return bytes(data)
    header = bytearray(64)
    header[0:4] = b"2IMG"
    # Creator, header size, version, format (0 = DOS order), flags, blocks, data offset, data length.
    struct.pack_into("<4sHHIIIII", header, 4, b"TEST", 64, 1, 0, 0, 280, 64, len(data))
    return bytes(header) + bytes(data)


def main():
    donor_boot = boot_block(b"SOS BOOT 2.2 by B.C. (c) 1985 by ON THREE.", True)
    apple_boot = boot_block(b"SOS BOOT  1.1 \nSOS.KERNEL", False)
    checks = 0
    with tempfile.TemporaryDirectory() as tmp:
        for form in ("po", "dsk", "2mg"):
            donor = os.path.join(tmp, f"donor.{form}")
            target = os.path.join(tmp, f"target.{form}")
            output = os.path.join(tmp, f"out.{form}")
            with open(donor, "wb") as handle:
                handle.write(image(volume(b"DONOR", donor_boot), form))
            target_blocks = volume(b"TARGET", apple_boot)
            with open(target, "wb") as handle:
                handle.write(image(target_blocks, form))

            report = tool("--check", donor, target).stdout
            assert "/DONOR, ON THREE SOS BOOT 2.2: sees 512K" in report, report
            assert "/TARGET, Apple SOS BOOT 1.1: 256K at most" in report, report
            tool(donor, target, output)

            result = onthree_boot.Image(output)
            assert result.block(0) == donor_boot, form
            for n in range(1, 280):
                assert result.block(n) == bytes(target_blocks[n]), (form, n)
            with open(target, "rb") as a, open(output, "rb") as b:
                before, after = a.read(), b.read()
            changed = sum(1 for x, y in zip(before, after) if x != y)
            assert len(before) == len(after) and 0 < changed <= BLOCK, (form, changed)
            checks += 1

            # The donor must really be ON THREE's, and the target a SOS disk.
            refused = tool(target, donor, output, check=False)
            assert refused.returncode != 0 and "not ON THREE's" in refused.stderr, refused.stderr
            checks += 1

            # --patch: Apple's bytes become ours, everything else stays.
            for release in ("1.1", "7.0"):
                apple = os.path.join(tmp, f"apple.{form}")
                patched = os.path.join(tmp, f"patched.{form}")
                original = apple_patch_target(release)
                apple_blocks = volume(b"APPLE", original)
                with open(apple, "wb") as handle:
                    handle.write(image(apple_blocks, form))
                report = tool("--check", apple).stdout
                assert f"Apple SOS BOOT {release}: 256K at most" in report, report
                tool("--patch", apple, patched)
                expected = bytearray(original)
                for offset, _, new in onthree_boot.PATCH:
                    expected[offset:offset + len(new)] = new
                result = onthree_boot.Image(patched)
                assert result.block(0) == bytes(expected), (form, release)
                for n in range(1, 280):
                    assert result.block(n) == bytes(apple_blocks[n]), (form, release, n)
                report = tool("--check", patched).stdout
                assert "with the 512K patch: sees 512K" in report, report
                again = tool("--patch", patched, output, check=False)
                assert again.returncode != 0 and "already sees 512K" in again.stderr, again.stderr
                checks += 1
            refused = tool("--patch", donor, output, check=False)
            assert refused.returncode != 0 and "already sees 512K" in refused.stderr, refused.stderr
            refused = tool("--patch", target, output, check=False)
            assert refused.returncode != 0 and "left alone" in refused.stderr, refused.stderr
            checks += 1
    checks += check_assembly_table()
    print(f"PASS onthree_boot: donor copy and --patch change block 0 only, in PO, DSK and 2MG ({checks} checks)")


if __name__ == "__main__":
    main()
