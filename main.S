; Rules and conventions:
; - R0 is the IRAM destination pointer.
; - R1 is the IRAM source pointer.
; - All multi-byte values are little-endian.
; - A, B, and C can be clobbered by any function.
; - DPTR points to the next RV instruction in CODE/PMEM.
; - RV's PC = 0x80000000 + (DPTR - #rv_code)
; - Instruction execution functions are each responsible for extracting
;   their parameters from their instructions.
; - Only the "fetch_instruction" function can modify instruction_[0-3].
; - Only the "set_dst_to_rd_iram_addr" function can modify R0.
; - Only the "set_src_to_rs1_iram_addr" and "set_src_to_rs2_iram_addr"
;   functions can modify R1.
; - Only the "rv_calc_pc" function can modify rv_pc_[0-1].

rv_rom_base = 0x80000000

; Global variables
instruction_0	= 0x20
instruction_1	= 0x21
instruction_2	= 0x22
instruction_3	= 0x23
rd	= 0x24
funct3	= 0x25
rs1	= 0x26
rs2	= 0x27
funct7	= 0x2C
immediate_0	= 0x28
immediate_1	= 0x29
immediate_2	= 0x2A
immediate_3	= 0x2B
rd_dat0	= 0x30
rd_dat1	= 0x31
rd_dat2	= 0x32
rd_dat3	= 0x33
rs1_dat0	= 0x34
rs1_dat1	= 0x35
rs1_dat2	= 0x36
rs1_dat3	= 0x37
rs2_dat0	= 0x38
rs2_dat1	= 0x39
rs2_dat2	= 0x3A
rs2_dat3	= 0x3B
rv_pc_0	= 0x3C
rv_pc_1	= 0x3D

	.area	XSEG	(XDATA)
	.area	PSEG	(PAG,XDATA)
	.area	HOME	(ABS,CODE)
	.org	0x0000
reset:
	ljmp	init
	sjmp	.

init:
	; Set stack pounter to scratch pad area.
	mov	sp, #0x40
	; Use dptr as the RV's PC, offset by #rv_code.
	mov	dptr, #(rv_code)
emu_loop:
	lcall	fetch_instruction
	lcall	decode_opcode
	sjmp	emu_loop

; We should never get here.
busy_loop:
	sjmp	.

decode_opcode:
	; Extract the opcode from the first byte of the instruction.
	mov	a, instruction_0
	anl	a, #0x7F
	; Opcode dispatch.
	cjne	a, #0x37, decode_0  ; LUI
	lcall	exec_lui
	sjmp	decode_done
decode_0:
	cjne    a, #0x17, decode_1  ; AUIPC
	lcall   exec_auipc
	sjmp    decode_done
decode_1:
	cjne	a, #0x13, decode_7  ; OP-IMM
	lcall	exec_op_imm
	sjmp	decode_done
decode_7:
	sjmp	.
decode_done:
	ret

exec_op_imm:
	lcall	extract_rd

	; Return early if we're writing the zero register.
	mov	a, rd
	cjne	a, #0, exec_op_imm_rd_not_zero
	ret

exec_op_imm_rd_not_zero:
	lcall	extract_funct3
	lcall	extract_rs1
	lcall	extract_imm_11_0

	; Load the dst and src addresses into R0 and R1, respectively.
	lcall	set_dst_to_rd_iram_addr
	lcall	set_src_to_rs1_iram_addr

	; Compare funct3.
	mov	a, funct3
	cjne	a, #0, exec_op_imm_0  ; ADDI
	lcall	exec_addi
	sjmp	exec_op_imm_done
exec_op_imm_0:
	cjne	a, #7, exec_op_imm_7  ; ANDI
	lcall	exec_andi
	sjmp	exec_op_imm_done
exec_op_imm_7:
	sjmp	.
exec_op_imm_done:
	ret

exec_addi:
	; For each byte in the source and destination registers, ADD the
	; source byte with the corresponding immediate byte and store
	; the result in the corresponding destination byte.
	mov	a, @R1
	add	a, immediate_0
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, @R1
	addc	a, immediate_1
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, @R1
	addc	a, immediate_2
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, @R1
	addc	a, immediate_3
	mov	@R0, a

	ret

exec_andi:
	; For each byte in the source and destination registers, AND the
	; source byte with the corresponding immediate byte and store
	; the result in the corresponding destination byte.
	mov	a, @R1
	anl	a, immediate_0
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, @R1
	anl	a, immediate_1
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, @R1
	anl	a, immediate_2
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, @R1
	anl	a, immediate_3
	mov	@R0, a

	ret

exec_auipc:
	lcall	extract_rd

	; Return early if we're writing the zero register.
	mov	a, rd
	cjne	a, #0, exec_lui_rd_not_zero
	ret

exec_auipc_rd_not_zero:
	lcall	extract_imm_31_12
	lcall	rv_calc_pc

	; Write the immediate directly to rd.
	lcall	set_dst_to_rd_iram_addr

	; We know the lowest byte of the immediate is zero, so we can
	; write the lowest byte of the PC to the destination directly.
	mov	@R0, rv_pc_0
	inc	R0

	mov	a, rv_pc_1
	add	a, immediate_1
	mov	@R0, a
	inc	R0

	mov	a, #(rv_rom_base >> 16)
	addc	a, immediate_2
	mov	@R0, a
	inc	R0

	mov	a, #(rv_rom_base >> 24)
	addc	a, immediate_3
	mov	@R0, a

	ret

