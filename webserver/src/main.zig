const std = @import("std");
const video = @import("io/video.zig");

export fn _start() callconv(.Naked) noreturn {
    asm volatile ("call main");
    asm volatile ("hlt" : : );
}

export fn main() void {
    video.clear_screen();
        video.println("1: hello world!");
        video.println("2: its");
        video.println("3: a");
        video.println("4: pleasure");
        video.println("5: beef");
        video.println("6: beef 2");
        video.println("7: >");
        video.println("8: hello world!");
        video.println("9: its");
        video.println("10: a");
        video.println("11: pleasure");
        video.println("12: beef");
        video.println("13: beef 2");
        video.println("14: >");
        video.println("15: hello world!");
        video.println("16: its");
        video.println("17: a");
        video.println("18: pleasure");
        video.println("19: beef");
        video.println("20: beef 2");
        video.println("21: >");
        video.println("22: a");
        video.println("23: b");
        video.println("24: c");
        video.println("25: >");
        video.println("26: >");
        video.println("27: >");
        video.println("28: >");
        video.println("29: >");
}