;------------------------------------------------------------------------;
; rv51 - A RISC-V emulator for the 8051 microcontroller.                 ;
; Copyright (C) 2020  Forest Crossman <cyrozap@gmail.com>                ;
;                                                                        ;
; This program is free software: you can redistribute it and/or modify   ;
; it under the terms of the GNU General Public License as published by   ;
; the Free Software Foundation, either version 3 of the License, or      ;
; (at your option) any later version.                                    ;
;                                                                        ;
; This program is distributed in the hope that it will be useful,        ;
; but WITHOUT ANY WARRANTY; without even the implied warranty of         ;
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the          ;
; GNU General Public License for more details.                           ;
;                                                                        ;
; You should have received a copy of the GNU General Public License      ;
; along with this program.  If not, see <https://www.gnu.org/licenses/>. ;
;------------------------------------------------------------------------;


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
; - Only the "set_dst_to_rd_iram_addr" and "init" functions can modify
;   R0.
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
rv_x0	= 0x80

	.area	XSEG	(XDATA)
	.area	PSEG	(PAG,XDATA)
	.area	HOME	(ABS,CODE)
	.org	0x0000
reset:
	ljmp	init
	sjmp	.

init:
	; Set stack pointer to scratch pad area.
	mov	sp, #0x40
	; Use dptr as the RV's PC, offset by #rv_code.
	mov	dptr, #(rv_code)
	; Zero out the x0 register. It's best to hand reads from it as a
	; special case, since that can speed things up quite a bit, but
	; to simplify the code and expedite development, set it to zero
	; so reading from it will return the correct value.
	mov	R0, #rv_x0
	mov	@R0, #0
	inc	R0
	mov	@R0, #0
	inc	R0
	mov	@R0, #0
	inc	R0
	mov	@R0, #0
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
	cjne    a, #0x6F, decode_2  ; JAL
	lcall   exec_jal
	sjmp    decode_done
decode_2:
	cjne    a, #0x67, decode_3  ; JALR
	lcall	extract_funct3
	mov	a, funct3
	cjne	a, #0, decode_3
	lcall   exec_jalr
	sjmp    decode_done
decode_3:
	cjne    a, #0x63, decode_4  ; BRANCH
	lcall   exec_branch
	sjmp    decode_done
decode_4:
	cjne	a, #0x23, decode_6  ; STORE
	lcall	exec_store
	sjmp	decode_done
decode_6:
	cjne	a, #0x13, decode_7  ; OP-IMM
	lcall	exec_op_imm
	sjmp	decode_done
decode_7:
	sjmp	.
decode_done:
	ret

exec_branch:
	; Skip extracting funct3--instead use the bits directly from the
	; instruction.
	inst_funct3_bit_0__set_if_negated	= (((instruction_0 - 0x20) * 8) + 12)
	inst_funct3_bit_1__set_if_unsigned_cleared_if_signed	= (((instruction_0 - 0x20) * 8) + 13)
	inst_funct3_bit_2__set_if_lt_ge_cleared_if_eq	= (((instruction_0 - 0x20) * 8) + 14)

	; Extract rs1 and rs2.
	lcall	extract_rs1
	lcall	extract_rs2

	; Load rs1 into R1.
	lcall	set_src_to_rs1_iram_addr

	; Read rs1 into immediate_[0-3].
	mov	immediate_0, @R1
	inc	R1
	mov	immediate_1, @R1
	inc	R1
	mov	immediate_2, @R1
	inc	R1
	mov	immediate_3, @R1

	; Load rs2 into R1.
	lcall	set_src_to_rs2_iram_addr

	; Read rs2 into rd, funct3, rs1, rs2.
	; DO NOT USE THESE AGAIN IN THIS FUNCTION EXCEPT FOR COMPARISONS!
	mov	rd, @R1
	inc	R1
	mov	funct3, @R1
	inc	R1
	mov	rs1, @R1
	inc	R1
	mov	rs2, @R1

	; Determine if we need to do an equality comparison or not.
	jb	inst_funct3_bit_2__set_if_lt_ge_cleared_if_eq, branch_check_lt_ge

	; We're checking EQ/NE, not LT/GE.
	mov	a, immediate_0
	xrl	a, rd
	jnz	branch_eq_ne_result_not_equal
	mov	a, immediate_1
	xrl	a, funct3
	jnz	branch_eq_ne_result_not_equal
	mov	a, immediate_2
	xrl	a, rs1
	jnz	branch_eq_ne_result_not_equal
	mov	a, immediate_3
	xrl	a, rs2
	jnz	branch_eq_ne_result_not_equal

	; rs1 == rs2. If the negated bit is cleared, that means we take the branch on EQ.
	jnb	inst_funct3_bit_0__set_if_negated, branch_take

	; Don't take the branch when rs1 == rs2 and the bit is set.
	ret

