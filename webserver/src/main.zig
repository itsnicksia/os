const std = @import("std");

export fn _start() callconv(.Naked) noreturn {
    asm volatile ("call main");
    while (true) {}
}

export fn main() void {
    asm volatile ("movl 0xcafebabe, %edx" : : );
}