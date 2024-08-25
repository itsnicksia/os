const outl = @import("../x86/asm.zig").outl;

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

// pub fn scan_devices() void {
//     for (0..NUM_PCI_BUS) |bus_index| {
//         for (0..NUM_DEVICE) |device_index| {
//             //const vendor_id =
//         }
//     }
// }

fn read_word() void {
    const address = ConfigurationAddress {

    }
}