/* Thin wrappers around Firedancer utility lifecycle primitives. */

#include "../../../util/fd_util.h"

void tk_boot( int * pargc, char *** pargv ) { fd_boot( pargc, pargv ); }
void tk_halt( void ) { fd_halt(); }
