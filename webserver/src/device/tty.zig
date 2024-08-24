const fmt = @import("std").fmt;
const mem = @import("std").mem;
const math = @import("std").math;
const io = @import("std").io;
const outb = @import ("../sys/x86/asm.zig").outb;

const NUM_COLUMNS: u16 = 80;
const NUM_ROWS: u16 = 25;

const VIDEO_CURSOR_REGISTER_PORT = 0x3D4;
const VIDEO_CURSOR_DATA_PORT = 0x3D5;

const ROW_NUMBER_WIDTH = 0;
const STATUS_ROW = NUM_ROWS - 1;
const MSG_START = ROW_NUMBER_WIDTH;

var row_number: u32 = 0;
var current_row: u32 = 0;
var is_screen_full = false;

const TerminalChar = packed struct {
    ascii_code: u8,
    colour_code: u8,
};

var buf: [80]u8 = undefined;
var fbs = io.fixedBufferStream(buf);

const Terminal = struct {
    buffer: * volatile [NUM_COLUMNS * NUM_ROWS]TerminalChar,
    row_number: u16,

    pub fn clear(self: *Terminal) void {
        @memset(self.buffer[0..], TerminalChar { .ascii_code = 0, .colour_code = 0x0f });
    }

    pub fn write_at_row_col(self: *Terminal, row: u16, col: u16, string: []const u8) void {
        const offset = row * NUM_COLUMNS + col;

        for (0..string.len) |index| {
            self.buffer[offset + index] = TerminalChar { .ascii_code = string[index], .colour_code = 0x0f };
        }
    }

    pub fn write_at_row(self: *Terminal, row: u16, string: []const u8) void {
        self.write_at_row_col(row, MSG_START, string);
    }

    pub fn write_line(self: *Terminal, string: []const u8) void {
        const row = self.row_number;

        //terminal.write_row_number();
        terminal.write_at_row(row, string);

        self.row_number += 1;
    }

    pub fn fprintln(self: *Terminal, comptime format:  []const u8, args: anytype) void {
        const string = fmt.bufPrint(&buf, format, args) catch |err| switch (err) {
            fmt.BufPrintError.NoSpaceLeft => "0"
        };

        terminal.write_at_row_col(self.row_number, ROW_NUMBER_WIDTH,string);
    }

    fn write_row_number(self: *Terminal) void {
        const string = fmt.format(&buf, "{d: >4}  ", .{self.row_number}) catch |err| switch (err) {
            fmt.BufPrintError.NoSpaceLeft => "0"
        };

        terminal.write_at_row_col(self.row_number, 0,string);
    }
};

var terminal = Terminal {
    .buffer = @ptrFromInt(0xB8000),
    .row_number = 0,
};

pub fn init() void {
    terminal.clear();
    //enable_cursor();
    println("TTY Online!");
    println("TTY Online!");
}

pub fn set_status(string: []const u8) void {
    terminal.write_at_row_col(STATUS_ROW, 0,string);
}

pub fn println(string: []const u8) void {
    terminal.write_line(string);
}

pub fn fprintln(comptime format:  []const u8, args: anytype) void {
    terminal.fprintln(format, args);
}

//
// fn enable_cursor() void {
//     outb(VIDEO_CURSOR_REGISTER_PORT, 0x0A);
//     outb(VIDEO_CURSOR_DATA_PORT, 0xC0 | 0);
//
//     outb(VIDEO_CURSOR_REGISTER_PORT, 0x0B);
//     outb(VIDEO_CURSOR_DATA_PORT, 0xE0 | 15);
// }
//
// fn update_cursor(col: usize) void {
//     const cursor_offset = get_video_mode_3_offset(@intCast(current_row), @intCast(col));
//
//     // Vertical Blanking Start Register
//     outb(VIDEO_CURSOR_REGISTER_PORT, 0x0F);
//     outb(VIDEO_CURSOR_DATA_PORT, @intCast(cursor_offset & 0xFF));
//
//     // Vertical Blanking End Register
//     outb(VIDEO_CURSOR_REGISTER_PORT, 0x0E);
//     outb(VIDEO_CURSOR_DATA_PORT, @intCast((cursor_offset >> 8) & 0xFF));
// }