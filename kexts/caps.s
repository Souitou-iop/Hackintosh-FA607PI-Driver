	.text
	.globl _caps
_caps:
	movl	-0x90(%rbp), %esi        # 0x6d6e loop exit: restore the pitch alignment (as the original)
	jmp	1f                       # skip the early-path entry
	nop; nop; nop
	xorl	%r12d, %r12d             # 0x6d79 early path (no NVKMS list): r15d is already 0
1:	movl	0x294(%rbx), %edx        # fW
	addl	%edx, %edx               # 2 x boot width
	cmpl	%r12d, %edx
	cmovbl	%r12d, %edx              # edx = max(2*fW, panel's widest mode)
	movl	0x298(%rbx), %ecx        # fH
	addl	%ecx, %ecx
	cmpl	%r15d, %ecx
	cmovbl	%r15d, %ecx              # ecx = max(2*fH, panel's tallest mode)
