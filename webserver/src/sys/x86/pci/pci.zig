const eql = @import("std").mem.eql;
const fmt = @import("std").fmt;

const outl = @import("../../x86/asm.zig").outl;
const inl = @import("../../x86/asm.zig").inl;

const terminal = @import("../../../device/terminal.zig");
const println = terminal.println;
const fprintln = terminal.fprintln;

const PciCommandRegister = @import("pci-command-register.zig").PciCommandRegister;

const NUM_PCI_BUS = 4;
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

    pub fn create(device_number: u5, bus_number: u8, register_index: u8) ConfigurationAddress {
        return ConfigurationAddress {
            .register_offset = register_index * 4,
            .function_number = 0,
            .device_number = device_number,
            .bus_number = bus_number,
            ._ = 0,
            .enable = true,
        };
    }
};

// We're just assuming this is a header type 0 device for now.
const PCIDevice = packed struct {
    // register 0
    vendor_id:          u16,
    device_id:          u16,

    // register 1
    command:            u16,
    status:             u16,

    // register 2
    revision_id:        u8,
    prog_if:            u8,
    subclass:           u8,
    class_code:         u8,

    // register 3
    cache_line_size:    u8,
    latency_timer:      u8,
    header_type:        u8,
    bist:               u8,

    bar_0:              u32,
    bar_1:              u32,
    bar_2:              u32,
    bar_3:              u32,
    bar_4:              u32,

    _padding:           u96,

    pub fn exists(self: *PCIDevice) bool {
        return self.device_id != 0xffff;
    }

    pub fn initializeBars(self: *PCIDevice, busNumber: u5, deviceNumber: u8) void {
        println("initializing BARs:");

        var bar0 = MemoryBaseAddressRegister.fromBytes(self.bar_0);
        bar0.print();
        fprintln("    1={x}", .{self.bar_1});
        fprintln("    2={x}", .{self.bar_2});
        fprintln("    3={x}", .{self.bar_3});
        fprintln("    4={x}", .{self.bar_4});

        // test each BAR
        for (0x4..0x9) |index| {
            const configAddress = ConfigurationAddress.create(
                busNumber,
                deviceNumber,
                @truncate(index)
            );

            // switch address register
            outl(PCI_CONFIG_ADDRESS, @bitCast(configAddress));

            // send test
            outl(PCI_CONFIG_DATA, 0xffffffff);

            // read sizes
            const data = inl(PCI_CONFIG_DATA);

            fprintln("bar {d} {x}", .{ index - 4, data});

            // write allocated address
        }

        // rescan BAR

    }
};

const MemoryBaseAddressRegister = packed struct {
    _: bool, // always zero
    type: u2,
    prefetchable: bool,
    baseAddress: u28,

    pub fn print(self: *MemoryBaseAddressRegister) void {
        fprintln("baseAddress={x}", .{self.baseAddress});
        fprintln("type={x}", .{self.type});
        fprintln("prefetchable={any}", .{self.prefetchable});

    }

    pub fn fromBytes(bytes: u32) MemoryBaseAddressRegister {
        // fixme: learn how to do errors
        return @bitCast(bytes);
    }

    pub fn isMemoryBAR(bytes: u32) bool {
        return bytes & 1 == 0;
    }
};

const IOBaseAddressRegister = packed struct {
    _: bool, // always one
    reserved: bool,
    baseAddress: u30,

    pub fn asString() []const u8 {

    }
};

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
        // doesnt belong here
        if (device.device_id == 0x100e) {
            device.initializeBars(bus_number, device_number);
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

    const commandRegister = PciCommandRegister.fromBytes(device.command);
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