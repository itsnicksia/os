#!/bin/bash
set -e
nasm -f bin -o bootloader.bin bootloader.asm
nasm -f bin -o main.bin main.asm

# setup 4mb disk
dd if=/dev/zero of=boot.img bs=512 count=8192

# write bootloader binary code to image
dd if=bootloader.bin of=boot.img conv=notrunc

# write bootstrap code to image
dd if=main.bin of=boot.img seek=1 conv=notrunc

qemu-system-x86_64 -monitor stdio -hda boot.img
