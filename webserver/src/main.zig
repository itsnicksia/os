const std = @import("std");
const video = @import("device/screen.zig");
const println = video.println;
const acpi = @import("sys/acpi.zig");
const fmt = @import("fmt_dbg.zig");

export fn _start() callconv(.Naked) noreturn {
    asm volatile ("call main");
    asm volatile ("hlt" : : );
}

export fn main() void {
    acpi.setup();
    video.clear_screen();
    print_welcome();
    var buf = [_]u8{0} ** 80;
    const foo = fmt.bufPrint(&buf, "{*}", .{&buf}) catch |err| switch (err) {
        fmt.BufPrintError.NoSpaceLeft => "error"
    };
    println(foo);
}

fn print_welcome() void {
    for (0..26) |_| {
        println("spoopy");
    }
}