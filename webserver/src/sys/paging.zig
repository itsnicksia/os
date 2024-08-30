const cfg = @import("cfg");

const PAGE_MAP_BASE_ADDRESS = cfg.mem.PAGE_MAP_BASE_ADDRESS;

const NUM_4K_PAGES = 16384;
const PAGE_TABLE_SIZE_BYTES = 4096;
const PAGE_SIZE_BYTES = 4096;

const PAGE_MAP_L1_PTR: * align(4096) PageTable = @ptrFromInt(PAGE_MAP_BASE_ADDRESS);
const PAGE_MAP_L2_PTR: * align(4096) PageDirectoryTable = @ptrFromInt(PAGE_MAP_BASE_ADDRESS + @sizeOf(PageTable));

const PageTable = [NUM_4K_PAGES]PageTableEntry;
const PageDirectoryTable = [1024]PageDirectoryEntry;

const PageTableEntry = packed struct {
    present:            bool,
    read_write:         bool,
    user_supervisor:    bool,
    page_write_through: bool,
    page_cache_disable: bool,
    accessed:           bool,
    dirty:              bool,
    pat:                bool,
    global:             bool,
    available:          u3,
    page_frame_address: u20,

    pub fn create(address: u20, rw: bool) PageTableEntry {
        return PageTableEntry {
            .present            = true,
            .read_write         = rw,
            .user_supervisor    = false,
            .page_write_through = false,
            .page_cache_disable = false,
            .accessed           = false,
            .dirty              = false,
            .pat                = false,
            .global             = false,
            .available           = 0,
            .page_frame_address = address,
        };
    }
};

const PageDirectoryEntry = packed struct {
    present:            bool,
    read_write:         bool,
    user_supervisor:    bool,
    page_write_through: bool,
    page_cache_disable: bool,
    accessed:           bool,
    page_size:          bool,
    available:          u5,
    page_frame_address: u20,

    pub fn create(address: u20, rw: bool) PageDirectoryEntry {
        return PageDirectoryEntry {
            .present            = true,
            .read_write         = rw,
            .user_supervisor    = false,
            .page_write_through = false,
            .page_cache_disable = false,
            .accessed           = false,
            .page_size          = false,
            .available           = 0,
            .page_frame_address = address,
        };
    }
};

pub fn init() void {
    init_pm1();
    init_pm2();
    enable_paging();
}

fn init_pm1() void {
    for (0..PAGE_MAP_L1_PTR.len) |index| {
        const offset = index * PAGE_SIZE_BYTES;
        PAGE_MAP_L1_PTR[index] = PageTableEntry.create(@truncate(offset >> 12), true);
    }
}

fn init_pm2() void {
    for (0..PAGE_MAP_L2_PTR.len) |index| {
        const offset = PAGE_MAP_BASE_ADDRESS + (index * PAGE_TABLE_SIZE_BYTES);
        PAGE_MAP_L2_PTR[index] = PageDirectoryEntry.create(@truncate(offset >> 12), true);
    }
}

fn enable_paging() void {
    // Set cr3 to PM2 base address
    asm volatile ("mov %eax, %[pdt]" : : [pdt] "r" (PAGE_MAP_L2_PTR));
    asm volatile ("mov %eax, %cr3");

    // Enable paging flag
    asm volatile ("mov %cr0, %eax");
    asm volatile ("orl $0x80000000, %eax");
    asm volatile ("mov %eax, %cr0");
}
