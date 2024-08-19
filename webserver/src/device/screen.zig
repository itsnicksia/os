const fmt = @import("std").fmt;
const mem = @import("std").mem;
const ports = @import ("../io/ports.zig");

const VIDEO_COLUMNS: u16 = 80;
const VIDEO_ROWS: u16 = 25;
const VIDEO_BUFFER_SIZE: u16 = VIDEO_COLUMNS * VIDEO_ROWS * VIDEO_CHAR_WIDTH;
const VIDEO_CHAR_WIDTH: u16 = 2;

const VIDEO_BUFFER: *volatile [VIDEO_BUFFER_SIZE]u8 = @ptrFromInt(0xB8000);
const VIDEO_CURSOR_REGISTER_PORT = 0x3D4;
const VIDEO_CURSOR_DATA_PORT = 0x3D5;

const LINE_NUMBER_WIDTH = 6;

var line_number: u16 = 0;
var current_row: u16 = 0;
var is_screen_full = false;

pub fn init() void {
    clear_screen();
    enable_cursor();
}

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
    for (0..VIDEO_COLUMNS - LINE_NUMBER_WIDTH) |column| {
        const char = if (column < string.len) string[column] else ' ';
        write_line_number(&write_buffer);
        const offset = (column + LINE_NUMBER_WIDTH) * VIDEO_CHAR_WIDTH ;
        write_buffer[offset] = char;
        write_buffer[offset + 1] = 0x0f;
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

    line_number += 1;

    update_cursor(string.len + LINE_NUMBER_WIDTH);
}

fn write_line_number(write_buffer: []u8) void {
    const line_number_string = get_line_number();
    for (0..LINE_NUMBER_WIDTH) |i| {
        const offset = i * 2;
        write_buffer[offset] = line_number_string[i];
        write_buffer[offset + 1] = 0x0f;
    }
}

fn get_line_number() []const u8 {
    var buf = [_]u8{0} ** LINE_NUMBER_WIDTH;
    const line_string = fmt.bufPrint(&buf, "{d: >4}  ", .{line_number}) catch |err| switch (err) {
        fmt.BufPrintError.NoSpaceLeft => "0"
    };
    return line_string;
}

fn enable_cursor() void {
    ports.outb(VIDEO_CURSOR_REGISTER_PORT, 0x0A);
    ports.outb(VIDEO_CURSOR_DATA_PORT, 0xC0 | 0);

    ports.outb(VIDEO_CURSOR_REGISTER_PORT, 0x0B);
    ports.outb(VIDEO_CURSOR_DATA_PORT, 0xE0 | 15);
}

fn update_cursor(col: usize) void {
    const cursor_offset = get_video_mode_3_offset(@intCast(current_row), @intCast(col));

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