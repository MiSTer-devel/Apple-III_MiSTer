# Builds the ROM images the core is built with from Apple's ROMs.
#
#   1. Put these ROMs in this folder, under the names MAME gives them:
#        apple3.rom      boot ROM, 4K (MAME apple3)
#        341-0270-c.4b   mouse card firmware EPROM, 2K (MAME a2mouse)
#        341-0269.2b     mouse card 68705 program, 2K (MAME a2mouse)
#      or MAME's apple3.zip and a2mouse.zip, which hold them.
#   2. make
#
# Produces (all git-ignored -- we cannot redistribute Apple ROM content):
#   apple3_rom.hex          boot ROM, read by the simulations
#   apple3_rom.mif          the same for Quartus
#   apple3_mouse_eprom.hex  mouse card firmware
#   apple3_mouse_mcu.hex    mouse card 68705 program

PYTHON ?= python3

all: roms

# $(call extract,ZIP): take the ROM from the MAME zip that holds it.
define extract
	@if [ ! -f $(1) ]; then \
		echo "ERROR: $@ not found."; \
		echo ""; \
		echo "Place $@, or a MAME $(1) holding it, in this folder, then re-run make."; \
		echo "We cannot redistribute Apple's ROMs -- you must supply your own."; \
		false; \
	fi
	unzip -o -j $(1) $@
endef

apple3.rom:
	$(call extract,apple3.zip)

341-0270-c.4b 341-0269.2b:
	$(call extract,a2mouse.zip)

# $(call rom2hex,SHA-1): one byte per line for $readmemh, from the dump the
# core was tested with.
define rom2hex
	@if [ "$$(shasum < $< | cut -c1-40)" != $(1) ]; then \
		echo "ERROR: $< is not the ROM this core expects (SHA-1 $(1))."; \
		false; \
	fi
	xxd -p -c 1 $< > $@
endef

apple3_rom.hex: apple3.rom
	$(call rom2hex,8043f914ebdcdab9838dbb78f8a2ee3867d210d2)

apple3_rom.mif: apple3_rom.hex ../tools/hex2mif.py
	$(PYTHON) ../tools/hex2mif.py $< $@

apple3_mouse_eprom.hex: 341-0270-c.4b
	$(call rom2hex,3a9d881a8a8d30f55b9719aceebbcf717f829d6f)

apple3_mouse_mcu.hex: 341-0269.2b
	$(call rom2hex,3a2baa6648efe4456d3ec3721216e57c64f7acfc)

roms: apple3_rom.hex apple3_rom.mif apple3_mouse_eprom.hex apple3_mouse_mcu.hex

clean:
	rm -f apple3_rom.hex apple3_rom.mif apple3_mouse_eprom.hex apple3_mouse_mcu.hex

.PHONY: all roms clean
