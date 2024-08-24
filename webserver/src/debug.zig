const std = @import("std");
const format = @import("std").fmt;
const tty = @import("device/tty.zig");
const bump_allocator = @import("mem/bump_allocator.zig");


pub fn println(comptime fmt: []const u8, args: anytype) void {
    var buf: [512] u8 = undefined;

    const string = format.bufPrint(&buf, fmt, args) catch |err| switch (err) {
        format.BufPrintError.NoSpaceLeft => "<oom>"
    };

    tty.println(string);
}