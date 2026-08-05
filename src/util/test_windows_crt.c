/* Test for windows_crt.c — verifies the CRT compat symbol exists
 * and has the expected value.
 *
 * windows_crt.c provides: int _fltused = 0;
 * This symbol is needed by the Windows CRT when float constants are
 * referenced. It's a trivial zero-initialized int, but linking
 * verification is still important.
 *
 * Built only on Windows (FD_HAS_WINDOWS) to match the platform
 * file pattern used elsewhere. */

#include "fd_util.h"

#if FD_HAS_WINDOWS

/* External declaration — links against windows_crt.c's definition */
extern int _fltused;

int
main( int     argc,
      char ** argv ) {
  fd_boot( &argc, &argv );

  /* Verify _fltused symbol exists and has the expected value.
   * The Windows CRT expects this to be defined; it's traditionally
   * set to 0 by the linker, but we explicitly set it here. */
  FD_TEST( _fltused == 0 );

  FD_LOG_NOTICE(( "pass" ));
  fd_halt();
  return 0;
}

#else

/* On non-Windows, this file is a no-op stub — the test only
 * runs on Windows where _fltused actually matters. */
int
main( int     argc,
      char ** argv ) {
  (void)argc;
  (void)argv;
  /* No test to run on this platform */
  return 0;
}

#endif
