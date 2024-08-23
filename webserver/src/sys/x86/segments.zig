const isr = @import("interrupt_handlers/debug.zig");

const GDT_DESCRIPTOR_ADDRESS = 0x700000;
const gdtr: *GlobalDescriptorTableRegister = @ptrFromInt(GDT_DESCRIPTOR_ADDRESS);
const gdt: * align(4096) GlobalDescriptorTable = @ptrFromInt(GDT_DESCRIPTOR_ADDRESS + 4096);

const GDT_OFFSET_CODE_SEGMENT: u16 = 0x8;

const GlobalDescriptorTableRegister = packed struct {
    size:               u16,
    offset:             u32,
};

const NUM_GDT_ENTRIES = 2;
const GlobalDescriptorTable = [NUM_GDT_ENTRIES]GlobalDescriptorTableEntry;

const GlobalDescriptorTableEntry = packed struct {
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
        gdt[index] = switch (index) {
            9 => create_idt_entry(&isr.keyboard_input_debug),
            else => create_idt_entry(&isr.noop),
        };
    }
}

fn init_idtr() void {
    gdtr.* = InterruptDescriptorTableRegister {
        .size = @sizeOf(InterruptDescriptorTable) * 8 - 1,
        .offset = @intFromPtr(gdt),
    };
}

inline fn load_idtr() void {
    asm volatile ("lidt (%[idtr])" : : [idtr] "r" (gdtr));
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