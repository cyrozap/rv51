# Contributing to rv51


## Boundaries and expectations

[rv51][rv51] is a personal project of [@cyrozap][cyrozap]. This means that
[@cyrozap][cyrozap] works on this project for fun, in his free time, on his own
schedule, and in the direction he chooses. To this end, [@cyrozap][cyrozap]
reserves the right to ignore or reject issues, pull requests, and requests for
support, for any reason or no reason at all.

rv51 is also a [Free Software][free-software] project. That means anyone can use
rv51 for any purpose, can study and modify it, redistribute it, and distribute
modified copies of it. So if you'd like to use rv51 for some particular purpose,
would like to change it to meet some need of yours, or simply want to share it
with others, so long as you follow the terms of the [license][license] you have
every right to do so. You don't need any extra permission to make changes in
your own fork of the project, whether that fork exists only privately on your
computer or if it has been posted publicly on the internet.

That said, if you intend for your changes to be included in [@cyrozap's fork of
rv51][rv51], please open an issue to ask if those changes would be merged
_before_ you perform any work. If you don't ask first and just open a pull
request once you've finished your work, there's a good chance that the pull
request will be rejected. As rv51 is an assembly-language project, it's critical
for the maintenance of the project that the code style and design/architecture
be kept consistent. Since every new feature will have some impact on code size
or performance, and "simply" making features configurable makes testing much
more difficult (every new feature flag doubles the number of possible feature
combinations), new features (like the C extension, M mode, and performance
counters) and their designs must be considered carefully _before_ they are
implemented. It's for this reason that you're asked to open an issue first if
you have an idea for a change--this way, the design and tradeoffs can be
discussed before any work is done, reducing the likelihood of the change being
rejected.


## Contribution process

1. Check the [Project scope](#project-scope) to make sure your idea is either
   in-scope or at least is not out-of-scope.
2. Search through both [open and closed issues][all-issues] to make sure that
   what you're about to ask hasn't already been asked about.
3. [Open an issue][new-issue] in this repository explaining the kind of change
   you would like to make.
4. [@cyrozap][cyrozap] will inform you in the issue of any next steps to take.


## Code design guidelines

- Follow the "Rules and conventions" in [main.S][main] unless it's necessary to
  break them.
  - If a rule/convention needs to be broken, note it in a comment near the
    relevant code.
- If you need internal memory for this feature, use the [register mapping
  spreadsheet][regmap] to help plan the allocation.
  - Take memory from the stack space first, unless the memory will need some
    special kind of access (e.g., for direct access to bits).
- Avoid pushing data to the stack except where necessary (e.g., to temporarily
  save `DPTR` before loading the address of a jump table).
- Comment your code extensively, as if you'll wake up one day having no memory
  of ever having written that code.
  - Explain what registers are being used for what variables, why you're making
    the calculations you're making--those kinds of things.
  - See the existing comments in the code to get a better idea of what code
    should or should not have comments.


## Project scope


### In scope

Some suggestions for implementation are included.

- RISC-V C-extension (compressed instructions)
  - To start, all compressed instructions must be decompressed into 4-byte
    instructions before returning to the standard instruction emulation code.
  - Optimizations (such as skipping decompression steps, pre-decoding before
    jumping directly to emulation code, and performing the instruction emulation
    directly while decoding the compressed instruction) can be made after the
    initial, less-optimized support is added.
- RISC-V M-mode (privileged architecture)
  - Performance Monitor
    - `minstret` CSR
    - `mcounteren` CSR
    - `mcountinhibit` CSR


### Out of scope

This is not an exhaustive list, but it should at least give you an idea of the
kinds of functionality that will probably never be included in rv51.

- RISC-V RV64 instruction set (64-bit operations) and F/D/Q/L-extensions
  (single-precision/double-precision/quad-precision/decimal floating point)
  - Support for RV64I would take up more internal memory than is available in
    the 8051. The registers themselves would require at least 248 bytes of
    internal data memory in total, leaving only 8 bytes for a stack and other
    emulator state, which is not nearly enough.
    - In theory, the registers could be stored in XDATA-attached RAM, but the
      presence, size, and base address of this RAM is platform-dependent and
      would require a significant rewrite of rv51.
  - The "F" Standard Extension adds 32 32-bit floating point registers, plus a
    32-bit floating point control and status register, so at least 128
    additional bytes of internal data memory would be required to store those
    registers. And the other floating point extensions would require even more
    memory.
  - 64-bit operations are _extremely slow_ on the 8051. Assuming there was
    enough space somewhere for the 248-byte register file, 64-bit operations
    would take about twice as long for the 8051 to emulate as the equivalent
    32-bit instructions while providing little-to-no benefit on common
    microcontroller tasks.
  - The marginal gains of implementing those instruction sets is far outweighed
    by the marginal cost of implementing them, in terms of how much data and
    code memory would be required.
    - Going from "not being able to execute any RISC-V instructions at all" to
      "being able to execute any RV32I instruction" is a huge leap in
      functionality. And in addition to significantly speeding up multiply and
      divide operations, support for the "M" extension is required in order to
      use Rust toolchains that emit compressed instructions
      (`riscv32imc-unknown-none-elf` and `riscv32imac-unknown-none-elf`).
      Compared to those, floating point and 64-bit support are simultaneously
      much more costly to implement and much less useful than those other
      extensions, at least for applications where an 8051 might be used.
- Bootloader to dynamically load RISC-V code
  - There are simply too many potential platforms and use cases to make
    supporting this feasible. For example, many 8051-based microcontrollers use
    the standard 8051 serial port peripheral, but some use memory-mapped
    8250-style UARTs in XDATA space. And while many users might want to load
    code over serial, others might want to load it over SPI, I2C, or even USB or
    PCIe, depending on what peripherals are available on their target
    microcontroller and their target application.
- Porting to specific platforms (e.g., adding support for non-standard
  peripherals in SFR or XDATA space, extended addressing modes, firmware
  headers, etc.)
  - There are simply too many platforms to support, and making the build
    configurable would make it very difficult to test everything due to the
    large number of possible configuration combinations.


[rv51]: https://github.com/cyrozap/rv51
[cyrozap]: https://github.com/cyrozap
[free-software]: https://www.gnu.org/philosophy/free-sw.html
[license]: COPYING.txt
[all-issues]: https://github.com/cyrozap/rv51/issues?q=is%3Aissue
[new-issue]: https://github.com/cyrozap/rv51/issues/new
[main]: src/main.S
[regmap]: doc/Register-Mapping.ods
