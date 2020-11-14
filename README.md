# rv51


## What is this?

rv51 is an emulator that can execute bare-metal RV32I binaries on most 8051
(MCS-51) and similar microcontrollers.


## But why?

The [8051][8051] is an extremely popular CPU core, used in everything from LCD
controllers, to wireless microcontrollers, to USB device, hub, and host
controllers, laptop embedded controllers, and more. It's popular in part due
to the simplicity of its design, the lack of patent-encumberance, its
flexibility, and ease of implementation.

However, for better or for worse, it's a 40 year old design, and it really
shows its age:

* 8-bit registers, ALU, and data bus.
* 16-bit pointers (but some implementations support paged data access).
* Only 256 bytes of "fast" memory built-in, with all other memory accessed
  over the much slower external memory bus (both due to access latency and the
  number of instructions required to read from it).
* Many instructions require first moving data into the Accumulator (A/ACC)
  register in order to operate on it.
* Multiple memory regions, with directly and indirectly accessed internal
  memory, special function registers (SFRs), bitmapped registers, banked
  registers, external memory, and read-only code memory.
* Internal stack space is shared with the internal data memory, which is also
  shared with the register memory.

Due to these and other limitations, it is very difficult to target C compilers
for the device, and those that have been ported (like [SDCC][sdcc]) tend to
lack many of the useful features modern compilers like [GCC][gcc] and
[LLVM][llvm] have, like advanced, configurable warnings, robust dead code
elimitation and other optimization techniques, and more. In addition, without
support from either LLVM or a dedicated compiler project, LLVM-based languages
like [Rust][rust] can't be compiled for the device. One way to fix these
problems is to do the difficult software development work needed to add the
8051 as a target to GCC and LLVM.

Another way is to emulate on the 8051 a simple, patent-unencumbered CPU
architecture that already has excellent compiler support--namely,
[RISC-V][risc-v].

Due to my inexperience with compiler development, and having recently read
about [someone else's experience writing an ARM Cortex-M23 emulator in
assembly for the Sega VMU][vmu], I decided to take the latter approach.
Wanting to avoid having to fight with a C compiler to produce efficient,
working assembly, I decided to write this emulator in assembly directly.
Surprisingly this was much easier than I imagined it would be, and I was able
to emulate some simple programs in just a few hours.

So, really the "Why?" comes down to several factors. In no particular order:

* Frustration with the user experience of 8051 compilers.
  * "Why is the generated assembly so bloated with all these extra moves?"
  * "Why were these unused functions not removed from the assembly?"
  * "Why is my code not working? Oh, it's because the compiler silently
    converted a 32-bit int to a 16-bit one, and now the conditional it's a
    part of is always false."
* A desire to build Rust code for the 8051.
* A desire to try programming a microcontroller the way it was originally
  intended (to my knowledge, there were no C compilers targeting the 8051 when
  it was released in 1980).
* An interest in emulators and their construction.
* An interest in the RISC-V ISA.
* "Because why not? It sounds like fun and I'll probably learn something."


## How do I use it?

1. Install [SDCC][sdcc].
2. Run `make`.
3. `cat rv51.bin your-risc-v-program.bin > firmware.bin`
4. Write `firmware.bin` to your 8051's program memory.
5. Power on the 8051 and release it from reset.


## What are the limitations?

The target 8051-family microcontroller must have at least 256 bytes of
internal data memory, since the emulator uses the upper 128 bytes as the
register file.

This emulator is only meant to support the RV32I instruction set, and maybe
the "M" and "C" extensions if they're not too difficult to implement. 64-bit
and floating point support will never be added, since both would require too
much memory and the hardware doesn't have floating point support.

Currently, only 20 instructions of the 40 in the RV32I Base Instruction Set
have been implemented. You can see instruction support status in [Instruction
Support][isa-support].


## What's the license?

This software is licensed under the [GNU General Public License, version 3 or
later][gpl].


[8051]: https://en.wikipedia.org/wiki/Intel_MCS-51
[sdcc]: http://sdcc.sourceforge.net/
[gcc]: https://gcc.gnu.org/
[llvm]: https://llvm.org/
[rust]: https://www.rust-lang.org/
[risc-v]: https://riscv.org/
[vmu]: http://dmitry.gr/?r=05.Projects&proj=25.%20VMU%20Hacking
[isa-support]: Instruction-Support.md
[gpl]: https://www.gnu.org/licenses/gpl-3.0.en.html
