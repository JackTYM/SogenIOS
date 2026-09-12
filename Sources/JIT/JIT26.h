#ifndef JIT26_h
#define JIT26_h

#include <stdbool.h>
#include <stddef.h>

void jit26_detach(void);
void *jit26_prepare_region(void *address, size_t length);
bool jit26_is_debugged(void);
void *jit26_writable_alias(void *rx_address, size_t length, int *out_kern_return, unsigned int *out_cur_prot,
                            unsigned int *out_max_prot);

#endif
