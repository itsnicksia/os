const std = @import("std");



const VIDEO_COLUMNS = 80;
const VIDEO_ROWS = 25;
const VIDEO_BUFFER_SIZE = VIDEO_COLUMNS * VIDEO_ROWS * 2;

const VIDEO_BUFFER: *volatile [VIDEO_BUFFER_SIZE]u8 = @ptrFromInt(0xB8000);

export fn _start() callconv(.Naked) noreturn {
    asm volatile ("call main");
}

export fn main() void {
    clearScreen();
    asm volatile ("hlt" : : );
}

fn clearScreen() void {
    @memset(VIDEO_BUFFER[0..VIDEO_BUFFER_SIZE], 0);
    const string = "Hello World!";

    for (0..VIDEO_COLUMNS) |i| {
        const char = if (i < string.len) string[i] else ' ';
        const offset = i * 2;
        VIDEO_BUFFER[offset] = char;
        VIDEO_BUFFER[offset + 1] = 0x0f;
    }
    asm volatile ("hlt" : : );
}