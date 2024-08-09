#!/bin/bash
set -e
nasm -f bin -o bootloader.bin bootloader.asm
dd if=/dev/zero of=boot.img bs=512 count=2880
dd if=bootloader.bin of=boot.img conv=notrunc
cp boot.img /var/lib/libvirt/images/boot.img 
