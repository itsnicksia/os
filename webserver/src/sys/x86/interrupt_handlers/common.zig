pub inline fn ack_interrupt() void {
    asm volatile ("outb %%al, $0x20" : : [ack] "{al}" (0x20));
}

