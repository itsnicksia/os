const std = @import("std");

const x86 = @import("asm").x86;
const outl = x86.outl;
const inl = x86.inl;

const cfg = @import("cfg");
const NIC_BASE_ADDRESS = cfg.mem.NIC_MIMO_ADDRESS;
const NIC_ADDRESS = cfg.mem.NIC_ADDRESS;

const tty = @import("tty");
const print = tty.print;
const println = tty.println;
const fprintln = tty.fprintln;
const printStruct32 = tty.printStruct32;

const eeprom = @import("eeprom.zig");
const EEPROMControlRegister = eeprom.EEPROMControlRegister;
const EEPROMReadRegister = eeprom.EEPROMReadRegister;

const PCIDevice = @import("../../../pci-device.zig").PCIDevice;

const ConfigurationAddress = @import("../../../configuration-address.zig").ConfigurationAddress;

const RECEIVE_BUFFER_BASE_ADDRESS: * align(16) volatile []u8 = @ptrFromInt(NIC_BASE_ADDRESS + 0x10000);

const PCI_CONFIG_ADDRESS = 0xCF8;
const PCI_CONFIG_DATA = 0xCFC;
const PCI_MMIO_OFFSET = 0x4;

// EEPROM Registers
const EECD_OFFSET = 0x10;
const EERD_OFFSET = 0x14;

// Receive Control Register
const RCTL_ADDRESS = NIC_BASE_ADDRESS + 0x100;

// Receive Descriptor Registers
const RDBAL_OFFSET = 0x2800;
const RDBAH_OFFSET = 0x2804;
const RDLEN_OFFSET = 0x2808;

// Receive Filter
const RAL_ADDRESS = NIC_BASE_ADDRESS + 0x5400;
const RAH_ADDRESS = NIC_BASE_ADDRESS + 0x5404;

const memory: * Memory = @ptrFromInt(NIC_ADDRESS);
const Memory = struct {
    macAddress: MACAddress,

    pub fn init() Memory {
        return Memory {
            .macAddress = [_]u8{0} ** 6
        };
    }
};

const MACAddress = [6]u8;

// The Receive Descriptor Head and Tail registers are initialized (by hardware) to 0b after a power-on
// or a software-initiated Ethernet controller reset. Receive buffers of appropriate size should be
// allocated and pointers to these buffers should be stored in the receive descriptor ring. Software
// initializes the Receive Descriptor Head (RDH) register and Receive Descriptor Tail (RDT) with the
// appropriate head and tail addresses. Head should point to the first valid receive descriptor in the
// descriptor ring and tail should point to one descriptor beyond the last valid descriptor in the
// descriptor ring.

// Software Developer’s Manual 377
// General Initialization and Reset Operation
// Program the Receive Control (RCTL) register with appropriate values for desired operation to
// include the following:
// • Set the receiver Enable (RCTL.EN) bit to 1b for normal operation. However, it is best to leave
// the Ethernet controller receive logic disabled (RCTL.EN = 0b) until after the receive
// descriptor ring has been initialized and software is ready to process received packets.
// • Set the Long Packet Enable (RCTL.LPE) bit to 1b when processing packets greater than the
// standard Ethernet packet size. For example, this bit would be set to 1b when processing Jumbo
// Frames.
// • Loopback Mode (RCTL.LBM) should be set to 00b for normal operation.
// • Configure the Receive Descriptor Minimum Threshold Size (RCTL.RDMTS) bits to the
// desired value.
// • Configure the Multicast Offset (RCTL.MO) bits to the desired value.
// • Set the Broadcast Accept Mode (RCTL.BAM) bit to 1b allowing the hardware to accept
// broadcast packets.
// • Configure the Receive Buffer Size (RCTL.BSIZE) bits to reflect the size of the receive buffers
// software provides to hardware. Also configure the Buffer Extension Size (RCTL.BSEX) bits if
// receive buffer needs to be larger than 2048 bytes.

// Set the Strip Ethernet CRC (RCTL.SECRC) bit if the desire is for hardware to strip the CRC
// prior to DMA-ing the receive packet to host memory.
pub fn initialize(busNumber: u5, deviceNumber: u8) void {
    memory.* = Memory.init();

    initializeBARs(busNumber, deviceNumber);
    enablePCIBusMastering(busNumber, deviceNumber);
    reset();

    memory.macAddress = loadMAC();

    setupReceiveRegisters(memory.macAddress);
    setupReceiveControl();
}

