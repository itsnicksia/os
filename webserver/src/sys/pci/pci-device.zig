// We're just assuming this is a header type 0 device for now.
pub const PCIDevice = packed struct {
    // register 0
    vendor_id:          u16,
    device_id:          u16,

    // register 1
    command:            u16,
    status:             u16,

    // register 2
    revision_id:        u8,
    prog_if:            u8,
    subclass:           u8,
    class_code:         u8,

    // register 3
    cache_line_size:    u8,
    latency_timer:      u8,
    header_type:        u8,
    bist:               u8,

    bar_0:              u32,
    bar_1:              u32,
    bar_2:              u32,
    bar_3:              u32,
    bar_4:              u32,

    _padding:           u96,

    pub fn exists(self: *PCIDevice) bool {
        return self.device_id != 0xffff;
    }
};