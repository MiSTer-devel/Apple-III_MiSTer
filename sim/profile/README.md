# ProFile card tests

`./sim/profile/run.sh` builds and runs two benches for
[`rtl/cards/apple3_profile_card.sv`](../../rtl/cards/apple3_profile_card.sv)
([design notes](../../docs/PROFILE.md)):

- `profile_card_tb.sv` (Icarus): the card's registers and switches, the
  drive's handshakes, RBUF/WBUF and pseudo-DMA transfers, status bytes,
  special blocks, resets and image states, against a modelled host.
- `core_profile_tb.sv` (Verilator): `diagnostic.s` on the real T65, MMU and
  slot bus with the card in slot 4. The ROM image reproduces Apple's
  pseudo-DMA ladder at $F7FE–$F900; the runner checks it against
  `research/roms/apple3.rom` when that file is present. The program follows
  the driver's sequences, including the last-page trick that depends on the
  6502's taken-branch dummy fetches, and checks every byte's destination.

Whole-system runs mount a ProFile image on the boot harness:

```sh
tools/blank_hd.py --size 9728 profile.po
./sim/run_core_boot.sh 2400000000 sysutils13.woz --profile=profile.po --writable \
    --profile-out=after.po \
    --keys=text:f,wait3,text:l,wait3,text:.profile,enter,enter,enter,wait20,dump \
    --keys-after="Device handling"
```

`sysutils13.woz` is the SOS 1.3 utilities disk converted with Main's
`storage_test --convert`; its `SOS.DRIVER` has Apple's `.PROFILE` driver at
slot 4, which is where `--profile` puts the card unless `--profile-slot=3`
or `2` says otherwise. The keys open the utilities' file menu and list
`.profile` to the console; `text:m` opens the make-subdirectory form for a
write test, and `prodos_ls.py after.po` shows the result on the host.
