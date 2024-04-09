//
// sync_code.S: sync a memory area after code modification
//
// void sync_code(const volatile void *ptr, size_t len);
//

#define CACHE_BLOCK	4

	.section ".text.hot.sync_code"
	.balign 4
	.option norvc		// RVC is a net loss for this function
	.globl sync_code
sync_code:
	lui a2,%hi(__dram_start)
	blt a0,a2,1f
	add a2,a0,a1
	and a0,a0,~(CACHE_BLOCK-1)

2:
	cbo.clean (a0)
	add a0,a0,CACHE_BLOCK
	blt a0,a2,2b
1:
	fence.i
	ret
