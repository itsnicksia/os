const acpi = @import("sys/x86/acpi.zig");
const interrupts = @import("sys/x86/interrupt.zig");
const std = @import("std");
const tty = @import("device/tty.zig");
const debug = @import("debug.zig");

const format = std.fmt;

const println = tty.println;

export fn _start() callconv(.Naked) noreturn {
    asm volatile ("call main");
    asm volatile ("hlt");
}

export fn main() void {
    tty.init();
    tty.set_status("status: [anus is clenched] [hp = 100] [fistula is missing] [cloaca is open]");
    interrupts.init();
    //acpi.init();

    //print_welcome();
}

fn print_welcome() void {
    //println(">");
}