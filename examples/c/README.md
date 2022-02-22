# C Example

This is a simple RISC-V C program that prints some strings to the 8051 UART.


## Prerequisites

* [GNU Binutils][binutils] built with support for the `riscv32-elf` target
  (needed to assemble and link the program)
* [GCC][gcc] built with support for the `riscv64-elf` target (needed to compile
  the program)
* [SDCC][sdcc] (needed for `sdobjcopy` and the `s51` simulator)


## Usage

Run `make sim` in this directory to build the example and start the simulator.


## License

This example code is licensed under the [Zero-Clause BSD (0BSD)][0BSD] license.


[binutils]: https://www.gnu.org/software/binutils/
[gcc]: https://www.gnu.org/software/gcc/
[sdcc]: http://sdcc.sourceforge.net/
[0BSD]: https://opensource.org/licenses/0BSD
