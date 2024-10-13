// Manual: https://www.intel.com/content/dam/doc/manual/pci-pci-x-family-gbe-controllers-software-dev-manual.pdf
const std = @import("std");
const assert = std.debug.assert;

const x86 = @import("asm").x86;
const outl = x86.outl;
const inl = x86.inl;

const cfg = @import("cfg");
const NIC_MMIO_ADDRESS = cfg.mem.NIC_MIMO_ADDRESS;
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

const NIC_TRANSMIT_RING_BUFFER_ADDRESS = NIC_ADDRESS + 0xa0000;
const NIC_TRANSMIT_DATA_ADDRESS = NIC_ADDRESS + 0x100000;
const RECEIVE_DESCRIPTOR_RING_BUFFER: * align(16) volatile []u8 = @ptrFromInt(NIC_ADDRESS + 0x10000);
const TRANSMIT_DESCRIPTOR_RING_BUFFER: * align(128) volatile [64]LegacyTransmitDescriptor = @ptrFromInt(NIC_TRANSMIT_RING_BUFFER_ADDRESS);

const PCI_CONFIG_ADDRESS = 0xCF8;
const PCI_CONFIG_DATA = 0xCFC;
const PCI_MMIO_OFFSET = 0x4;

// EEPROM Registers
const EECD_OFFSET = 0x10;
const EERD_OFFSET = 0x14;

// Receive Control Register
const CTRL_ADDRESS = NIC_MMIO_ADDRESS;

const RCTL_ADDRESS = NIC_MMIO_ADDRESS + 0x100;
const ReceiveControlRegister = packed struct {
    resv0:                                  u1,
    enable:                                 bool,
    storeBadPackets:                        bool,
    unicastPromiscuous:                     bool,
    multicastPromiscuous:                   bool,
    longPacketReceptionEnable:              bool,
    loopbackMode:                           u2,
    receiveDescriptorMinimumThresholdSize:  u2,
    resv1:                                  u2,
    multicastOffset:                        u2,
    resv2:                                  u1,
    broadcastAcceptMode:                    bool,
};

// Receive Descriptor Registers
// const ReceiveDescriptor = packed struct {
//
// }

// Receive 02800h RDBAL Receive Descriptor Base Low R/W 306
const RDBAL_OFFSET = 0x2800;
const ReceiveControlBaseLow = packed struct {
    address: u32,
};

// Receive 02804h RDBAH Receive Descriptor Base High R/W 306
const RDBAH_OFFSET = 0x2804;

// Receive 02808h RDLEN Receive Descriptor Length R/W 307
const RDLEN_OFFSET = 0x2808;

// Receive 02810h RDH Receive Descriptor Head R/W 307
// Receive 02818h RDT Receive Descriptor Tail R/W 308
// Receive 02820h RDTR Receive Delay Timer R/W 308

// Receive Filter
const RAL_ADDRESS = NIC_MMIO_ADDRESS + 0x5400;
const RAH_ADDRESS = NIC_MMIO_ADDRESS + 0x5404;
const RDH_ADDRESS = NIC_MMIO_ADDRESS + 0x2810;
const RDT_ADDRESS = NIC_MMIO_ADDRESS + 0x2818;

// Transmit Descriptor Registers
const TransmitDescriptor = packed struct {
    dataBufferAddress: u64,
    dataLength: u20,
    dataType: u4,
    commandField: u8,
    tcpStatusField: u4,
    reserved: u4,
    packetOption: u8,
    special: u16,
};
comptime {
    if (@sizeOf(TransmitDescriptor) != 16) {
        @compileError("Descriptor is wrong size");
    }
}

// Transmit Descriptor Registers
const LegacyTransmitDescriptor = packed struct {
    dataBufferAddress: u64,
    dataLength: u16,
    checksumOffset: u8,
    commandField: u8,
    statusField: u4,
    reserved: u4,
    checksumStartField: u8,
    special: u16,

    comptime {
        assert(@sizeOf(TransmitDescriptor) == 16);
    }
};

// Transmit 03800h TDBAL Transmit Descriptor Base Low R/W
const TDBAL_OFFSET = 0x3800;

// Transmit 03804h TDBAH Transmit Descriptor Base High R/W
const TDBAH_OFFSET = 0x3804;

// Transmit 03808h TDLEN Transmit Descriptor Length R/W
const TDLEN_OFFSET = 0x3808;

// Transmit 03810h TDH Transmit Descriptor Head R/W
const TDH_OFFSET = 0x3810;

// Transmit 03818h TDT Transmit Descriptor Tail R/W
const TDT_OFFSET = 0x3818;

// Transmit 00400h TCTL Transmit Control
const TCTL_OFFSET = 0x400;

// Transmit 00410h TIPG Transmit IPG
const TIPG_OFFSET = 0x0410;
const TransmitInterPacketGapRegister = packed struct  {
    ipgTransmitTime: u10,
    ipgReceiveTime1: u10,
    ipgReceiveTime2: u10,
    reserved:        u2,
};

// Interrupt
const INTERRUPT_MASK_ADDRESS = NIC_MMIO_ADDRESS + 0xD0;

