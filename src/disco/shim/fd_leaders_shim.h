/* fd_leaders_shim.h — Shim for epoch leader schedule functions.
   Provides fd_epoch_leaders_{footprint,new,join,leave,delete} and
   compute_id_weights_from_vote_weights without pulling in flamenco.

   Includes fd_leaders.h for type declarations and constants, then
   provides function definitions in fd_leaders_shim.c to satisfy
   libfd_flamenco.a's empty symbol set.
*/
#ifndef FD_LEADERS_SHIM_H
#define FD_LEADERS_SHIM_H

#include "../../flamenco/leaders/fd_leaders.h"

#endif /* FD_LEADERS_SHIM_H */