branch_eq_ne_result_not_equal:
	; rs1 != rs2. If the negated bit is set, that means we take the branch on NE.
	jb	inst_funct3_bit_0__set_if_negated, branch_take

	; Don't take the branch when rs1 != rs2 and the bit is cleared.
	ret

branch_check_lt_ge:
	; We're checking LT/GE, not EQ/NE.

	; Determine if we need to do a signed comparison or not.
	jb	inst_funct3_bit_1__set_if_unsigned_cleared_if_signed, branch_check_lt_ge_unsigned

	; We're doing a signed comparison.

	; if rs1 is negative (sign bit set) and rs2 is positive (sign bit cleared), rs1 < rs2.

	; Jump if rs1 is negative.
	jb	(((immediate_0 - 0x20) * 8) + 31), branch_rs1_is_negative_rs2_is_unknown

	; rs1 is positive.

	; if rs1 is positive (sign bit cleared) and rs2 is negative (sign bit set), rs1 > rs2.

	; Jump if rs2 is negative.
	jb	(((rd - 0x20) * 8) + 31), branch_lt_ge_result_greater_than_or_equal_to

	; rs2 is positive.

	; if rs1 is positive (sign bit cleared) and rs2 is positive
	; (sign bit cleared), we just do an unsigned comparison.
	sjmp	branch_check_lt_ge_unsigned

branch_rs1_is_negative_rs2_is_unknown:
	; rs1 is negative.

	; Jump if rs2 is negative.
	jb	(((rd - 0x20) * 8) + 31), branch_rs1_and_rs2_are_both_negative

	; rs2 is positive.

	; rs1 < rs2.
	sjmp	branch_lt_ge_result_less_than

branch_rs1_and_rs2_are_both_negative:
	; rs1 is negative and rs2 is negative. Since they're the same sign, we
	; can just treat them like they're unsigned and do an unsigned
	; comparison.
	; Fall through here.

branch_check_lt_ge_unsigned:
	; We're doing an unsigned comparison.

	; Do comparison by rs1 - rs2.
	clr	c
	mov	a, immediate_0
	subb	a, rd
	mov	a, immediate_1
	subb	a, funct3
	mov	a, immediate_2
	subb	a, rs1
	mov	a, immediate_3
	subb	a, rs2

	; if rs1 < rs2, the carry bit will be set.
	jc	branch_lt_ge_result_less_than

branch_lt_ge_result_greater_than_or_equal_to:
	; rs1 >= rs2. If the negated bit is set, that means we take the branch on GE.
	jb	inst_funct3_bit_0__set_if_negated, branch_take

	; Don't take the branch when rs1 >= rs2 and the bit is cleared.
	ret

branch_lt_ge_result_less_than:
	; rs1 < rs2. If the negated bit is cleared, that means we take the branch on LT.
	jnb	inst_funct3_bit_0__set_if_negated, branch_take

	; Don't take the branch when rs1 < rs2 and the bit is set.
	ret

branch_take:
	; Load the immediate and take the branch.
	lcall	extract_imm_12_10_5_4_1_11
	ljmp	jump_to_current_PC_plus_immediate

exec_jalr:
	lcall	extract_rd
	lcall	extract_rs1
	lcall	extract_imm_11_0

	; Skip writing the link register when rd is zero.
	mov	a, rd
	jz	exec_jalr_rd_zero

	; Write the next RV PC into rd.
	lcall	rv_calc_pc
	lcall	set_dst_to_rd_iram_addr
	mov	@R0, rv_pc_0
	inc	R0
	mov	@R0, rv_pc_1
	inc	R0
	mov	@R0, #(rv_rom_base >> 16)
	inc	R0
	mov	@R0, #(rv_rom_base >> 24)

