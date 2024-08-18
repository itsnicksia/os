const std = @import("std");
const video = @import("io/video.zig");

export fn _start() callconv(.Naked) noreturn {
    asm volatile ("call main");
    asm volatile ("hlt" : : );
}

export fn main() void {
    video.clear_screen();
    video.println("hello world!");
}