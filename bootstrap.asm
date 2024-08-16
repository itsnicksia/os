[BITS 16]
org 0x8000 ; start at bootstrapper origin

mov si, msg_load_code
print_load_code_msg:
    lodsb                           ; load byte from si into AL
    mov ah, 0x0E                    ; teletype output command (1 char?)
    int 0x10                        ; execute bios video service command (teletype output)
    test al, al                     ; check if we reached null terminator
    jnz print_load_code_msg         ; else print next char

load_code_into_memory:
    mov ah, 0x42
    mov dl, 0x80
    mov si, disk_address_packet             ; need intermediary register...
    int 0x13                                ; INT 13 - IBM/MS INT 13 Extensions - EXTENDED READ
    jc handle_load_error

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

    ; TODO: load interrupt descripter table
    
    ; far jump to reset CS
    jmp 0x08:protected_mode_start

[BITS 32]
protected_mode_start:
    ; reinitialize segment registers
    mov ax, 0x10    ; gdt 2 = data
    mov ds, ax      ; data segment
    mov es, ax      ; extra segment
    mov fs, ax      ; fs (extra 2)
    mov gs, ax      ; gs (extra 3)
    mov ss, ax      ; stack segment

    ; TODO: enable paging
    ; map first megabyte as identity pages

    mov eax, 0 ; index
    mov edx, page_table_data ; base address
    mov ebx, edx ; base address

create_identity_page_table:
    mov ecx, ebx
    or ecx, 1 ; ro and present
    mov [edx + eax * 4], ecx ; write page table entry at index
    add ebx, 4096 ; next page base address
    inc eax ; index++
    cmp eax, 1024
    jne create_identity_page_table



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

enable_paging:

[BITS 64]
long_mode_start:

jump_to_main:
; todo: setup identity map for my code
;    jmp 0x0000:0xB000

; strings
msg_load_code db 'Loading web-api-lnd code...', 0x0D, 0x0A, 0
msg_main_startup db 'Starting web-api-lnd...', 0x0D, 0x0A, 0
msg_load_error db 'Failed to load code :(', 0

disk_address_packet:
    db 0x10                                 ; 00h       BYTE    size of packet (10h or 18h)
    db 0                                    ; 01h       BYTE    reserved (0)
    dw 16                                    ; 02h       WORD    number of blocks to transfer
    dd 0x0000A000                           ; 04h       DWORD   address of transfer buffer
    dq 2                                    ; 08h       QWORD    starting absolute block number

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
gdt_end:

gdt_desc:
    dw gdt_end - gdt_start - 1 ; size
    dw gdt_start, 0

align 4096
page_table_data:
    times 1024 dd 0

align 4096
page_directory:
    ; TODO: map to page tables
    times 1024 dd 0

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