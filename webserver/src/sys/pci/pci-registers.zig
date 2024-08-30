const terminal = @import("tty");
const println = terminal.println;
const fprintln = terminal.fprintln;

pub const PCICommandRegister = packed struct {
    // I/O Space - If set to 1 the device can respond to I/O Space accesses; otherwise, the device's response is disabled.
    ioSpace: bool,

    // Memory Space - If set to 1 the device can respond to Memory Space accesses; otherwise, the device's response is disabled.
    memorySpace: bool,

    // Bus Master - If set to 1 the device can behave as a bus master; otherwise, the device can not generate PCI accesses.
    busMaster: bool,

    // Special Cycles - If set to 1 the device can monitor Special Cycle operations; otherwise, the device will ignore them.
    specialCycles: bool,

    // Memory Write and Invalidate Enable - If set to 1 the device can generate the Memory Write and Invalidate command; otherwise, the Memory Write command must be used.
    memoryWriteAndInvalidateEnable: bool,

    // VGA Palette Snoop - If set to 1 the device does not respond to palette register writes and will snoop the data; otherwise, the device will trate palette write accesses like all other accesses.
    vgaPaletteSnoop: bool,

    // Parity Error Response - If set to 1 the device will take its normal action when a parity error is detected; otherwise, when an error is detected, the device will set bit 15 of the Status register (Detected Parity Error Status Bit), but will not assert the PERR# (Parity Error) pin and will continue operation as normal.
    parityErrorResponse: bool,

    // Bit 7 - As of revision 3.0 of the PCI local bus specification this bit is hardwired to 0. In earlier versions of the specification this bit was used by devices and may have been hardwired to 0, 1, or implemented as a read/write bit.
    reserved: u1,

    // SERR# Enable - If set to 1 the SERR# driver is enabled; otherwise, the driver is disabled.
    serrEnable: bool,

    // Fast Back-Back Enable - If set to 1 indicates a device is allowed to generate fast back-to-back transactions; otherwise, fast back-to-back transactions are only allowed to the same agent.
    fastBackToBackEnable: bool,

    // Interrupt Disable - If set to 1 the assertion of the devices INTx# signal is disabled; otherwise, assertion of the signal is enabled.
    interruptDisable: bool,
    reserved2: u5,

    pub inline fn fromBytes(data: u16) PCICommandRegister {
        return @as(PCICommandRegister, @bitCast(data));
    }

    pub fn print(command: PCICommandRegister) void {
        println("command:");
        fprintln("    ioSpace={any}", .{command.ioSpace});
        fprintln("    memorySpace={any}", .{command.memorySpace});
        fprintln("    busMaster={any}", .{command.busMaster});
        fprintln("    specialCycles={any}", .{command.specialCycles});
        fprintln("    memoryWriteAndInvalidateEnable={any}", .{command.memoryWriteAndInvalidateEnable});
        fprintln("    vgaPaletteSnoop={any}", .{command.vgaPaletteSnoop});
        fprintln("    parityErrorResponse={any}", .{command.parityErrorResponse});
        fprintln("    serrEnable={any}", .{command.serrEnable});
        fprintln("    fastBackToBackEnable={any}", .{command.fastBackToBackEnable});
        fprintln("    interruptDisable={any}", .{command.interruptDisable});
    }
};

pub const ControlRegister = packed struct {
    notReset:    u31,
    reset:       bool,
};

pub const MemoryBaseAddressRegister = packed struct {
    _: bool, // always zero
    type: u2,
    prefetchable: bool,
    baseAddress: u28,

    pub fn print(self: *MemoryBaseAddressRegister) void {
        fprintln("    baseAddress={x}", .{self.baseAddress});
        fprintln("    type={x}", .{self.type});
        fprintln("    prefetchable={any}", .{self.prefetchable});
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