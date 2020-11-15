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

rv_ram_base = 0x00000000
rv_rom_base = 0x80000000
rv_sfr_base = 0xC0000000
rv_hyp_base = 0xE0000000

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
	; Zero all RV registers. This is necessary for x0 since we don't
	; currently treat reads from it as a special case. And while
	; this isn't necessary for the other registers, doing this here
	; means the RV code won't have to (slowly) zero registers when
	; it starts, resulting in a slightly faster RV application
	; startup time.
	mov	R0, #rv_x0
zero_rv_regs:
	mov	@R0, #0
	inc	R0
	cjne	R0, #0, zero_rv_regs
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
	mov	R2, a

	; Opcode dispatch.
	cjne	R2, #0x37, decode_0  ; LUI
	ljmp	exec_lui
decode_0:
	cjne	R2, #0x17, decode_1  ; AUIPC
	ljmp	exec_auipc
decode_1:
	cjne	R2, #0x6F, decode_2  ; JAL
	ljmp	exec_jal
decode_2:
	cjne	R2, #0x67, decode_3  ; JALR
	lcall	extract_funct3
	mov	R3, funct3
	cjne	R3, #0, decode_3
	ljmp	exec_jalr
decode_3:
	cjne	R2, #0x63, decode_4  ; BRANCH
	ljmp	exec_branch
decode_4:
	cjne	R2, #0x03, decode_5  ; LOAD
	ljmp	exec_load
decode_5:
	cjne	R2, #0x23, decode_6  ; STORE
	ljmp	exec_store
decode_6:
	cjne	R2, #0x13, decode_7  ; OP-IMM
	ljmp	exec_op_imm
decode_7:
	cjne	R2, #0x33, decode_8  ; OP
	ljmp	exec_op
decode_8:
	cjne	R2, #0x0F, decode_9  ; MISC-MEM
	; FENCE instructions are a no-op because this virtual core is
	; entirely in-order, meaning all memory operations are already
	; guaranteed to finish before the instructions that follow them.
	ret
decode_9:
	cjne	R2, #0x73, decode_10  ; SYSTEM
	jb	(((instruction_0 - 0x20) * 8) + 12), exec_ebreak
	; Ignore ECALL for now.
	ret
exec_ebreak:
	; EBREAK is a no-op, but with an explicit "nop" instruction so
	; we can both easily break on it in an 8051 debugger while
	; ignoring it on real hardware.
	nop
	ret
decode_10:
	; Unrecognized instruction or execution function didn't "ret".
	sjmp	.

exec_load:
	lcall	extract_rd

	; Return early if we're writing the zero register.
	mov	a, rd
	cjne	a, #0, exec_load_rd_not_zero
	ret

exec_load_rd_not_zero:
	lcall	extract_funct3

	; Bit 2 of funct3 indicates that we should zero-extend instead of sign-extend.
	inst_funct3_bit_2__zero_extend = (((instruction_0 - 0x20) * 8) + 14)

	lcall	extract_rs1
	lcall	extract_imm_11_0

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

	; The upper bytes are used to access different address spaces.
	; e.g., XDATA, CODE, SFR, hypercall registers, etc.
	mov	a, @R1
	addc	a, immediate_2
	mov	rs1_dat2, a
	inc	R1

	mov	a, @R1
	addc	a, immediate_3
	mov	rs1_dat3, a

	; Now that we have the final virtual source address, we need to
	; convert that into a real dptr. Push the current dptr to the
	; stack, then set the new dptr from the lowest two bytes of the
	; source address.
	push	dph
	push	dpl
	mov	dpl, rs1_dat0
	mov	dph, rs1_dat1

	; The data to LOAD gets stored in rd, so load rd into R0.
	lcall	set_dst_to_rd_iram_addr

	; Check what address space we're reading.
	clr	c
	mov	a, rs1_dat3
	subb	a, #((rv_rom_base - rv_ram_base) >> 24)
	jc	exec_load_lt_80_xdata
	subb	a, #((rv_sfr_base - rv_rom_base) >> 24)
	jc	exec_load_lt_C0_code
	subb	a, #((rv_hyp_base - rv_sfr_base) >> 24)
	jc	exec_load_lt_E0_sfr
	sjmp	exec_load_ge_E0_hyp

