#ifndef JITSelfAttach_h
#define JITSelfAttach_h

// Returns 0 on success, -1 on failure. On failure, *out_errno holds the
// errno from the failing ptrace() call.
int jit_self_attach(int *out_errno);

#endif
