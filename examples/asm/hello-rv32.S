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

	.section	.text, "ax", %progbits

	.global	_start

_start:
	lui	a5, %hi(message)
	addi	a5, a5, %lo(message)

	lui	a3, 0xC0000

loop:
	lbu	a4, 0(a5)
	addi	a5, a5, 1
	beqz	a4, finish
	sb	a4, 0x99(a3)
	j	loop

finish:
	ebreak

message:
	.string	"Hello from RISC-V!\r\n"
