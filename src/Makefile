AS := sdas8051
ASFLAGS := -l -o -s
CC := sdcc
CFLAGS := -mmcs51 --std-sdcc11 --model-small --stack-auto
OBJCOPY := sdobjcopy

all: rv51.bin

%.rel: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

%.rel: %.S
	$(AS) $(ASFLAGS) $<

rv51.ihx: main.rel
	$(CC) $(CFLAGS) -o $@ $^

%.bin: %.ihx
	$(OBJCOPY) -I ihex -O binary $< $@

test: rv51.bin
	./test-runner.py $<

clean:
	rm -f *.asm *.bin *.ihx *.lk *.lst *.map *.mem *.rel *.rst *.sym

.PHONY: all clean test
