const isr = @import("interrupt_handlers/common.zig");
const kb_isr = @import("../../device/keyboard.zig").handle_kb_input;
const IDT_DESCRIPTOR_ADDRESS = @import("../config.zig").IDT_DESCRIPTOR_ADDRESS;

const idtr: *InterruptDescriptorTableRegister = @ptrFromInt(IDT_DESCRIPTOR_ADDRESS);
const idt: * align(4096) InterruptDescriptorTable = @ptrFromInt(IDT_DESCRIPTOR_ADDRESS + 4096);

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

const InterruptDescriptorTableRegister = packed struct {
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
    init_idt();
    init_idtr();
    load_idtr();
    enable_interrupt();
}

fn init_idt() void {
    for (0..NUM_IDT_ENTRIES) |index| {
        idt[index] = switch (index) {
            9 => create_idt_entry(&kb_isr),
            else => create_idt_entry(&isr.noop),
        };
    }
}

fn init_idtr() void {
    idtr.* = InterruptDescriptorTableRegister {
        .size = @sizeOf(InterruptDescriptorTable) * 8 - 1,
        .offset = @intFromPtr(idt),
    };
}

inline fn load_idtr() void {
    asm volatile ("lidt (%[idtr])" : : [idtr] "r" (idtr));
}

inline fn enable_interrupt() void {
    asm volatile("sti");
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