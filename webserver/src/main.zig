const std = @import("std");
const video = @import("io/video.zig");

export fn _start() callconv(.Naked) noreturn {
    asm volatile ("call main");
    asm volatile ("hlt" : : );
}

export fn main() void {
    video.clear_screen();
    for (0..4) |_| {
        video.println("sys: hello world!");
        video.println("sys: its");
        video.println("sys: a");
        video.println("sys: pleasure");
        video.println("sys: beef");
        video.println("sys: beef 2");
        video.println(">");
    }
}