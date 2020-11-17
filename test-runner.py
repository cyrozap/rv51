#!/usr/bin/env python3

import argparse
import os
import pathlib
import subprocess
import tempfile


TESTS = [
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
]


class RiscvTestsTestRunner:
    def __init__(self, rv_emulator):
        self.rv_emu = open(rv_emulator, 'rb').read()

    def run_test(self, test):
        # Create the temporary files for the emulator + RISC-V code binary.
        name_prefix = "rv51-test-runner-{}-combined.".format(test)
        combined_bin = tempfile.NamedTemporaryFile(prefix=name_prefix, suffix=".bin")
        combined_ihex = tempfile.NamedTemporaryFile(prefix=name_prefix, suffix=".ihx")

        # Combine the emulator and RISC-V test code into a single binary.
        test_runner_dir = pathlib.Path(__file__).parent
        test_binary_name = "rv32ui-p-{}.bin".format(test)
        test_binary_path = test_runner_dir.joinpath("riscv-tests", "isa", test_binary_name)
        test_binary = open(test_binary_path, 'rb').read()
        combined_bin.write(self.rv_emu)
        combined_bin.write(test_binary)
        combined_bin.flush()

        # Convert the combined binary into an IHEX file for the simulator.
        objcopy = "sdobjcopy -I binary -O ihex {} {}".format(combined_bin.name, combined_ihex.name).split()
        subprocess.run(objcopy, check=True)
        combined_bin.close()

        # Make a FIFO for the serial output from the simulator.
        serial_fifo_dir = tempfile.TemporaryDirectory(prefix=name_prefix)
        serial_fifo_path = pathlib.PurePath(serial_fifo_dir.name, "serial_fifo")
        os.mkfifo(serial_fifo_path)

        # Start the simulator, writing serial output to the FIFO.
        simulator = "s51 -t 8052 -X 78M -P -b -S out={} -G -e run {}".format(serial_fifo_path, combined_ihex.name).split()
        sim_proc = subprocess.Popen(simulator, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

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
    parser = argparse.ArgumentParser()
    parser.add_argument("emulator", type=str, help="RISC-V emulator binary compiled for 8051.")
    args = parser.parse_args()

    runner = RiscvTestsTestRunner(args.emulator)
    for test in TESTS:
        error = runner.run_test(test)
        if error:
            print("{}: FAIL: {}".format(test, error))
        else:
            print("{}: PASS".format(test))


if __name__ == "__main__":
    main()
