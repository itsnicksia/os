[BITS 16]
org 0x8000 ; start at bootstrapper origin

start:
    mov si, msg_bootstrapper_startup

print_si:
    lodsb                           ; load byte from si into AL
    mov ah, 0x0E                    ; teletype output command (1 char?)
    int 0x10                        ; execute bios video service command (teletype output)
    test al, al                     ; check if we reached null terminator
    jnz print_si                    ; else print next char

halt:
    cli
    hlt

; strings
msg_bootstrapper_startup         db 'Starting bootstrapper...', 0
