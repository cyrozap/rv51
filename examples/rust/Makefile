# SPDX-License-Identifier: 0BSD
#
# Copyright (C) 2022 by Forest Crossman <cyrozap@gmail.com>
#
# Permission to use, copy, modify, and/or distribute this software for
# any purpose with or without fee is hereby granted.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
# WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
# AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL
# DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR
# PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
# TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
# PERFORMANCE OF THIS SOFTWARE.


PREFIX := riscv32-elf-
OBJCOPY := $(PREFIX)objcopy
OBJDUMP := $(PREFIX)objdump

TARGET := target/riscv32i-unknown-none-elf/release/hello-rv32

all: $(TARGET)

$(TARGET): src/main.rs
	cargo build --release

%.bin: %
	$(OBJCOPY) -S -O binary $< $@
	chmod -x $@

disasm-bin: $(TARGET).bin
	$(OBJDUMP) -mriscv -b binary -D $<

disasm-elf: $(TARGET)
	$(OBJDUMP) -d $<

combined.bin: ../../src/rv51.bin $(TARGET).bin
	cat $^ > $@

../../src/rv51.bin:
	make -C ../../src

%.ihx: %.bin
	sdobjcopy -I binary -O ihex $< $@

sim: combined.ihx
	s51 -t 8052 -X 12M -b -S out=- -e "break $(shell grep exec_ebreak: ../../src/main.lst | sed 's/\s\+\([0-9A-F]\+\).*/0x\1/g')" -e run $<

clean:
	rm -f *.bin *.ihx
	cargo clean


.PHONY: all clean disasm-bin disasm-elf sim
