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

    mov ax, 0x1000
    mov fs, ax

mov si, msg_startup
CALL println_si

mov si, msg_read_bootstrap
CALL println_si

; INT 13 - IBM/MS INT 13 Extensions - EXTENDED READ
load_bootstrapper_into_memory:
    mov ah, 0x42
    mov dl, 0x80
    mov si, dap_bootstrap
    int 0x13
    jc handle_error

mov si, success
CALL println_si

mov si, msg_read_kernel
CALL println_si

load_kernel_into_memory:
    mov dl, 0x80
    mov ah, 0x42
    mov si, dap_kernel_1
    int 0x13
    mov ah, 0x42
    mov si, dap_kernel_2
    int 0x13
    mov ah, 0x42
    mov si, dap_kernel_3
    int 0x13
    mov ah, 0x42
    mov si, dap_kernel_4
    int 0x13
    jc handle_error

mov si, success
CALL println_si

mov si, newline
CALL println_si

mov si, msg_set_protected_mode
CALL println_si

mov si, msg_create_32_bit_page_tables
CALL println_si

set_protected_mode:
    ; clear segment registers
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax

    cli
    lgdt [gdt_desc]

    ; enable cr0 protect bit
    mov eax, cr0
    or al, 1
    mov cr0, eax

    ; TODO: load interrupt descriptor table

    ; far jump to reset CS
    jmp 0x08:BOOTSTRAP

; status
msg_startup               db '[lnd-web-api]', 0
msg_read_bootstrap        db 'Reading bootstrapper from disk...', 0
msg_read_kernel           db 'Reading kernel from disk...', 0
msg_set_protected_mode    db 'Enabling Protected Mode...', 0

; paging
msg_create_32_bit_page_tables               db 'Creating Page Table and Page Descriptor Table...', 0
;msg_create_page_descriptor_pointer_table    db 'Creating Page Descriptor Pointer Table...', 0
;msg_create_page_map_4               db 'Creating Page Map L4...', 0

newline                         db ' ', 0
success                         db 'Success!', 0
error                           db 'Error :(', 0

handle_error:
print_error:
    lodsb                           ; load byte from si into AL
    mov ah, 0x0e                    ; teletype output command (1 char?)
    int 0x10                        ; execute bios video service command (teletype output)
    test al, al                     ; check if we reached null terminator
    jnz print_error                 ; else print next char
    hlt

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

dap_bootstrap:
    db 0x10                                 ; 00h       BYTE    size of packet (10h or 18h)
    db 0                                    ; 01h       BYTE    reserved (0)
    dw 1                                    ; 02h       WORD    number of blocks to transfer
    dd 0x00008000                           ; 04h       DWORD   address of transfer buffer
    dq 1                                   ; 08h       QWORD    starting absolute block number

dap_kernel_1:
    db 0x10                                 ; 00h       BYTE    size of packet (10h or 18h)
    db 0                                    ; 01h       BYTE    reserved (0)
    dw 128                                 ; 02h       WORD    number of blocks to transfer
    dw 0x0000                               ; 04h       DWORD   address of transfer buffer
    dw 0x1000
    dq 2                                    ; 08h        QWORD    starting absolute block number

dap_kernel_2:
    db 0x10                                 ; 00h       BYTE    size of packet (10h or 18h)
    db 0                                    ; 01h       BYTE    reserved (0)
    dw 128                                 ; 02h       WORD    number of blocks to transfer
    dw 0x0000                               ; 04h       DWORD   address of transfer buffer
    dw 0x2000
    dq 130                                    ; 08h        QWORD    starting absolute block number

dap_kernel_3:
    db 0x10                                 ; 00h       BYTE    size of packet (10h or 18h)
    db 0                                    ; 01h       BYTE    reserved (0)
    dw 128                                 ; 02h       WORD    number of blocks to transfer
    dw 0x0000                               ; 04h       DWORD   address of transfer buffer
    dw 0x3000
    dq 258                                    ; 08h        QWORD    starting absolute block number

dap_kernel_4:
    db 0x10                                 ; 00h       BYTE    size of packet (10h or 18h)
    db 0                                    ; 01h       BYTE    reserved (0)
    dw 128                                 ; 02h       WORD    number of blocks to transfer
    dw 0x0000                               ; 04h       DWORD   address of transfer buffer
    dw 0x4000
    dq 376                                    ; 08h        QWORD    starting absolute block number


y_position:
    db 0

gdt_start:
    dq 0 ; required null
    ; limit (2 bytes) = 0 (ignored in 64-bit mode)
    ; base (20 bits) = 0 (ignore in 64-bit mode)
    ;               P|DPL|S|E|DC|RW|A
    ; code access = 1|00 |1|1|1 |1 |1 = 1001 1111 = 9F
    ; data access = 1|00 |1|0|1 |1 |1 = 1001 0011 = 93
    ; access | base    | limit
    ;        | 00000   | 0000
    ; code segment
    dw 0xffff   ; limit low
    dw 0        ; base low
    db 0        ; base mid
    db 0x9f     ; access
    db 0xcf     ; flag, limit high
    db 0        ; base high

    ; data segment
    dw 0xffff   ; limit low
    dw 0        ; base low
    db 0        ; base mid
    db 0x93     ; access
    db 0xcf     ; flag, limit high
    db 0        ; base high

    ; video segment
    dw 0xffff   ; limit low
    dw 0x8000   ; base low
    db 0x0b     ; base mid
    db 0x93     ; access
    db 0x4f     ; flag, limit high
    db 0        ; base high
gdt_end:

gdt_desc:
    dw gdt_end - gdt_start - 1 ; size
    dw gdt_start, 0

;mov si, msg_create_page_descriptor_pointer_table
;CALL println_si
;
;mov si, success
;CALL println_si
;
;mov si, msg_create_page_map_4
;CALL println_si
;
;mov si, success
;CALL println_si


;
;create_page_table_L3:
;    mov eax, PAGE_TABLE_L2  ; destination table
;    mov edi, PAGE_TABLE_L3  ; this table
;    mov ecx, 1024 ; loop count
;
;fill_page_table_L3:
;    mov ebx, eax
;    or ebx, 3       ; rw and present
;
;    mov [edi], ebx
;
;    add edi, 4      ; page entry offset along 4 bytes
;    add eax, 4   ; move page offset along 4096 bytes
;
;    loop fill_page_table_L3
;
;create_page_table_L4:
;    mov eax, PAGE_TABLE_L3  ; destination table
;    mov edi, PAGE_TABLE_L4  ; this table
;    mov ecx, 1024 ; loop count
;
;fill_page_table_L4:
;    mov ebx, eax
;    or ebx, 3       ; ro and present
;
;    mov [edi], ebx
;
;    add edi, 4      ; page entry offset along 4 bytes
;    add eax, 4      ; move page offset along 4096 bytes
;
;    loop fill_page_table_L4
;
;mov si, success
;CALL println_si

pad_with_zeroes:
    times 510-($-$$) db 0

write_boot_signature:
    dw 0xAA55
