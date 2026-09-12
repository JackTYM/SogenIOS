#include "JITSelfAttach.h"

#include <errno.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

// iOS's public SDK omits <sys/ptrace.h>; declare the symbol manually.
// It still exists in libSystem and is callable when the process holds
// the get-task-allow entitlement.
extern int ptrace(int request, pid_t pid, caddr_t addr, int data);

#define PT_ATTACHEXC 14
#define PT_DETACH 11

int jit_self_attach(int *out_errno)
{
	const pid_t parent = getpid();
	const pid_t child = fork();

	if (child == 0)
	{
		const int result = ptrace(PT_ATTACHEXC, parent, 0, 0);
		const int saved_errno = errno;
		ptrace(PT_DETACH, parent, 0, 0);
		_exit(result == 0 ? 0 : (saved_errno & 0xFF));
	}

	if (child < 0)
	{
		if (out_errno)
		{
			*out_errno = errno;
		}
		return -1;
	}

	int status = 0;
	waitpid(child, &status, 0);
	const int exit_code = WEXITSTATUS(status);
	if (out_errno)
	{
		*out_errno = exit_code;
	}
	return exit_code == 0 ? 0 : -1;
}
