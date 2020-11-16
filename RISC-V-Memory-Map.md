# RISC-V Memory Map

The memory map for the virtual RISC-V CPU is as follows:

| Start | End | Name | Permissions | Notes |
| :---- | :-- | :--- | :---------- | :---- |
| 0x00000000 | 0x7FFFFFFF | RAM | RW | Data memory, mapped directly to the 8051's XDATA. Wraps every 0x10000 bytes (64 kB). |
| 0x80000000 | 0xBFFFFFFF | ROM | RX | Read-only program and data memory. Wraps every 0x10000 bytes (64 kB). The emulator code can be read from the very end of any one of the 0x10000 byte blocks. |
