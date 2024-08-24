const KEYBOARD_INPUT_ADDRESS = @import("../../config.zig").KEYBOARD_INPUT_ADDRESS;

// ACK the interrupt and return.
pub fn noop() callconv(.Naked) noreturn {
    asm volatile ("push %eax");
    asm volatile ("movb $0x20, %al");
    asm volatile ("outb %al, $0x20");
    asm volatile ("pop %eax");

    asm volatile("iret");
}

// EAX=00000003 EBX=00000010 ECX=0000009f EDX=00000020
// ESI=00007d15 EDI=0000041e EBP=00400000 ESP=00400000
// EIP=00011006 EFL=00000206 [-----P-] CPL=0 II=0 A20=1 SMM=0 HLT=1

/// 00000000003fffd0: 0x000b8140 [0x0000041e] 0x00007d15 0x00400000
// 00000000003fffe0: 0x003ffff4 0x00000010 0x00000020 0x0000009f
// 00000000003ffff0: 0x00000003 0x00011006 0x00000008 0x00000206

// xp /128wx 0x3fff00
// Keyboard debugging ISR.
pub fn keyboard_input_debug() callconv(.Naked) noreturn {
    asm volatile ("pushal");
    asm volatile ("mov %esp, %ebp");

    var scancode: u8 = 0;
    var counter: u32 = 0;

    //read from port to AL
    asm volatile ("inb $0x60, %%al" : [out] "={al}" (scancode));

    // load counter
    asm volatile ("mov (%[counter_address]), %%eax"
        : [out] "={eax}" (counter)
        : [counter_address] "r" (KEYBOARD_INPUT_ADDRESS));

    // should be 1 but... debugging.
    counter += 2;
    asm volatile ("mov %[counter], %[counter_address]"
        :
        :   [counter]           "r" (counter),
            [counter_address]   "p" (KEYBOARD_INPUT_ADDRESS));

    // map scancode to ascii
    //asm volatile ("mov %[ascii], %ecx)

    const dest_adr: usize = counter + 0xB8000;

    // save scancode to location in buffer
    asm volatile ("movb %[ascii], %[dest_adr]"
        :
        : [ascii]       "r" (scancode),
          [dest_adr]    "p" (dest_adr)
    );

    ack_interrupt();

    asm volatile ("popal");

    asm volatile("iret");
}

pub inline fn ack_interrupt() void {
    asm volatile ("outb %%al, $0x20" : : [ack] "{al}" (0x20));
}

//