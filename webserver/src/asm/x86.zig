// https://gcc.gnu.org/onlinedocs/gcc/Simple-Constraints.html

pub inline fn iret () void {
    asm volatile("iret");
}

pub inline fn halt() void {
    asm volatile("hlt");
}

pub inline fn outb(port: u16, data: u8) void {
    asm volatile ("outb %[data], %[port]"
        :
        :   [data] "{al}" (data),
            [port] "N{dx}" (port)
    );
}

pub inline fn outl(port: u16, data: u32) void {
    asm volatile ("outl %[data], %[port]"
        :
        :   [data] "{eax}" (data),
            [port] "N{dx}" (port)
    );
}

pub inline fn inl(port: u16) u32 {
    return asm volatile ("inl %[port], %[data]"
        : [data] "={eax}" (-> u32)
        : [port] "N{dx}" (port)
    );
}