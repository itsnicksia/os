const format = @import("std").fmt;
const tty = @import("device/tty.zig");

const buf: *[0x1000]u8 = @ptrFromInt(0xe00000);

pub fn println(comptime fmt: []const u8, _: anytype) void {
    // _ = format.bufPrint(buf[0..0x1000], fmt, args) catch |err| switch (err) {
    //     format.BufPrintError.NoSpaceLeft => blk: {
    //         @memcpy(buf[0..3], "...");
    //         break :blk buf;
    //     }
    // };
    tty.println(fmt);
}