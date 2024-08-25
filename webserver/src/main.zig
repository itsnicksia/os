const acpi = @import("sys/x86/acpi.zig");
const interrupts = @import("sys/x86/interrupt.zig");
const paging = @import("sys/x86/paging.zig");
const std = @import("std");
const tty = @import("device/tty.zig");
const shell = @import("io/shell.zig");
const keyboard = @import("device/keyboard.zig");
const bump_allocator = @import("mem/bump_allocator.zig");
const format = std.fmt;

const HEAP_BASE_ADDRESS = @import("sys/config.zig").HEAP_BASE_ADDRESS;

const println = tty.println;
const fprintln = tty.fprintln;
const print_at_cursor = tty.print_at_cursor;

const BUFFER_SIZE = 16777215; // 16mb
const buffer: []u8 = @ptrFromInt(HEAP_BASE_ADDRESS); // Define the size of your fixed buffer

var fixed_allocator = std.heap.FixedBufferAllocator.init(&buffer);

const allocator: *std.mem.Allocator = &fixed_allocator.allocator;

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

    shell.init();

    //acpi.init();

    //fprintln("Formatted print is working!", .{});

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