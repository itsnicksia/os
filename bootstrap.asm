[BITS 32]
BOOTSTRAP       EQU 0x8000


VIDEO_BUFFER  EQU  0xB8000

PROTECTED_STACK_START EQU  0x400000

VIDEO_MODE_TEXT_80_25 EQU 3
TEXT_WIDTH  EQU 80
TEXT_HEIGHT EQU 25

org 0x8000

protected_mode_start:
    ; reinitialize segment registers
    mov ax, 0x10    ; gdt 2 = data
    mov bx, ax    ; gdt 3 = video
    mov ds, ax      ; data segment
    mov es, bx      ; extra segment
    mov fs, ax      ; fs (extra 2)
    mov gs, ax      ; gs (extra 3)
    mov ss, ax      ; stack segment


; copied from https://wiki.osdev.org/SSE
enable_sse:
    mov eax, cr0
    and ax, 0xFFFB		;clear coprocessor emulation CR0.EM
    or ax, 0x2			;set coprocessor monitoring  CR0.MP
    mov cr0, eax
    mov eax, cr4
    or ax, 3 << 9		;set CR4.OSFXSR and CR4.OSXMMEXCPT at the same time
    mov cr4, eax

update_stack_pointer:
    mov esp, PROTECTED_STACK_START
    mov ebp, esp

in al, 0x21           ; Read the current mask from the PIC master port (0x21)
or al, 0x01           ; Set the mask bit for IRQ 0 (the timer interrupt)
out 0x21, al          ; Write the new mask back to the PIC

jmp 0x11000