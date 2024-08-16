[BITS 16]
; memory areas
IVT         EQU 0x0000
BIOS_DATA   EQU 0x0400

STACK       EQU 0x7000
STACK_SIZE  EQU 0x0400

BOOTLOADER  EQU 0x7C00
BOOTSTRAP   EQU 0x8000

VIDEO_BUFFER  EQU  0xB8000

; video
VIDEO_MODE_TEXT_80_25 EQU 3
TEXT_WIDTH  EQU 80
TEXT_HEIGHT EQU 25

; start from bootloader origin
org BOOTLOADER

; EAX — Accumulator for operands and results data.
; EBX — Pointer to data in the DS segment.
; ECX — Counter for string and loop operations.
; EDX — I/O pointer.
; ESI — Pointer to data in the segment pointed to by the DS register; source pointer for string operations.
; EDI — Pointer to data (or destination) in the segment pointed to by the ES register; destination pointer for string operations.
; ESP — Stack pointer (in the SS segment).
; EBP — Pointer to data on the stack (in the SS segment).

initialize_stack:
    mov ax, STACK
    mov ss, ax
    mov sp, STACK_SIZE

set_video_mode:
    mov al, VIDEO_MODE_TEXT_80_25
    mov ah, 0
    int 0x10

set_extra_segment_to_video_buffer:
    mov ax, VIDEO_BUFFER >> 4
    mov es, ax

mov si, msg_startup
CALL println_si

mov si, msg_read_bootstrap_start
CALL println_si

; INT 13 - IBM/MS INT 13 Extensions - EXTENDED READ
load_bootstrapper_into_memory:
    mov ah, 0x42
    mov dl, 0x80
    mov si, disk_address_packet
    int 0x13
    jc handle_error

mov si, msg_read_bootstrap_finish
CALL println_si

cli
hlt

jump_to_bootstrap:
    jmp 0x0000:0x8000

; strings
msg_startup                 db '[lnd-web-api]', 0
msg_read_bootstrap_start    db 'Reading bootstrapper from disk...', 0
msg_read_bootstrap_finish   db 'Finished reading bootstrapper!', 0

error                       db 'Error :(', 0

handle_error:
print_error:
    lodsb                           ; load byte from si into AL
    mov ah, 0x0e                    ; teletype output command (1 char?)
    int 0x10                        ; execute bios video service command (teletype output)
    test al, al                     ; check if we reached null terminator
    jnz print_error                 ; else print next char

println_si:
    ; load white on black into first byte
    mov bh, 0x0f
    mov cx, 0   ; column offset
println_si_char:
    ; load character into second byte
    mov bl, [si]

    ; calculate relative offset stored in ax
    mov ax, [y_position]    ; ax = y_position

    mov dx, TEXT_WIDTH      ; dx = TEXT_WIDTH
    mul dx                  ; dx = index offset from row
    shl ax, 1               ; ax = byte offset from row (2 byte per index)

    mov dx, cx              ; dx = column offset
    shl dx, 1               ; dx = byte offset from column (2 byte per index)
    add ax, dx              ; ax += bye offset

    ; ax is now full byte offset

    mov di, ax              ; di is the byte offset now

    mov [es:di], bx            ; write char to buffer

    ; next column
    inc cl

    ; next character
    inc si
    mov dl, [si]
    cmp dl, 0               ; null byte?

    jne println_si_char     ; else next char

    ; move to next line
    ; todo: scrolling
    mov dl, [y_position]
    inc dl
    mov [y_position], dl

    ret

disk_address_packet:
    db 0x10                                 ; 00h       BYTE    size of packet (10h or 18h)
    db 0                                    ; 01h       BYTE    reserved (0)
    dw 1                                    ; 02h       WORD    number of blocks to transfer
    dd 0x00008000                           ; 04h       DWORD   address of transfer buffer
    dq 1                                   ; 08h       QWORD    starting absolute block number

y_position:
    db 0

pad_with_zeroes:
    times 510-($-$$) db 0

write_boot_signature:
    dw 0xAA55
