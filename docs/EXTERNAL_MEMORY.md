# External memory and the 512K board

**Memory** has a third choice, ON THREE's 512K board. It needs a MiSTer SDRAM
module; without one the option lists only 256K and 128K, and a saved 512K
setting runs as 256K. [The memory map](MEMORY_MAP.md#the-on-three-512k-board)
has what the board does, from its PROMs.

Like a board swap, a new choice takes effect at the next reset. SOS uses the
extra memory on a disk that boots with ON THREE's boot block, as ON THREE's
own disks do. Apple's boot block stops at 256K, and
[the update disk](#giving-a-disk-512k) gives it the 512K check.

## Where the banks are

| Banks | 128K / 256K | 512K |
|---|---|---|
| 0-6 | block RAM (0-2 with 128K) | block RAM |
| system | block RAM, as bank 7 | block RAM, in bank 7's place (the MMU calls it 15) |
| 7-14 | none | SDRAM |

The block RAM is the same in every configuration, so the video, which reads only
bank 0 and the system bank through the RAM's second port, never waits and never
changes. Only CPU accesses reach the SDRAM. Its word holds a byte and its sister
byte, like the block RAM's, so a read of an upper bank returns the X-byte pair
and the pseudo-DMA byte as any other read does.

## The core's port

`apple3_core` offers banks 7-14 on `ext_ram_*`. `ext_ram_cycle` is
`cpu_enable`, the end of a CPU cycle. From the clock after it until the next,
`ext_ram_select` says the new cycle's RAM access is external, with the
sister-byte word address (17 bits), direction and byte lane; `ext_ram_din` is
valid a clock later, because a ProFile card's pseudo-DMA byte comes from its
buffer a clock after the address. The word must be on `ext_ram_q` by the next
`ext_ram_cycle`, at least seven clocks on. `sim/coretest/core_tb.sv` checks this
contract on every cycle of every simulated run with `--ram512k`.

## The controller

`apple3_sdram` runs on the 14.318 MHz machine clock and follows the CPU cycle
rather than arbitrating for it:

| Clock | Command |
|---|---|
| E | `cycle`: the CPU cycle ends and the next address appears |
| E+1 | ACTIVE, the row |
| E+2 | READ or WRITE with auto precharge; a write drives its byte and masks the other |
| E+4 | the word reaches the DQ input register (CAS latency 2) |
| E+5 | `q` holds it; the CPU takes it at E+7 or later |

MiSTer's SDRAM modules take the byte masks on A12 and A11 during READ and
WRITE, not on the DQM pins, so the controller puts DQMH and DQML there and the
top level drives the DQM pins from those two lines, as other MiSTer cores do. A
first build that drove only the DQM pins stored both bytes on every write; the
benches now wire the model's DQM to A12:A11 the same way.

`SDRAM_CLK` is the machine clock inverted, from a DDIO output, so the chip
samples a command half a clock after it leaves the FPGA. At 70 ns a clock the
read capture has about 25 ns of setup and 40 ns of hold, and every chip timing
(tRCD, tRP, tRAS, tWR, and tRC and tRFC up to 70 ns) fits in the one- and
two-clock gaps. Quartus puts the command, address, DQM and DQ registers in the
I/O cells. An auto refresh goes out every 80 clocks or so, after an access and
never where an ACTIVE could follow within two clocks; power-up is 286 us of
NOPs, PRECHARGE ALL, eight refreshes and the mode register, with the machine
held in reset until it is done.

The simulation model, `sim/sdram/sdram_model.sv`, runs on the inverted clock
like the chip and checks the power-up sequence, the timings above at the
slowest of the modules' data sheets, the refresh interval, DQM and bus
contention. `sim/sdram/run.sh` drives the controller as the core does, with
runs of shortest cycles, slow cycles and long RDY waits over 85 ms; changing
the capture clock, the byte masks or their place on A12:A11, the write-data
clock or the refresh guard each makes it fail.

## Checked on a MiSTer

With a 128 MB SDRAM module: `memmap.po` shows `MAP 512K` and `PPPPPPPPPPP.`,
ON THREE's own "512K MEMORY TEST (VERSION 2.1)" (`Apple3RamTest.dsk`) passes
every bank, 0-15, pass after pass, and SOS 1.3 boots to System Utilities. In
simulation the same test marks banks 7-14 absent at 256K, and SOS parks itself
in bank 14 at 512K where it uses bank 6 at 256K, making 3.6 million reads and
219,000 writes of the upper banks on the way to the menu.

That System Utilities disk (volume `III.UTILS.01`, the image apple3.org and
asimov carry) boots with ON THREE's boot block, not Apple's. SOS takes its
memory size from the bank register the boot block leaves (`SYSBANK:=BREG`),
and Apple's boot block ("SOS BOOT 1.1") searches down from bank 6, so it never
reports more than 256K. ON THREE's ("SOS BOOT 2.0", 1984, and "2.2", 1985)
first marks bank 14 and then bank 6, which is the same cell on a 256K board,
and hands SOS bank 14 if the mark survives. The same disk with Apple's boot
block put back boots at 512K using bank 6 and never touches banks 7-14. So a
disk sees 512K only with ON THREE's boot block, which ON THREE put on all its
products (Draw ON ///, Lazarus, Selector ///, BOS, the Disk of the Month) and
which installing the upgrade put on the owner's disks. The kernel is Apple's
SOS 1.3 either way.

## The upgrade software

The kit's `UPGRADE.TO.512K` disk has not turned up, but what it did can be
pieced together. Its General Update made programs "see" the memory; since SOS
itself supports 512K, the boot block is the change that does that, and the
guide's warning that an un-updated program "will work just as if [it] were
running on your old 256K Apple ///" is exactly what Apple's boot block does
on this core. The other updaters patched VisiCalc, Advanced VisiCalc, Apple
Writer and III E-Z Pieces, whose own counters and limits assume 256K (the
guide: memory indicators that go blank above 255K, file sizes shown modulo
255K, a 414K desktop). Its `BASIC.RTINTERP` is Business BASIC 1.23Ax, a
reassembled BASIC with programs over 64K and a `PROGPREFIX$`; copies survive
on Selector ///'s language disk, the BOS data disk and `CATALYST.FIXER.dsk`.

## Giving a disk 512K

**The SOS 512K update disk**, `releases/SOS512K.po`, does it on the machine,
as ON THREE's updates did. `tools/sos512k/build.sh` assembles it (ca65 and
ld65) into `sim/obj_dir/sos512k/SOS512K.po`. Boot it. Then either swap the disk to update
into the built-in drive and press RETURN, or put it in drive 2 and press 2.
It changes block 0 and nothing else. It adds a 512K check of this repository's
own to the disk's Apple boot block, so it carries no Apple or ON THREE code,
and the updated disk still boots as before with 128K or 256K. It leaves alone
a disk that already sees 512K, and any boot block that is not Apple's SOS
BOOT 1.1 or 7.0. (7.0 has the same code
and is on SOS 1.0-era disks.) After writing, it reads the block back to check
it.

A freshly inserted disk reads as no disk at all until the drive's head steps
through phase 1, as with the Disk /// analog card the core models. SOS's own
driver steps the head, but the ROM's block reader, which the update disk uses,
would find the head already on track 0 and report no drive. So before each
read the program records the head as on track 1, and the ROM steps it back.

`tools/onthree_boot.py --patch` applies the same bytes to an image on a
computer, and its table is what the tests check the update disk against.
Given a donor image instead, the tool copies ON THREE's own boot block from
it, for example from the SOS 1.3 System Utilities image above. `--check` says
which boot block a disk has and what SOS makes of 512K with it. The tool takes
DSK, DO, PO and 2MG images. Hard-disk images made for soshdboot need nothing,
because Rob Justice's loader already makes the check.

The patch probes with bank registers 15 and 7. It writes through 15, then
through 7, and reads back through 15. Apple's boards decode three bank
register bits, so both writes land in the same byte and the read gives 7. The
512K board decodes four bits and gives 15. Apple's own search then starts from
that value and finds bank 14 at 512K, or bank 6 (2 with 128K) as before.

The patch also stores `$AD` at `$2034` of bank 6, where ON THREE's 2.2 stores
`$FF`. SOS 1.1-1.3's loader runs in bank 14 when it selects bank 0, and 2.2's
byte suggests that on a real board the opcode fetched next came from bank 6
([the timing question](MEMORY_MAP.md#the-on-three-512k-board)). `$AD` is the
opcode SOS has at `$2034` (`LDA $1E0A`), so on such a board the instruction
would run as SOS wrote it. The core latches all four bank bits, so it never
fetches that byte.

The code fits in parts of the block that nothing uses:

- the header text, which nothing reads;
- the spaces after the kernel's name;
- the unused tail of the block;
- seven bytes of Apple's setup at `$A078`. Its search loop ends with A and X
  at 0, which makes two loads redundant, and `INX` can replace `LDA #$01`.

The floppy image files in the Apple III DVD, asimov and apple3.org collections
were counted, including each duplicate copy. 848 have SOS BOOT 1.1 and 31
have 7.0, and every one of them matches the bytes the patch expects. Another
325 already see 512K.

In simulation, Apple's Business BASIC 1.23 disk at 512K starts with `FRE`
191,385 and runs out of memory after five 32K arrays. Patched, or given ON
THREE's boot block, it starts with 453,529, exactly eight banks more, and
holds twelve arrays with 69K to spare. At 256K and 128K the patched disk gives
the same numbers as the original. Business BASIC 1.23Ax gives the same numbers
too, so the boot block is what gives BASIC's data the memory. Whatever 1.23Ax
adds for programs, a saved program is still under 64K, because its length is a
16-bit word.

On the MiSTer (seed-1 build, 128 MB module), the update disk updated a copy of
that Business BASIC disk in drive 2. It also updated another copy swapped into
the built-in drive after the update disk had booted, through Main's disk
change. Main saved each copy with block 0 alone changed, byte for byte what
`tools/onthree_boot.py --patch` writes. Booted at 512K, the updated disk shows
`FRE` 453,529 and fills all twelve arrays; at 256K it shows 191,385 and five,
as before. In simulation, Business BASIC 1.0's disk (SOS BOOT 7.0, SOS 1.0)
boots patched at 512K with SOS in bank 14 and using banks 7-14, where the
original stays in bank 6.

## Budget

**Block RAM.** The core uses 504 of the 5CSEBA6's 553 M10K blocks, the same
with or without the 512K option; holding banks 7-14 in block RAM would take
another 256. Card memory or disk buffers larger than the 49 blocks left belong
in the SDRAM.

**SDRAM space.** The smallest module is 32 MB. The CPU's banks use 256 KiB of
it, bank 0 rows 0-255. The rest of bank 0 is for other memory the CPU sees,
such as a card's RAM: the MMU marks it external and it takes the same port,
since the CPU still makes one access a cycle. Banks 1-3 are for buffers the
CPU does not address, such as disk images.

**Commands.** The CPU's access takes E+1 to E+5, so E+5 and E+6 of every cycle
are free, and so is every clock of a slow cycle or an RDY wait. A refresh takes
one of those clocks about every eleven cycles. The others could carry one
access a cycle for a second client in banks 1-3: ACTIVE at E+5 and READ or
WRITE at E+6, whose data leaves the bus before the CPU's next command. That is
about 1.8 million words a second, over a hundred times a floppy's 32 KB/s.
The port does not exist yet; this is the room it has.
