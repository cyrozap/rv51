# Rust Example

This is a simple RISC-V Rust program that prints some strings to the 8051 UART.


## Prerequisites

* Rust, version 1.59.0 or later, with support for the `riscv32i-unknown-none-elf` target
  * `rustup target add riscv32i-unknown-none-elf`
* [GNU Binutils][binutils] built with support for the `riscv32-elf` target
  (needed for `objcopy` to convert the ELF to a raw binary)
* [SDCC][sdcc] (needed for `sdobjcopy` and the `s51` simulator)


## Usage

Run `make sim` in this directory to build the example and start the simulator.


## License

This example code is licensed under the [Zero-Clause BSD (0BSD)][0BSD] license.


[binutils]: https://www.gnu.org/software/binutils/
[sdcc]: http://sdcc.sourceforge.net/
[0BSD]: https://opensource.org/licenses/0BSD
