const fmt = @import ("std").fmt;
const mem = @import("std").mem;
const ports = @import ("ports.zig");

const VIDEO_COLUMNS: u16 = 80;
const VIDEO_ROWS: u16 = 25;
const VIDEO_BUFFER_SIZE: u16 = VIDEO_COLUMNS * VIDEO_ROWS * VIDEO_CHAR_WIDTH;
const VIDEO_CHAR_WIDTH: u16 = 2;

const VIDEO_BUFFER: *volatile [VIDEO_BUFFER_SIZE]u8 = @ptrFromInt(0xB8000);
const VIDEO_CURSOR_REGISTER_PORT = 0x3D4;
const VIDEO_CURSOR_DATA_PORT = 0x3D5;

var current_row: u16 = 0;
var is_screen_full = false;

pub fn clear_screen() void {
    @memset(VIDEO_BUFFER[0..VIDEO_BUFFER_SIZE], 0);
}

// todo: add screen buffer
pub fn println(string: []const u8) void {

    // scrolling
    if (is_screen_full) {
        for (0..current_row) |row| {
            const this_row_offset = get_video_mode_3_byte_offset(@intCast(row), 0);
            const this_row = VIDEO_BUFFER[this_row_offset .. this_row_offset + VIDEO_COLUMNS * VIDEO_CHAR_WIDTH];

            if (row < VIDEO_ROWS - 1) {
                const next_row_offset = get_video_mode_3_byte_offset(@intCast(row + 1), 0);
                const next_row = VIDEO_BUFFER[next_row_offset .. next_row_offset + VIDEO_COLUMNS * VIDEO_CHAR_WIDTH];
                @memcpy(this_row, next_row);
            }

            for (0..VIDEO_COLUMNS) |column| {
                this_row[(column * 2) + 1] = 0x0f;
            }
        }
    }

    // write string
    var write_buffer = [_]u8{0} ** (VIDEO_COLUMNS * VIDEO_CHAR_WIDTH);
    for (0..VIDEO_COLUMNS) |column| {
        const char = if (column < string.len) string[column] else ' ';
        const offset = column * VIDEO_CHAR_WIDTH;
        write_buffer[offset] = char;
        write_buffer[offset + 1] = 0x1f;
    }

    const row_to_write_offset = get_video_mode_3_byte_offset(@intCast(current_row), 0);
    const row_to_write = VIDEO_BUFFER[row_to_write_offset .. row_to_write_offset + VIDEO_COLUMNS * VIDEO_CHAR_WIDTH];

    @memcpy(row_to_write, &write_buffer);

    // next row
    if (current_row < VIDEO_ROWS - 1) {
        current_row += 1;
    } else {
        is_screen_full = true;
    }

    update_cursor(string.len);
}

pub fn update_cursor(col: usize) void {
    const cursor_offset = get_video_mode_3_offset(@intCast(current_row), @intCast(col));

    ports.outb(VIDEO_CURSOR_REGISTER_PORT, 0x0A);
    ports.outb(VIDEO_CURSOR_DATA_PORT, 0xC0 | 0);

    ports.outb(VIDEO_CURSOR_REGISTER_PORT, 0x0B);
    ports.outb(VIDEO_CURSOR_DATA_PORT, 0xE0 | 15);

    // Vertical Blanking Start Register
    ports.outb(VIDEO_CURSOR_REGISTER_PORT, 0x0F);
    ports.outb(VIDEO_CURSOR_DATA_PORT, @intCast(cursor_offset & 0xFF));

    // Vertical Blanking End Register
    ports.outb(VIDEO_CURSOR_REGISTER_PORT, 0x0E);
    ports.outb(VIDEO_CURSOR_DATA_PORT, @intCast((cursor_offset >> 8) & 0xFF));
}

fn printdbg(string: []const u8) void {
    for (0..VIDEO_COLUMNS) |column| {
        const char = if (column < 6) string[column] else ' ';
        const offset = get_video_mode_3_byte_offset(VIDEO_ROWS - 1, @intCast(column));
        VIDEO_BUFFER[offset] = char;
        VIDEO_BUFFER[offset + 1] = 0x1f;
    }
}

fn get_video_mode_3_offset(row: u16, col: u16) u16 {
    return (row * VIDEO_COLUMNS) + col;
}

fn get_video_mode_3_byte_offset(row: u16, col: u16) u16 {
    return get_video_mode_3_offset(row, col) * VIDEO_CHAR_WIDTH;
}

fn hack_print_int(value: u16) []const u8 {
    var buffer: [80]u8 = [_]u8{0} ** 80;

    var position: u8 = 5;

    if (value == 0) {
        buffer[0] = '0';
        position -= 1;
    } else {
        var temp: u16 = value;
        while (temp != 0) {
            const foo: u8 = @intCast(temp % 10);
            const digit: u8 = foo + '0';
            buffer[position] = digit;
            temp /= 10;
            position -= 1;
        }
    }

    return &buffer;
}