[BITS 16]
org 0x7C00 ;start at bootloader origin

start:
	mov si, splash_message  ; load splash message address into SI

print_splash_char:
	lodsb						; load byte from si into AL
	mov ah, 0x0E 				; teletype output command (1 char?)
	int 0x10 					; execute bios video service command (teletype output)
	test al, al					; check if we reached null terminator
	jnz print_splash_char		; hang...?

; constants
splash_message db 'Web API LnD', 0

pad_with_zeroes:
	times 510-($-$$) db 0

write_boot_signature:
	dw 0xAA55
