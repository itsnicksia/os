pub const ConfigurationAddress = packed struct {
    register_offset:    u8,
    function_number:    u3,
    device_number:      u5,
    bus_number:         u8,
    _:                  u7,
    enable:             bool,

    pub fn create(device_number: u5, bus_number: u8, register_index: u8) ConfigurationAddress {
        return ConfigurationAddress {
            .register_offset = register_index * 4,
            .function_number = 0,
            .device_number = device_number,
            .bus_number = bus_number,
            ._ = 0,
            .enable = true,
        };
    }
};
