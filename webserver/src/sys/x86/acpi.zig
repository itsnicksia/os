const mem = @import("std").mem;
const print = @import("../../debug.zig").println;

const RSDP_WIDTH = 8;

const MAIN_BIOS_RSDP_START  = 0x000E0000;
const MAIN_BIOS_RSDP_END    = 0x000FFFFF;

pub fn init() void {
    _ = find_rsd_ptr();
}

// scan through certain ranges to find rsd_ptr
fn find_rsd_ptr() usize {
    print("looking for rsdp from {x} to {x} ", .{MAIN_BIOS_RSDP_START, MAIN_BIOS_RSDP_END});
    const address: usize = MAIN_BIOS_RSDP_START;
    const ptr: *[8]u8 = @ptrFromInt(address);
    _ = ptr[0..RSDP_WIDTH];
    const rsdp_signature = "RSD PTR ";

    //_ = mem.eql(u8, bytes, );

    //print("{*}", .{ptr});
    print("checking {*} {any}", .{rsdp_signature, rsdp_signature});
    print("checking {*},{any}", .{rsdp_signature, rsdp_signature});
    //
    // if (is_match) {
    //     print("found rsdp@{*}", .{ptr});
    //     return address;
    // }

    print("unable to find rsdp ", .{});

    return 0;
}