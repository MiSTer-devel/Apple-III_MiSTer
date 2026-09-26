#!/usr/bin/env bash
# ProFile card tests: the register/handshake bench and the whole-core
# diagnostic that runs the ROM's pseudo-DMA ladder on the real CPU. Needs
# Icarus Verilog, Verilator, cc65 and GHDL.
set -euo pipefail
cd "$(dirname "$0")/../.."
out=sim/profile/obj_dir
mkdir -p "$out"
if ! iverilog -g2012 -s profile_card_tb -o "$out/profile_card_tb" \
  rtl/apple3_slot_rom.sv rtl/cards/apple3_profile_card.sv sim/profile/profile_card_tb.sv >"$out/unit-build.log" 2>&1; then
  cat "$out/unit-build.log"
  exit 1
fi
vvp "$out/profile_card_tb"
ca65 sim/profile/diagnostic.s -o "$out/diagnostic.o" -l "$out/diagnostic.lst"
ld65 -C sim/serial/rom.cfg "$out/diagnostic.o" -o "$out/diagnostic.rom"
xxd -p -c 1 "$out/diagnostic.rom" > "$out/diagnostic.hex"
# The ladder must be Apple's, byte for byte, where the ROM image is at hand.
if [[ -f research/roms/apple3.rom ]]; then
  cmp -s <(dd if="$out/diagnostic.rom" bs=1 skip=2046 count=259 2>/dev/null) \
         <(dd if=research/roms/apple3.rom bs=1 skip=2046 count=259 2>/dev/null) ||
    { echo "the diagnostic's pseudo-DMA ladder differs from Apple's ROM" >&2; exit 1; }
fi
if [[ ! -f sim/gen/t65.v || ! -f sim/gen/via6522.v ]]; then ./sim/gen_vhdl.sh; fi
if ! verilator --binary --timing -j 4 --top-module core_profile_tb \
  -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-TIMESCALEMOD \
  --Mdir "$out/core" \
  sim/gen/t65.v sim/gen/via6522.v \
  rtl/disk/apple3_p6.sv rtl/disk/apple3_disk_sequencer.sv rtl/apple3_mmu.sv \
  rtl/apple3_timing.sv rtl/apple3_ram.sv rtl/apple3_rom.sv rtl/apple3_extaddr.sv \
  rtl/apple3_keyboard.sv rtl/apple3_io.sv rtl/apple3_rtc.sv \
  rtl/acia/gen_uart.v rtl/apple3_acia.sv rtl/apple3_disk.sv rtl/apple3_video.sv \
  rtl/apple3_slots.sv rtl/apple3_slot_rom.sv rtl/cards/apple3_profile_card.sv rtl/apple3_core.sv \
  sim/profile/core_profile_tb.sv >"$out/core-build.log" 2>&1; then
  cat "$out/core-build.log"
  exit 1
fi
"$out/core/Vcore_profile_tb"
