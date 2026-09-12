#include "JIT26.h"

#include <dlfcn.h>
#include <mach/mach.h>
#include <stdint.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <unistd.h>

#define CS_OPS_STATUS 0
#define CS_DEBUGGED 0x10000000

// iOS's public SDK #errors out of <mach/mach_vm.h> entirely; declare the
// symbol manually. It still exists in libSystem and is callable when the
// process holds CS_DEBUGGED.
typedef uint64_t mach_vm_address_t;
typedef uint64_t mach_vm_size_t;

extern kern_return_t mach_vm_remap(
    vm_map_t target_task,
    mach_vm_address_t *target_address,
    mach_vm_size_t size,
    mach_vm_address_t mask,
    int flags,
    vm_map_t src_task,
    mach_vm_address_t src_address,
    boolean_t copy,
    vm_prot_t *cur_protection,
    vm_prot_t *max_protection,
    vm_inherit_t inheritance);

#define VM_FLAGS_ANYWHERE 0x0001
#define VM_INHERIT_NONE ((vm_inherit_t)2)

typedef int (*csops_fn)(pid_t, unsigned int, void *, size_t);

bool jit26_is_debugged(void)
{
	static csops_fn csops_ptr = NULL;
	if (!csops_ptr)
	{
		csops_ptr = (csops_fn)dlsym(RTLD_DEFAULT, "csops");
	}
	if (!csops_ptr)
	{
		return false;
	}

	unsigned int flags = 0;
	if (csops_ptr(getpid(), CS_OPS_STATUS, &flags, sizeof(flags)) != 0)
	{
		return false;
	}
	return (flags & CS_DEBUGGED) != 0;
}

void *jit26_writable_alias(void *rx_address, size_t length, int *out_kern_return, unsigned int *out_cur_prot,
                            unsigned int *out_max_prot)
{
	mach_vm_address_t target_address = 0;
	vm_prot_t cur_prot = 0;
	vm_prot_t max_prot = 0;

	kern_return_t kr = mach_vm_remap(
	    mach_task_self(),
	    &target_address,
	    length,
	    0,
	    VM_FLAGS_ANYWHERE,
	    mach_task_self(),
	    (mach_vm_address_t)rx_address,
	    FALSE,
	    &cur_prot,
	    &max_prot,
	    VM_INHERIT_NONE);

	if (kr == KERN_SUCCESS && (max_prot & VM_PROT_WRITE) != 0 && (cur_prot & VM_PROT_WRITE) == 0)
	{
		if (mprotect((void *)target_address, length, PROT_READ | PROT_WRITE) == 0)
		{
			cur_prot = VM_PROT_READ | VM_PROT_WRITE;
		}
	}

	if (out_kern_return)
	{
		*out_kern_return = kr;
	}
	if (out_cur_prot)
	{
		*out_cur_prot = (unsigned int)cur_prot;
	}
	if (out_max_prot)
	{
		*out_max_prot = (unsigned int)max_prot;
	}
	if (kr != KERN_SUCCESS)
	{
		return NULL;
	}
	return (void *)target_address;
}

__attribute__((noinline, optnone, naked)) void jit26_detach(void)
{
	__asm__(
	    "mov x16, #0\n"
	    "brk #0xf00d\n"
	    "ret\n");
}

__attribute__((noinline, optnone, naked)) void *jit26_prepare_region(void *address, size_t length)
{
	__asm__(
	    "mov x16, #1\n"
	    "brk #0xf00d\n"
	    "ret\n");
}
