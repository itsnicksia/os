const nic = @import("sys").pci.e1000;

pub fn sendARP() void {
    nic.sendPacket("fooasdsad");
}