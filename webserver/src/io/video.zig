const VIDEO_COLUMNS = 80;
const VIDEO_ROWS = 25;
const VIDEO_BUFFER_SIZE = VIDEO_COLUMNS * VIDEO_ROWS * 2;

const VIDEO_BUFFER: *volatile [VIDEO_BUFFER_SIZE]u8 = @ptrFromInt(0xB8000);

pub fn clear_screen() void {
    @memset(VIDEO_BUFFER[0..VIDEO_BUFFER_SIZE], 0);
}

// fixme: can only write to first row
pub fn println(string: []const u8) void {
    for (0..VIDEO_COLUMNS) |i| {
        const char = if (i < string.len) string[i] else ' ';
        const offset = i * 2;
        VIDEO_BUFFER[offset] = char;
        VIDEO_BUFFER[offset + 1] = 0x0f;
    }
}