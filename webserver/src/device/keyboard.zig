const KEYBOARD_INPUT_ADDRESS = @import("../sys/config.zig").KEYBOARD_INPUT_ADDRESS;

const keyboard_state: * KeyboardState = @ptrFromInt(KEYBOARD_INPUT_ADDRESS);

pub const SCANCODE_ENTER = 0x1c;

const KeyboardState = struct {
    counter: u32,
    ring_buffer: [1024]u8,
    head: usize,
    tail: usize,

    pub fn init() KeyboardState {
        return KeyboardState {
            .counter = 0,
            .ring_buffer = [_]u8{0} ** 1024,
            .head  = 0,
            .tail = 0,
        };
    }
};

pub fn init() void {
    keyboard_state.* = KeyboardState.init();
}

pub fn poll() ?u8 {
    // broken ring buffer impl but im sleepy. is that a good enough excuse?
    // if not - don't kinkshame me!

    if (keyboard_state.head > keyboard_state.tail) {
        const char = keyboard_state.ring_buffer[keyboard_state.tail];
        keyboard_state.tail += 1;
        keyboard_state.tail %= keyboard_state.ring_buffer.len;
        return char;
    }

    return null;
}

const ack_interrupt = @import("../sys/x86/interrupt_handlers/common.zig").ack_interrupt;

// i chatgpt'd this, because ain't no way im writing out a scancode map by hand.
//
// in fact, i don't even know which scancode map this is. but it partially works.
const SCANCODE_TO_ASCII: [128]u8 = [_]u8 {
    // 0x00 - 0x0F
    0, 0, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 0x08, 0x09, // Backspace, Tab
    // 0x10 - 0x1F
    'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', 0x0D, 0, 'a', 's', // Enter, reserved
    // 0x20 - 0x2F
    'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'', '`', 0, '\\', 'z', 'x', 'c', 'v',
    // 0x30 - 0x3F
    'b', 'n', 'm', ',', '.', '/', 0, 0, 0, 0, 0, 0, 0, ' ', 0, 0, // Space
    // 0x40 - 0x4F
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    // 0x50 - 0x5F
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    // 0x60 - 0x6F
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    // 0x70 - 0x7F
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
};


pub fn handle_kb_input() callconv(.Naked) noreturn {
    @setRuntimeSafety(false);

    asm volatile ("pushal");
    asm volatile ("mov %esp, %ebp");

    var scancode: u8 = 0;
    var counter: u32 = 0;

    //read from port to AL
    asm volatile ("inb $0x60, %%al" : [out] "={al}" (scancode));

    if (scancode == SCANCODE_ENTER) {
        keyboard_state.ring_buffer[keyboard_state.counter] = SCANCODE_ENTER;
        keyboard_state.counter += 1;
        keyboard_state.head += 1;
        keyboard_state.head %= keyboard_state.ring_buffer.len;
    } else if (scancode <= 0x58) { // keydown
        // load counter
        asm volatile ("mov (%[counter_address]), %%eax"
            : [out] "={eax}" (counter)
            : [counter_address] "r" (KEYBOARD_INPUT_ADDRESS));

        // scancode translation
        const ascii: u16 = SCANCODE_TO_ASCII[scancode];

        // fixme: decouple input buffer from video buffer jfc
        // put on second last row.
        const hack_video_offset = (80 * 23 + 3 + counter) * 2;
        const dest_adr: usize = 0xB8000 + hack_video_offset;

        // save scancode to location in buffer
        asm volatile ("movw %[ascii], %[dest_adr]"
            :
            : [ascii]       "r" (ascii | 0x0f00),
              [dest_adr]    "p" (dest_adr)
        );

        counter += 1;
        keyboard_state.ring_buffer[keyboard_state.counter] = @truncate(ascii);
        keyboard_state.counter += 1;
        keyboard_state.head += 1;
        keyboard_state.head %= keyboard_state.ring_buffer.len;

        // save counter
        asm volatile ("mov %[counter], %[counter_address]"
            :
            : [counter]           "r" (counter),
              [counter_address]   "p" (KEYBOARD_INPUT_ADDRESS));
    }

    ack_interrupt();
    @setRuntimeSafety(true);
    asm volatile ("popal");
    asm volatile("iret");
}