exec_load_lt_80_xdata:
	; We're always reading at least one byte. Use R2 to store the
	; byte for sign extension.
	movx	a, @dptr
	mov	@R0, a
	mov	R2, a

	; Jump to the sign extension if we're done. Otherwise, continue.
	mov	a, funct3
	anl	a, #0x03
	jz	exec_load_sign_extend_B
	dec	funct3

	; Read the next byte of the 16-bit word. Use R2 to store the
	; byte for sign extension.
	inc	dptr
	movx	a, @dptr
	inc	R0
	mov	@R0, a
	mov	R2, a

	; Jump to the the sign extension if we're done. Otherwise,
	; continue.
	mov	a, funct3
	anl	a, #0x03
	jz	exec_load_sign_extend_H

	; Read the next two bytes of the 32-bit word.
	inc	dptr
	movx	a, @dptr
	inc	R0
	mov	@R0, a

	inc	dptr
	movx	a, @dptr
	inc	R0
	mov	@R0, a

	; We just finished loading a 32-bit word, so we don't do sign
	; extension. Just jump to the end.
	sjmp	exec_load_done

exec_load_lt_C0_code:
	; To get the real CODE address, add the virtual address to
	; rv_code, then store the result in dptr.
	mov	a, dpl
	add	a, #(rv_code)
	mov	dpl, a
	mov	a, dph
	addc	a, #(rv_code >> 8)
	mov	dph, a

	; We're always reading at least one byte. Use R2 to store the
	; byte for sign extension.
	clr	a
	movc	a, @a+dptr
	mov	@R0, a
	mov	R2, a

	; Jump to the sign extension if we're done. Otherwise, continue.
	mov	a, funct3
	anl	a, #0x03
	jz	exec_load_sign_extend_B
	dec	funct3

	; Read the next byte of the 16-bit word. Use R2 to store the
	; byte for sign extension.
	inc	dptr
	clr	a
	movc	a, @a+dptr
	inc	R0
	mov	@R0, a
	mov	R2, a

	; Jump to the the sign extension if we're done. Otherwise,
	; continue.
	mov	a, funct3
	anl	a, #0x03
	jz	exec_load_sign_extend_H

	; Read the next two bytes of the 32-bit word.
	inc	dptr
	clr	a
	movc	a, @a+dptr
	inc	R0
	mov	@R0, a

	inc	dptr
	clr	a
	movc	a, @a+dptr
	inc	R0
	mov	@R0, a

	; We just finished loading a 32-bit word, so we don't do sign
	; extension. Just jump to the end.
	sjmp	exec_load_done

exec_load_lt_E0_sfr:
exec_load_ge_E0_hyp:
	; Unimplemented--return zero for now.
	mov	@R0, #0
	inc	R0
	mov	@R0, #0
	inc	R0
	mov	@R0, #0
	inc	R0
	mov	@R0, #0
	sjmp	exec_load_done

exec_load_sign_extend_B:
	; Extend the sign for three bytes.

	; Jump if we should zero extend instead of sign extend.
	jb	inst_funct3_bit_2__zero_extend, exec_load_zero_extend_B

	; Check if the sign is positive or negative.
	mov	a, R2
	jnb	ACC.7, exec_load_zero_extend_B

	; Sign was negative.
	mov	a, #0xFF
	sjmp	exec_load_sign_extend_B_final

exec_load_zero_extend_B:
	; Zero extend for three bytes.
	mov	a, #0x00

exec_load_sign_extend_B_final:
	inc	R0
	mov	@R0, a
	inc	R0
	mov	@R0, a
	inc	R0
	mov	@R0, a

	; Done extending, jump to the end.
	sjmp	exec_load_done

exec_load_sign_extend_H:
	; Extend the sign for two bytes.

	; Jump if we should zero extend instead of sign extend.
	jb	inst_funct3_bit_2__zero_extend, exec_load_zero_extend_H

	; Check if the sign is positive or negative.
	mov	a, R2
	jnb	ACC.7, exec_load_zero_extend_H

	; Sign was negative.
	mov	a, #0xFF
	sjmp	exec_load_sign_extend_H_final

