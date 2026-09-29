# Companion Main storage integration

This core requires the companion Main on the `apple3-disk-storage` branch of
[jakesjews/Main_MiSTer](https://github.com/jakesjews/Main_MiSTer/tree/apple3-disk-storage).
The branch also includes Newsdee's upstream
[PR #1330](https://github.com/MiSTer-devel/Main_MiSTer/pull/1330) (the //e and
IIgs WOZ CRC refresh and save-state naming), which hasn't landed upstream yet.

The Apple III code lives in `support/a3/`: `a3_disk.cpp` mounts and
serves the images, `a3_woz.cpp` builds the synchronized tracks and the SOS
protection key. `user_io.cpp` reaches it through three hook lines, the way the
Mac support code is wired, and two more inside PR #1330's blocks. It calls the
2MG, DC42, sector-order, WOZ-type and NIB-track helpers that the //e and IIgs use
in `support/a2/iigs_fmt.cpp`, and changes nothing
outside `support/a3/` beyond those hook lines and one include, apart from
PR #1330 itself. The
hardware retains its own P6 controller and Disk III drive logic.

| Main mount | Apple III assignment | Policy |
|---|---|---|
| S0 | Internal Disk III (.D1) | Native WOZ2, sector-image and NIB writes |
| S1 | First external Disk III (.D2) | Native WOZ2, sector-image and NIB writes |
| S2 | Second external Disk III (.D3) | Native WOZ2, sector-image and NIB writes |
| S3 | Third external Disk III (.D4) | Native WOZ2, sector-image and NIB writes |
| S4, S5 | Block Disks 1 and 2, the block card's drives (.PROFILE and .PB2 with Problock3) | ProDOS-order blocks written in place |
| S6, S7 | ProFile Disks 1 and 2, one for each ProFile card (Apple's .PROFILE driver) | As S4 and S5 |

The FPGA exposes **S0 through S7**. S4 and S5 feed the
[virtual block-storage card](BLOCK_STORAGE.md), in slot 1 as shipped, and S6
and S7 the [ProFile cards](PROFILE.md); the OSD shows each disk while a slot
holds its card.

Main recognizes the Apple III by its core name, so every Apple-III build gets
this path. The //e and IIgs retain their existing, different mount assignments
and write policies.

## Formats and transport

- A raw 140K image's sector order is detected from its ProDOS volume directory
  or DOS 3.3 VTOC, read in either order, with upstream's detector; the Apple III
  code adds the same check for SOS volumes with 12 directory entries per block.
  When neither is present, DSK/DO mean DOS order and PO ProDOS order. 2MG's
  format, data offset, payload length and volume flags take precedence. A 2MG
  header that doesn't parse leaves the file treated as a raw image, as on the
  //e and IIgs.
- A sector image has no address fields. Their volume number is 254 unless a
  2MG header gives one or the image has a DOS 3.3 VTOC, whose volume byte is
  then used: `INIT` writes that number to the VTOC and to every address field,
  and the DOS it saves asks RWTS for it from its first command. Apple's ///
  and /// Plus dealer diagnostics are volume 1, and stopped at VOLUME MISMATCH
  before their HELLO ran.
- 140K ProDOS-order images use the standard sector map: block 2, the volume
  directory, is DOS sectors 11 and 10. The tests pin upstream's map to those
  block positions, because an earlier map placed only sectors 0 and 15
  correctly and real `.po` images did not boot.
- SOS copy protection (`BFM.INIT2`) reads one address-field volume byte on each
  of tracks 9 to 16. If those tracks are synchronized and the bytes differ, SOS
  takes them as a key and decrypts `SOS.INTERP` in memory. Main rebuilds that
  key only for a volume whose `SOS.INTERP` is encrypted: it decodes a sample
  with the key and keeps whichever version has the byte statistics of 6502
  code. Of 29 apple3.org images checked, three are protected dumps (Apple
  Writer III, the System Demonstration and VisiCalc's boot disk). Giving the key
  to a plain disk makes SOS decrypt working code and stop with SYSTEM FAILURE
  $06 whenever its synchronization check passes, which on hardware was most
  boots.
- NIB is packed directly into a bitstream without a sector decode/re-encode.
  Standard FF sync gaps acquire ten-bit spacing; data/address bytes stay intact.
- Native WOZ is checked only for its signature, an INFO chunk inside the file
  and a 5.25" disk type, then served unchanged by Main's generic SD code, as
  on the //e and IIgs. A WOZ inside a zip is read into RAM instead, because a
  zip is slow to seek back, and is read-only. Converted images keep a separate
  buffer per drive.
- Archived images and files that are read-only on the SD card are read-only.
  The drive itself refuses writes to a FLUX WOZ or one marked write-protected,
  and writes only existing track allocations: it cannot allocate an unmapped
  track or resize tracks.
- DSK, DO, PO and sector-order 2MG images are written in place. The drive saves
  a track one 512-byte block at a time, so the track is torn until its last
  block arrives. Main then frames the track's bits into nibbles and decodes them
  with upstream's //e and IIgs decoder, `a2_nib_track_to_dsk`: no checksum or
  track-number checks, and the first copy of a sector wins. Once any sector is found, the whole track replaces the file's,
  in the file's own sector order and behind any 2MG header, in one 4 KiB write,
  with missing sectors written as zeros, as upstream's //e and IIgs write-back
  does.
  The image is opened O_SYNC, and sixteen separate sector writes held the
  drive's cache busy long enough to break SOS's formatter. The reconstructed
  SOS address-field key is not stored, because sector images have no address
  fields.
- NIB sources (`.nib` and 2MG NIB payloads) are writable through upstream's
  NIB write-back, adapted for the Apple III. A NIB track cannot be patched a
  sector at a time, so a saved track is stored only when all sixteen sectors
  are found. It is re-nibblized to the canonical 6,656-byte layout, keeps each
  sector's address-field volume byte, which is where SOS's protection key
  lives, and goes to the file in one write.
- Converted Apple III tracks hold 51,424 cells read at 3.875 us (INFO timing
  31), not the bare 50,304 at 4 us. The drive model consumes one cell per bit
  the machine writes, so a track's cell count is what the machine's own
  formatter measures as drive speed. Apple's Disk III formatter shrinks its
  sync gap until sixteen sectors of 10n + 2,988 cells close the track and
  accepts 19 to 24 nibbles, 22 being a correctly adjusted drive. On 50,304
  cells SOS reported "drive is too fast" and the Confidence Program's Align
  check failed; on 51,904 it closed at 25, "too slow". 51,424 closes at 22. The
  inter-track rotation is recomputed so SOS's key sectors still pass the head
  56.5 ms apart.
- Main receives complete transfers of up to 16 KiB and zero-pads partial reads.
- About a second after the core's last write to a native WOZ, Main recomputes
  the file's CRC, so AppleWin and wozardry don't report a mismatch. The Apple
  III code does this itself, in the same two `user_io.cpp` places as PR #1330's
  //e and IIgs refresh, without calling it.
- A raw PO or HDV hard disk is checked, then served by Main's generic SD code,
  as the //e and IIgs hard disks are. The Apple III code serves only images
  behind a 2MG or DC42 header: their payloads use the declared lengths,
  excluding 2MG comments or DC42 tags, and the cards' 512-byte writes go in
  place behind the header; a write to a read-only one is acknowledged and
  dropped. Main never silently moves an image to another mount slot.

## Build and install

From the Apple III repository root, clone the companion Main next to it:

```sh
git clone -b apple3-disk-storage https://github.com/jakesjews/Main_MiSTer.git ../Main_MiSTer-AppleIII
```

In that checkout, use Main's normal ARM Linux cross toolchain and run
`make -j6 MAKEFLAGS=-j6`. For the FPGA, follow the
[core build instructions](DEVELOPMENT.md#building).
Copy `bin/MiSTer` to `/media/fat/MiSTer_AppleIII`. In `MiSTer.ini`:

```ini
[Apple-III]
main=MiSTer_AppleIII
```

MiSTer selects that binary only for Apple III and returns to the normal Main
when loading Menu or another core. Keep the paired Main and RBF together.
For an MGL, mount files with `type="s"`, indexes 0 through 3. The validation MGL
uses eight-second mount delays and a three-second reset delay (units are seconds).

## Tests and conversion utility

From this repository, run `support/main/tests/run.sh`; set `MAIN_DIR` if the
Main checkout is not `../Main_MiSTer-AppleIII`. It builds Main's
`support/a3` and `support/a2` sources with file/SPI shims under address
and undefined-behavior sanitizers.
Tests cover four simultaneous mounts, independent write protection, writes and
replacement/ejection, format/slot matching, DOS/PO/2MG equivalence, bit-packed GCR, NIB
preservation, NIB write-back of whole tracks with their volume bytes,
multi-block transfers, read-only enforcement, block-image writes
behind a 2MG header, and native WOZ passthrough. The
ProDOS-order map is
pinned to block positions rather than to the codec's own inverse, and the
protection key must appear only for an encrypted `SOS.INTERP`. Sector write-back tests
save tracks block by block into DSK, PO and 2MG sources and check after every
block that each sector holds either its old or its new contents. The tests live here rather than in the Main
branch: upstream Main has no test tree.

After that build, use the same backend to save an explicit WOZ2 copy of a sector
image or a NIB (a native WOZ is served unchanged, so a WOZ1 stays WOZ1):

```sh
/tmp/mister-apple3-tests/storage_test --convert source.dsk writable-copy.woz
```

This writes a separate output file. Mounting never creates an implicit converted
file; a sector image changes only when the Apple III writes to it. ROMs and
software disks are not distributed.
