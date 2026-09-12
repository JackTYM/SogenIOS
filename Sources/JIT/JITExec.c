#include "JITExec.h"

#include <dlfcn.h>
#include <errno.h>
#include <libkern/OSCacheControl.h>
#include <sys/mman.h>

#ifndef MAP_JIT
#define MAP_JIT 0x0800
#endif

// iOS's public pthread.h marks pthread_jit_write_protect_np unavailable,
// and re-declaring it directly still inherits that attribute through
// Clang's declaration merging. dlsym looks the symbol up by name instead,
// which isn't subject to the availability check — the symbol itself still
// exists in libSystem and works once the process holds CS_DEBUGGED (or
// the dynamic-codesigning entitlement).
typedef void (*jit_write_protect_fn)(int);

void *jit_mmap_region(size_t size, int *out_errno)
{
	void *region = mmap(NULL, size, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_ANON | MAP_PRIVATE | MAP_JIT, -1, 0);
	if (region == MAP_FAILED)
	{
		if (out_errno)
		{
			*out_errno = errno;
		}
		return NULL;
	}
	return region;
}

void jit_toggle_write(int enabled)
{
	static jit_write_protect_fn write_protect = NULL;
	if (!write_protect)
	{
		write_protect = (jit_write_protect_fn)dlsym(RTLD_DEFAULT, "pthread_jit_write_protect_np");
	}
	if (write_protect)
	{
		write_protect(enabled);
	}
}

void jit_invalidate_icache(void *region, size_t size)
{
	sys_icache_invalidate(region, size);
}

typedef void (*jit_fn)(void);

void jit_execute(void *region)
{
	((jit_fn)region)();
}

void jit_munmap_region(void *region, size_t size)
{
	munmap(region, size);
}
