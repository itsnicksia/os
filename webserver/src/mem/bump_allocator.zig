const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const buffer: * [1024]u8 = @ptrFromInt(0x1000000);

const bump_allocator: * BumpAllocator = @ptrFromInt(0xffe000);
const allocator: * std.mem.Allocator = @ptrFromInt(0xfff000);

pub fn init() void {
    bump_allocator.* = init_allocator(buffer);
    allocator.* = get_allocator(bump_allocator);
}

pub fn getHeapAllocator() std.mem.Allocator {
    return allocator.*;
}

const BumpAllocator = struct {
    buffer: []u8,
    position: usize
};

fn init_allocator(buf: []u8) BumpAllocator {
    return BumpAllocator{
        .buffer = buf,
        .position = 0,
    };
}

fn get_allocator(self: *BumpAllocator) std.mem.Allocator {
    return .{
        .ptr = self,
        .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .free = free,
        },
    };
}

fn alloc(ctx: *anyopaque, len: usize, _: u8, _: usize) ?[*]u8 {
    const self: *BumpAllocator = @ptrCast(@alignCast(ctx));
    self.position += len;
    return self.buffer.ptr + self.position;
}

fn resize(_: *anyopaque, _: []u8, _: u8, _: usize, _: usize) bool {
    return false;
}

fn free(_: *anyopaque, _: []u8, _: u8, _: usize) void { }