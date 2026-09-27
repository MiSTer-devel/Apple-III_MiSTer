# SOS features test

`sosfeat.s` is a SOS interpreter that checks, on the machine, the SOS
features Rick Sidwell's "Undocumented Apple /// SOS Features" (January 1989)
describes, where they rest on the hardware: D_READ and D_WRITE through the
Disk /// driver and its errors, the keyboard NMI and NMIDSBL/NMIENBL (the
environment register's bit 4 gating RESET and CONTROL-RESET), SUSPFLSH from
CONTROL-7 and CONTROL-9 on the keypad, MEMSIZE and SYSBANK for each board,
CLRBACK, the page $19 globals and SYSFAIL. The buffer routines (REQBUF,
GETBUFADR, RELBUF) are for device drivers only; SOS's own file buffers use
them during the D_WRITE and CLRBACK groups.

It runs in place of a SOS 1.3 disk's `SOS.INTERP`, so the disk's kernel and
drivers, which are Apple's, stay out of the repository:

```sh
sim/sosfeat/build.sh Apple3SOS1.3SysUtils.dsk ac.jar sosfeat.dsk   # AppleCommander
```

Drive 2 needs a writable SOS disk with room for a one-block file; block 279
is written and put back. The program prints a line per group and a summary:

```
SOS FEATURES 123456789ABCD
             PPPPPPPPPPPPP
```

then waits for RETURN and calls SYSFAIL with `$42`, which shows
`SYSTEM FAILURE = $42` and saves the registers at `$19F6`-`$19FF`.

| Group | Checks |
|---|---|
| 1 | MEMSIZE `$08`, `$10` or `$20` (128K, 256K, 512K) and MEMSIZE = SYSBANK * 2 + 4 |
| 2 | D_READ `.D1` block 0 (the boot block) and block 2 (the volume header) |
| 3 | D_READ errors: BYTECNT (`$2C`) for 256 bytes, BLKNUM (`$2D`) for block 280 |
| 4 | D_WRITE `.D2` block 279, read back, then restored |
| 5 | CLRBACK: SET_FILE_INFO keeps a new file's backup bit unless CLRBACK comes first |
| 6 | NMIPEND bit 7 clear, DISKBUSY 0, DFLTNMI set; GRAFMEM and SCRNMODE shown |
| 7 | RESET runs the interpreter's USRNMI handler |
| 8 | NMIDSBL clears environment bit 4; RESET and CONTROL-RESET are ignored |
| 9 | NMIENBL sets it again; RESET is handled |
| A | CONTROL-7 on the keypad sets SUSPFLSH bit 7, again clears it |
| B | CONTROL-9 on the keypad sets SUSPFLSH bit 6, again clears it |
| C | D_READ after drive 2's disk is swapped returns DISKSW (`$2E`), then reads |
| D | D_READ with drive 2 empty returns NODRIVE (`$28`) |

In the harness, from the first prompt (F2 is RESET):

```sh
./sim/run_core_boot.sh 5000000000 sosfeat.woz --drive2=scratch.woz --writable \
  --keys-after="PRESS RESET" \
  --keys=wait1,f2,wait2,enter,wait4,f2,wait2,ctrl+f2,wait2,enter,wait4,f2,wait2,enter,wait4,ctrl+kp7,wait3,ctrl+kp7,wait4,ctrl+kp9,wait3,ctrl+kp9,wait4,disk2:other.woz,wait2,enter,wait12,disk2:-,wait2,enter,wait12,dump,enter,wait5,dump \
  --dump-mem=19F0,10
```

Add `--ram128k` or `--ram512k` for the other boards (512K needs a boot block
that sees it, as the System Utilities disk's does).
