
// ACK the interrupt and return.
pub fn noop() callconv(.Naked) noreturn {
    asm volatile ("push %eax");
    asm volatile ("movb $0x20, %al");
    asm volatile ("outb %al, $0x20");
    asm volatile ("pop %eax");

    asm volatile("iret");
}

// Keyboard debugging ISR.
pub fn keyboard_input_debug() callconv(.Naked) noreturn {
    asm volatile ("push %eax");
    asm volatile ("push %ebx");

    // read from port to AL
    asm volatile ("inb $0x60, %al");

    // load counter
    asm volatile ("mov (0x700000), %ebx");

    // inc counter
    asm volatile ("addl $2, %ebx");
    asm volatile ("mov %ebx, 0x700000");

    // offset address
    asm volatile ("addl $0xB8000, %ebx");

    // move to 0x700000
    asm volatile ("movb %al, (%ebx)");

    // ACK interrupt
    asm volatile ("movb $0x20, %al");
    asm volatile ("outb %al, $0x20");

    asm volatile ("pop %ebx");
    asm volatile ("pop %eax");
    asm volatile("iret");
}