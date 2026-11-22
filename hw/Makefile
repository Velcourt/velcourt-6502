# Makefile - build the ROM, run the tests, build the FPGA bitstream.
# Build Your Own 6502 Computer on an FPGA - Adrian Velcourt. MIT licence.
#
#   make rom        BASIC + kernel -> build/rom.hex
#   make test-cpu   Klaus Dormann's functional test and Bruce Clark's decimal test
#   make sim        build the whole-computer simulator
#   make bitstream  synthesise, place and route for the Tang Nano 20K
#   make flash      send the bitstream to the board (openFPGALoader)

TOOLS   ?= $(abspath ../tools)
export PATH := $(TOOLS)/oss-cad-suite/bin:$(TOOLS)/cc65/bin:$(PATH)
PY      := python3 -I

RTL     := rtl/soc.v rtl/cpu6502.v rtl/alu6502.v rtl/video.v rtl/uart.v \
           rtl/ps2_kbd.v rtl/spi_sd.v rtl/via.v rtl/sound.v
BOARD   := rtl/top_tangnano20k.v rtl/dvi_out.v rtl/tmds_encoder.v

all: rom

# ---------------- software ----------------
sw/basic/m6502_velcourt.asm: ../thirdparty/msbasic/m6502.asm tools/make_basic.py
	@mkdir -p sw/basic
	$(PY) tools/make_basic.py $< $@

sw/basic/basic.bin: sw/basic/m6502_velcourt.asm tools/msasm.py
	$(PY) tools/msasm.py $< $@ sw/basic/basic.sym 0xC000 0xFFFF

sw/basic_syms.inc: sw/basic/basic.bin
	$(PY) tools/basic_syms.py sw/basic/basic.sym $@

sw/font.inc: sw/font.txt tools/font2inc.py
	$(PY) tools/font2inc.py $< $@ build/font_preview.png

sw/ps2map.inc: tools/ps2map.py
	$(PY) tools/ps2map.py $@

sw/kernel.bin: sw/kernel.s sw/kernel.cfg sw/basic_syms.inc sw/font.inc sw/ps2map.inc
	cd sw && ca65 -o kernel.o -l kernel.lst kernel.s && \
	ld65 -C kernel.cfg -o kernel.bin -m kernel.map -Ln kernel.lbl kernel.o

build/rom.hex: sw/basic/basic.bin sw/kernel.bin tools/make_rom.py
	$(PY) tools/make_rom.py sw/basic/basic.bin sw/kernel.bin $@

rom: build/rom.hex

# ---------------- tests ----------------
sim/obj_dormann/sim_dormann: rtl/cpu6502.v rtl/alu6502.v sim/sim_dormann.cpp
	cd sim && verilator --cc --exe --build -O3 -Wno-fatal -Wno-WIDTH --top-module cpu6502 \
	  ../rtl/cpu6502.v ../rtl/alu6502.v sim_dormann.cpp -o sim_dormann -Mdir obj_dormann

test-cpu: sim/obj_dormann/sim_dormann
	./sim/obj_dormann/sim_dormann ../thirdparty/dormann/bin_files/6502_functional_test.bin 3469
	./sim/obj_dormann/sim_dormann sim/decimal_test.bin 024B 0200 000B

sim/obj_soc/sim_soc: $(RTL) sim/sim_soc.cpp build/rom.hex
	cd sim && verilator --cc --exe --build -O3 -Wno-fatal -Wno-WIDTH -DSIM --top-module soc \
	  -GROM_FILE='"../build/rom.hex"' $(addprefix ../,$(RTL)) sim_soc.cpp -o sim_soc -Mdir obj_soc

sim: sim/obj_soc/sim_soc

# ---------------- FPGA ----------------
build/top.json: $(RTL) $(BOARD) build/rom.hex
	cd build && yosys -q -l yosys.log -p "read_verilog $(addprefix ../,$(RTL) $(BOARD)); \
	  synth_gowin -top top_tangnano20k -json top.json"

build/top_pnr.json: build/top.json build/tangnano20k.cst
	cd build && nextpnr-himbaechel --json top.json --write top_pnr.json \
	  --device GW2AR-LV18QN88C8/I7 --vopt family=GW2A-18C --vopt cst=tangnano20k.cst \
	  --freq 25.2 -l nextpnr.log

build/top.fs: build/top_pnr.json
	cd build && gowin_pack -d GW2A-18C -o top.fs top_pnr.json

bitstream: build/top.fs

flash: build/top.fs
	openFPGALoader -b tangnano20k build/top.fs

.PHONY: all rom test-cpu sim bitstream flash
