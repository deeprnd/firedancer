/* Cross-platform OS operations shim.
 * Linux: uses native syscalls
 * macOS: uses Darwin equivalents via system headers
 * Zig callers just call these — no platform forks in .zig files.
 */

#define _GNU_SOURCE
#include <signal.h>
#include <stdint.h>
#include <time.h>
#include <unistd.h>
#include <string.h>
#include "../../../util/fd_util.h"

#if FD_HAS_LINUX

int64_t tk_monotonic_nanos( void ) {
  struct timespec ts;
  clock_gettime( CLOCK_MONOTONIC, &ts );
  return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

void tk_sleep_nanos( uint64_t ns ) {
  struct timespec ts = { .tv_sec  = (time_t)(ns / 1000000000ULL),
                         .tv_nsec = (long)(ns % 1000000000ULL) };
  nanosleep( &ts, NULL );
}

int tk_self_exe_path( char * buf, size_t buf_len ) {
  ssize_t n = readlink( "/proc/self/exe", buf, buf_len - 1 );
  if (n < 0) return -1;
  buf[n] = '\0';
  return (int)n;
}

int tk_parent_pid( int pid ) {
  char path[64];
  int n = snprintf( path, sizeof(path), "/proc/%d/status", pid );
  if (n < 0 || n >= (int)sizeof(path)) return -1;

  FILE *f = fopen( path, "r" );
  if (!f) return -1;

  char line[256];
  int ppid = -1;
  while (fgets(line, sizeof(line), f)) {
    if (strncmp(line, "PPid:", 5) == 0) {
      ppid = atoi( line + 5 );
      break;
    }
  }
  fclose( f );
  return ppid;
}

int tk_kill_process( int pid ) {
  return kill( pid, SIGKILL );
}

int tk_write( int fd, void const * buf, size_t count ) {
  ssize_t n = write( fd, buf, count );
  return n < 0 ? 0 : (int)n;
}

#elif defined(__APPLE__)
#include <mach-o/dyld.h>
#include <sys/sysctl.h>

int64_t tk_monotonic_nanos( void ) {
  struct timespec ts;
  clock_gettime( CLOCK_MONOTONIC, &ts );
  return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

void tk_sleep_nanos( uint64_t ns ) {
  struct timespec ts = { .tv_sec  = (time_t)(ns / 1000000000ULL),
                         .tv_nsec = (long)(ns % 1000000000ULL) };
  nanosleep( &ts, NULL );
}

int tk_self_exe_path( char * buf, size_t buf_len ) {
  uint32_t size = (uint32_t)buf_len;
  if ( _NSGetExecutablePath( buf, &size ) == 0 ) return (int)strlen( buf );
  return -1;
}

int tk_parent_pid( int pid ) {
  struct kinfo_proc info;
  size_t size = sizeof(info);
  int mib[] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
  if ( sysctl( mib, 4, &info, &size, NULL, 0 ) != 0 ) return -1;
  return (int)info.kp_eproc.e_ppid;
}

int tk_kill_process( int pid ) {
  return kill( pid, SIGKILL );
}

int tk_write( int fd, void const * buf, size_t count ) {
  ssize_t n = write( fd, buf, count );
  return n < 0 ? 0 : (int)n;
}

#else
/* Fallback for other Unix-like systems */
int64_t tk_monotonic_nanos( void ) {
  struct timespec ts;
  clock_gettime( CLOCK_MONOTONIC, &ts );
  return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

void tk_sleep_nanos( uint64_t ns ) {
  struct timespec ts = { .tv_sec  = (time_t)(ns / 1000000000ULL),
                         .tv_nsec = (long)(ns % 1000000000ULL) };
  nanosleep( &ts, NULL );
}

int tk_self_exe_path( char * buf, size_t buf_len ) {
  (void)buf; (void)buf_len;
  return -1;
}

int tk_parent_pid( int pid ) {
  (void)pid;
  return -1;
}

int tk_kill_process( int pid ) {
  return kill( pid, SIGKILL );
}

int tk_write( int fd, void const * buf, size_t count ) {
  ssize_t n = write( fd, buf, count );
  return n < 0 ? 0 : (int)n;
}

#endif
