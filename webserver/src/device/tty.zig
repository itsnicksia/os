const fmt = @import("std").fmt;
const mem = @import("std").mem;
const outb = @import ("../sys/x86/asm.zig").outb;

const VIDEO_COLUMNS: u16 = 80;
const VIDEO_ROWS: u16 = 25;
const VIDEO_BUFFER_SIZE: u32 = VIDEO_COLUMNS * VIDEO_ROWS * VIDEO_CHAR_WIDTH;
const VIDEO_CHAR_WIDTH: u16 = 2;

const VIDEO_BUFFER: *volatile [VIDEO_BUFFER_SIZE]u8 = @ptrFromInt(0xB8000);
const VIDEO_CURSOR_REGISTER_PORT = 0x3D4;
const VIDEO_CURSOR_DATA_PORT = 0x3D5;

const LINE_NUMBER_WIDTH = 6;

var line_number: u32 = 0;
var current_row: u32 = 0;
var is_screen_full = false;

pub fn init() void {
    clear_screen();
    println("initializing tty...");

    // "hacky '>' prompt"
    VIDEO_BUFFER[(80 * 23 + 2) * 2] = 0x3e;
    VIDEO_BUFFER[(80 * 23 + 2) * 2 + 1] = 0x0f;

    //enable_cursor();
    println("done!");
}

pub fn clear_screen() void {
    @memset(VIDEO_BUFFER[0..VIDEO_BUFFER_SIZE], 0);
}

pub fn set_status(string: []const u8) void {
    const row_offset = get_video_mode_3_byte_offset(@intCast(VIDEO_ROWS - 1), 0);
    const write_buffer = VIDEO_BUFFER[row_offset .. row_offset + VIDEO_COLUMNS * VIDEO_CHAR_WIDTH];

    // write string
    for (0..VIDEO_COLUMNS) |column| {
        const char = if (column < string.len) string[column] else ' ';
        const offset = (column) * VIDEO_CHAR_WIDTH ;
        write_buffer[offset] = char;
        write_buffer[offset + 1] = 0x1f;
    }
}

// todo: add screen buffer
pub fn println(string: []const u8) void {
    //scrolling
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

    const row_offset = get_video_mode_3_byte_offset(@intCast(current_row), 0);
    const write_buffer = VIDEO_BUFFER[row_offset .. row_offset + VIDEO_COLUMNS * VIDEO_CHAR_WIDTH];

    // write string
    for (0..VIDEO_COLUMNS - LINE_NUMBER_WIDTH) |column| {
        const char = if (column < string.len) string[column] else ' ';
        write_line_number(write_buffer);
        const offset = (column + LINE_NUMBER_WIDTH) * VIDEO_CHAR_WIDTH ;
        write_buffer[offset] = char;
        write_buffer[offset + 1] = 0x0f;
    }

    //next row
    if (current_row < VIDEO_ROWS - 2) {
        current_row += 1;
    } else {
        is_screen_full = true;
    }

    line_number += 1;
    if (line_number > 9999) {
        line_number = 0;
    }

    update_cursor(string.len + LINE_NUMBER_WIDTH);
}

fn write_line_number(write_buffer: []volatile u8) void {
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
    outb(VIDEO_CURSOR_REGISTER_PORT, 0x0A);
    outb(VIDEO_CURSOR_DATA_PORT, 0xC0 | 0);

    outb(VIDEO_CURSOR_REGISTER_PORT, 0x0B);
    outb(VIDEO_CURSOR_DATA_PORT, 0xE0 | 15);
}

fn update_cursor(col: usize) void {
    const cursor_offset = get_video_mode_3_offset(@intCast(current_row), @intCast(col));

    // Vertical Blanking Start Register
    outb(VIDEO_CURSOR_REGISTER_PORT, 0x0F);
    outb(VIDEO_CURSOR_DATA_PORT, @intCast(cursor_offset & 0xFF));

    // Vertical Blanking End Register
    outb(VIDEO_CURSOR_REGISTER_PORT, 0x0E);
    outb(VIDEO_CURSOR_DATA_PORT, @intCast((cursor_offset >> 8) & 0xFF));
}

fn get_video_mode_3_offset(row: u16, col: u16) u16 {
    return (row * VIDEO_COLUMNS) + col;
}

fn get_video_mode_3_byte_offset(row: u16, col: u16) u16 {
    return get_video_mode_3_offset(row, col) * VIDEO_CHAR_WIDTH;
}