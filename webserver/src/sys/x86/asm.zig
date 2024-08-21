// https://gcc.gnu.org/onlinedocs/gcc/Simple-Constraints.html

pub inline fn iret () void {
    asm volatile("iret");
}

pub inline fn halt() void {
    asm volatile("hlt");
}

pub inline fn load_idt(address: u32) void {
    asm volatile ("lidt %[address]" : : [address] "m" (address));
}

pub inline fn enable_interrupt() void {
    asm volatile("sti");
}

pub fn outb(port: u16, data: u8) void {
    asm volatile ("outb %[data], %[port]"
        :
        :   [data] "{al}" (data),
            [port] "N{dx}" (port)
    );
}