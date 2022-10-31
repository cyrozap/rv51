#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

# generate_labels.py - A tool to generate a list of labels for Ghidra from an
# 8051 assembler code listing.
# Copyright (C) 2022  Forest Crossman <cyrozap@gmail.com>
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


REGEX = re.compile(r'^\s+([0-9A-F]+)\s+[0-9]+\s([a-zA-Z0-9_]+):$')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-o", "--output", type=str, help="The output file. Defaults to stdout if not specified.")
    parser.add_argument("input", type=str, help="The input .lst/.rst code listing file.")
    args = parser.parse_args()

    listing = open(args.input, 'r').readlines()

    output = sys.stdout
    if args.output:
        output = open(args.output, 'w')

    for line in listing:
        line = line.strip('\n')
        match = REGEX.fullmatch(line)
        if not match:
            continue

        addr, symbol = match.groups()
        addr = int(addr, 16)

        addr_string = "CODE:0x{:04X}".format(addr)

        label = "{} {} l\n".format(symbol, addr_string)
        output.write(label)

    output.close()

    return 0


if __name__ == "__main__":
    sys.exit(main())
