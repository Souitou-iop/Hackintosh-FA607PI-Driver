 .text
_fz:                          # bzero(rdi, rsi) replacement for the BAR-mapped vidmem: 64-byte AVX stores, then the tail
 vxorps %ymm0,%ymm0,%ymm0
 cmpq $0x40,%rsi
 jb 2f
1:
 vmovups %ymm0,(%rdi)
 vmovups %ymm0,0x20(%rdi)
 addq $0x40,%rdi
 subq $0x40,%rsi
 cmpq $0x40,%rsi
 jae 1b
2:
 testq %rsi,%rsi
 je 3f
 movb $0,(%rdi)
 incq %rdi
 decq %rsi
 jmp 2b
3:
 sfence
 vzeroupper
 ret
