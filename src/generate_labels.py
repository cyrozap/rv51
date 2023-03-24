#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

# generate_labels.py - A tool to generate a list of labels for Ghidra from an
# 8051 assembler code listing.
# Copyright (C) 2022-2023  Forest Crossman <cyrozap@gmail.com>
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


import argparse
import re
import sys


VARS_REGEX = re.compile(r'^\s+[0-9]+\s+; Global variables$')
HOME_REGEX = re.compile(r'^\s+[0-9]+\s+\.area\s+HOME\s+\([A-Z,]+\)$')
IRAM_REGEX = re.compile(r'^\s+([0-9A-F]+)\s+[0-9]+\s([a-zA-Z0-9_]+)\s+=\s+.+$')
CODE_REGEX = re.compile(r'^\s+([0-9A-F]+)\s+[0-9]+\s([a-zA-Z0-9_]+):$')

STATE_IDLE = 0
STATE_IRAM = 1
STATE_CODE = 2


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-o", "--output", type=str, help="The output file. Defaults to stdout if not specified.")
    parser.add_argument("input", type=str, help="The input .lst/.rst code listing file.")
    args = parser.parse_args()

    listing = open(args.input, 'r').readlines()

    output = sys.stdout
    if args.output:
        output = open(args.output, 'w')

    state = STATE_IDLE
    for line in listing:
        line = line.strip('\n')

        if state == STATE_IDLE:
            if VARS_REGEX.fullmatch(line):
                state = STATE_IRAM

        elif state == STATE_IRAM:
            iram_match = IRAM_REGEX.fullmatch(line)
            if iram_match:
                addr, symbol = iram_match.groups()
                addr = int(addr, 16)

                addr_string = "INTMEM:0x{:02X}".format(addr)
                if symbol.startswith("misc_bit"):
                    addr_string = "BITS:0x{:02X}".format(addr)

                label = "{} {} l\n".format(symbol, addr_string)
                output.write(label)

            elif HOME_REGEX.fullmatch(line):
                state = STATE_CODE

        elif state == STATE_CODE:
            code_match = CODE_REGEX.fullmatch(line)
            if code_match:
                addr, symbol = code_match.groups()
                addr = int(addr, 16)

                addr_string = "CODE:0x{:04X}".format(addr)

                label = "{} {} l\n".format(symbol, addr_string)
                output.write(label)

    output.close()

    return 0


if __name__ == "__main__":
    sys.exit(main())
