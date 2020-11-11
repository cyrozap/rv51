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
	cjne	a, #0x37, 0$  ; LIU
	lcall	exec_liu
	sjmp	done$
0$:
done$:
	pop	a
	ret

; IN: 0x20, r3:r2:r1:r0
; Clobbers: a, c, r1:r0
exec_liu:
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

	; Multiply the RV reg number by 4 to get the IRAM offset.
	rl	a
	rl	a

	; Add 0x80 to get the offset in the upper IRAM registers.
	add	a, #0x80

	; Increment the pointer to point to the 2nd byte.
	inc	a

	; Move the pointer into r0 so we can access the memory,
	mov	r0, a

	; ANL the RV reg byte with 0x0F.
	mov	a, #0x0F
	anl	a, @r0

	; ANL the R1 byte with 0xF0.
	xch	a, r1
	anl	a, #0xF0

	; ORL the two bytes together.
	orl	a, r1

	; Store the result back in r0.
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
