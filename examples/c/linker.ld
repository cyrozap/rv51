/* SPDX-License-Identifier: 0BSD */

/*
 * Copyright (C) 2022 by Forest Crossman <cyrozap@gmail.com>
 *
 * Permission to use, copy, modify, and/or distribute this software for
 * any purpose with or without fee is hereby granted.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
 * WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
 * AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL
 * DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR
 * PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
 * TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
 * PERFORMANCE OF THIS SOFTWARE.
 *
 */

MEMORY
{
	RAM (rw) : ORIGIN = 0x00000000, LENGTH = 4k
	ROM (rx) : ORIGIN = 0x80000000, LENGTH = 64k
}

__stack_top = ORIGIN(RAM) + LENGTH(RAM);

ENTRY(_start)

SECTIONS
{
	.text : {
		*(.init)
		*(.text*)
		. = ALIGN(4);
		*(.rodata*)
		. = ALIGN(4);
	} >ROM

	.data : {
		_data_start = .;
		*(.sdata*)
		*(.data*)
		. = ALIGN(4);
		_data_end = .;
	} >RAM AT >ROM
	_data_loadaddr = LOADADDR(.data);
	_data_len = _data_end - _data_start;

	.bss : {
		_bss_start = .;
		*(.sbss*)
		*(.bss*)
		. = ALIGN(4);
		_bss_end = .;
	} >RAM
	_bss_len = _bss_end - _bss_start;

	/DISCARD/ : { *(.eh_frame) }

	. = ALIGN(4);
	end = .;
}
