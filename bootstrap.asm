[BITS 32]
BOOTSTRAP       EQU 0x8000
PAGE_TABLE_L1   EQU 0x9000
PAGE_TABLE_L2   EQU PAGE_TABLE_L1 + 0x1000
PAGE_TABLE_L3   EQU PAGE_TABLE_L2 + 0x1000
PAGE_TABLE_L4   EQU PAGE_TABLE_L3 + 0x1000

VIDEO_BUFFER  EQU  0xB8000

; video
VIDEO_MODE_TEXT_80_25 EQU 3
TEXT_WIDTH  EQU 80
TEXT_HEIGHT EQU 25

org 0x8000

protected_mode_start:
    ; reinitialize segment registers
    mov ax, 0x10    ; gdt 2 = data
    mov bx, 0x18    ; gdt 3 = video
    mov ds, ax      ; data segment
    mov es, bx      ; extra segment
    mov fs, ax      ; fs (extra 2)
    mov gs, ax      ; gs (extra 3)
    mov ss, ax      ; stack segment

; TODO: enable paging
create_page_table_L1:
    mov eax, 0
    mov ecx, 1023 ; loop count. reserve 1 for video
    mov edi, PAGE_TABLE_L1

fill_page_table_L1:
    mov ebx, eax
    or ebx, 3       ; ro and present

    mov [edi], ebx

    add edi, 4      ; page entry offset along 4 bytes
    add eax, 4096   ; move page offset along 4096 bytes

    loop fill_page_table_L1

; hackminster palace
add_video_buffer_identity_map:
    mov ebx, VIDEO_BUFFER
    or ebx, 3

    mov [edi], ebx

create_page_table_L2:
    mov eax, PAGE_TABLE_L1  ; destination table
    mov edi, PAGE_TABLE_L2  ; this table
    mov ecx, 1024 ; loop count

fill_page_table_L2:
    mov ebx, eax
    or ebx, 3       ; rw and present

    mov [edi], ebx

    add edi, 4   ; page entry offset along 4 bytes
    add eax, 4   ; move page offset along 4096 bytes

    loop fill_page_table_L2

enable_paging:
    mov eax, PAGE_TABLE_L2
    mov cr3, eax

    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax

mov si, success
CALL println_si

mov si, newline
CALL println_si

mov si, msg_main_startup
CALL println_si

jmp 0x11000

enable_pae:
    mov eax, cr4
    or eax, 0x5
    mov cr4, eax

; ia32_efer
; bit 0 is syscall enable (not using yet)
; bit 8 is ia32e enable
enable_long_mode:
    mov ax, 0x1000 
    rdmsr

; strings
msg_main_startup db 'Starting web-api-lnd kernel!', 0

newline                         db ' ', 0
success                         db 'Success!', 0

println_si:
    ; load white on black into first byte
    mov eax, 0
    mov edx, 0
    mov bh, 0x0f
    mov ecx, 0   ; column offset
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

    mov edi, eax              ; di is the byte offset now

    mov [es:edi], bx            ; write char to buffer

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

; smelly hack
y_position:
    dw 8

[BITS 64]
long_mode_start:

jump_to_main:
; todo: setup identity map for my code
    jmp 0x11000