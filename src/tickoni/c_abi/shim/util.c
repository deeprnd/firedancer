/* Thin wrappers around Firedancer utility lifecycle primitives. */

#include "../../../util/fd_util.h"

void tk_boot( int * pargc, char *** pargv ) { fd_boot( pargc, pargv ); }
void tk_halt( void ) { fd_halt(); }

/* Yields the calling logical core for one bounded-poll iteration without
   giving up the CPU to the scheduler, per fd_util_base.h FD_SPIN_PAUSE. */
void tk_spin_pause( void ) { FD_SPIN_PAUSE(); }
