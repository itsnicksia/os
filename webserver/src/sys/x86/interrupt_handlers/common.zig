pub inline fn ack_interrupt() void {
    asm volatile ("outb %%al, $0x20" : : [ack] "{al}" (0x20));
}

pub fn noop() callconv(.Naked) noreturn {
    asm volatile ("push %eax");
    asm volatile ("movb $0x20, %al");
    asm volatile ("outb %al, $0x20");
    asm volatile ("pop %eax");

    asm volatile("iret");
}