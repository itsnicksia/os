#!/bin/bash
set -e
nasm -f bin -o bootloader.bin bootloader.asm
nasm -f bin -o bootstrap.bin bootstrap.asm

# setup 4mb disk
dd if=/dev/zero of=boot.img bs=512 count=8192

# write bootloader binary code to image
dd if=bootloader.bin of=boot.img conv=notrunc

# write bootstrap code to image
dd if=bootstrap.bin of=boot.img seek=1 conv=notrunc

cd ./webserver
zig build
cd ..

# write main code to image
dd if=./webserver/zig-out/bin/webserver.bin of=boot.img seek=3 conv=notrunc

qemu-system-x86_64 -monitor stdio -m 256m -hda boot.img -no-reboot -no-shutdown -d int,cpu_reset -D qemu.log -s
qemu-system-x86_64 -monitor stdio -m 256m -hda boot.img -no-reboot -no-shutdown -d int,cpu_reset -D qemu.log -s
