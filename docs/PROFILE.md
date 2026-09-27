# ProFile interface card

The core carries a model of Apple's ProFile Interface card for the Apple ///
(schematic 050-5007-A) with a ProFile drive behind it, served from a hard-disk
image. It exists so that Apple's own `.PROFILE` driver, the
one on the SOS 1.3 utilities disk and in Catalyst, Selector and the Pascal
ProFile Manager, runs unmodified. The [block-storage card](BLOCK_STORAGE.md)
remains the faster route for Problock3 and soshdboot; the two can be used
together.

## Using it

1. Put a ProDOS-order image in `games/Apple-III/` and choose it with **Mount
   Hard Disk 1**. PO, HDV and ProDOS-order 2MG are accepted; the length must be a
   multiple of 512 bytes. `tools/blank_hd.py --size 9728 profile.po` makes an
   empty 5 MB volume, the size Apple's driver expects; a larger image works,
   but the SOS 1.3 driver's device information block declares 9,728 blocks,
   so SOS uses only that much of it.
2. Set **Slot 4** in the OSD's Hardware page to **ProFile HD1** and reset.
   That is where Apple's software expects the card: the utilities disk's
   `.PROFILE` driver is configured for slot 4, and the owner's manual calls it
   the usual slot. It takes the mouse card's place; put the mouse card in
   another slot if a mouse driver there is configured to match. **ProFile HD2**
   is a second card on **Hard Disk 2**, for a second copy of the driver set to
   its slot with the System Configuration Program
   ([choosing the cards](SLOTS.md#choosing-the-cards)).
3. Boot the SOS 1.3 utilities or any disk whose `SOS.DRIVER` holds
   `.PROFILE`. The volume appears under its own name and SOS reads and writes
   it in place, so keep a copy of the image.

With no ProFile card in a slot, the default, nothing answers the driver,
which reports no ProFile. The block card, in slot 1 as shipped, serves the
same hard disks to the Problock3 driver ([block storage](BLOCK_STORAGE.md)).

## The card

The card is small: four soft switches in an addressable latch, an 8-bit data
latch, a status buffer and a parity generator; the drive's Z8 controller does
the rest. Apple's driver source and the ProFile Level 2 manual describe the
interface, and the model follows them.

Device select, $C0n0–$C0nF, decoded on R/W and A1–A0 only (the card has no
A4 and up; A3 and A2 go to the switches):

| Offset | Access | Function |
|---|---|---|
| +0 | write | WBUF: a byte to the drive, strobed by the write |
| +1 | read | RBUF: a byte from the drive; the read strobes the next one |
| +2 | read | RSTAT: bit 7 = 1 drive not busy, bit 6 parity error, bit 0 = 1 no drive connected |
| +3 | write | CLRPE: clear the parity error |

I/O select, $Cn00–$CnFF, is the 9334 latch: A3, A1 and A0 pick a switch and A2
is the value, on a read as much as a write. The driver reads them.

| Offset | Switch |
|---|---|
| 0 / 4 | CMD low / high |
| 1 / 5 | CRW low / high (the card's read/write direction) |
| 2 / 6 | INTEN low / high (BSY interrupt; the driver leaves it off) |
| 3 / 7 | DATARW low / high (write to the drive / read from it) |
| 8 / C | CRES low / high (drive reset) |

Any access to the $Cnxx page also latches the card as the pseudo-DMA card
until an access to $C02x releases it, which SOS's `SELC800` does on the way
out of the driver. The card has no expansion ROM and drives no RDY or IRQ.

## The drive

The protocol is Apple's, as the driver and the manual give it:

- Raising CMD makes the drive busy and puts a response on RBUF: $01 when it
  waits for a command, $02 after a read command, $03 or $04 after a write or
  write/verify command, $06 once the write data is in. Dropping CMD ends the
  handshake; the byte last written to WBUF is the host's answer, $55 to go
  on, anything else to abort.
- Six command bytes follow the first handshake: the command (0 read, 1
  write, 2 write/verify), the block number high byte first, the retry count
  and the sparing threshold. The second handshake starts the operation.
- A read ends with the drive idle and four status bytes then 512 data bytes
  on RBUF. A write takes 512 data bytes and up to 20 tag bytes on WBUF (the
  driver sends six check bytes), then a third handshake and four status
  bytes. The status bytes are zero when all went well; a block beyond the
  drive sets bit 0 of the first and bit 6 of the third ("block number
  invalid"), a write to a read-only image bit 0 of the first, both of which
  the driver reports as SOS I/O errors.
- Block $FFFFFF is the spare table, whose first bytes name the drive
  (`PROFILE`), give its type, firmware revision 3.98, the block count and the
  532-byte block size; block $FFFFFE returns the buffer as it stands. Apple's
  diagnostics read the first.
- CRES holds the drive in reset; it comes back idle at the first handshake.
  The card's own reset (slot reset) clears the switches and the handshake
  state; the image stays mounted.

Host transfers use the MiSTer SD interface one block at a time while the
drive reports busy, so the driver's polling loops, which allow eight
seconds, cover Main's latency. A reset in the middle of a transfer lets the
abandoned acknowledgement finish before the next command starts.

## Pseudo-DMA

The service manual's system overview lists an "I/O block transfer" that
"permits up to 1 page (256 byte) fast I/O transfer without DMA hardware on
peripheral", and the boot ROM has kept a "monitor pseudo DMA block" since
1979: an RTS at $F7FE, then 64 pairs of `SBC #1` / `BEQ` at $F800–$F8FF,
the branches of the first half going back to $F7FE, the pair at $F87C hopping
through $F882, the rest forward to an RTS at $F900. It is entered at any even
offset with a count in A. Its purpose was listed as unknown in the ROM
notes; the driver shows what it is for.

The motherboard marks each fetch from that page with DMAOK (slot pin 27),
and the decode PROM 342-0045 turns the CPU's data transceiver off for a cycle
in which a card answers on DMAI (pin 28). The card, once selected through
its $Cnxx page, answers every DMAOK cycle; with DATARW high the drive's next
byte goes to RAM, with it low the RAM byte goes to the drive. The RAM side of
the cycle is a zero-page access: the byte lands at the fetch's low address
byte in the page the zero-page register names, in the bank the bank register
selects, while the CPU reads its ROM byte. One byte moves per fetch, so a
whole page takes 256 CPU cycles at the 1 MHz the driver selects, a byte a
microsecond.

Apple's driver (`DATRANS`, `GO_DMA`, `LAST_PGE` in PROFILE.B.TEXT) sets the
zero-page register to the target page, the bank register to its bank,
disables interrupts and NMI, switches I/O out and write-protects the upper
16K, and calls the ladder through a stub in page $18 whose JSR low byte it
patches to the entry offset, the buffer's low address rounded up to even. A
whole page runs off the end of the ladder to $F900. For a partial last page
the entry is $F802 with a count that makes a `BEQ` exit early, and the
driver's arithmetic counts the bytes the 6502's taken branch fetches on its
own: the next opcode at Y-4, then, when the branch crosses a page, the
old-page address with the new low byte, $FE from the first half of the page
and $00 from the second. The driver saves those two bytes first and moves
the stray one into place afterwards, and it avoids a transfer of exactly $84
bytes, whose exit through $F882 would fetch differently. It also uses
byte-at-a-time moves (`MOVE`) through RBUF and WBUF for short remainders.

In the core, `apple3_core` raises `slot_dma_ok` for such fetches,
`apple3_slots` collects the cards' claims, and `apple3_mmu` translates the
zero page's address for the RAM side of a claimed cycle while decoding the
ROM for the CPU ([slot interface](SLOTS.md)). The T65 CPU had to change for
the last-page trick: it applied a taken branch's offset to the bus address a
cycle early, reading the old-page/new-low-byte address in the third cycle and
the target in the fourth, where the NMOS 6502 reads the next opcode's address
in the third and the old-page address in the fourth. The fix moves the low
byte first and the page correction to the fourth cycle, so the bus sequence
is the 6502's; cycle counts are unchanged.

What the model does not settle is how the motherboard makes the RAM address
the zero page's during the fetch, and what it does if the zero-page register
points at ROM, VIA or I/O space then. The driver never does that; the model
treats such a cycle as it would a zero-page access there, that is, no RAM
access.

## Interface to the machine

The card takes the slot the **Slot** options give it, latched at reset since
cards are installed with the power off ([choosing the cards](SLOTS.md#choosing-the-cards)).
Its image is the hard disk's, Main's S4 or S5, so 2MG data offsets are
honoured, writes go in place and read-only sources are refused
([Main storage](MAIN_STORAGE.md)). When the block card is installed too it
reaches the same image, and `apple3_sd_arbiter` passes Main one card's
request at a time.

## Validation

`./sim/profile/run.sh` (in `sim/run_tests.sh`) runs two benches:

- `profile_card_tb.sv` drives the card's bus and host ports directly, the
  way the driver does: the register mirrors, both handshakes of a read and
  all three of a write/verify through RBUF and WBUF and through pseudo-DMA
  cycles, the status bytes, selection and deselection through $Cnxx and
  $C02x, blocks $FFFFFE and $FFFFFF, a block beyond the image, a nacked
  handshake, the driver's `GOODEXIT` sequence, CRES, a slot reset, a reset
  during a host transfer, a read-only image and an unmounted one.
  5,246 checks.
- `core_profile_tb.sv` runs `diagnostic.s` on the real T65, MMU and card bus
  with the card in slot 4 and a host with 5,000 clocks of latency. The ROM
  image carries Apple's ladder byte for byte (the runner compares it with
  the ROM when the file is at hand). It reads blocks through RBUF, through
  whole pseudo-DMA pages, through a partial first page entered at $F838, and
  through the last-page trick from both halves of the page, checking where
  every byte landed and that the drive's pointer moved by exactly the bytes
  fetched; writes a block by pseudo-DMA and checks the host image; and
  confirms that a deselected card leaves the ladder alone. 945,434 clocks,
  5 host transfers, 1,728 pseudo-DMA cycles.

Whole-system runs use `sim/run_core_boot.sh` with `--hd1=IMAGE
--slot4=profile1` and the SOS 1.3 utilities converted to WOZ, which boot with
Apple's `.PROFILE` driver at slot 4 and the card there.

## Results, 2026-09-26

- `sim/profile/run.sh`: the register bench passes 5,246 checks; the
  real-CPU diagnostic completes in 945,434 clocks with 5 host transfers and
  1,728 pseudo-DMA cycles. `sim/run_tests.sh` and `sim/accuracy/run.sh`
  pass with the card and the T65 change, as do `make lint` and
  `make format-check`.
- Stock ROM, SOS 1.3 utilities floppy unmodified, a 5 MB image made with
  `blank_hd.py --size 9728` holding two text files: SOS initialises
  `.PROFILE`, and **List files** of `.profile` prints `/PROFILE` with both
  files and `9717 blocks available` (15 host transfers, the image unchanged).
  **Make a new subdirectory** `.profile/mkdirtest` reports
  `/PROFILE/MKDIRTEST made` (33 transfers); the saved image differs from the
  original in blocks 2, 6 and 11, the volume directory, its bitmap and the
  new key block, and lists the directory on the host.
- Quartus 17.0.2: 0 errors; worst setup slack 0.302 ns (the HDMI PLL, as
  before), 5.5 ns on the machine clock; 21,639 ALMs (52%) and 503 M10K
  blocks (91%).
- MiSTer with the paired Main and the card in slot 4 (the build before the
  **Slot** options had its own ProFile image and option): the same floppy and
  image. **List files** of `.profile` prints
  `/PROFILE` with both files and `9717 blocks available`; **Make a new
  subdirectory** `.profile/hwtest` reports `/PROFILE/HWTEST made`. The image
  pulled from the SD card differs from the original in blocks 2, 6 and 11,
  the same blocks as in simulation, and lists the new directory.

With the **Slot** options, the same day:

- `sim/slots/run.sh`'s card bench passes 138 checks, and `make test` passes
  whole, with its serial and joystick benches, which the first ProFile build
  had left without the card's source.
- The same floppy and image on the harness: the ProFile card for **Hard Disk
  1** in slot 4 lists `/PROFILE` and makes `/PROFILE/MKDIRTEST` with the
  block card in slot 1 on the same disk and without it; the card for **Hard
  Disk 2** lists the image mounted there; the Problock3 utilities list it
  through the block card moved to slot 3; and the soshdboot ROM boots from
  the block card in slot 2.
- Quartus 17.0.2: 0 errors, every clock meets timing (worst setup slack
  0.530 ns, hold 0.243 ns); 22,001 ALMs (52%) and 504 M10K blocks (91%),
  one more for the second ProFile card's buffer.
- MiSTer, **Slot 4** at ProFile HD1 and the image on **Hard Disk 1**: the
  utilities [list `/PROFILE`](profile/2026-09-26-profile-slot4-list.png) and
  make `/PROFILE/SLOTTEST`. With the slots as shipped the Problock3 utilities
  then [list the same image](profile/2026-09-26-block-card-list-after.png)
  through the block card, the new directory included, and the image pulled
  from the SD card holds it.

## Sources

- Apple's *SOS ProFile Driver 1.30* source listing (PROFILE.TEXT,
  PROFILE.A.TEXT, PROFILE.B.TEXT; asimov `apple3_SRC_Profile_Driver`): the
  register addresses, switch offsets, handshake, command bytes, status
  checks and the pseudo-DMA calling sequence.
- Apple's schematic *Apple III Interface, ProFile*, 050-5007-A
  (apple3.org): the slot pins the card uses (A0–A3, IOSEL, DEVSEL, C02X,
  DMAOK, DMAI, PHI, Q3), the 9334 latch, the 74LS374/244 data path and the
  74LS280 parity generator.
- *ProFile Level 2 Service Manual* (apple3.org), parts 2 and 7 and the
  controller theory of operation: responses $01–$06, the command bytes,
  block $FFFFFF, and the status byte bits.
- *Apple /// Level 2 Service Reference Manual*: the slot pin descriptions
  (DMAOK, DMAI, TSADB), the "I/O block transfer" feature and the net list.
- Decode PROM 342-0045 equations (`/EN8304 = -ROMSEL * -DMAI * -FSPACE *
  PH2M`) from the PROM notes: DMAI turns the CPU transceiver off.
- Apple's boot ROM, $F7FE–$F900, "MONITOR PSUEDO DMA BLOCK" in the 1979
  listing.
- *Apple III ProFile Owner's Manual*: slot 4 as the usual slot and the SCP
  procedure for another.
- The SOS 1.3 utilities disk's `SOS.DRIVER`: `.PROFILE`, type $D1, slot 4.
- A Macintosh-era Apple /// emulator's `ProFile.c` (asimov "A3 Emulation"),
  which transfers a byte on each read of a $F8xx ROM location, as a
  cross-check of the reading of the driver.