fn setupReceiveRegisters(mac: MACAddress) void {
    const receiveAddressLow: * volatile ReceiveAddressLow = @ptrFromInt(RAL_ADDRESS);
    const receiveAddressHigh: * volatile ReceiveAddressHigh = @ptrFromInt(RAH_ADDRESS);

    fprintln("setup mac address: {x}:{x}:{x}:{x}:{x}:{x}", .{
        mac[0],
        mac[1],
        mac[2],
        mac[3],
        mac[4],
        mac[5],
    });

    for (0..4) |byte| {
        receiveAddressLow[byte] = mac[byte];
    }

    for (4..6) | byte| {
        receiveAddressHigh[byte] = mac[byte];
    }
}

// Enable receive and set buffer addresses.
fn setupReceiveControl() void {
    const receiveControl: * volatile ReceiveControlRegister = @ptrFromInt(RCTL_ADDRESS);
    receiveControl.enable = true;
    receiveControl.multicastPromiscuous = true;
    receiveControl.unicastPromiscuous = true;

    const receiveBaseLow: * volatile ReceiveControlBaseLow = @ptrFromInt(NIC_BASE_ADDRESS + RDBAL_OFFSET);
    receiveBaseLow.address = @intFromPtr(RECEIVE_BUFFER_BASE_ADDRESS.ptr);

    const receiveLength: * volatile ReceiveLength = @ptrFromInt(NIC_BASE_ADDRESS + RDBAL_OFFSET);
    receiveLength.length = 64;
}

fn loadMAC() MACAddress {
    const controlRegister: *volatile EEPROMControlRegister = @ptrFromInt(NIC_BASE_ADDRESS + EECD_OFFSET);
    const readRegister: *volatile EEPROMReadRegister = @ptrFromInt(NIC_BASE_ADDRESS + EERD_OFFSET);

    if (!controlRegister.present) {
        println("ERROR: EEPROM not found!");
    }
    controlRegister.enableRead();
    controlRegister.lock();
    @memcpy(&memory.macAddress, readRegister.readMAC());
    fprintln("found mac address: {x}:{x}:{x}:{x}:{x}:{x}", .{
        memory.macAddress[0],
        memory.macAddress[1],
        memory.macAddress[2],
        memory.macAddress[3],
        memory.macAddress[4],
        memory.macAddress[5],
    });
    controlRegister.unlock();
    return memory.macAddress;
}

fn initializeBARs(busNumber: u5, deviceNumber: u8) void {
    println("Initializing BARs...");

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
            fprintln("Setting BAR {d} to 0x{x}", .{ index - 0x4, NIC_BASE_ADDRESS });
            outl(PCI_CONFIG_DATA, NIC_BASE_ADDRESS);
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

    // enable bus master
    const enableBusMaster = data | 0x4;
    outl(PCI_CONFIG_DATA, enableBusMaster);
}

fn reset() void {
    const control: *volatile ControlRegister = @ptrFromInt(NIC_BASE_ADDRESS);
    control.reset = true;
    delay(1000);
    println("reset finished!");
}

fn delay(cycles: u32) void {
    for (0..cycles) |_| {
        print(".");
    }
}

// Registers
const ReceiveAddressLow = [32]u8;
const ReceiveAddressHigh = [32]u8;

const ReceiveControlRegister = packed struct {
    _:                      u1,
    enable:                 bool,
    storeBadPackets:        bool,
    unicastPromiscuous:     bool,
    multicastPromiscuous:   bool,
};

const ReceiveControlBaseLow = packed struct {
    address: u32,
};

const ReceiveLength = packed struct {
    zero: u7,
    length: u13,
    _: u12,
};

const ControlRegister = packed struct {
    _:      u26,
    reset:  bool,
    __:     u4,
    phy_reset:  bool,
};

// Descriptors
const ReceiveDescriptor = packed struct {
    bufferAddress:  u64,
    length:         u16,
    _:              u16,
    status:         u8,
    errors:         u8,
    __:             u16,
};