exec_load_zero_extend_H:
	; Zero extend for two bytes.
	mov	a, #0x00

exec_load_sign_extend_H_final:
	inc	R0
	mov	@R0, a
	inc	R0
	mov	@R0, a

	; Done extending, and we're at the end already so there's no
	; need to jump.

exec_load_done:
	; Restore dptr.
	pop	dpl
	pop	dph

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

	; Compare rs1 and rs2 byte-by-byte, from most significant to
	; least significant, until a difference is found. If the carry
	; bit is set, then rs1 < rs2. If the carry bit is not set and
	; the result is non-zero, then rs1 > rs2.
	clr	c
	mov	a, immediate_3
	subb	a, rs2
	jc	branch_lt_ge_result_less_than
	jnz	branch_lt_ge_result_greater_than_or_equal_to
	mov	a, immediate_2
	subb	a, rs1
	jc	branch_lt_ge_result_less_than
	jnz	branch_lt_ge_result_greater_than_or_equal_to
	mov	a, immediate_1
	subb	a, funct3
	jc	branch_lt_ge_result_less_than
	jnz	branch_lt_ge_result_greater_than_or_equal_to
	mov	a, immediate_0
	subb	a, rd
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
	; it, clearing the lowest bit, and storing the results in R3:R2.
	; This is the virtual jump address.
	mov	a, @R1
	add	a, immediate_0
	anl	a, #0xFE
	mov	R2, a
	inc	R1

	mov	a, @R1
	addc	a, immediate_1
	mov	R3, a

	; We can't jump anywhere but CODE memory, so just ignore the upper
	; two bytes of rs1.

	; TODO: Use immediate_2 to support paged CODE memory.

	; To get the real jump address, add the virtual jump address to
	; rv_code, then store the result in dptr.
	mov	a, R2
	add	a, #(rv_code)
	mov	dpl, a
	mov	a, R3
	addc	a, #(rv_code >> 8)
	mov	dph, a

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

	; The upper bytes are used to access different address spaces.
	; e.g., XDATA, SFR, hypercall registers, etc.
	mov	a, @R1
	addc	a, immediate_2
	mov	rs1_dat2, a
	inc	R1

	mov	a, @R1
	addc	a, immediate_3
	mov	rs1_dat3, a

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

	; Check what address space we're reading.
	clr	c
	mov	a, rs1_dat3
	subb	a, #((rv_rom_base - rv_ram_base) >> 24)
	jc	exec_store_lt_80_xdata
	subb	a, #((rv_sfr_base - rv_rom_base) >> 24)
	jc	exec_store_lt_C0_code
	subb	a, #((rv_hyp_base - rv_sfr_base) >> 24)
	jc	exec_store_lt_E0_sfr
	sjmp	exec_store_ge_E0_hyp

exec_store_lt_80_xdata:
	; We're always writing at least one byte.
	mov	a, @R1
	movx	@dptr, a

	; Jump to the end if we're done. Otherwise, continue.
	mov	a, funct3
	jz	exec_store_done
	dec	funct3

	; Write the next byte of the 16-bit word.
	inc	R1
	mov	a, @R1
	inc	dptr
	movx	@dptr, a

	; Jump to the end if we're done. Otherwise, continue.
	mov	a, funct3
	jz	exec_store_done

	; Write the next two bytes of the 32-bit word.
	inc	R1
	mov	a, @R1
	inc	dptr
	movx	@dptr, a

	inc	R1
	mov	a, @R1
	inc	dptr
	movx	@dptr, a

	; We're definitely done writing now, so jump to the end.
	sjmp	exec_store_done

exec_store_lt_C0_code:
	; This should never happen. If execution gets here, there's
	; either a bug in the emulator or a bug in the RV code. Which
	; means it could be literally anywhere. Good luck.
	sjmp	.

