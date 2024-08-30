const PCIDevice = @import("../../pci-device.zig").PCIDevice;

const terminal = @import("tty");
const print = terminal.print;
const println = terminal.println;
const fprintln = terminal.fprintln;

const registers = @import("../../pci-registers.zig");
const MemoryBaseAddressRegister = registers.MemoryBaseAddressRegister;
const ConfigurationAddress = @import("../../configuration-address.zig").ConfigurationAddress;
const ControlRegister = registers.ControlRegister;

const x86 = @import("asm").x86;
const outl = x86.outl;
const inl = x86.inl;

const cfg = @import("cfg");
const NIC_ADDRESS = cfg.mem.NIC_ADDRESS;

const PCI_CONFIG_ADDRESS = 0xCF8;
const PCI_CONFIG_DATA = 0xCFC;

pub fn initialize(self: *PCIDevice, busNumber: u5, deviceNumber: u8) void {
    println("[Initializing BARs...]");

    println("[BAR 0]");
    var bar0 = MemoryBaseAddressRegister.fromBytes(self.bar_0);
    bar0.print();

    println("[Poking BARs...]");
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

        fprintln("    bar {d} - required space={x} ({d}) bytes", .{ index, requiredSpace, requiredSpace});
        // fixme: hacky!
        if (index == 4) {
            fprintln("Setting BAR {d} to 0x{x}", .{ index, NIC_ADDRESS });
            outl(PCI_CONFIG_DATA, NIC_ADDRESS);
        }
    }

    // todo: set bus master bit
    const configAddress = ConfigurationAddress.create(
        busNumber,
        deviceNumber,
        1
    );


    outl(PCI_CONFIG_ADDRESS, @bitCast(configAddress));
    const data = inl(PCI_CONFIG_DATA);

    // enable bus master
    const enableBusMaster = data | 0x4;
    fprintln("register: {b}", .{enableBusMaster});
    outl(PCI_CONFIG_DATA, enableBusMaster);

    // todo: reset NIC
    const control: *volatile ControlRegister = @ptrFromInt(NIC_ADDRESS);
    control.reset = true;

    for (0..20) |_| {
        print(".");
    }
    println("reset finished!");

    control.reset = false;
}