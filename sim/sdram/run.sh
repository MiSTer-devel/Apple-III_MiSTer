#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
out=sim/sdram/obj_dir
mkdir -p "$out"
if ! verilator --binary --timing -j 4 --top-module sdram_tb \
  -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-TIMESCALEMOD \
  --Mdir "$out" rtl/apple3_sdram.sv sim/sdram/sdram_model.sv sim/sdram/sdram_tb.sv \
  >"$out/build.log" 2>&1; then
  cat "$out/build.log"
  exit 1
fi
"$out/Vsdram_tb"