exec_store_lt_E0_sfr:
exec_store_ge_E0_hyp:
	; Unimplemented--noop for now.

	; Fall through here.

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
	lcall	extract_funct7

	; Load the dst and src addresses into R0 and R1, respectively.
	lcall	set_dst_to_rd_iram_addr
	lcall	set_src_to_rs1_iram_addr

	; Compare funct3 and sometimes funct7.
	mov	R3, funct3
	mov	R7, funct7

	cjne	R3, #0, exec_op_imm_0  ; ADDI
	ljmp	exec_addi
exec_op_imm_0:
	cjne	R3, #1, exec_op_imm_1  ; SLLI
	cjne	R7, #0, exec_op_imm_1
	ljmp	exec_slli
exec_op_imm_1:
	cjne	R3, #2, exec_op_imm_2  ; SLTI
	ljmp	exec_slti_sltiu
exec_op_imm_2:
	cjne	R3, #3, exec_op_imm_3  ; SLTIU
	ljmp	exec_slti_sltiu
exec_op_imm_3:
	cjne	R3, #4, exec_op_imm_4  ; XORI
	ljmp	exec_xori
exec_op_imm_4:
	cjne	R3, #5, exec_op_imm_5  ; SRLI/SRAI
	mov	a, R7
	anl	a, #0xDF
	cjne	a, #0, exec_op_imm_5
	ljmp	exec_srli_srai
exec_op_imm_5:
	cjne	R3, #6, exec_op_imm_6  ; ORI
	ljmp	exec_ori
exec_op_imm_6:
	cjne	R3, #7, exec_op_imm_7  ; ANDI
	ljmp	exec_andi
exec_op_imm_7:
	; Unrecognized instruction or execution function didn't "ret".
	sjmp	.

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

exec_slli:
	; Return early if the shift is zero.
	mov	a, immediate_0
	jnz	exec_slli_shift_not_zero
	ret

exec_slli_shift_not_zero:
	; Read rs1 into its IRAM variable because we're going to be
	; making a lot of modifications to it before storing the result
	; in the destination register.
	mov	rs1_dat0, @R1
	inc	R1
	mov	rs1_dat1, @R1
	inc	R1
	mov	rs1_dat2, @R1
	inc	R1
	mov	rs1_dat3, @R1

exec_slli_loop:
	clr	c
	mov	a, rs1_dat0
	rlc	a
	mov	rs1_dat0, a
	mov	a, rs1_dat1
	rlc	a
	mov	rs1_dat1, a
	mov	a, rs1_dat2
	rlc	a
	mov	rs1_dat2, a
	mov	a, rs1_dat3
	rlc	a
	mov	rs1_dat3, a
	djnz	immediate_0, exec_slli_loop

	mov	@R0, rs1_dat0
	inc	R0
	mov	@R0, rs1_dat1
	inc	R0
	mov	@R0, rs1_dat2
	inc	R0
	mov	@R0, rs1_dat3

	ret

exec_slti_sltiu:
	funct3_bit_0__set_if_unsigned_cleared_if_signed	= (((funct3 - 0x20) * 8) + 0)

	; Offset R1 by 3 because the unsigned comparison process starts
	; from the high byte, and the sign comparison needs to check the
	; high bit.
	inc	R1
	inc	R1
	inc	R1

	; Determine if we need to do a signed comparison or not.
	jb	funct3_bit_0__set_if_unsigned_cleared_if_signed, slti_sltiu_check_unsigned

	; We're doing a signed comparison.

	; if rs1 is negative (sign bit set) and immediate is positive
	; (sign bit cleared), rs1 < immediate.

	; Jump if rs1 is negative. Do this by fetching the last byte in
	; rs1 and checking if bit 7 is set.
	mov	a, @R1
	jb	ACC.7, slti_sltiu_rs1_is_negative_immediate_is_unknown

	; rs1 is positive.

	; if rs1 is positive (sign bit cleared) and immediate is
	; negative (sign bit set), rs1 > immediate.

	; Jump if immediate is negative.
	jb	(((immediate_0 - 0x20) * 8) + 31), slti_sltiu_result_greater_than

	; immediate is positive.

	; if rs1 is positive (sign bit cleared) and immediate is positive
	; (sign bit cleared), we just do an unsigned comparison.
	sjmp	slti_sltiu_check_unsigned

slti_sltiu_result_greater_than:
	; rs1 > immediate.
	clr	c
	sjmp	slti_sltiu_final

slti_sltiu_rs1_is_negative_immediate_is_unknown:
	; rs1 is negative.

	; Jump if immediate is negative.
	jb	(((immediate_0 - 0x20) * 8) + 31), slti_sltiu_rs1_and_immediate_are_both_negative

	; immediate is positive.

	; rs1 < immediate.
	setb	c
	sjmp	slti_sltiu_final

slti_sltiu_rs1_and_immediate_are_both_negative:
	; rs1 is negative and immediate is negative. Since they're the
	; same sign, we can just treat them like they're unsigned and do
	; an unsigned comparison.
	; Fall through here.

slti_sltiu_check_unsigned:
	; We're doing an unsigned comparison.

	; Compare rs1 and the immediate byte-by-byte, from most
	; significant to least significant, until a difference is found.
	; If the carry bit is set, then rs1 < immediate.
	clr	c
	mov	a, @R1
	subb	a, immediate_3
	jc	slti_sltiu_final
	jnz	slti_sltiu_final
	dec	R1
	mov	a, @R1
	subb	a, immediate_2
	jc	slti_sltiu_final
	jnz	slti_sltiu_final
	dec	R1
	mov	a, @R1
	subb	a, immediate_1
	jc	slti_sltiu_final
	jnz	slti_sltiu_final
	dec	R1
	mov	a, @R1
	subb	a, immediate_0

slti_sltiu_final:
	; if rs1 < immediate, the carry bit will be set. Clear A, then
	; do "A = A + 0 + C" so that A is 1 when rs1 < immediate and 0
	; otherwise.
	clr	a
	addc	a, #0

	; Set the result in the register.
	mov	@R0, a
	inc	R0
	mov	@R0, #0
	inc	R0
	mov	@R0, #0
	inc	R0
	mov	@R0, #0

	ret

exec_xori:
	; For each byte in the source and destination registers, XOR the
	; source byte with the corresponding immediate byte and store
	; the result in the corresponding destination byte.
	mov	a, @R1
	xrl	a, immediate_0
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, @R1
	xrl	a, immediate_1
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, @R1
	xrl	a, immediate_2
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, @R1
	xrl	a, immediate_3
	mov	@R0, a

	ret

exec_srli_srai:
	; Return early if the shift is zero.
	mov	a, immediate_0
	anl	a, #0x1F
	jnz	exec_srli_srai_shift_not_zero
	ret

exec_srli_srai_shift_not_zero:
	; Read rs1 into its IRAM variable because we're going to be
	; making a lot of modifications to it before storing the result
	; in the destination register.
	mov	rs1_dat0, @R1
	inc	R1
	mov	rs1_dat1, @R1
	inc	R1
	mov	rs1_dat2, @R1
	inc	R1
	mov	rs1_dat3, @R1

	jb	(((funct7 - 0x20) * 8) + 5), exec_srli_srai_arith

exec_srli_srai_loop:
	clr	c
	mov	a, rs1_dat3
	rrc	a
	mov	rs1_dat3, a
	mov	a, rs1_dat2
	rrc	a
	mov	rs1_dat2, a
	mov	a, rs1_dat1
	rrc	a
	mov	rs1_dat1, a
	mov	a, rs1_dat0
	rrc	a
	mov	rs1_dat0, a
	djnz	immediate_0, exec_srli_srai_loop
	sjmp	exec_srli_srai_done

exec_srli_srai_arith:
	; Do the regular right shift if the sign bit is clear.
	mov	a, rs1_dat3
	jnb	ACC.7, exec_srli_srai_loop

	; Fall through for the shift with the sign set.

exec_srli_srai_loop_arith:
	setb	c
	mov	a, rs1_dat3
	rrc	a
	mov	rs1_dat3, a
	mov	a, rs1_dat2
	rrc	a
	mov	rs1_dat2, a
	mov	a, rs1_dat1
	rrc	a
	mov	rs1_dat1, a
	mov	a, rs1_dat0
	rrc	a
	mov	rs1_dat0, a
	djnz	immediate_0, exec_srli_srai_loop_arith

	; Fall through when done.

exec_srli_srai_done:
	mov	@R0, rs1_dat0
	inc	R0
	mov	@R0, rs1_dat1
	inc	R0
	mov	@R0, rs1_dat2
	inc	R0
	mov	@R0, rs1_dat3

	ret

exec_ori:
	; For each byte in the source and destination registers, OR the
	; source byte with the corresponding immediate byte and store
	; the result in the corresponding destination byte.
	mov	a, @R1
	orl	a, immediate_0
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, @R1
	orl	a, immediate_1
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, @R1
	orl	a, immediate_2
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, @R1
	orl	a, immediate_3
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

exec_op:
	lcall	extract_rd

	; Return early if we're writing the zero register.
	mov	a, rd
	cjne	a, #0, exec_op_rd_not_zero
	ret

exec_op_rd_not_zero:
	lcall	extract_funct3
	lcall	extract_rs1
	lcall	extract_rs2
	lcall	extract_funct7

	; Load the dst and src addresses into R0 and R1, respectively.
	lcall	set_dst_to_rd_iram_addr
	lcall	set_src_to_rs1_iram_addr

	; Load rs1 into rs1_dat[0-3].
	mov	rs1_dat0, @R1
	inc	R1
	mov	rs1_dat1, @R1
	inc	R1
	mov	rs1_dat2, @R1
	inc	R1
	mov	rs1_dat3, @R1

	; Load the second src address into R1.
	lcall	set_src_to_rs2_iram_addr

	; Compare funct3 and funct7.
	mov	R3, funct3
	mov	R7, funct7

	cjne	R3, #0, exec_op_0_0  ; ADD
	cjne	R7, #0x00, exec_op_0_0
	ljmp	exec_add
exec_op_0_0:
	cjne	R3, #0, exec_op_0_1  ; SUB
	cjne	R7, #0x20, exec_op_0_1
	ljmp	exec_sub
exec_op_0_1:
	cjne	R3, #1, exec_op_1  ; SLL
	cjne	R7, #0x00, exec_op_1
	ljmp	exec_sll
exec_op_1:
	cjne	R3, #4, exec_op_4  ; XOR
	cjne	R7, #0x00, exec_op_4
	ljmp	exec_xor
exec_op_4:
	cjne	R3, #5, exec_op_5  ; SRL/SRA
	mov	a, R7
	anl	a, #0xDF
	cjne	a, #0x00, exec_op_5
	ljmp	exec_srl_sra
exec_op_5:
	cjne	R3, #6, exec_op_6  ; OR
	cjne	R7, #0x00, exec_op_6
	ljmp	exec_or
exec_op_6:
	cjne	R3, #7, exec_op_7  ; AND
	cjne	R7, #0x00, exec_op_7
	ljmp	exec_and
exec_op_7:
	; Unrecognized instruction or execution function didn't "ret".
	sjmp	.

exec_add:
	; For each byte in the source and destination registers, ADD the
	; first source byte with the corresponding second source byte
	; and store the result in the corresponding destination byte.
	mov	a, rs1_dat0
	add	a, @R1
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, rs1_dat1
	addc	a, @R1
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, rs1_dat2
	addc	a, @R1
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, rs1_dat3
	addc	a, @R1
	mov	@R0, a

	ret

exec_sub:
	; For each byte in the source and destination registers, SUB the
	; first source byte with the corresponding second source byte
	; and store the result in the corresponding destination byte.
	clr	c
	mov	a, rs1_dat0
	subb	a, @R1
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, rs1_dat1
	subb	a, @R1
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, rs1_dat2
	subb	a, @R1
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, rs1_dat3
	subb	a, @R1
	mov	@R0, a

	ret

exec_sll:
	; Get the shift amount from the lower five bits of rs2.
	lcall	set_src_to_rs2_iram_addr
	mov	a, @R1
	anl	a, #0x1F

	; Return early if the shift is zero.
	jnz	exec_sll_shift_not_zero
	ret

exec_sll_shift_not_zero:
	; Save the shift amount in R2.
	mov	R2, a

