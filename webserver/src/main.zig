const std = @import("std");
const format = std.fmt;
const acpi = @import("sys/x86/acpi.zig");
const interrupts = @import("sys/x86/interrupt.zig");
const paging = @import("sys/x86/paging.zig");
const keyboard = @import("device/keyboard.zig");
const tty = @import("device/tty.zig");
const shell = @import("io/shell.zig");
const pci = @import("sys/x86//pci.zig");

const println = tty.println;
const fprintln = tty.fprintln;
const print_at_cursor = tty.print_at_cursor;

export fn _start() callconv(.Naked) noreturn {
    asm volatile ("call main");
}

export fn main() void {
    @setRuntimeSafety(false);
    paging.init();
    interrupts.init();
    keyboard.init();

    tty.init();
    tty.set_status(" status: [anus is clenched] [hp = 100] [fistula is missing] [cloaca is open]    ");

    pci.scan_devices();

    shell.init();


    //acpi.init();

    print_welcome();

    // event loop
    while (true) {
        asm volatile ("hlt");
        tick();
    }
}

fn tick() void {
    shell.tick();
}

fn print_welcome() void {
    println("Ready!");
    shell.show_prompt();
}