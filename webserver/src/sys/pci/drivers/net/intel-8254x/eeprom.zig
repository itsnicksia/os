
pub const EEPROMControlRegister = packed struct {
    clockInput:       bool,
    chipSelect:       bool,
    dataInput:        bool,
    _:                u3,
    requestAccess:    bool,
    grantAccess:      bool,
    present:          bool,
    __:               u23,

    pub fn lock(self: * volatile EEPROMControlRegister) void {
        self.requestAccess = true;

        // 3us Delay before turning off reset bit
        for (0..10000) |_| {
            if (self.grantAccess) break;
            print(".");
        }

        if (self.grantAccess) {
            println("obtained eeprom lock!");
        } else {
            println("failed to obtain eeprom lock");
        }


    }

    pub fn unlock(self: * volatile EEPROMControlRegister) void {
        self.requestAccess = false;
        println("released eeprom lock!");
    }

    pub fn enableRead(self: * volatile EEPROMControlRegister) void {
        self.clockInput = true;
        self.chipSelect = true;
        self.dataInput = true;
    }
};


pub const EEPROMReadRegister = packed struct {
    start:  bool,
    rsv1:   u3,
    done:   bool,
    rsv2:   u3,
    address:   u8,
    data:   u16,

    pub fn buildReadCommand(address: u8) EEPROMReadRegister {
        return EEPROMReadRegister {
            .start = true,
            .rsv1 = 0,
            .done = false,
            .rsv2 = 0,
            .address = address,
            .data = 0,
        };
    }

    pub fn readMAC(self: * volatile EEPROMReadRegister) []const u8 {
        var macData = [_]u8{0} ** 6;
        for (0x0..0x3) |index| {
            const readCommand = std.mem.asBytes(&buildReadCommand(@truncate(index)));

            @memcpy(std.mem.asBytes(self), readCommand);
            for (0..1000) |_| {
                if (self.done) break;
                print(".");
            }

            self.start = false;

            if (!self.done) {
                fprintln("read failed! {b:0>32}", .{@as(u32, @bitCast(self.*))});
            } else {

                const mac0: u8 = @truncate(self.*.data);
                const mac1: u8 = @truncate(self.*.data >> 8);
                macData[index * 2] = mac0;
                macData[index * 2 + 1] = mac1;
            }

        }

        return &macData;
    }
};

