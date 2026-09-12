#ifndef JITExec_h
#define JITExec_h

#include <stddef.h>

void *jit_mmap_region(size_t size, int *out_errno);
void jit_toggle_write(int enabled);
void jit_invalidate_icache(void *region, size_t size);
void jit_execute(void *region);
void jit_munmap_region(void *region, size_t size);

#endif
