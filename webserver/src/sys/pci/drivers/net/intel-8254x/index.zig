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

const controller = @import("controller.zig");
const ControlRegister = controller.ControlRegister;
const ReceiveControlRegister = controller.ReceiveControlRegister;
const ReceiveControlBaseLow = controller.ReceiveControlBaseLow;
const ReceiveLength = controller.ReceiveLength;

const eeprom = @import("eeprom.zig");
const EEPROMControlRegister = eeprom.EEPROMControlRegister;
const EEPROMReadRegister = eeprom.EEPROMReadRegister;

const PCIDevice = @import("../../pci-device.zig").PCIDevice;

const registers = @import("../../pci-controller.zig");
const MemoryBaseAddressRegister = registers.MemoryBaseAddressRegister;
const ConfigurationAddress = @import("../../configuration-address.zig").ConfigurationAddress;

const RECEIVE_BUFFER_BASE_ADDRESS: * align(16) volatile []u8 = @ptrFromInt(NIC_BASE_ADDRESS + 0x10000);

const PCI_CONFIG_ADDRESS = 0xCF8;
const PCI_CONFIG_DATA = 0xCFC;
const PCI_MMIO_OFFSET = 0x4;

const BAR_EECD_OFFSET = 0x10;
const BAR_EERD_OFFSET = 0x14;
const BAR_RCTL_OFFSET = 0x100;

const BAR_RDBAL_OFFSET = 0x2800;
const BAR_RDBAH_OFFSET = 0x2804;
const BAR_RDLEN_OFFSET = 0x2808;

// Program the Receive Address Register(s) (RAL/RAH) with the desired Ethernet addresses.
// RAL[0]/RAH[0] should always be used to store the Individual Ethernet MAC address of the
// Ethernet controller. This can come from the EEPROM or from any other means (for example, on
// some machines, this comes from the system PROM not the EEPROM on the adapter port).
// Initialize the MTA (Multicast Table Array) to 0b. Per software, entries can be added to this table as
// desired.
// Program the Interrupt Mask Set/Read (IMS) register to enable any interrupt the software driver
// wants to be notified of when the event occurs. Suggested bits include RXT, RXO, RXDMT,
// RXSEQ, and LSC. There is no immediate reason to enable the transmit interrupts.
// If software uses the Receive Descriptor Minimum Threshold Interrupt, the Receive Delay Timer
// (RDTR) register should be initialized with the desired delay time.
// Allocate a region of memory for the receive descriptor list. Software should insure this memory is
// aligned on a paragraph (16-byte) boundary. Program the Receive Descriptor Base Address
// (RDBAL/RDBAH) register(s) with the address of the region. RDBAL is used for 32-bit addresses
// and both RDBAL and RDBAH are used for 64-bit addresses.
// Set the Receive Descriptor Length (RDLEN) register to the size (in bytes) of the descriptor ring.
// This register must be 128-byte aligned.
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
// • Set the Strip Ethernet CRC (RCTL.SECRC) bit if the desire is for hardware to strip the CRC
// prior to DMA-ing the receive packet to host memory.
// • For the 82541xx and 82547GI/EI, program the Interrupt Mask Set/Read (IMS) register to
// enable any interrupt the driver wants to be notified of when the even occurs. Suggested bits
// include RXT, RXO, RXDMT, RXSEQ, and LSC. There is no immediate reason to enable the
// transmit interrupts. Plan to optimize interrupts later, including programming the interrupt
// moderation registers TIDV, TADV, RADV and IDTR.
// • For the 82541xx and 82547GI/EI, if software uses the Receive Descriptor Minimum
// Threshold Interrupt,

pub fn initialize(device: *PCIDevice, busNumber: u5, deviceNumber: u8) void {

    fprintln("id: {x}", .{device.device_id});
    initializeBARs(device, busNumber, deviceNumber);
    enablePCIBusMastering(busNumber, deviceNumber);
    reset();

    _ = getMAC();

    setupReceiveControl();
}

fn setupReceiveControl() void {
    const receiveControl: * volatile ReceiveControlRegister = @ptrFromInt(NIC_BASE_ADDRESS + BAR_RCTL_OFFSET);
    receiveControl.enable = true;
    receiveControl.multicastPromiscuous = true;
    receiveControl.unicastPromiscuous = true;

    const receiveBaseLow: * volatile ReceiveControlBaseLow = @ptrFromInt(NIC_BASE_ADDRESS + BAR_RDBAL_OFFSET);
    receiveBaseLow.address = @intFromPtr(RECEIVE_BUFFER_BASE_ADDRESS.ptr);

    const receiveLength: * volatile ReceiveLength = @ptrFromInt(NIC_BASE_ADDRESS + BAR_RDBAL_OFFSET);
    receiveLength.length = 64;
}

const MACAddress = []const u8;

const ReceiveDescriptor = packed struct {
    bufferAddress:  u64,
    length:         u16,
    _:              u16,
    status:         u8,
    errors:         u8,
    __:             u16,
};



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

    // enable bus master
    const enableBusMaster = data | 0x4;
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