exec_jalr_rd_zero:
	; Load rs1 into R1.
	lcall	set_src_to_rs1_iram_addr

	; Read the base address byte by byte, adding the immediate to
	; it, clearing the lowest bit, and storing the results in dptr.
	mov	a, @R1
	add	a, immediate_0
	anl	a, #0xFE
	mov	dpl, a
	inc	R1

	mov	a, @R1
	addc	a, immediate_1
	mov	dph, a

	; We can't jump anywhere but CODE memory, so just ignore the upper
	; two bytes of rs1.

	; TODO: Use immediate_2 to support paged CODE memory.

	ret

exec_jal:
	lcall	extract_rd
	lcall	extract_imm_20_10_1_11_19_12

	; Skip writing the link register when rd is zero.
	mov	a, rd
	jz	exec_jal_rd_zero

	; Write the next RV PC into rd.
	lcall	rv_calc_pc
	lcall	set_dst_to_rd_iram_addr
	mov	@R0, rv_pc_0
	inc	R0
	mov	@R0, rv_pc_1
	inc	R0
	mov	@R0, #(rv_rom_base >> 16)
	inc	R0
	mov	@R0, #(rv_rom_base >> 24)

exec_jal_rd_zero:
jump_to_current_PC_plus_immediate:
	; Subtract 4 from the dptr, since it's currently pointing to the
	; next instruction and we need it to be pointing to the current
	; instruction
	mov	a, dpl
	add	a, #-4
	mov	dpl, a
	mov	a, dph
	addc	a, #-1
	mov	dph, a

	; Add the immediate to dptr, the "real" PC.
	mov	a, dpl
	add	a, immediate_0
	mov	dpl, a
	mov	a, dph
	addc	a, immediate_1
	mov	dph, a

	ret

exec_store:
	lcall	extract_funct3
	lcall	extract_rs1
	lcall	extract_rs2
	lcall	extract_imm_11_5_4_0

	; Load rs1 into R1.
	lcall	set_src_to_rs1_iram_addr

	; Read the base address byte by byte, adding the immediate to it
	; and storing the results in rs1_dat[0-3].
	mov	a, @R1
	add	a, immediate_0
	mov	rs1_dat0, a
	inc	R1

	mov	a, @R1
	addc	a, immediate_1
	mov	rs1_dat1, a
	inc	R1

	; TODO: Use the upper two bytes to support paged XRAM and
	; multiple address spaces (e.g., IRAM, SFRs).
	;mov	a, @R1
	;addc	a, immediate_2
	;mov	rs1_dat2, a
	;inc	R1

	;mov	a, @R1
	;addc	a, immediate_3
	;mov	rs1_dat3, a

	; Now that we have the final virtual destination address, we
	; need to convert that into a real dptr. Push the current dptr
	; to the stack, then set the new dptr from the lowest two bytes
	; of the destination address.
	push	dph
	push	dpl
	mov	dpl, rs1_dat0
	mov	dph, rs1_dat1

	; The data to STORE comes from rs2, so load rs2 into R1.
	lcall	set_src_to_rs2_iram_addr

	; We're always writing at least one byte.
	mov	a, @R1
	movx	@dptr, a

	; Jump to the end if we're done. Otherwise, continue.
	mov	a, funct3
	jz	exec_store_done
	dec	funct3

	; Write the next byte of the 16-bit word.
	inc	R1
	mov     a, @R1
	inc	dptr
	movx    @dptr, a

	; Jump to the end if we're done. Otherwise, continue.
	mov	a, funct3
	jz	exec_store_done

	; Write the next two bytes of the 32-bit word.
	inc	R1
	mov     a, @R1
	inc	dptr
	movx    @dptr, a

	inc	R1
	mov     a, @R1
	inc	dptr
	movx    @dptr, a

exec_store_done:
	; Restore dptr.
	pop	dpl
	pop	dph

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

rv_calc_pc:
	mov	a, dpl
	clr	c
	subb	a, #(rv_code)
	mov	rv_pc_0, a
	mov	a, dph
	subb	a, #(rv_code >> 8)
	mov	rv_pc_1, a
	ret

extract_imm_12_10_5_4_1_11:
	; Extract imm[4:1] and store it in immediate_0.
	mov	a, instruction_1
	anl	a, #0x0F
	rl	a
	mov	immediate_0, a

	; Extract imm[11] and OR it with immediate_1.
	mov	immediate_1, #0
	jnb	(((instruction_0 - 0x20) * 8) + 7), extract_imm_12_10_5_4_1_11_bit_11_zero
	setb	(((immediate_1 - 0x20) * 8) + 3)

