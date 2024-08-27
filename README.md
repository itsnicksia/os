# os

## TODO
jump out of bootloader
 - test writing a binary to byte 1k
 - 
"bootstrap stuff"
implement ethernet 

0000000002820000: 0x0282000c 0x00000018 0xbeefdead 0x6e756f46
0000000002820010: 0x43502064 0x65442049 0x65636976 0x5b204020
0000000002820020: 0x5d303a30 0x00000000 0x00000000 0x00000000

[str_ptr][str_len][cursor_pos][row_number][format_buffer]

rodata.str1.1
    expected:   
    mem:        0x41a68
    img(exp):   0x40c68
    elf:        0x40668

mem is 7 blocks "behind"
should be loaded 7 blocks "after"

mem segment is too forwards
block offset is too behind