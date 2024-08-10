[BITS 16]
org 0x8000 ; start at bootstrapper origin

mov si, msg_load_code

print_load_code_msg:
    lodsb                           ; load byte from si into AL
    mov ah, 0x0E                    ; teletype output command (1 char?)
    int 0x10                        ; execute bios video service command (teletype output)
    test al, al                     ; check if we reached null terminator
    jnz print_load_code_msg   ; else print next char

load_code_into_memory:
    mov ah, 0x42
    mov dl, 0x80
    mov si, disk_address_packet             ; need intermediary register...
    int 0x13                                ; INT 13 - IBM/MS INT 13 Extensions - EXTENDED READ
    jc handle_load_error

mov si, msg_main_startup
print_main_start_msg:
    lodsb                           ; load byte from si into AL
    mov ah, 0x0E                    ; teletype output command (1 char?)
    int 0x10                        ; execute bios video service command (teletype output)
    test al, al                     ; check if we reached null terminator
    jnz print_main_start_msg        ; else print next char
   
jump_to_main:
    jmp 0x0000:0xA000

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
