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
AS := $(PREFIX)as
ASFLAGS := -march=rv32im
CC := riscv64-elf-gcc
CFLAGS := -Wall -march=rv32im -mabi=ilp32 -nostdlib -nostartfiles -nodefaultlibs -fno-builtin -ffreestanding -O2
LD := $(PREFIX)ld
LDFLAGS := -T linker.ld -Map hello-rv32.map
OBJCOPY := $(PREFIX)objcopy
OBJDUMP := $(PREFIX)objdump


all: hello-rv32.bin

%.o: %.S
	$(AS) $(ASFLAGS) -o $@ $<

hello-rv32.elf: main.o init.o
	$(LD) $(LDFLAGS) -o $@ $^

%.bin: %.elf
	$(OBJCOPY) -S -O binary $< $@
	chmod -x $@

disasm-bin: hello-rv32.bin
	$(OBJDUMP) -mriscv -b binary -D $<

disasm-elf: hello-rv32.elf
	$(OBJDUMP) -d $<

combined.bin: ../../src/rv51.bin hello-rv32.bin
	cat $^ > $@

../../src/rv51.bin:
	make -C ../../src

%.ihx: %.bin
	sdobjcopy -I binary -O ihex $< $@

sim: combined.ihx
	s51 -t 8052 -X 12M -b -S out=- -e "break $(shell grep exec_ebreak: ../../src/main.lst | sed 's/\s\+\([0-9A-F]\+\).*/0x\1/g')" -e run $<

clean:
	rm -f *.bin *.elf *.ihx *.map *.o


.PHONY: all clean disasm-bin disasm-elf sim
