const acpi = @import("sys/x86/acpi.zig");
const interrupts = @import("sys/x86/interrupt.zig");
const paging = @import("sys/x86/paging.zig");
const std = @import("std");
const tty = @import("device/tty.zig");
const keyboard = @import("device/keyboard.zig");
const debug = @import("debug.zig");
const bump_allocator = @import("mem/bump_allocator.zig");
const format = std.fmt;

const println = tty.println;

export fn _start() callconv(.Naked) noreturn {
    asm volatile ("call main");
}

export fn main() void {
    paging.init();
    interrupts.init();
    bump_allocator.init();
    keyboard.init();
    tty.init();
    tty.set_status("status: [anus is clenched] [hp = 100] [fistula is missing] [cloaca is open]");

    //acpi.init();

    print_welcome();
    debug.println("is formatted print working yet? {d}", .{5});

    // event loop
    while (true) {
        asm volatile ("hlt");
        //tick();
    }
}

// temp hack
const cmd_buf: * [16]u8 = @ptrFromInt(0x2900000);
const VIDEO_BUFFER: * [80 * 25 * 2]u8 = @ptrFromInt(0xB8000);
fn tick() void {
    // read from kb input queue. only enter for now.
    const maybe_kb_input = keyboard.poll();

    // very hacky
    if (maybe_kb_input != null) {
        const kb_input = maybe_kb_input orelse unreachable;
        if (kb_input == keyboard.SCANCODE_ENTER) {
            const hack_video_offset = (80 * 23 + 3) * 2;
            const buf = VIDEO_BUFFER[hack_video_offset..hack_video_offset + 32];

            var i: u16 = 0;
            while (i < buf.len / 2) {
                cmd_buf[i] = 'a';
                i += 1;
            }
            execute_command();
        }
    }
}

fn execute_command() void {
    println("got command:");
    println(cmd_buf);
}

fn print_welcome() void {
    println(">");
}