// Status
const STATUS_ADDRESS = NIC_MMIO_ADDRESS + 0x8;

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

// Set the Strip Ethernet CRC (RCTL.SECRC) bit if the desire is for hardware to strip the CRC
// prior to DMA-ing the receive packet to host memory.
pub fn initialize(busNumber: u5, deviceNumber: u8) void {
    memory.* = Memory.init();


    initializeBARs(busNumber, deviceNumber);
    enablePCIBusMastering(busNumber, deviceNumber);
    detectExtra(busNumber, deviceNumber);
    reset();

    memory.macAddress = loadMAC();

    setupReceive(memory.macAddress);
    setupTransmit();

    // Test packet
    // const testData: * [64]u8 = @ptrFromInt(NIC_TRANSMIT_DATA_ADDRESS);
    // @memcpy(testData[0..4], &[_]u8{0x11, 0x11, 0x11, 0x11});
    // sendPacket(testData);
}

pub fn sendPacket(payload: []const u8) void {
    const transmitDescriptorHead: * volatile TransmitDescriptorHead = @ptrFromInt(CTRL_ADDRESS + TDH_OFFSET);
    const transmitDescriptorTail: * volatile TransmitDescriptorTail = @ptrFromInt(CTRL_ADDRESS + TDT_OFFSET);

    fprintln("sending packet: {x}", .{ payload });
    // Test transmit
    TRANSMIT_DESCRIPTOR_RING_BUFFER[transmitDescriptorTail.index] = LegacyTransmitDescriptor {
        .dataBufferAddress = @intFromPtr(payload.ptr),
        .dataLength = 42,
        .checksumOffset = 0,
        .commandField = 1,
        .statusField = 0,
        .reserved = 0,
        .checksumStartField = 0,
        .special = 0,
    };
    transmitDescriptorTail.index += 1;

    fprintln("tail: {any}", .{transmitDescriptorTail});
    fprintln("head: {any}", .{transmitDescriptorHead});
}

fn detectExtra(busNumber: u5, deviceNumber: u8) void {
    const configAddress = ConfigurationAddress.create(
        busNumber,
        deviceNumber,
        15
    );

    outl(PCI_CONFIG_ADDRESS, @bitCast(configAddress));
    const bits = inl(PCI_CONFIG_DATA);
    const extraData: PCIExtraRegister = @bitCast(bits);

    println("PCI Extra Registers: ");
    fprintln("    interruptLine: {d}", .{extraData.interruptLine});
    fprintln("    interruptPin: {d}", .{extraData.interruptPin});
    fprintln("    maxLatency: {d}", .{extraData.maxLatency});
    fprintln("    minGrant: {d}", .{extraData.minGrant});
}

fn setupReceive(mac: MACAddress) void {
    const receiveAddressLow: * volatile ReceiveAddressLow = @ptrFromInt(RAL_ADDRESS);
    const receiveAddressHigh: * volatile ReceiveAddressHigh = @ptrFromInt(RAH_ADDRESS);
    const receiveAddressExtra: * volatile ReceiveAddressHighExtra = @ptrFromInt(RAH_ADDRESS + 0x16);

    fprintln("setup mac address: {x}:{x}:{x}:{x}:{x}:{x}", .{
        mac[0],
        mac[1],
        mac[2],
        mac[3],
        mac[4],
        mac[5],
    });

    receiveAddressLow[0] = mac[1];
    receiveAddressLow[1] = mac[0];
    receiveAddressLow[2] = mac[3];
    receiveAddressLow[3] = mac[2];
    receiveAddressHigh[0] = mac[5];
    receiveAddressHigh[1] = mac[4];
    receiveAddressExtra.addressSelect = 0;

    fprintln("confirm mac address: {x}:{x}:{x}:{x}:{x}:{x}", .{
        receiveAddressLow[0],
        receiveAddressLow[1],
        receiveAddressLow[2],
        receiveAddressLow[3],
        receiveAddressHigh[0],
        receiveAddressHigh[1],
    });

    const receiveBaseLow: * volatile ReceiveControlBaseLow = @ptrFromInt(NIC_MMIO_ADDRESS + RDBAL_OFFSET);
    receiveBaseLow.address = @intFromPtr(RECEIVE_DESCRIPTOR_RING_BUFFER.ptr);

    const receiveLength: * volatile ReceiveLength = @ptrFromInt(NIC_MMIO_ADDRESS + RDLEN_OFFSET);
    receiveLength.length = 0x1000;

    const receiveDescriptorHead: * volatile ReceiveDescriptorHead = @ptrFromInt(RDH_ADDRESS);
    receiveDescriptorHead.index = 0;

    const receiveDescriptorTail: * volatile ReceiveDescriptorTail = @ptrFromInt(RDT_ADDRESS);
    receiveDescriptorTail.index = 5;

    const interruptMaskSet: * volatile [1]u16 = @ptrFromInt(INTERRUPT_MASK_ADDRESS);
    interruptMaskSet[0] = 0xf;

    const status: * volatile u32 = @ptrFromInt(STATUS_ADDRESS);
    fprintln("status bits: {x}", .{status.*});

    const receiveControl: * volatile ReceiveControlRegister = @ptrFromInt(RCTL_ADDRESS);
    receiveControl.multicastPromiscuous = true;
    receiveControl.unicastPromiscuous = true;
    receiveControl.broadcastAcceptMode = true;
    receiveControl.enable = true;
    receiveControl.loopbackMode = 0;
}

