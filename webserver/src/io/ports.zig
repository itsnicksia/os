pub fn outb(port: u16, data: u8) void {
    asm volatile ("outb %[data], %[port]"
        :
        :   [data] "{al}" (data),
            [port] "N{dx}" (port)
    );
}