/* Thin wrappers around Firedancer sandbox primitives. */

#include "fd_util.h"

/* Sandbox functions are Linux-only (seccomp, user namespaces). */
#if FD_HAS_LINUX

#include "fd_sandbox.h"

int tk_sandbox_requires_cap_sys_admin( uint desired_uid, uint desired_gid ) { return fd_sandbox_requires_cap_sys_admin( desired_uid, desired_gid ); }

void
tk_sandbox_enter( uint        desired_uid,
                  uint        desired_gid,
                  int         keep_host_networking,
                  int         allow_connect,
                  int         allow_renameat,
                  int         keep_controlling_terminal,
                  int         dumpable,
                  ulong       rlimit_file_cnt,
                  ulong       rlimit_address_space,
                  ulong       rlimit_data,
                  ulong       rlimit_nproc,
                  ulong       allowed_file_descriptor_cnt,
                  int const * allowed_file_descriptor,
                  ulong       seccomp_filter_cnt,
                  void *      seccomp_filter ) {
  fd_sandbox_enter( desired_uid,
                    desired_gid,
                    keep_host_networking,
                    allow_connect,
                    allow_renameat,
                    keep_controlling_terminal,
                    dumpable,
                    rlimit_file_cnt,
                    rlimit_address_space,
                    rlimit_data,
                    rlimit_nproc,
                    allowed_file_descriptor_cnt,
                    allowed_file_descriptor,
                    seccomp_filter_cnt,
                    seccomp_filter );
}

void tk_sandbox_switch_uid_gid( uint desired_uid, uint desired_gid ) { fd_sandbox_switch_uid_gid( desired_uid, desired_gid ); }
int tk_sandbox_getpid( void ) { return fd_sandbox_getpid(); }
int tk_sandbox_gettid( void ) { return fd_sandbox_gettid(); }

#else

/* macOS stubs — sandbox not supported on this platform. */
#include <unistd.h>

int tk_sandbox_requires_cap_sys_admin( uint desired_uid, uint desired_gid ) { (void)desired_uid; (void)desired_gid; return 0; }
void tk_sandbox_enter( uint desired_uid, uint desired_gid, int keep_host_networking, int allow_connect, int allow_renameat, int keep_controlling_terminal, int dumpable, ulong rlimit_file_cnt, ulong rlimit_address_space, ulong rlimit_data, ulong rlimit_nproc, ulong allowed_file_descriptor_cnt, int const * allowed_file_descriptor, ulong seccomp_filter_cnt, void * seccomp_filter ) {
  (void)desired_uid; (void)desired_gid; (void)keep_host_networking; (void)allow_connect; (void)allow_renameat; (void)keep_controlling_terminal; (void)dumpable; (void)rlimit_file_cnt; (void)rlimit_address_space; (void)rlimit_data; (void)rlimit_nproc; (void)allowed_file_descriptor_cnt; (void)allowed_file_descriptor; (void)seccomp_filter_cnt; (void)seccomp_filter;
}
void tk_sandbox_switch_uid_gid( uint desired_uid, uint desired_gid ) { (void)desired_uid; (void)desired_gid; }
int tk_sandbox_getpid( void ) { return getpid(); }
int tk_sandbox_gettid( void ) { return getpid(); } /* gettid() is Linux-only; use getpid() as fallback */

#endif /* FD_HAS_LINUX */
