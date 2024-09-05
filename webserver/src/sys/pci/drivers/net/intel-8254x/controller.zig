pub const ReceiveControlRegister = packed struct {
    _:                      u1,
    enable:                 bool,
    storeBadPackets:        bool,
    unicastPromiscuous:     bool,
    multicastPromiscuous:   bool,
};

pub const ReceiveControlBaseLow = packed struct {
    address: u32,
};

pub const ReceiveLength = packed struct {
    zero: u7,
    length: u13,
    _: u12,
};

pub const ControlRegister = packed struct {
    _:      u26,
    reset:  bool,
    __:     u4,
    phy_reset:  bool,
};