extract_imm_12_10_5_4_1_11_bit_11_zero:
	; Extract imm[10:5] and store it as imm[7:5]|00|imm[10:8] in R2.
	mov	a, instruction_3
	anl	a, #0x7E
	swap	a
	mov	R2, a

	; Extract imm[10:8] and OR it with immediate_1.
	anl	a, #0x07
	orl	immediate_1, a

	; Extract imm[7:5] and OR it with immediate_0.
	mov	a, R2
	anl	a, #0xE0
	orl	immediate_0, a

	; Extend the sign of the 13-bit immediate. I know the function says
	; "twelve_bit_immediate", but since the sign is always in instruction
	; bit 31, and that's where bit 12 is, and bit 12 will be overwritten by
	; this function, it'll work for this 13-bit immediate, too.
	ljmp	twelve_bit_immediate_sign_extension

extract_imm_20_10_1_11_19_12:
	; Extract imm[15:12] and store it in immediate_1.
	mov	a, instruction_1
	anl	a, #0xF0
	mov	immediate_1, a

	; Extract imm[19:16] and store it in immediate_2.
	mov	a, instruction_2
	anl	a, #0x0F
	mov	immediate_2, a

	; Extract imm[3:1] and store it in immediate_0.
	mov	a, instruction_2
	swap	a
	anl	a, #0x0E
	mov	immediate_0, a

	; Extract imm[11] and OR it with immediate_1.
	mov	a, instruction_2
	swap	a
	rr	a
	anl	a, #0x80
	swap	a
	orl	immediate_1, a

	; Extract imm[10:4] and store it as imm[7:4]|0|imm[10:8] in R2.
	mov	a, instruction_3
	anl	a, #0x7F
	swap	a
	mov	R2, a

	; Extract imm[10:8] and OR it with immediate_1.
	anl	a, #0x07
	orl	immediate_1, a

	; Extract imm[7:4] and OR it with immediate_0.
	mov	a, R2
	anl	a, #0xF0
	orl	immediate_0, a

	; Extend the sign.
	jb	(((instruction_3 - 0x20) * 8) + 7), extract_imm_20_10_1_11_19_12_negative

	; Positive
	anl	immediate_2, #0x0F
	mov	immediate_3, #0x00
	ret

extract_imm_20_10_1_11_19_12_negative:
	; Negative
	orl	immediate_2, #0xF0
	mov	immediate_3, #0xFF
	ret

extract_imm_11_5_4_0:
	ar2 = 2

	; Copy the lowest instruction byte to working register R2.
	mov	R2, instruction_0

	; Rotate instruction_1:R2 left by 1.
	MOV	A, instruction_1
	MOV	C, ACC.7
	XCH	A, R2
	RLC	A
	XCH	A, R2
	RLC	A

	; Extract imm[4:0] from R3.
	anl	a, #0x1F

	; Copy the result to immediate_0.
	mov	immediate_0, a

	; Copy the highest instruction byte to A.
	mov	a, instruction_3

	; Swap the nybbles to make imm[7:5]|X|imm[11:8].
	swap	a

	; Store imm[7:5]|X|imm[11:8] in immediate_1 (the upper 4 bits will be
	; overwritten by the sign extension process).
	mov	immediate_1, a

	; Extract imm[7:5] and OR it with immediate_0.
	anl	a, #0xE0
	orl	immediate_0, a

	; Extend the sign of the 12-bit immediate.
	ljmp	twelve_bit_immediate_sign_extension

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

twelve_bit_immediate_sign_extension:
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

extract_rs2:
	ar2	= 0x02

	; ANL instruction_2 with 0xF0 to get the bottom four bits of rs2.
	mov	a, instruction_2
	anl	a, #0xF0

	; ANL R2 with 0x01 to get the top bit of rs2.
	mov	R2, instruction_3
	anl	ar2, #0x01

	; ORL the two registers, then swap nybbles to get rs2.
	orl	a, R2
	swap	a

	; Store the result in rs2.
	mov	rs2, a

	ret

extract_rs1:
	ar2	= 0x02
	mov	R2, instruction_1

	; ANL R2 with 0x80 to get the bottom bit of rs1.
	anl	ar2, #0x80

	; ANL instruction_2 with 0x0F to get the top four bits of rs1.
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
