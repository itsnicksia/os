const acpi = @import("sys/x86/acpi.zig");
const interrupts = @import("sys/x86/interrupt.zig");
const std = @import("std");
const tty = @import("device/tty.zig");
const debug = @import("debug.zig");
const bump_allocator = @import("mem/bump_allocator.zig");
const format = std.fmt;

const println = tty.println;

export fn _start() callconv(.Naked) noreturn {
    asm volatile ("call main");
    while (true) {
        asm volatile ("hlt");
    }
}

export fn main() void {
    interrupts.init();
    bump_allocator.init();
    tty.init();
    tty.set_status("status: [anus is clenched] [hp = 100] [fistula is missing] [cloaca is open]");

    //acpi.init();

    print_welcome();
}

fn print_welcome() void {
    println(">");
}