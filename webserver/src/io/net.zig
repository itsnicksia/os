const std = @import("std");
const asBytes = std.mem.asBytes;
const nic = @import("sys").pci.e1000;
const assert = std.debug.assert;

const tty = @import("tty");
const fprintln = tty.fprintln;

const ARP_PACKET_SIZE = 28;

pub fn sendDHCP() void {
    nic.sendPacket(createDHCPRequest());
}

pub fn sendARP() void {
    nic.sendPacket(createARPPacket());
}

fn createDHCPRequest() []u8 {
    _ = createUDPPacket(300);
}

fn createUDPPacket(payloadSize: u16) void {
    const udpPacketSize = payloadSize + @sizeOf(UDPHeader);
    _ = createIPPacket(udpPacketSize);
}

fn createIPPacket(payloadSize: u16) void {
    const ipPacketSize = payloadSize + @sizeOf(IPHeader);
    const ethernetFrame = createEthernetFrame(ipPacketSize);
    // TODO: Write IP Header
    return ethernetFrame;
}

fn createARPPacket() []const u8 {
    const ethernetHeader = EthernetHeader {
        .destinationAddress = 0xffffffffffff,
        .sourceAddress = 0x525400123456,
        .etherType = 0x0806,
    };

    const arpFrame: * ARPEthernetFrame = @ptrFromInt(0x4100000);
    arpFrame.* = ARPEthernetFrame {
        .header = ethernetHeader,
        .hardwareType = 0x001, // ethernet
        .protocolType = 0x800, // ipv4
        .hardwareAddressLength = 6, // mac length
        .protocolAddressLength = 4, // ip length
        .operation = 1, // request
        .senderHardwareAddress = 0x525400123456,
        .senderProtocolAddress = 0,
        .targetHardwareAddress = 0,
        .targetProtocolAddress = 0x0a000202,
    };

    return asBytes(arpFrame);
}

fn createEthernetFrame(_: u16) []u8 {
    // const frameSize = ARP_PACKET_SIZE + @sizeOf(EthernetHeader);
    // var frame = [_]u8{0} ** frameSize;
    // const header: *[]u8 = @ptrCast(&);
    // @memcpy(frame[0..@sizeOf(EthernetHeader)], header[0..14]);
}

const EthernetHeader = packed struct {
    destinationAddress: u48,
    sourceAddress: u48,
    etherType: u16,
};

const ARPEthernetFrame = packed struct {
    header: EthernetHeader,
    hardwareType: u16,
    protocolType: u16,
    protocolAddressLength: u8,
    hardwareAddressLength: u8,
    operation: u16,
    senderHardwareAddress: u48,
    senderProtocolAddress: u32,
    targetHardwareAddress: u48,
    targetProtocolAddress: u32,
};

const UDPHeader = packed struct {

};

const IPHeader = packed struct {

};