// Enable receive and set buffer addresses.
fn setupTransmit() void {
    const transmitBaseLow: * volatile TransmitControlBaseLow = @ptrFromInt(CTRL_ADDRESS + TDBAL_OFFSET);
    transmitBaseLow.address = NIC_TRANSMIT_RING_BUFFER_ADDRESS;

    const transmitBaseHigh: * volatile TransmitControlBaseHigh = @ptrFromInt(CTRL_ADDRESS + TDBAH_OFFSET);
    transmitBaseHigh.address = 0;

    const transmitLength: * volatile TransmitLength = @ptrFromInt(CTRL_ADDRESS + TDLEN_OFFSET);
    transmitLength.length = 0x1000;

    const transmitDescriptorHead: * volatile TransmitDescriptorHead = @ptrFromInt(CTRL_ADDRESS + TDH_OFFSET);
    transmitDescriptorHead.index = 0;

    const transmitDescriptorTail: * volatile TransmitDescriptorTail = @ptrFromInt(CTRL_ADDRESS + TDT_OFFSET);
    transmitDescriptorTail.index = 0;

    const transmitControl: * volatile TransmitControlRegister = @ptrFromInt(CTRL_ADDRESS + TCTL_OFFSET);
    transmitControl.transmitEnable = true;
    transmitControl.padShortPackets = true;
    transmitControl.collisionThreshold = 0x10;
    transmitControl.collisionDistance = 0x40;

    const transmitIPG: * volatile TransmitInterPacketGapRegister = @ptrFromInt(CTRL_ADDRESS + TIPG_OFFSET);
    transmitIPG.ipgTransmitTime = 10;
    transmitIPG.ipgReceiveTime1 = 10;
    transmitIPG.ipgReceiveTime2 = 10;
}

fn loadMAC() MACAddress {
    const controlRegister: *volatile EEPROMControlRegister = @ptrFromInt(NIC_MMIO_ADDRESS + EECD_OFFSET);
    const readRegister: *volatile EEPROMReadRegister = @ptrFromInt(NIC_MMIO_ADDRESS + EERD_OFFSET);

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
            fprintln("Setting BAR {d} to 0x{x}", .{ index - 0x4, NIC_MMIO_ADDRESS });
            outl(PCI_CONFIG_DATA, NIC_MMIO_ADDRESS);
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
    const control: *volatile ControlRegister = @ptrFromInt(NIC_MMIO_ADDRESS);
    control.reset = true;
    delay(1000);
    if (control.reset) {
        println("it didnt reset...");
    } else {
        println("reset finished!");
    }
}

fn delay(cycles: u32) void {
    for (0..cycles) |_| {
        print(".");
    }
}

// Registers
const ReceiveAddressLow = [4]u8;
const ReceiveAddressHigh = [2]u8;
const ReceiveAddressHighExtra = packed struct {
    addressSelect: u2,
    reserved: u13,
    valid: bool,
};

const TransmitControlRegister = packed struct {
    reserved_0:                 u1,     // Reserved (bit 0)
    transmitEnable:             bool,   // Transmit Enable (bit 1)
    reserved_2:                 u1,     // Reserved (bit 2)
    padShortPackets:            bool,     // Pad Short Packets (bit 3)
    collisionThreshold:         u7,     // Collision Threshold (bits 4:10)
    collisionDistance:          u10,    // Collision Distance (bits 12:21)
    softwareXOff:               bool,   // Software XOFF Transmission (bit 22)
    reserved_23:                u1,     // Reserved (bit 23)
    retransmitOnLateCollision:  bool,   // Re-transmit on Late Collision (bit 24)
    noRetransmitOnUnderrun:     bool,   // No Re-transmit on underrun (bit 25)
    reserved_31:                u6,     // Reserved (bits 26:31)
};

const ReceiveDescriptorHead = packed struct {
    index: u16,
    _: u16,
};

const ReceiveDescriptorTail = packed struct {
    index: u16,
    _: u16,
};


const TransmitDescriptorHead = packed struct {
    index: u16,
    _: u16,
};

const TransmitDescriptorTail = packed struct {
    index: u16,
    _: u16,
};


const TransmitControlBaseLow = packed struct {
    address: u32,
};

const TransmitControlBaseHigh = packed struct {
    address: u32,
};

const ReceiveLength = packed struct {
    zero: u7,
    length: u13,
    _: u12,
};

const TransmitLength = packed struct {
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

const PCIExtraRegister = packed struct {
    interruptLine:u8,
    interruptPin: u8,
    minGrant: u8,
    maxLatency: u8,

    comptime {
        assert(@sizeOf(PCIExtraRegister) == 4);
    }
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