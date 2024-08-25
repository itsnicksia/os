const keyboard = @import("../device/keyboard.zig");

const SHELL_ADDRESS = @import("../sys/config.zig").SHELL_ADDRESS;
const INPUT_BUFFER_SIZE = 256;

const tty = @import("../device/tty.zig");
const println = tty.println;
const fprintln = tty.fprintln;
const print_at_cursor = tty.print_at_cursor;

const shell: *Shell = @ptrFromInt(SHELL_ADDRESS);

const Shell = struct {
    input_buffer: [INPUT_BUFFER_SIZE]u8,
    input_position: u16,

    pub fn init() Shell {
        return Shell {
            .input_buffer = [_]u8{0} ** INPUT_BUFFER_SIZE,
            .input_position = 0,
        };
    }

    pub fn push(self: *Shell, char: u8) void {
        self.input_buffer[self.input_position] = char;
        self.input_position += 1;
    }

    pub fn read(self: *Shell) []const u8 {
        return self.input_buffer[0..self.input_position];
    }

    pub fn clear_buffer(self: *Shell) void {
        self.input_position = 0;
    }

    pub fn has_input(self: *Shell) bool {
        return self.input_position > 0;
    }
};


pub fn init() void {
    shell .* = Shell.init();
}

pub fn tick() void {
    // read from kb input queue. only enter for now.
    const maybe_ascii_code = keyboard.poll();

    // very hacky
    if (maybe_ascii_code != null) {
        const ascii_code = maybe_ascii_code orelse unreachable;

        // send command
        if (ascii_code == keyboard.SCANCODE_ENTER) {
            execute_command();
        } else {
            shell.push(ascii_code);
            print_at_cursor(ascii_code);
        }
    }
}

pub fn show_prompt() void {
    println(">");
}

fn execute_command() void {

    if (!shell.has_input()) {
        return;
    }

    const input = shell.read();
    fprintln("Unknown command: {s}", .{ input });
    show_prompt();
    shell.clear_buffer();

}