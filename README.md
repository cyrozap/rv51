# rv51


## What is this?

rv51 is an emulator that can execute bare-metal [RISC-V][risc-v] RV32IM
firmware on microcontrollers that use the [8051 (MCS-51)][8051] instruction
set.


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
2. `cd` to the `src` directory.
3. Run `make`.
4. `cat rv51.bin your-risc-v-program.bin > firmware.bin`
5. Write `firmware.bin` to your 8051's program memory.
6. Power on the 8051 and release it from reset.

Example RISC-V programs that can run on rv51 in an 8051 simulator can be found
in the [examples][examples] directory.


## What are the limitations?

The target 8051-family microcontroller must have at least 256 bytes of
internal data memory, since the emulator uses the upper 128 bytes as the
register file. And while having some additional XDATA-attached RAM is not
strictly required, operating exclusively on registers will severely limit the
kinds of RISC-V code that can be built and executed (no global variables, no
nested function calls, and no stack usage in general).

Only the RV32IM instruction set is supported at this time. Support for the "C"
extension may be added if it's not too difficult to implement and doesn't
require much additional code and data memory. Support for 64-bit (RV64I) and
floating point (the "F" extension) will never be added. The rationale for this
can be found in [CONTRIBUTING.md][out-of-scope].

All 40 instructions of the RV32I Base Instruction Set and all eight
instructions of the RV32M Standard Extension have been implemented. The full
list of supported instructions can be found in [Instruction
Support][isa-support].

Traps (interrupts and exceptions) are partially supported. Deliberate
synchronous exceptions (e.g., EBREAK and ECALL) are confirmed to work, and
asynchronous interrupts appear to work in simple cases, but other exceptions
have not yet been implemented. For example, because the illegal instruction
exception has not been implemented, illegal instructions will either put rv51
into an infinite loop or execute undefined behavior. For this reason, please
be sure your RISC-V code doesn't try to execute any instructions that are
unsupported by rv51.


## What's the license?

This software is licensed under the [GNU General Public License, version 3 or
later][gpl].


[risc-v]: https://en.wikipedia.org/wiki/RISC-V
[8051]: https://en.wikipedia.org/wiki/Intel_MCS-51
[sdcc]: https://sdcc.sourceforge.net/
[gcc]: https://gcc.gnu.org/
[llvm]: https://llvm.org/
[rust]: https://www.rust-lang.org/
[vmu]: https://dmitry.gr/?r=05.Projects&proj=25.%20VMU%20Hacking
[examples]: examples
[out-of-scope]: CONTRIBUTING.md#out-of-scope
[isa-support]: doc/Instruction-Support.md
[gpl]: https://www.gnu.org/licenses/gpl-3.0.en.html
