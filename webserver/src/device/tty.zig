const fmt = @import("std").fmt;
const mem = @import("std").mem;
const math = @import("std").math;
const io = @import("std").io;
const outb = @import ("../sys/x86/asm.zig").outb;
const TERMINAL_ADDRESS = @import("../sys/config.zig").TERMINAL_ADDRESS;

const NUM_COLUMNS: u16 = 80;
const NUM_ROWS: u16 = 25;

const VIDEO_CURSOR_REGISTER_PORT = 0x3D4;
const VIDEO_CURSOR_DATA_PORT = 0x3D5;

const ROW_NUMBER_WIDTH = 6;
const STATUS_ROW = NUM_ROWS - 1;
const MSG_START = ROW_NUMBER_WIDTH;

const DEFAULT_COLOUR = 0x0f;
const STATUS_COLOUR = 0x9f;

const TerminalChar = packed struct {
    ascii_code: u8,
    colour_code: u8,
};

const terminal: *Terminal = @ptrFromInt(TERMINAL_ADDRESS);

pub const Terminal = struct {
    format_buffer: [80]u8,
    buffer: * volatile [NUM_COLUMNS * NUM_ROWS]TerminalChar,
    row_number: u16,
    cursor_position: u16,

    pub fn init() Terminal {
        return Terminal {
            .buffer = @ptrFromInt(0xB8000),
            .format_buffer = [_]u8{0} ** 80,
            .row_number = 0,
            .cursor_position = 0,
        };
    }

    pub inline fn write_raw(string: []const u8, colour_code: u8) void {
        @setRuntimeSafety(false);
        const buffer: * volatile [NUM_COLUMNS * NUM_ROWS]TerminalChar = @ptrFromInt(0xB8000);
        const slice = buffer[0..];
        const offset = STATUS_ROW * NUM_COLUMNS;
        for (0..string.len) |index| {
            slice[offset] = TerminalChar { .ascii_code = string[index], .colour_code = colour_code };
        }
        @setRuntimeSafety(true);
    }

    pub fn clear(self: *Terminal) void {
        @memset(self.buffer[0..], TerminalChar { .ascii_code = 0, .colour_code = DEFAULT_COLOUR });
    }

    pub fn write(self: *Terminal, offset: u16, string: []const u8, colour_code: u8) void {
        const width: u16 =  @truncate(string.len);
        self.update_cursor(offset + width);

        for (0..string.len) |index| {
            self.buffer[offset + index] = TerminalChar { .ascii_code = string[index], .colour_code = colour_code };
        }
    }

    pub fn write_at_cursor(self: *Terminal, string: []const u8, colour_code: u8) void {
        self.write(self.cursor_position, string, colour_code);
    }

    pub fn write_at_row(self: *Terminal, row: u16, string: []const u8) void {
        const offset: u16 = row * NUM_COLUMNS + MSG_START;
        terminal.write_row_number();
        self.write(offset, string, DEFAULT_COLOUR);
        self.row_number += 1;
    }

    pub fn write_line(self: *Terminal, string: []const u8) void {
        terminal.write_at_row(self.row_number, string);
    }

    pub fn fprintln(self: *Terminal, comptime format:  []const u8, args: anytype) void {
        const string = fmt.bufPrint(&self.format_buffer, format, args) catch |err| switch (err) {
            fmt.BufPrintError.NoSpaceLeft => "<error: No Space Left>"
        };
        terminal.write(terminal.next_line_offset(),string, DEFAULT_COLOUR);
        self.row_number += 1;
    }

    fn write_row_number(self: *Terminal) void {
        const offset = self.row_number * NUM_COLUMNS;
        const string = fmt.bufPrint(&self.format_buffer, "{d: >4}  ", .{self.row_number}) catch |err| switch (err) {
            fmt.BufPrintError.NoSpaceLeft => "<error: No Space Left>"
        };

        terminal.write(offset,string, DEFAULT_COLOUR);
    }

    fn update_cursor(self: *Terminal, position: u16) void {
        self.cursor_position = position;

        // Vertical Blanking Start Register
        outb(VIDEO_CURSOR_REGISTER_PORT, 0x0F);
        outb(VIDEO_CURSOR_DATA_PORT, @intCast(position & 0xFF));

        // Vertical Blanking End Register
        outb(VIDEO_CURSOR_REGISTER_PORT, 0x0E);
        outb(VIDEO_CURSOR_DATA_PORT, @intCast((position >> 8) & 0xFF));
    }

    inline fn next_line_offset(self: *Terminal) u16 {
        return @truncate(self.row_number * NUM_COLUMNS + MSG_START);
    }
};

pub fn init() void {
    terminal .* = Terminal.init();
    terminal.clear();
    //enable_cursor();
    println("TTY Ready!");

}

pub fn set_status(string: []const u8) void {
    terminal.write(STATUS_ROW * NUM_COLUMNS,string, STATUS_COLOUR);
}

pub fn println(string: []const u8) void {
    terminal.write_line(string);
}

pub fn fprintln(comptime format:  []const u8, args: anytype) void {
    terminal.fprintln(format, args);
}

pub fn print_at_cursor(char: u8) void {
    const string = &[_]u8{char};
    terminal.write(terminal.cursor_position, string, DEFAULT_COLOUR);
}

fn enable_cursor() void {
    outb(VIDEO_CURSOR_REGISTER_PORT, 0x0A);
    outb(VIDEO_CURSOR_DATA_PORT, 0xC0 | 0);

    outb(VIDEO_CURSOR_REGISTER_PORT, 0x0B);
    outb(VIDEO_CURSOR_DATA_PORT, 0xE0 | 15);
}

