/* Unit tests for fd_log_windows.c — logging stack, time conversion, format output.
 *
 * Tests:
 *   - fd_log_wallclock() — verify non-zero, non-negative output
 *   - fd_log_wallclock_cstr() — verify format layout
 *   - fd_log_private_0() — format a message
 *   - fd_log_private_boot() — verify initialization
 *   - fd_log_private_app_set()/fd_log_app() — round-trip
 *   - fd_log_wallclock_set() + custom clock — verify custom clock used
 *   - fd_log_private_1() with level >= 2 — verify stderr output emitted
 *   - fd_log_private_1() with level < 2 — verify no stderr output
 *
 * On non-Windows, this is a no-op stub. */

#include "fd_util.h"

#if FD_HAS_WINDOWS

/* fd_log_windows.c exports */
extern long fd_log_wallclock( void );
extern char *fd_log_wallclock_cstr( long now, char *buf );
extern void fd_log_private_boot( int *pargc, char **pargv );
extern void fd_log_private_app_set( char const *app );
extern char const *fd_log_app( void );
extern void fd_log_wallclock_set( fd_clock_func_t clock, void const *args );
extern char const *fd_log_private_0( char const *fmt, ... );
extern void fd_log_private_1( int level, long now, char const *file, int line,
                              char const *func, char const *msg );

/* Custom clock that returns a fixed value. */
static long
custom_clock( void const *args ) {
  (void)args;
  return 0x12345678L;
}

int
main( int argc, char **argv ) {
  fd_boot( &argc, &argv );

  /* Test 1: fd_log_wallclock() returns a valid timestamp */
  {
    long ts = fd_log_wallclock();
    FD_TEST( ts > 0 );
  }

  /* Test 2: fd_log_wallclock_cstr() produces correct format */
  {
    long ts = fd_log_wallclock();
    char buf[ 64 ];
    char *result = fd_log_wallclock_cstr( ts, buf );
    FD_TEST( result != NULL );
    FD_TEST( result == buf );
    /* Format: YYYY-MM-DD hh:mm:ss.NNNNNNNNN GMT ±HH */
    FD_TEST( strlen( buf ) >= 31 );
    FD_TEST( buf[0] == '2' ); /* year starts with '2' */
    FD_TEST( buf[4] == '-' );
    FD_TEST( buf[7] == '-' );
    FD_TEST( strncmp( buf + 26, " GMT", 4 ) == 0 );
  }

  /* Test 3: fd_log_private_0() formats a message */
  {
    char const *result = fd_log_private_0( "test %d %s", 42, "hello" );
    FD_TEST( result != NULL );
    FD_TEST( strlen( result ) > 0 );
  }

  /* Test 4: fd_log_private_boot() initializes state */
  {
    fd_log_private_boot( NULL, NULL );
    FD_TEST( fd_log_wallclock() > 0 ); /* clock function is set */
  }

  /* Test 5: fd_log_private_app_set()/fd_log_app() round-trip */
  {
    fd_log_private_boot( NULL, NULL );
    fd_log_private_app_set( "test_app" );
    char const *app = fd_log_app();
    FD_TEST( app != NULL );
    FD_TEST( strcmp( app, "test_app" ) == 0 );
  }

  /* Test 6: Custom clock function */
  {
    fd_log_private_boot( NULL, NULL );
    fd_log_wallclock_set( custom_clock, NULL );
    long ts = fd_log_wallclock();
    FD_TEST( ts == 0x12345678L );
  }

  /* Test 7: fd_log_private_1() with level >= 2 emits to stderr
   * and level < 2 does not.
   *
   * Strategy: redirect stderr to a pipe, call fd_log_private_1,
   * read pipe contents, verify expected output. */
  {
    /* Save original stderr fd */
    int saved_stderr = _dup( 2 );
    FD_TEST( saved_stderr >= 0 );

    /* Create pipe: read end = pipe_read, write end = pipe_write */
    HANDLE pipe_read;
    HANDLE pipe_write;
    FD_TEST( CreatePipe( &pipe_read, &pipe_write, NULL, 0 ) );

    /* Convert HANDLE -> osfhandle -> int fd for _dup2 */
    intptr_t os_pipe_write = _open_osfhandle( (intptr_t)pipe_write, _O_WRONLY );
    FD_TEST( os_pipe_write >= 0 );

    /* Redirect fd 2 (stderr) to our pipe */
    int rc = _dup2( (int)os_pipe_write, 2 );
    FD_TEST( rc == 0 );

    char const *test_file = "/tmp/test.c";
    char const *test_msg = "test message";

    /* Level 1 (INFO) — should NOT emit */
    fd_log_private_1( 1, 0L, test_file, 100, "test_func", test_msg );

    char pipe_buf[ 1024 ];
    DWORD bytes_read;
    /* Drain any leftover */
    ReadFile( pipe_read, pipe_buf, sizeof( pipe_buf ) - 1, &bytes_read, NULL );
    FD_TEST( bytes_read == 0 );

    /* Level 2 (NOTICE) — should emit */
    fd_log_private_1( 2, 0L, test_file, 101, "test_func", test_msg );

    ReadFile( pipe_read, pipe_buf, sizeof( pipe_buf ) - 1, &bytes_read, NULL );
    FD_TEST( bytes_read > 0 );
    pipe_buf[ bytes_read ] = '\0';
    FD_TEST( strstr( pipe_buf, "NOTICE" ) != NULL );
    FD_TEST( strstr( pipe_buf, "test.c" ) != NULL );
    FD_TEST( strstr( pipe_buf, "test message" ) != NULL );

    /* Restore original stderr */
    _dup2( saved_stderr, 2 );
    _close( saved_stderr );
    CloseHandle( pipe_read );
    CloseHandle( pipe_write );
  }

  FD_LOG_NOTICE(( "pass" ));
  fd_halt();
  return 0;
}

#else

/* On non-Windows, this file is a no-op stub. */
int
main( int argc, char **argv ) {
  (void)argc;
  (void)argv;
  return 0;
}

#endif
