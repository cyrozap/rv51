# SPDX-License-Identifier: GPL-3.0-or-later

# Copyright (C) 2020-2022  Forest Crossman <cyrozap@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.


AS := sdas8051
ASFLAGS := -l -o -s -p
CC := sdcc
CFLAGS := -mmcs51 --std-sdcc11 --model-small --stack-auto
OBJCOPY := sdobjcopy

all: rv51.bin

%.rel: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

%.rel: %.S
	$(AS) $(ASFLAGS) $<

rv51.ihx: main.rel
	$(CC) $(CFLAGS) -o $@ $^

%.bin: %.ihx
	$(OBJCOPY) -I ihex -O binary $< $@

riscv-tests/env/p/link.ld:
	git submodule update --init --recursive

riscv-tests/isa/rv32ui-p-simple.bin: riscv-tests/env/p/link.ld
	make -C riscv-tests/isa

test: rv51.bin riscv-tests/isa/rv32ui-p-simple.bin
	python3 test-runner.py $<

clean:
	rm -f *.asm *.bin *.ihx *.lk *.lst *.map *.mem *.rel *.rst *.sym

.PHONY: all clean test
