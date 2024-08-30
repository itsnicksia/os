const std = @import("std");
const sys = @import("sys");
const shell = @import("io/shell.zig");

const terminal = @import("tty");
const println = terminal.println;
const fprintln = terminal.fprintln;

export fn _start() callconv(.Naked) noreturn {
    asm volatile ("call main");
}

export fn main() void {
    @setRuntimeSafety(false);
    sys.paging.init();
    sys.interrupts.init();
    sys.keyboard.init();

    terminal.init();
    shell.init();
    //acpi.init();

    sys.pci.scan_devices();

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