exec_lui:
	lcall	extract_rd

	; Return early if we're writing the zero register.
	mov	a, rd
	cjne	a, #0, exec_lui_rd_not_zero
	ret

exec_lui_rd_not_zero:
	lcall	extract_imm_31_12


	; Write the immediate directly to rd.
	lcall	set_dst_to_rd_iram_addr
	mov	@R0, immediate_0
	inc	R0
	mov	@R0, immediate_1
	inc	R0
	mov	@R0, immediate_2
	inc	R0
	mov	@R0, immediate_3

	ret

set_dst_to_rd_iram_addr:
	; Load the register number into A.
	mov	a, rd

	; Multiply the RV reg number by 4 to get the IRAM offset.
	rl	a
	rl	a

	; Add 0x80 to get the offset in the upper IRAM registers.
	add	a, #0x80

	; Set the destination address to the final register offset.
	mov	R0, a

	ret

set_src_to_rs2_iram_addr:
	; Load the register number into A.
	mov	a, rs2

	; Jump to the common routine.
	sjmp	set_src_to_rsN_iram_addr

set_src_to_rs1_iram_addr:
	; Load the register number into A.
	mov	a, rs1

	; Fall through to the common routine.

set_src_to_rsN_iram_addr:
	; Multiply the RV reg number by 4 to get the IRAM offset.
	rl	a
	rl	a

	; Add 0x80 to get the offset in the upper IRAM registers.
	add	a, #0x80

	; Set the source address to the final register offset.
	mov	R1, a

	ret

rv_rd_read:
	mov	a, rd
	sjmp	rv_reg_read

; IN: A
rv_reg_read:
	; Check if we're reading the zero register.
	cjne	a, #0, rv_reg_read_nonzero
	mov	r4, a
	mov	r5, a
	mov	r6, a
	mov	r7, a
	ret

rv_reg_read_nonzero:
	; Multiply the RV reg number by 4 to get the IRAM offset.
	rl	a
	rl	a

	; Add 0x80 to get the offset in the upper IRAM registers.
	add	a, #0x80

	mov	r0, a
	mov	a, @r0
	mov	r4, a
	inc	r0
	mov	a, @r0
	mov	r5, a
	inc	r0
	mov	a, @r0
	mov	r6, a
	inc	r0
	mov	a, @r0
	mov	r7, a
	ret

rv_calc_pc:
	mov	a, dpl
	clr	c
	subb	a, #(rv_code)
	mov	rv_pc_0, a
	mov	a, dph
	subb	a, #(rv_code >> 8)
	mov	rv_pc_1, a
	ret

extract_imm_11_0:
	; Copy the two highest instruction bytes to R3:R2.
	mov	R2, instruction_2
	mov	R3, instruction_3

	; rotate right R3:R2 by 4
	MOV A, R2
	XRL A, R3
	ANL A, #0xf0
	XCH A, R3
	XRL A, R3
	SWAP A
	XCH A, R2
	XRL A, R3
	SWAP A
	;MOV R3, A

	; Store the result in immediate_1:immediate_0.
	mov	immediate_0, R2
	mov	immediate_1, a

	; Extend the sign.
	jb	(((instruction_3 - 0x20) * 8) + 7), extract_imm_11_0_negative

	; Positive
	anl	immediate_1, #0x0F
	mov	immediate_2, #0x00
	mov	immediate_3, #0x00
	ret

extract_imm_11_0_negative:
	; Negative
	orl	immediate_1, #0xF0
	mov	immediate_2, #0xFF
	mov	immediate_3, #0xFF
	ret

extract_imm_31_12:
	; Set the lowest byte to zero.
	mov	immediate_0, #0

	; ANL the instruction_1 byte with 0xF0.
	mov	a, instruction_1
	anl	a, #0xF0

	; Store the result in immediate_1.
	mov	immediate_1, a

	; Bytes instruction_3:instruction_2 get stored into the top two bytes of the immediate.
	mov	immediate_2, instruction_2
	mov	immediate_3, instruction_3

	ret

extract_rs1:
	ar2	= 0x02
	mov	R2, instruction_1

	; ANL R1 with 0x80 to get the bottom bit of rs1.
	anl	ar2, #0x80

	; ANL R2 with 0x0F to get the top four bits of rs1.
	mov	a, instruction_2
	anl	a, #0x0F

	; ORL the two registers, then rotate left to get rs1.
	orl	a, R2
	rl	a

	; Store the result in rs1.
	mov	rs1, a

	ret

extract_funct3:
	mov	a, instruction_1
	anl	a, #0x70
	swap	a
	mov	funct3, a
	ret

extract_rd:
	mov	R2, instruction_0

	; Rotate instruction_1:R2 left by 1.
	MOV	A, instruction_1
	MOV	C, ACC.7
	XCH	A, R2
	RLC	A
	XCH	A, R2
	RLC	A

	; Extract the RV reg number from R3.
	anl	a, #0x1F

	; Copy the result to rd.
	mov	rd, a

	ret

fetch_instruction:
	clr	a
	movc	a, @a+dptr
	mov	instruction_0, a
	inc	dptr
	clr	a
	movc	a, @a+dptr
	mov	instruction_1, a
	inc	dptr
	clr	a
	movc	a, @a+dptr
	mov	instruction_2, a
	inc	dptr
	clr	a
	movc	a, @a+dptr
	mov	instruction_3, a
	inc	dptr
	ret

rv_code:
