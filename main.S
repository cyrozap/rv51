	.area	XSEG	(XDATA)
	.area	PSEG	(PAG,XDATA)
	.area	HOME	(ABS,CODE)
	.org	0x0000
reset:
	ljmp	init
	sjmp	.

init:
	; Set stack pounter to scratch pad area.
	mov	sp, #0x30
	; Use dptr as the RV's PC (offset by #rvcode) and fetch the
	; first RV instruction.
	mov	dptr, #(rvcode)
emu_loop:
	lcall	fetch_dword
	mov	0x20, r0  ; Move the opcode into a bit-addressable register.
	clr	7
	lcall	decode_opcode
	sjmp	emu_loop

; We should never get here.
busy_loop:
	sjmp	.

; IN: 0x20, r3:r2:r1:r0
decode_opcode:
	push	a
	mov	a, 0x20
	cjne	a, #0x37, decode_0  ; LUI
	lcall	exec_lui
	sjmp	decode_done
decode_0:
	cjne	a, #0x13, decode_7  ; OP-IMM
	lcall	exec_op_imm
	sjmp	decode_done
decode_7:
	sjmp	.
decode_done:
	pop	a
	ret

; IN: 0x20, r3:r2:r1:r0
; Clobbers: a, c, r1:r0, r7:r6:r5:r4
exec_op_imm:
	; Extract rd and store it on the stack.
	lcall	extract_rd
	push	a

	; Extract funct3 and store it in r0.
	lcall	extract_funct3
	mov	r0, a

	; Extract rs1 and store it in A.
	lcall	extract_rs1

	; Read the RV source register into r7:r6:r5:r4.
	lcall	rv_reg_read

	; Get the IRAM offset of the RV register.
	pop	a  ; rd
	lcall	get_rv_reg_offset

	; Now you have:
	; r0 = funct3
	; a = IRAM offset of rd
	; r7:r6:r5:r4 = rs

	; Compare funct3.
	cjne	r0, #7, exec_op_imm_7  ; ANDI
	lcall	exec_andi
	sjmp	exec_op_imm_done

exec_op_imm_7:
	sjmp	.
exec_op_imm_done:
	ret

; IN: a, r3:r2, r7:r6:r5:r4
; OUT: rd[0:4]
; Clobbers: a, r3:r2
exec_andi:
	; Store rd in r0.
	mov	r0, a

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

	; ANL r5 with the top 4 bits of the immediate and store in r2.
	anl	a, #0x0F
	orl	a, #0xF0
	anl	a, r5
	xch	a, r2

	; ANL the bottom byte of the immediate with r4 and store in A.
	anl	a, r4

	; Copy r7:r6:r2:a into rd.
	mov	@r0, a
	inc	r0
	mov	a, r2
	mov	@r0, a
	inc	r0
	mov	a, r6
	mov	@r0, a
	inc	r0
	mov	a, r7
	mov	@r0, a

	ret

; IN: 0x20, r3:r2:r1:r0
; Clobbers: a, c, r1:r0
exec_lui:
	; Extract rd and store it in A.
	lcall	extract_rd

	; Get the IRAM offset of the RV register.
	lcall	get_rv_reg_offset

	; Move the pointer into r0 so we can access the memory,
	mov	r0, a

	; Set the lowest byte to zero.
	mov	@r0, #0

	; Increment the pointer to point to the 2nd byte.
	inc	r0

	; ANL the R1 byte with 0xF0.
	mov	a, r1
	anl	a, #0xF0

	; Store the result in r0.
	mov	@r0, a

	; Increment the pointer to point to the 3rd byte.
	inc	r0

	; Bytes R3:R2 get stored into the top two bytes of the RV reg.
	mov	a, r2
	mov	@r0, a
	inc	r0
	mov	a, r3
	mov	@r0, a

	ret

; IN: a
; OUT: r7:r6:r5:r4
; Clobbers: a
rv_reg_read:
	; Check if we're reading the zero register.
	cjne	a, #0, rv_reg_read_nonzero
	mov	r4, a
	mov	r5, a
	mov	r6, a
	mov	r7, a
	ret

rv_reg_read_nonzero:
	ar0	= 0
	push	ar0

	; Get the IRAM offset of the RV register.
	lcall	get_rv_reg_offset

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
	pop	ar0
	ret

; IN: a
; OUT: a
get_rv_reg_offset:
	; Multiply the RV reg number by 4 to get the IRAM offset.
	rl	a
	rl	a

	; Add 0x80 to get the offset in the upper IRAM registers.
	add	a, #0x80

	ret

; IN: r2:r1
; OUT: a
; Clobbers: r1
extract_rs1:
	ar1	= 0x01

	; ANL R1 with 0x80 to get the bottom bit of rs1.
	anl	ar1, #0x80

	; ANL R2 with 0x0F to get the top four bits of rs1.
	mov	a, r2
	anl	a, #0x0F

	; ORL the two registers, then rotate left to get rs1.
	orl	a, r1
	rl	a

	ret

; IN: r1
; OUT: a
extract_funct3:
	mov	a, r1
	anl	a, #0x70
	swap	a
	ret

; IN: r1:r0
; OUT: a
; Clobbers: c, r0
extract_rd:
	; Rotate R1:R0 left by 1.
	MOV	A, R1
	MOV	C, ACC.7
	XCH	A, R0
	RLC	A
	XCH	A, R0
	RLC	A
	;MOV	R1, A

	; Extract the RV reg number from R1.
	anl	a, #0x1F

	ret

; IN:   dptr
; OUT:  r3:r2:r1:r0, dptr+=4
fetch_dword:
	push	a
	clr	a
	movc	a, @a+dptr
	mov	r0, a
	inc	dptr
	clr	a
	movc	a, @a+dptr
	mov	r1, a
	inc	dptr
	clr	a
	movc	a, @a+dptr
	mov	r2, a
	inc	dptr
	clr	a
	movc	a, @a+dptr
	mov	r3, a
	inc	dptr
	pop	a
	ret

rvcode:
