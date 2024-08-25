const eql = @import("std").mem.eql;

const outl = @import("../x86/asm.zig").outl;
const inl = @import("../x86/asm.zig").inl;


const tty = @import("../../device/tty.zig");
const println = tty.println;
const fprintln = tty.fprintln;

const NUM_PCI_BUS = 256;
const NUM_DEVICE = 32;

const PCI_CONFIG_ADDRESS = 0xCF8;
const PCI_CONFIG_DATA = 0xCFC;

const ConfigurationAddress = packed struct {
    register_offset:    u8,
    function_number:    u3,
    device_number:      u5,
    bus_number:         u8,
    _:                  u7,
    enable:             bool,
};

const PCIDevice = struct {
    device_id: u32,
};

pub fn scan_devices() void {
    for (0..NUM_PCI_BUS) |bus_index| {
        for (0..NUM_DEVICE) |device_index| {
            var device_id: u16 = undefined;
            var vendor_id: u16 = undefined;
            for (0..4) |register_index| {
                const address = ConfigurationAddress {
                    .register_offset = @truncate(register_index * 4),
                    .function_number = 0,
                    .device_number = @truncate(device_index),
                    .bus_number = @truncate(bus_index),
                    ._ = 0,
                    .enable = true,
                };

                outl(PCI_CONFIG_ADDRESS, @bitCast(address));
                const data = inl(PCI_CONFIG_DATA);

                if (register_index == 0) {
                    vendor_id = @truncate(data);
                    device_id = @truncate(data >> 16);
                }
            }

            if (device_id != 0xffff) {
                fprintln("Found pci device @ [{d}:{d}]", .{
                    bus_index,
                    device_index,
                });

                fprintln("    device_id={x} {s} ", .{
                    device_id,
                    get_device_name(device_id),
                });

                fprintln("    vendor_id={x} {s}", .{
                    vendor_id,
                    get_vendor_name(vendor_id)
                });
            }
        }

    }
}

inline fn get_device_name(device_id: u16) []const u8 {
    return switch (device_id) {
        0x100e => "82540EM Gigabit Ethernet Controller (Qemu virtual machine)",
        0x1237 => "440FX - 82441FX PMC [Natoma] (Qemu virtual machine)",
        0x7000 => "82371SB PIIX3 ISA [Natoma/Triton II] (Qemu virtual machine)",
        else => "unknown"
    };
}

inline fn get_vendor_name(vendor_id: u16) []const u8 {
    return switch (vendor_id) {
        0x8086 => "Intel Corporation",
        else => "unknown"
    };
}