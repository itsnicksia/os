const fmt = @import("std").fmt;
const mem = @import("std").mem;
const math = @import("std").math;
const io = @import("std").io;
const outb = @import ("../sys/x86/asm.zig").outb;
const TERMINAL_ADDRESS = @import("../sys/config.zig").TERMINAL_ADDRESS;

const NUM_COLUMNS: u16 = 80;
const NUM_ROWS: u16 = 25;
const NUM_PRINTABLE_ROWS = NUM_ROWS - 1;

const VIDEO_CURSOR_REGISTER_PORT = 0x3D4;
const VIDEO_CURSOR_DATA_PORT = 0x3D5;

const ROW_NUMBER_WIDTH = 0;
const STATUS_ROW = NUM_ROWS - 1;
const MSG_START = ROW_NUMBER_WIDTH;

const DEFAULT_COLOUR = 0x0f;
const ROW_NUM_COLOUR = 0x7f;
const STATUS_COLOUR = 0x9f;

const VIDEO_NUM_CHARS = NUM_COLUMNS * NUM_ROWS;
const VIDEO_BUFFER_SIZE = VIDEO_NUM_CHARS * @sizeOf(TerminalChar);

const TerminalChar = packed struct {
    ascii_code: u8,
    colour_code: u8,
};

const terminal: *Terminal = @ptrFromInt(TERMINAL_ADDRESS);
const video_buffer: * volatile [VIDEO_NUM_CHARS]TerminalChar = @ptrFromInt(0xB8000);

