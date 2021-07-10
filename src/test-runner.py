#!/usr/bin/env python3
#
# test-runner.py - A script to run tests for the rv51 emulator.
# Copyright (C) 2020-2021  Forest Crossman <cyrozap@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#


import argparse
import os
import pathlib
import struct
import subprocess
import sys
import tempfile


INSTRUCTION_SETS = {
    "I": {
        "name": "RV32I Base Instruction Set",
        "prefix": "rv32ui",
        "tests": [
            "simple",
            "lui",
            "auipc",
            "jal",
            "jalr",
            "beq",
            "bne",
            "blt",
            "bge",
            "bltu",
            "bgeu",
            "lb",
            "lh",
            "lw",
            "lbu",
            "lhu",
            "sb",
            "sh",
            "sw",
            "addi",
            "slti",
            "sltiu",
            "xori",
            "ori",
            "andi",
            "slli",
            "srli",
            "srai",
            "add",
            "sub",
            "sll",
            "slt",
            "sltu",
            "xor",
            "srl",
            "sra",
            "or",
            "and",
        ],
    },
    "M": {
        "name": "RV32M Standard Extension",
        "prefix": "rv32um",
        "tests": [
            "mul",
            "mulh",
            "mulhsu",
            "mulhu",
            "div",
            "divu",
            "rem",
            "remu",
        ],
    },
}


class RiscvTestsTestRunner:
    def __init__(self, rv_emulator):
        self.rv_emu = open(rv_emulator, 'rb').read()

    def run_test(self, prefix, test):
        # Create the temporary files for the emulator + RISC-V code binary.
        name_prefix = "rv51-test-runner-{}-combined.".format(test)
        combined_bin = tempfile.NamedTemporaryFile(prefix=name_prefix, suffix=".bin")
        combined_ihex = tempfile.NamedTemporaryFile(prefix=name_prefix, suffix=".ihx")

        # Combine the emulator and RISC-V test code into a single binary.
        test_runner_dir = pathlib.Path(__file__).parent
        test_name = "{}-p-{}".format(prefix, test)
        test_binary_name = "{}.bin".format(test_name)
        test_binary_path = test_runner_dir.joinpath("riscv-tests", "isa", test_binary_name)
        test_binary = open(test_binary_path, 'rb').read()
        combined_bin.write(self.rv_emu)
        combined_bin.write(test_binary)
        combined_bin.flush()

        # Convert the combined binary into an IHEX file for the simulator.
        objcopy = "sdobjcopy -I binary -O ihex {} {}".format(combined_bin.name, combined_ihex.name).split()
        subprocess.run(objcopy, check=True)
        combined_bin.close()

        # Read the ELF file so we can extract the .data section from it.
        test_binary_elf_path = test_runner_dir.joinpath("riscv-tests", "isa", test_name)
        test_binary_elf = open(test_binary_elf_path, 'rb').read()

        # Load the Section Header table information.
        e_shoff = struct.unpack_from('<I', test_binary_elf, 0x20)[0]
        e_shentsize = struct.unpack_from('<H', test_binary_elf, 0x2e)[0]
        e_shnum = struct.unpack_from('<H', test_binary_elf, 0x30)[0]
        e_shstrndx = struct.unpack_from('<H', test_binary_elf, 0x32)[0]

        # Load the string table offset and size.
        shstroff = e_shoff + e_shentsize * e_shstrndx
        stroff = struct.unpack_from('<I', test_binary_elf, shstroff+16)[0]
        strsize = struct.unpack_from('<I', test_binary_elf, shstroff+20)[0]

        # Read the .data section from the ELF file.
        data_section = b''
        for i in range(0, e_shnum):
            offset = e_shoff + e_shentsize * i
            sh_name = struct.unpack_from('<I', test_binary_elf, offset)[0]
            sh_offset = struct.unpack_from('<I', test_binary_elf, offset+16)[0]
            sh_size = struct.unpack_from('<I', test_binary_elf, offset+20)[0]

            name = test_binary_elf[stroff+sh_name:stroff+strsize].split(b'\0')[0]
            if name == b'.data':
                data_section = test_binary_elf[sh_offset:sh_offset+sh_size]
                break

        # If the .data section has data in it, generate a ucsim command file
        # with a sequence of commands that will write the data into XDATA.
        command_file_args = ""
        if data_section:
            command_file = tempfile.NamedTemporaryFile(prefix=name_prefix, suffix=".txt")
            for addr, data_byte in enumerate(data_section):
                command_file.write("fill xram 0x{:04x} 0x{:04x} 0x{:02x}\n".format(addr, addr, data_byte).encode('utf-8'))
            command_file.flush()
            command_file_args = "-C {}".format(command_file.name)

        # Make a FIFO for the serial output from the simulator.
        serial_fifo_dir = tempfile.TemporaryDirectory(prefix=name_prefix)
        serial_fifo_path = pathlib.PurePath(serial_fifo_dir.name, "serial_fifo")
        os.mkfifo(serial_fifo_path)

        # Start the simulator, writing serial output to the FIFO.
        simulator = "s51 -t 8052 -X 78M -P -b -S out={} {} -G {}".format(serial_fifo_path, command_file_args, combined_ihex.name).split()
        sim_proc = subprocess.Popen(simulator, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        # Open the FIFO *after* starting the simulator. Opening it before will
        # cause the runner to hang.
        serial_fifo = open(serial_fifo_path, 'rb')

        # Wait for the simulator to finish running the binary. If the
        # simulator doesn't exit on its own, kill the process.
        try:
            sim_proc.wait(timeout=0.25)
        except subprocess.TimeoutExpired:
            sim_proc.kill()

        # Get the result code printed from the emulated binary.
        result_code = serial_fifo.read()

        # If the emulator didn't print anything to the serial port, it's
        # probably hit an infinite loop somewhere.
        if len(result_code) < 1:
            return "Timeout."

        # The result code is ((test_number << 1) | 1).
        result_code = result_code[0]
        if result_code != 0:
            failed_test = (result_code >> 1) & 0xff
            return "Test {}.".format(failed_test)

        return None


def main():
    default_extensions = ','.join(INSTRUCTION_SETS.keys())
    parser = argparse.ArgumentParser()
    parser.add_argument("-e", "--extensions", type=str, default=default_extensions, help="A comma-separated list of extensions to run tests for. Default: {}".format(default_extensions))
    parser.add_argument("emulator", type=str, help="RISC-V emulator binary compiled for 8051.")
    args = parser.parse_args()

    extensions = args.extensions.split(',')

    runner = RiscvTestsTestRunner(args.emulator)

    errors = 0
    for (isa_ext, isa) in INSTRUCTION_SETS.items():
        if isa_ext not in extensions:
            continue
        isa_name = isa["name"]
        tests = isa["tests"]
        max_name_len = max(len(t) for t in tests)
        print("{}:".format(isa_name))
        for test in tests:
            padding = '.' * (3 + max_name_len - len(test))
            error = runner.run_test(isa["prefix"], test)
            if error:
                errors += 1
                print("  {} {} FAIL - {}".format(test, padding, error))
            else:
                print("  {} {} PASS".format(test, padding))

    if errors:
        print("Error: Failed {} tests.".format(errors))
    else:
        print("All tests passed!")

    return errors


if __name__ == "__main__":
    sys.exit(main())
