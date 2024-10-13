const std = @import("std");
const eql = std.mem.eql;
const fmt = std.fmt;

const x86 = @import("asm").x86;
const outl = x86.outl;
const inl = x86.inl;

const terminal = @import("tty");
const print = terminal.print;
const println = terminal.println;
const fprintln = terminal.fprintln;

const registers = @import("pci-registers.zig");
const PCICommandRegister = registers.PCICommandRegister;
const MemoryBaseAddressRegister = registers.MemoryBaseAddressRegister;
const ControlRegister = registers.ControlRegister;

const PCIDevice = @import("pci-device.zig").PCIDevice;
const ConfigurationAddress = @import("configuration-address.zig").ConfigurationAddress;

pub const e1000 = @import("drivers/net/intel-8254x/index.zig");

const NUM_PCI_BUS = 4;
const NUM_DEVICE = 32;

const PCI_CONFIG_ADDRESS = 0xCF8;
const PCI_CONFIG_DATA = 0xCFC;

pub fn scan_devices() void {
    for (0..NUM_PCI_BUS) |bus_number| {
        for (0..NUM_DEVICE) |device_number| {
            scan_device(@truncate(bus_number), @truncate(device_number));
        }
    }
}

fn scan_device(bus_number: u5, device_number: u8) void {
    const desired_registers = @sizeOf(PCIDevice) / @sizeOf(u32);
    var buffer: [desired_registers]u32 = undefined;

    for (0..desired_registers) |register_index| {
        const config_addr = ConfigurationAddress.create(
            bus_number,
            device_number,
            @truncate(register_index)
        );

        outl(PCI_CONFIG_ADDRESS, @bitCast(config_addr));

        const data = inl(PCI_CONFIG_DATA);
        buffer[register_index] = data;

        if (register_index == 0 and data == 0xffff) {
            return;
        }
    }

    var deviceRaw: PCIDevice = @bitCast(buffer);
    const device = &deviceRaw;

    if (device.exists()) {
        print_device_found(bus_number, device_number,device);
        // fixme: move to factory
        if (device.device_id == 0x100e) {
            e1000.initialize(bus_number, device_number);
        }
    }
}

fn print_device_found(bus_number: u8, device_number: u8, device: *PCIDevice) void {
    fprintln("Found PCI Device @ [{d}:{d}]", .{
        bus_number,
        device_number,
    });

    fprintln("    device_id={x} ({s})", .{
        device.device_id,
        get_device_name(device.device_id),
    });

    fprintln("    vendor_id={x} ({s})", .{
        device.vendor_id,
        get_vendor_name(device.vendor_id),
    });

    fprintln("    cmd={b} status={b}", .{
        device.command,
        device.status,
    });

    const commandRegister = PCICommandRegister.fromBytes(device.command);
    commandRegister.print();
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