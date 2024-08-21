const println = @import("../../debug.zig").println;
const x86 = @import("asm.zig");
const halt = x86.halt;

const IDT_ADDRESS: u32 = 0x600000;
const IDT_DESCRIPTOR_ADDRESS = 0x500000;
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

const InterruptDescriptorTable = [256]InterruptDescriptorTableEntry;

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
    println("initializing interrupt handling...", .{});
    _ = create_idt();
    _ = create_idt_descriptor();

    x86.load_idt(IDT_DESCRIPTOR_ADDRESS);

    x86.enable_interrupt();
}

fn create_idt() *InterruptDescriptorTable {
    println("creating IDT @ {x}", .{IDT_ADDRESS});
    const idt: *InterruptDescriptorTable = @ptrFromInt(IDT_ADDRESS);

    println("default ISR is {d}", .{&dummy_isr});

    const dummy_isr_ptr: u32 = @intFromPtr(&dummy_isr);

    const dummy_entry = InterruptDescriptorTableEntry {
        .isr_offset_low = @truncate(dummy_isr_ptr),
        .isr_offset_high = @truncate(dummy_isr_ptr >> 16),
        .segment_selector = GDT_OFFSET_CODE_SEGMENT,
        .gate_type = .interrupt_32,
        .privilege_level = DescriptorPrivilegeLevel.user,
        .present = 1,
        ._reserved = 0,
        ._zero = 0,
    };

    for (0..256) |index| {
        println("creating idt entry #{d}...", .{index});
        idt[index] = dummy_entry;
    }

    println("done!", .{});
    return idt;
}

fn create_idt_descriptor() *IDTDescriptor {
    println("creating IDT descriptor", .{});

    const idt_descriptor: *IDTDescriptor = @ptrFromInt(IDT_DESCRIPTOR_ADDRESS);

    idt_descriptor.* = IDTDescriptor {
        .size = 256 * 8 - 1,
        .offset = 0x600000,
    };

    println("done!", .{});
    return idt_descriptor;
}

fn dummy_isr() callconv(.Naked) noreturn {
    //println("got interrupt!", .{});
    x86.iret();
}