#ifndef HEADER_fd_src_waltz_mib_fd_seqlock_h
#define HEADER_fd_src_waltz_mib_fd_seqlock_h

#include "../../util/fd_util_base.h"
#include <stdatomic.h>

typedef _Atomic( ulong ) fd_seqlock_t;

static inline void
fd_seqlock_init( fd_seqlock_t * lock ) {
  atomic_store_explicit( lock, (ulong)0, memory_order_release );
}

static inline void
fd_seqlock_write_lock( fd_seqlock_t * lock ) {
  for(;;) {
    ulong seq = atomic_load_explicit( lock, memory_order_relaxed );
    if( FD_UNLIKELY( seq & 1UL ) ) continue;
    if( FD_LIKELY( atomic_compare_exchange_weak_explicit( lock, &seq, seq+1UL, memory_order_acquire, memory_order_relaxed ) ) ) {
      return;
    }
  }
}

static inline void
fd_seqlock_write_unlock( fd_seqlock_t * lock ) {
  atomic_fetch_add_explicit( lock, (ulong)1, memory_order_release );
}

static inline ulong
fd_seqlock_read_try( fd_seqlock_t const * lock ) {
  for(;;) {
    ulong seq = atomic_load_explicit( lock, memory_order_acquire );
    if( FD_LIKELY( !(seq & 1UL) ) ) return seq;
  }
}

static inline int
fd_seqlock_read_test( fd_seqlock_t const * lock,
                      ulong               seq ) {
  atomic_thread_fence( memory_order_acquire );
  return atomic_load_explicit( lock, memory_order_acquire )==seq;
}

static inline int
fd_seqlock_locked_hint( fd_seqlock_t const * lock ) {
  return atomic_load_explicit( lock, memory_order_relaxed ) & 1UL;
}

#endif /* HEADER_fd_src_waltz_mib_fd_seqlock_h */
