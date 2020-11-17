# RISC-V Memory Map

The memory map for the virtual RISC-V CPU is as follows:

| Start | End | Name | Permissions | Notes |
| :---- | :-- | :--- | :---------- | :---- |
| 0x00000000 | 0x7FFFFFFF | RAM | RW | Data memory, mapped directly to the 8051's XDATA. Wraps every 0x10000 bytes (64 kB). |
| 0x80000000 | 0xBFFFFFFF | ROM | RX | Read-only program and data memory. Wraps every 0x10000 bytes (64 kB). The emulator code can be read from the very end of any one of the 0x10000 byte blocks. |
| 0xC0000000 | 0xDFFFFFFF | SFR | RW | Special Function Register access. Wraps every 0x100 bytes (256 B). The bottom 128 bytes of each 256-byte block are read-only and always read as zero. The upper 128 bytes of each block are the SFRs. Do not write to the SP, DPTR (DPL and DPH), PSW, ACC (A), or B SFRs--doing so will almost certainly corrupt the state of the emulator. For safety, writes to these registers have been disabled in the emulator. |
