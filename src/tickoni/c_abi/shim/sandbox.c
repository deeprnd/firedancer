/* Thin wrappers around Firedancer sandbox primitives. */

#include "../../../util/fd_util.h"
#include "../../../util/sandbox/fd_sandbox.h"

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
