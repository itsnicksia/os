const mem = @import("std").mem;
const println = @import("terminal").println;

const RSDP_WIDTH = 8;

const MAIN_BIOS_RSDP_START  = 0x0009FC00;
const MAIN_BIOS_RSDP_END    = 0x0009FFFF;

pub fn init() void {
    _ = find_rsd_ptr();
}

// scan through certain ranges to find rsd_ptr
fn find_rsd_ptr() usize {
    println("looking for rsdp");
    const address: usize = MAIN_BIOS_RSDP_START;
    while (address <= MAIN_BIOS_RSDP_END) {
        const ptr: *[8]u8 = @ptrFromInt(address);
        const bytes = ptr[0..RSDP_WIDTH];

        const rsdp_signature = "RSD PTR ";

        const is_match = mem.eql(u8, bytes, rsdp_signature);

        if (is_match) {
            println("found rsdp!");
            return address;
        }
    }

    println("unable to find rsdp ");

    return 0;
}