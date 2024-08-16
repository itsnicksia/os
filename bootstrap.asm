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
hlt
load_code_into_memory:
    mov ah, 0x42
    mov dl, 0x80
    mov si, disk_address_packet             ; need intermediary register...
    int 0x13                                ; INT 13 - IBM/MS INT 13 Extensions - EXTENDED READ
    jc handle_load_error





cli
hlt

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
msg_load_code db 'Loading web-api-lnd code...', 0x0D, 0x0A, 0
msg_main_startup db 'Starting web-api-lnd...', 0x0D, 0x0A, 0
msg_load_error db 'Failed to load code :(', 0

success                         db 'Success!', 0

disk_address_packet:
    db 0x10                                 ; 00h       BYTE    size of packet (10h or 18h)
    db 0                                    ; 01h       BYTE    reserved (0)
    dw 16                                    ; 02h       WORD    number of blocks to transfer
    dd 0x0000A000                           ; 04h       DWORD   address of transfer buffer
    dq 2                                    ; 08h       QWORD    starting absolute block number



handle_load_error:
    mov bh, ah
    mov si, msg_load_error
print_error_msg:
    lodsb                           ; load byte from si into AL
    mov ah, 0x0E                    ; teletype output command (1 char?)
    int 0x10                        ; execute bios video service command (teletype output)
    test al, al                     ; check if we reached null terminator
    jnz print_error_msg             ; else print next char 
    cli
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

; smelly hack
y_position:
    db 6

[BITS 64]
long_mode_start:

jump_to_main:
; todo: setup identity map for my code
;    jmp 0x0000:0xB000