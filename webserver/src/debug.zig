const std = @import("std");
const format = @import("std").fmt;
const tty = @import("device/tty.zig");
const bump_allocator = @import("mem/bump_allocator.zig");


pub fn println(comptime _: []const u8, _: anytype) void {
    const allocator = bump_allocator.getHeapAllocator();
    _ = format.allocPrintZ(allocator, "PizzaTime", .{}) catch |err| switch (err) {
        format.AllocPrintError.OutOfMemory => "<oom>"
    };

    //tty.println(string);
}