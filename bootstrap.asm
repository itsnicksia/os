[BITS 32]
BOOTSTRAP       EQU 0x8000
PAGE_TABLE_L1   EQU 0x9000
PAGE_TABLE_L2   EQU PAGE_TABLE_L1 + 0x1000
PAGE_TABLE_L3   EQU PAGE_TABLE_L2 + 0x1000
PAGE_TABLE_L4   EQU PAGE_TABLE_L3 + 0x1000

VIDEO_BUFFER  EQU  0xB8000

PROTECTED_STACK_START EQU  0xFFFF0000
; To Thom - addresses are high and the stack is far away

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

; stolen from https://wiki.osdev.org/SSE
; now enable SSE and the like
mov eax, cr0
and ax, 0xFFFB		;clear coprocessor emulation CR0.EM
or ax, 0x2			;set coprocessor monitoring  CR0.MP
mov cr0, eax
mov eax, cr4
or ax, 3 << 9		;set CR4.OSFXSR and CR4.OSXMMEXCPT at the same time
mov cr4, eax

setup_idt:
    lidt [idt_desc]
    sti



mov si, msg_main_startup
call println_si

update_stack_pointer:
    mov esp, PROTECTED_STACK_START
    mov ebp, esp

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
msg_main_startup            db 'Starting web-api-lnd kernel!', 0
msg_dummy_interrupt         db 'Dummy interrupt!', 0

newline                     db ' ', 0
success                     db 'Success!', 0


 ; 00:15 - ISR offset low bits
; 15:32 - segment selector
; 32:39 - reserved
; 40:43 - gate type
;   0b0101 or 0x5: Task Gate, note that in this case, the Offset value is unused and should be set to zero.
;   0b0110 or 0x6: 16-bit Interrupt Gate
;   0b0111 or 0x7: 16-bit Trap Gate
;   0b1110 or 0xE: 32-bit Interrupt Gate
;   0b1111 or 0xF: 32-bit Trap Gate
; 44    - zero
; 45:46 - dpl (?)
; 47    - P
; 48:63 - ISR offset high bits

; DPL: A 2-bit value which defines the CPU Privilege Levels which are allowed to access this interrupt via the INT instruction. Hardware interrupts ignore this mechanism.
; P: Present bit. Must be set (1) for the descriptor to be valid.
; wip interrupt
; ISR offset low bits
idt_start:
    times 32 dq 0

    ; interrupt wip
    dw interrupt_dummy ; isr offset low
    dw 0x08 ; segment selector
    db 0 ; reserved
    db 0xee ; 1 (present) | 11 (ring 3 - LUL) | 0 (zero)
    dw 0x0 ; isr high bits
idt_end:

interrupt_dummy:
    mov si, msg_dummy_interrupt
    call println_si
    iret

idt_desc:
    dw idt_end - idt_start - 1; size
    dd idt_start ; offset

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