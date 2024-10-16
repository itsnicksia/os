const sys = @import("sys");
const keyboard = sys.keyboard;

const net = @import("net.zig");

const cfg = @import("cfg");
const SHELL_ADDRESS = cfg.mem.SHELL_ADDRESS;
const INPUT_BUFFER_SIZE = 256;

const terminal = @import("tty");

const println = terminal.println;
const print = terminal.print;
const fprintln = terminal.fprintln;
const printAtCursor = terminal.printAtCursor;

const eql = @import("std").mem.eql;

const pci = @import("sys").pci;

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

    pub fn backspace(self: *Shell) void {
        if (!shell.has_input()) {
            return;
        }

        self.input_position -= 1;
        self.input_buffer[self.input_position] = 0;

        terminal.delete();
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

        switch (ascii_code) {
            keyboard.SCANCODE_ENTER     => execute_command(),
            keyboard.SCANCODE_BACKSPACE => shell.backspace(),
            else => {
                shell.push(ascii_code);
                printAtCursor(ascii_code);
            }
        }
    }
}

pub fn show_prompt() void {
    print(">");
}

fn execute_command() void {
    if (!shell.has_input()) {
        return;
    }

    const input = shell.read();

    if (eql(u8,input, "clear")) {
        terminal.clear();
    } else if (eql(u8, input, "pci")) {
        pci.scan_devices();
    } else if (eql(u8, input, "help")) {
        println("clear (clear screen), pci (scan pci devices)");
    } else if (eql(u8, input, "sendpkt")) {
        net.sendARP();
    }
    else {
        println(input);
        fprintln("Unknown command: {s}", .{ input });
    }

    show_prompt();
    shell.clear_buffer();
}