pub const Terminal = struct {
    rowPosition: u16,
    colPosition: u16,
    screenBuffer: [2000]TerminalChar,
    formatBuffer: [2000]u8,
    rowScrollPosition: u16,

    pub fn init() Terminal {
        return Terminal {
            .formatBuffer = [_]u8{0} ** 2000,
            .rowPosition = 0,
            .colPosition = 0,
            .screenBuffer = undefined,
            .rowScrollPosition = 0,
        };
    }

    pub inline fn writeRaw(string: []const u8, colour_code: u8) void {
        @setRuntimeSafety(false);
        const offset = STATUS_ROW * NUM_COLUMNS;
        for (0..NUM_COLUMNS) |index| {
            const char = if(index < string.len) string[index] else ' ';
            video_buffer[offset + index] = TerminalChar { .ascii_code = char, .colour_code = colour_code };
        }
        @setRuntimeSafety(true);
    }

    pub fn clear(self: *Terminal) void {
        @memset(self.screenBuffer[0..], TerminalChar { .ascii_code = 0, .colour_code = DEFAULT_COLOUR });
        @memset(video_buffer[0..], TerminalChar { .ascii_code = 0, .colour_code = DEFAULT_COLOUR });
        self.rowPosition = 0;
    }

    pub fn write(self: *Terminal, offset: u16, string: []const u8, colour_code: u8) void {
        const bufferOffset = offset % self.screenBuffer.len;

        for (0..NUM_COLUMNS) |index| {
            const char = if(index < string.len) string[index] else ' ';
            self.screenBuffer[bufferOffset + index] = TerminalChar { .ascii_code = char, .colour_code = colour_code };
        }

        const numRowsToPrint = @min(NUM_PRINTABLE_ROWS, self.rowPosition + 1);

        // calculate cursor position
        self.colPosition += @truncate(string.len);
        self.colPosition %= NUM_COLUMNS;
        const cursorOffset = getStartOfRowOffset(numRowsToPrint - 1);
        updateCursorPosition(cursorOffset + self.colPosition);

        // NUM_ROWS = 25;
        // position 0, index 0 = 0
        // position 23, index 23 = 23
        // position 24, index 23 = 24
        // position 25, index 23 = 0

        // position 23, index 0 = 0
        // position 24, index 0 = 0
        // position 25, index 0 = 1
        // position 26, index 0 = 2
        // position 47, index 0 = 23
        // position 48, index 0 = 24
        // position 49, index 0 = 0
        // position 50, index 0 = 1

        // 23 = 23
        // 24 = 0

        // 46 = 23
        // 47 = 24
        // 48 = 0

        // position 24, index 23 = 24
        // position 24, index 1 = 2
        // position 24, index 2 = 3
        // +1 from divide, +1 from modulo, +0 = 2
        // position 25, index 0 = 2
        // +1 from divide, +1 from modulo, +0 = 2

        // position - 24


        // copy screen buffer to video buffer
        for (0..numRowsToPrint) | index| {
            const videoBufferOffset = getStartOfRowOffset(index);
            // rowPosition = 24
            // index = 23
            // bufferRow = 24

            // rowPosition = 24
            // index = 0
            // bufferRow = 1
            const fooOffset = if (self.rowPosition >= NUM_PRINTABLE_ROWS) self.rowPosition - (NUM_PRINTABLE_ROWS - 1) else 0;
            const bufferRow = (fooOffset + index) % NUM_ROWS;
            const screenBufferOffset = getStartOfRowOffset(bufferRow);
            @memcpy(
                video_buffer[videoBufferOffset..videoBufferOffset + NUM_COLUMNS],
                self.screenBuffer[screenBufferOffset..screenBufferOffset + NUM_COLUMNS]
            );
        }
    }

    pub fn writeStatus(self: *Terminal, comptime format:  []const u8, args: anytype) void {
        const offset = STATUS_ROW * NUM_COLUMNS;

        const string = self.formatString(format, args);

        for (0..NUM_COLUMNS) |index| {
            const char = if(index < string.len) string[index] else ' ';
            video_buffer[offset + index] = TerminalChar { .ascii_code = char, .colour_code = STATUS_COLOUR };
        }
    }

    pub fn println(self: *Terminal, string: []const u8) void {
        const offset: u16 = self.rowPosition * NUM_COLUMNS + MSG_START;
        //self.writeRowNumber();
        self.write(offset, string, DEFAULT_COLOUR);

        const numLines: u16 = @truncate(string.len / NUM_COLUMNS);
        self.rowPosition += numLines + 1;
        self.colPosition = 0;
    }

    pub fn fprintln(self: *Terminal, comptime format:  []const u8, args: anytype) void {
        const string = self.formatString(format, args);
        terminal.println(string);
    }

    pub fn printAtCursor(self: *Terminal, char: u8) void {
        const string = &[_]u8{char};
        const row = @min(NUM_PRINTABLE_ROWS - 1, self.rowPosition);
        const cursorPosition = getStartOfRowOffset(row) + self.colPosition;
        terminal.write(cursorPosition, string, DEFAULT_COLOUR);
    }

    fn getStartOfRowOffset(row: usize) u16 {
        return @truncate(row * NUM_COLUMNS);
    }

    fn writeRowNumber(self: *Terminal) void {
        var row_buffer = [_]u8{0} ** 16;
        const offset = self.rowPosition * NUM_COLUMNS;
        const string = fmt.bufPrint(&row_buffer, "{d: >4}", .{self.rowPosition}) catch |err| switch (err) {
            fmt.BufPrintError.NoSpaceLeft => "<error: No Space Left>"
        };

        terminal.write(offset,string, ROW_NUM_COLOUR);
    }

    fn updateCursorPosition(position: u16) void {
        // Vertical Blanking Start Register
        outb(VIDEO_CURSOR_REGISTER_PORT, 0x0F);
        outb(VIDEO_CURSOR_DATA_PORT, @intCast(position & 0xFF));

        // Vertical Blanking End Register
        outb(VIDEO_CURSOR_REGISTER_PORT, 0x0E);
        outb(VIDEO_CURSOR_DATA_PORT, @intCast((position >> 8) & 0xFF));
    }

    fn formatString(self: *Terminal, comptime format:  []const u8, args: anytype) []const u8 {
        var fbs = io.fixedBufferStream(&self.formatBuffer);
        fmt.format(fbs.writer().any(), format, args) catch |err| switch (err) {
            error.NoSpaceLeft => return "<error:NoSpaceLeft>",
            else => unreachable,
        };

        return fbs.getWritten();
    }

    inline fn getNextLineOffset(self: *Terminal) u16 {
        return @truncate(self.rowPosition * NUM_COLUMNS + MSG_START);
    }
};

pub fn init() void {
    terminal .* = Terminal.init();
    enable_cursor();

    terminal.clear();
    terminal.writeStatus("status: {s}", .{"ready"});
    terminal.println("Terminal OK");
}

pub inline fn println(string: []const u8) void {
    terminal.println(string);
}

pub inline fn fprintln(comptime format:  []const u8, args: anytype) void {
    terminal.fprintln(format, args);
}

pub inline fn printAtCursor(char: u8) void {
    terminal.printAtCursor(char);
}

pub fn clear() void {
    terminal.clear();
}

fn enable_cursor() void {
    outb(VIDEO_CURSOR_REGISTER_PORT, 0x0A);
    outb(VIDEO_CURSOR_DATA_PORT, 0xC0 | 0);

    outb(VIDEO_CURSOR_REGISTER_PORT, 0x0B);
    outb(VIDEO_CURSOR_DATA_PORT, 0xE0 | 15);
}

