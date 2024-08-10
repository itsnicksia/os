[BITS 16]
org 0x7C00 ;start at bootloader origin

; memory map
; 0x0000 interrupt vector table (IVT)
; 0x0400 bios data area (BDA)
; 0x0500 "probably safe starting address"
; 0x1000 data segment
; 0x7C00 bootloader
; 0x8000 bootstrap code

; EAX — Accumulator for operands and results data.
; EBX — Pointer to data in the DS segment.
; ECX — Counter for string and loop operations.
; EDX — I/O pointer.
; ESI — Pointer to data in the segment pointed to by the DS register; source pointer for string operations.
; EDI — Pointer to data (or destination) in the segment pointed to by the ES register; destination pointer for string operations.
; ESP — Stack pointer (in the SS segment).
; EBP — Pointer to data on the stack (in the SS segment).

start:
    mov si, msg_startup             ; load splash message address into SI
    
print_startup_msg:
    lodsb                           ; load byte from si into AL
    mov ah, 0x0E                    ; teletype output command (1 char?)
    int 0x10                        ; execute bios video service command (teletype output)
    test al, al                     ; check if we reached null terminator
    jnz print_startup_msg           ; else print next char

; INT 13 - IBM/MS INT 13 Extensions - EXTENDED READ
;   AH = 42h
;   DL = drive number
;   DS:SI -> disk address packet (see #00272)
;
;   Return: CF clear if successful
;       AH = 00h
;   CF set on error
;       AH = error code (see #00234)
;       disk address packet's block count field set to number of blocks successfully transferred

load_bootstrapper_into_memory:
    mov ah, 0x42
    mov dl, 0x80
    mov si, disk_address_packet             ; need intermediary register...
    int 0x13                                ; INT 13 - IBM/MS INT 13 Extensions - EXTENDED READ
    jc handle_error
    mov si, msg_bootstrap_load

print_bootstrap_load_msg:
    lodsb                           ; load byte from si into AL
    mov ah, 0x0E                    ; teletype output command (1 char?)
    int 0x10                        ; execute bios video service command (teletype output)
    test al, al                     ; check if we reached null terminator
    jnz print_bootstrap_load_msg    ; else print next char

jump_to_bootstrap:
    jmp 0x0000:0x8000

; helpers

; strings
msg_startup         db 'Web API LnD...', 0x0D, 0x0A, 0
msg_bootstrap_load  db 'Successfully loaded bootstrapper...', 0x0D, 0x0A, 0
error               db 'Error :(', 0

disk_address_packet:
    db 0x10                                 ; 00h       BYTE    size of packet (10h or 18h)
    db 0                                    ; 01h       BYTE    reserved (0)
    dw 1                                    ; 02h       WORD    number of blocks to transfer
    dd 0x00008000                           ; 04h       DWORD   address of transfer buffer
    dq 1                                   ; 08h       QWORD    starting absolute block number

handle_error:
print_error:
    lodsb                           ; load byte from si into AL
    mov ah, 0x0E                    ; teletype output command (1 char?)
    int 0x10                        ; execute bios video service command (teletype output)
    test al, al                     ; check if we reached null terminator
    jnz print_error    ; else print next char

pad_with_zeroes:
    times 510-($-$$) db 0

write_boot_signature:
    dw 0xAA55