exec_sll_loop:
	clr	c
	mov	a, rs1_dat0
	rlc	a
	mov	rs1_dat0, a
	mov	a, rs1_dat1
	rlc	a
	mov	rs1_dat1, a
	mov	a, rs1_dat2
	rlc	a
	mov	rs1_dat2, a
	mov	a, rs1_dat3
	rlc	a
	mov	rs1_dat3, a
	djnz	R2, exec_sll_loop

	; Store the result in the destination register.
	mov	@R0, rs1_dat0
	inc	R0
	mov	@R0, rs1_dat1
	inc	R0
	mov	@R0, rs1_dat2
	inc	R0
	mov	@R0, rs1_dat3

	ret

exec_xor:
	; For each byte in the source and destination registers, XOR the
	; first source byte with the corresponding second source byte
	; and store the result in the corresponding destination byte.
	mov	a, rs1_dat0
	xrl	a, @R1
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, rs1_dat1
	xrl	a, @R1
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, rs1_dat2
	xrl	a, @R1
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, rs1_dat3
	xrl	a, @R1
	mov	@R0, a

	ret

exec_srl_sra:
	; Get the shift amount from the lower five bits of rs2.
	lcall	set_src_to_rs2_iram_addr
	mov	a, @R1
	anl	a, #0x1F

	; Return early if the shift is zero.
	jnz	exec_srl_sra_shift_not_zero
	ret

exec_srl_sra_shift_not_zero:
	; Save the shift amount in R2.
	mov	R2, a

	; Jump if this is an arithmetic right shift.
	jb	(((funct7 - 0x20) * 8) + 5), exec_srl_sra_arith

exec_srl_sra_loop:
	clr	c
	mov	a, rs1_dat3
	rrc	a
	mov	rs1_dat3, a
	mov	a, rs1_dat2
	rrc	a
	mov	rs1_dat2, a
	mov	a, rs1_dat1
	rrc	a
	mov	rs1_dat1, a
	mov	a, rs1_dat0
	rrc	a
	mov	rs1_dat0, a
	djnz	R2, exec_srl_sra_loop
	sjmp	exec_srl_sra_done

exec_srl_sra_arith:
	; Do the regular right shift if the sign bit is clear.
	mov	a, rs1_dat3
	jnb	ACC.7, exec_srl_sra_loop

	; Fall through for the shift with the sign bit set.

exec_srl_sra_loop_arith:
	setb	c
	mov	a, rs1_dat3
	rrc	a
	mov	rs1_dat3, a
	mov	a, rs1_dat2
	rrc	a
	mov	rs1_dat2, a
	mov	a, rs1_dat1
	rrc	a
	mov	rs1_dat1, a
	mov	a, rs1_dat0
	rrc	a
	mov	rs1_dat0, a
	djnz	R2, exec_srl_sra_loop_arith

	; Fall through when done.

exec_srl_sra_done:
	; Store the result in the destination register.
	mov	@R0, rs1_dat0
	inc	R0
	mov	@R0, rs1_dat1
	inc	R0
	mov	@R0, rs1_dat2
	inc	R0
	mov	@R0, rs1_dat3

	ret

exec_or:
	; For each byte in the source and destination registers, OR the
	; first source byte with the corresponding second source byte
	; and store the result in the corresponding destination byte.
	mov	a, rs1_dat0
	orl	a, @R1
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, rs1_dat1
	orl	a, @R1
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, rs1_dat2
	orl	a, @R1
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, rs1_dat3
	orl	a, @R1
	mov	@R0, a

	ret

exec_and:
	; For each byte in the source and destination registers, AND the
	; first source byte with the corresponding second source byte
	; and store the result in the corresponding destination byte.
	mov	a, rs1_dat0
	anl	a, @R1
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, rs1_dat1
	anl	a, @R1
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, rs1_dat2
	anl	a, @R1
	mov	@R0, a
	inc	R1
	inc	R0

	mov	a, rs1_dat3
	anl	a, @R1
	mov	@R0, a

	ret

exec_auipc:
	lcall	extract_rd

	; Return early if we're writing the zero register.
	mov	a, rd
	cjne	a, #0, exec_auipc_rd_not_zero
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

extract_funct7:
	mov	a, instruction_3
	anl	a, #0xFE
	rr	a
	mov	funct7, a
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
