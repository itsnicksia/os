const std = @import("std");

const x86 = @import("asm").x86;
const outl = x86.outl;
const inl = x86.inl;

const cfg = @import("cfg");
const NIC_BASE_ADDRESS = cfg.mem.NIC_ADDRESS;

const tty = @import("tty");
const print = tty.print;
const println = tty.println;
const fprintln = tty.fprintln;
const printStruct32 = tty.printStruct32;


const PCIDevice = @import("../../pci-device.zig").PCIDevice;

const registers = @import("../../pci-registers.zig");
const MemoryBaseAddressRegister = registers.MemoryBaseAddressRegister;
const ConfigurationAddress = @import("../../configuration-address.zig").ConfigurationAddress;

const PCI_CONFIG_ADDRESS = 0xCF8;
const PCI_CONFIG_DATA = 0xCFC;
const PCI_MMIO_OFFSET = 0x4;
const BAR_EECD_OFFSET = 0x10;
const BAR_EERD_OFFSET = 0x14;

pub fn initialize(device: *PCIDevice, busNumber: u5, deviceNumber: u8) void {

    fprintln("id: {x}", .{device.device_id});
    initializeBARs(device, busNumber, deviceNumber);
    enablePCIBusMastering(busNumber, deviceNumber);
    reset();

    _ = getMAC();
}

const MACAddress = []const u8;

fn getMAC() MACAddress {
    const controlRegister: *volatile EEPROMControlRegister = @ptrFromInt(NIC_BASE_ADDRESS + BAR_EECD_OFFSET);
    const readRegister: *volatile EEPROMReadRegister = @ptrFromInt(NIC_BASE_ADDRESS + BAR_EERD_OFFSET);

    if (!controlRegister.present) {
        println("ERROR: EEPROM not found!");
    }
    controlRegister.enableRead();
    controlRegister.lock();
    const mac = readRegister.readMAC();
    fprintln("found mac address: {x}:{x}:{x}:{x}:{x}:{x}", .{
        mac[0],
        mac[1],
        mac[2],
        mac[3],
        mac[4],
        mac[5],
    });
    controlRegister.unlock();
    return mac;
}

fn initializeBARs(device: *PCIDevice, busNumber: u5, deviceNumber: u8) void {
    println("Initializing BARs...");
    println("[BAR 0]");
    var bar0 = MemoryBaseAddressRegister.fromBytes(device.bar_0);
    bar0.print();

    println("Testing BARs...");
    for (0x4..0x5) |index| {
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
        const bytes = inl(PCI_CONFIG_DATA);
        const requiredSpace = ~(bytes & 0xfffffff0) + 1;

        fprintln("    bar {d} - required space={x} ({d}) bytes", .{ index - 4, requiredSpace, requiredSpace});

        if (index == PCI_MMIO_OFFSET) {
            fprintln("Setting BAR {d} to {b}", .{ index - 0x4, NIC_BASE_ADDRESS });
            outl(PCI_CONFIG_DATA, NIC_BASE_ADDRESS);
            fprintln("BAR {d} has        {b}", .{ index - 0x4, inl(PCI_CONFIG_DATA) });
        }
    }
}

fn enablePCIBusMastering(busNumber: u5, deviceNumber: u8) void {
    const configAddress = ConfigurationAddress.create(
        busNumber,
        deviceNumber,
        1
    );

    outl(PCI_CONFIG_ADDRESS, @bitCast(configAddress));
    const data = inl(PCI_CONFIG_DATA);
    fprintln("before bus master: {b}", .{data});

    // enable bus master
    const enableBusMaster = data | 0x4;
    fprintln("after bus master: {b}", .{enableBusMaster});
    outl(PCI_CONFIG_DATA, enableBusMaster);
}

fn reset() void {
    const control: *volatile ControlRegister = @ptrFromInt(NIC_BASE_ADDRESS);
    control.reset = true;
    printStruct32("before", control.*);

    delay(1000);
    printStruct32("after", control.*);
    println("reset finished!");
}

fn delay(cycles: u32) void {
    for (0..cycles) |_| {
        print(".");
    }
}

// Registers
pub const ControlRegister = packed struct {
    _:      u26,
    reset:  bool,
    __:     u4,
    phy_reset:  bool,
};

pub const EEPROMControlRegister = packed struct {
    clockInput:       bool,
    chipSelect:       bool,
    dataInput:        bool,
    _:                u3,
    requestAccess:    bool,
    grantAccess:      bool,
    present:          bool,
    __:               u23,

    pub fn lock(self: * volatile EEPROMControlRegister) void {
        self.requestAccess = true;

        // 3us Delay before turning off reset bit
        for (0..10000) |_| {
            if (self.grantAccess) break;
            print(".");
        }

        if (self.grantAccess) {
            println("obtained eeprom lock!");
        } else {
            println("failed to obtain eeprom lock");
        }


    }

    pub fn unlock(self: * volatile EEPROMControlRegister) void {
        self.requestAccess = false;
        println("released eeprom lock!");
    }

    pub fn enableRead(self: * volatile EEPROMControlRegister) void {
        self.clockInput = true;
        self.chipSelect = true;
        self.dataInput = true;
    }
};


pub const EEPROMReadRegister = packed struct {
    start:  bool,
    rsv1:   u3,
    done:   bool,
    rsv2:   u3,
    address:   u8,
    data:   u16,

    pub fn buildReadCommand(address: u8) EEPROMReadRegister {
        return EEPROMReadRegister {
            .start = true,
            .rsv1 = 0,
            .done = false,
            .rsv2 = 0,
            .address = address,
            .data = 0,
        };
    }

    pub fn readMAC(self: * volatile EEPROMReadRegister) []const u8 {
        var macData = [_]u8{0} ** 6;
        for (0x0..0x3) |index| {
            const readCommand = std.mem.asBytes(&buildReadCommand(@truncate(index)));

            @memcpy(std.mem.asBytes(self), readCommand);
            for (0..1000) |_| {
                if (self.done) break;
                print(".");
            }

            self.start = false;

            if (!self.done) {
                fprintln("read failed! {b:0>32}", .{@as(u32, @bitCast(self.*))});
            } else {
                fprintln("got      {b:0>32}", .{@as(u32, @bitCast(self.*))});

                const mac0: u8 = @truncate(self.*.data);
                const mac1: u8 = @truncate(self.*.data >> 8);

                fprintln("mac0 {x}", .{mac0});
                fprintln("mac1 {x}", .{mac1});

                macData[index * 2] = mac0;
                macData[index * 2 + 1] = mac1;
            }

        }

        return &macData;
    }
};

