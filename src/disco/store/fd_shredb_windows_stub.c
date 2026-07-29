#include "fd_shredb.h"

#if FD_HAS_WINDOWS

FD_FN_CONST ulong
fd_shredb_footprint( ulong max_size_gib ) {
  if( FD_UNLIKELY( !max_size_gib ) ) return 0UL;
  return fd_ulong_align_up( sizeof(fd_shredb_t), fd_shredb_align() );
}

void *
fd_shredb_new( void       * shmem,
               ulong        max_size_gib,
               char const * file_path,
               ulong        seed ) {
  (void)max_size_gib; (void)file_path; (void)seed;

  if( FD_UNLIKELY( !shmem ) ) {
    FD_LOG_WARNING(( "NULL shmem" ));
    return NULL;
  }

  if( FD_UNLIKELY( !fd_ulong_is_aligned( (ulong)shmem, fd_shredb_align() ) ) ) {
    FD_LOG_WARNING(( "misaligned shmem" ));
    return NULL;
  }

  fd_shredb_t * store = (fd_shredb_t *)shmem;
  fd_memset( store, 0, sizeof(fd_shredb_t) );
  store->fd = -1;
  return shmem;
}

fd_shredb_t *
fd_shredb_join( void * shstore ) {
  if( FD_UNLIKELY( !shstore ) ) {
    FD_LOG_WARNING(( "NULL shstore" ));
    return NULL;
  }

  if( FD_UNLIKELY( !fd_ulong_is_aligned( (ulong)shstore, fd_shredb_align() ) ) ) {
    FD_LOG_WARNING(( "misaligned shstore" ));
    return NULL;
  }

  return (fd_shredb_t *)shstore;
}

void *
fd_shredb_leave( fd_shredb_t const * store ) {
  if( FD_UNLIKELY( !store ) ) {
    FD_LOG_WARNING(( "NULL store" ));
    return NULL;
  }
  return (void *)store;
}

void *
fd_shredb_delete( void * shstore ) {
  if( FD_UNLIKELY( !shstore ) ) {
    FD_LOG_WARNING(( "NULL shstore" ));
    return NULL;
  }

  if( FD_UNLIKELY( !fd_ulong_is_aligned( (ulong)shstore, fd_shredb_align() ) ) ) {
    FD_LOG_WARNING(( "misaligned shstore" ));
    return NULL;
  }

  return shstore;
}

void
fd_shredb_insert( fd_shredb_t * store,
                  fd_shred_t const * shred ) {
  (void)store; (void)shred;
}

int
fd_shredb_query( fd_shredb_t * store,
                 ulong         slot,
                 uint          shred_idx,
                 uchar         out[ FD_SHRED_MAX_SZ ] ) {
  (void)store; (void)slot; (void)shred_idx; (void)out;
  return -1;
}

int
fd_shredb_query_highest( fd_shredb_t * store,
                         ulong         slot,
                         uint          min_shred_idx,
                         uchar         out[ FD_SHRED_MAX_SZ ] ) {
  (void)store; (void)slot; (void)min_shred_idx; (void)out;
  return -1;
}

#endif
