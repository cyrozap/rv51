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

#include <stdint.h>
#include <stddef.h>

volatile uint32_t zero_initialized = 0;
volatile uint32_t nonzero_initialized = 0x12345678;

static uint8_t volatile * const sbuf = (uint8_t volatile *)0xC0000099;

#define SYS_memset 1025
static uintptr_t syscall(uintptr_t which, uint32_t arg0, uint32_t arg1, uint32_t arg2)
{
        register uint32_t a7 asm ("a7") = which;
        register uint32_t a0 asm ("a0") = arg0;
        register uint32_t a1 asm ("a1") = arg1;
        register uint32_t a2 asm ("a2") = arg2;

        asm volatile("ecall" :: "r"(a7), "r"(a0), "r"(a1), "r"(a2) );
        return arg0;
}



void * memcpy (void * destination, void const * source, size_t num) {
	for (size_t i = 0; i < num; i++)
		((uint8_t *)destination)[i] = ((uint8_t *)source)[i];

	return destination;
}

void * memset (void * ptr, int value, size_t num) {
	/* use system call */
	return (void*)syscall(SYS_memset, ptr, value, num);
}

static void putchar(char c) {
	if (c == '\n')
		*sbuf = '\r';

	*sbuf = c;
}

static void print(char const * message) {
	for (size_t i = 0; message[i] != 0; i++) {
		putchar(message[i]);
	}
}

static void println(char const * message) {
	print(message);
	putchar('\n');
}

static char nybble_to_char(uint8_t n) {
	if (n < 0xa)
		return '0' + n;
	else
		return 'A' - 0xa + n;
}

static void print_hex_word(uint32_t word) {
	print("0x");
	for (uint8_t i = 0; i < 8; i++) {
		uint8_t nybble = (word >> (28 - (4*i))) & 0xf;
		putchar(nybble_to_char(nybble));
	}
}

void main(void) {
	println("Hello from RISC-V!");

	putchar('\n');
	println("Values before:");

	volatile uint32_t stack_variable = 0;
	print("stack_variable = ");
	print_hex_word(stack_variable);
	putchar('\n');

	print("zero_initialized = ");
	print_hex_word(zero_initialized);
	putchar('\n');

	print("nonzero_initialized = ");
	print_hex_word(nonzero_initialized);
	putchar('\n');
	putchar('\n');

	stack_variable = 0xc0decafe;
	zero_initialized = 0xaabbccdd;
	nonzero_initialized = 0x11223344;

	println("Values after:");

	print("stack_variable = ");
	print_hex_word(stack_variable);
	putchar('\n');

	print("zero_initialized = ");
	print_hex_word(zero_initialized);
	putchar('\n');

	print("nonzero_initialized = ");
	print_hex_word(nonzero_initialized);
	putchar('\n');
	putchar('\n');

	println("RISC-V done!");
	putchar('\n');
}
