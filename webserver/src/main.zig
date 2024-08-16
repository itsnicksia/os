const std = @import("std");

const VIDEO_BUFFER: *volatile [80 * 25 * 2]u8 = @ptrFromInt(0xB8000);

export fn _start() callconv(.Naked) noreturn {
    asm volatile ("call main");
}

export fn main() void {
    clearScreen();
    asm volatile ("hlt" : : );
}

var i: u8 = 0;
fn clearScreen() void {
    const string = "Hello World!";

    const offset = i * 2;
    VIDEO_BUFFER[offset] = string[i];
    VIDEO_BUFFER[offset + 1] = 0x0f;
}