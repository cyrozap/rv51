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

#![no_std]
#![no_main]

use core::panic::PanicInfo;
use riscv::asm::ebreak;
use riscv_rt::entry;
use volatile_register::RW;

const SFR_BASE: *const RW<u8> = 0xC0000000 as *const RW<u8>;

fn putchar(c: u8) {
    let sbuf = unsafe { SFR_BASE.offset(0x99) };
    if c == b'\n' {
        unsafe {
            (*sbuf).write(b'\r');
        }
    }
    unsafe {
        (*sbuf).write(c);
    }
}

fn print(s: &str) {
    for c in s.as_bytes() {
        putchar(*c);
    }
}

fn println(s: &str) {
    print(s);
    putchar(b'\n');
}

#[entry]
fn main() -> ! {
    println("Hello from Rust on RISC-V!");
    unsafe {
        ebreak();
    }
    loop {}
}

#[panic_handler]
fn panic(info: &PanicInfo) -> ! {
    let message = match info.payload().downcast_ref::<&str>() {
        Some(m) => m,
        None => "Panic!",
    };
    println(message);
    unsafe {
        ebreak();
    }
    loop {}
}
