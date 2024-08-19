const format = @import("std").fmt;
const println = @import("device/screen.zig").println;

pub fn print(comptime fmt: []const u8, args: anytype) void {
    var buf = [_]u8{0} ** 80;
    const string = format.bufPrint(&buf, fmt, args) catch |err| switch (err) {
        format.BufPrintError.NoSpaceLeft => "output too long"
    };
    println(string);
}