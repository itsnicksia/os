
const NUM_PCI_BUS = 256;
const NUM_DEVICE = 32;

const PCI_CONFIG_ADDRESS = 0xCF8;
const PCI_CONFIG_DATA = 0xCFC;

// pub fn scan_devices() void {
//     for (0..NUM_PCI_BUS) |bus_index| {
//         for (0..NUM_DEVICE) |device_index| {
//             //const vendor_id =
//         }
//     }
// }

// fn update_cursor() void {
//     self.cursor_position = position;
//
//     // Vertical Blanking Start Register
//     outb(VIDEO_CURSOR_REGISTER_PORT, 0x0F);
//     outb(VIDEO_CURSOR_DATA_PORT, @intCast(position & 0xFF));
//
//     // Vertical Blanking End Register
//     outb(VIDEO_CURSOR_REGISTER_PORT, 0x0E);
//     outb(VIDEO_CURSOR_DATA_PORT, @intCast((position >> 8) & 0xFF));
// }