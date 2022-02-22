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

	.section .init, "ax"
	.global	_start
	.type   _start, @function
_start:
	.cfi_startproc
	.cfi_undefined	ra

	/* Load data. */
	la	a0, _data_start
	la	a1, _data_loadaddr
	la	a2, _data_len
	call	memcpy

	/* Zero bss. */
	la	a0, _bss_start
	li	a1, 0
	la	a2, _bss_len
	call	memset

	/* Set the stack pointer and jump to main(). */
	la	sp, __stack_top
	jal	main

	/* Trigger a breakpoint in the emulator. */
	ebreak

	/* Loop forever. */
	j	.

	.cfi_endproc
	.end
