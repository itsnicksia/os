const println = @import("../../debug.zig").println;
const x86 = @import("asm.zig");
const halt = x86.halt;

const GDT_ADDRESS: u32 = 0x900000;
const GDT_DESCRIPTOR_ADDRESS = 0x800000;
const GDT_OFFSET_CODE_SEGMENT: u16 = 0x8;

const GateType = enum(u4) {
    task            = 0x5,
    interrupt_16    = 0x6,
    trap_16         = 0x7,
    interrupt_32    = 0xE,
    trap_32         = 0xF,
};

const DescriptorPrivilegeLevel = enum(u2) {
    kernel          = 0b0,
    user            = 0b11,
};

const IDTDescriptor = packed struct {
    size:               u16,
    offset:             u32,
};

const NUM_IDT_ENTRIES = 256;
const InterruptDescriptorTable = [NUM_IDT_ENTRIES]InterruptDescriptorTableEntry;

const InterruptDescriptorTableEntry = packed struct {
    isr_offset_low:     u16,
    segment_selector:   u16,
    _reserved:          u8,
    gate_type:          GateType,
    _zero:              u1,
    privilege_level:    DescriptorPrivilegeLevel,
    present:            u1,
    isr_offset_high:    u16
};

pub fn init() void {
    create_idt();
    create_idt_descriptor();

    asm volatile ("lidt 0x800000");

    x86.enable_interrupt();
}

fn create_idt() void {
    const idt: *InterruptDescriptorTable = @ptrFromInt(IDT_ADDRESS);

    for (0..NUM_IDT_ENTRIES) |index| {
        idt[index] = switch (index) {
            9 => create_idt_entry(&kb_isr),
            else => create_idt_entry(&dummy_isr),
        };
    }
}

fn create_idt_descriptor() void {
    const idt_descriptor: *IDTDescriptor = @ptrFromInt(GDT_DESCRIPTOR_ADDRESS);

    idt_descriptor.* = IDTDescriptor {
        .size = @sizeOf(InterruptDescriptorTable) * 8 - 1,
        .offset = IDT_ADDRESS,
    };
}

// ACK the interrupt and return.
fn dummy_isr() callconv(.Naked) noreturn {
    asm volatile ("push %eax");
    asm volatile ("movb $0x20, %al");
    asm volatile ("outb %al, $0x20");
    asm volatile ("pop %eax");

    asm volatile("iret");
}

// Keyboard debugging ISR.
fn kb_isr() callconv(.Naked) noreturn {
    asm volatile ("push %eax");
    asm volatile ("push %ebx");

    // read from port to AL
    asm volatile ("inb $0x60, %al");

    // load counter
    asm volatile ("mov (0x700000), %ebx");

    // inc counter
    asm volatile ("addl $2, %ebx");
    asm volatile ("mov %ebx, 0x700000");

    // offset address
    asm volatile ("addl $0xB8000, %ebx");

    // move to 0x700000
    asm volatile ("movb %al, (%ebx)");

    // ACK interrupt
    asm volatile ("movb $0x20, %al");
    asm volatile ("outb %al, $0x20");

    asm volatile ("pop %ebx");
    asm volatile ("pop %eax");
    asm volatile("iret");
}

fn create_idt_entry(func: *const fn() callconv(.Naked) void) InterruptDescriptorTableEntry {
    const isr_ptr: u32 = @intFromPtr(func);

    return InterruptDescriptorTableEntry {
        .isr_offset_low = @truncate(isr_ptr),
        .isr_offset_high = @truncate(isr_ptr >> 16),
        .segment_selector = GDT_OFFSET_CODE_SEGMENT,
        .gate_type = .interrupt_32,
        .privilege_level = DescriptorPrivilegeLevel.user,
        .present = 1,
        ._reserved = 0,
        ._zero = 0,
    };
}