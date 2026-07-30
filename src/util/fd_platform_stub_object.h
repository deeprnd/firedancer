#ifndef HEADER_fd_src_util_fd_platform_stub_object_h
#define HEADER_fd_src_util_fd_platform_stub_object_h

#include "fd_util.h"

FD_FN_CONST static inline ulong
fd_platform_stub_object_footprint( ulong align,
                                   ulong footprint ) {
  return fd_ulong_align_up( footprint, align );
}

static inline void *
fd_platform_stub_object_new( void * shmem,
                             ulong  align,
                             ulong  footprint ) {
  if( FD_UNLIKELY( !shmem ) ) return NULL;
  if( FD_UNLIKELY( !fd_ulong_is_aligned( (ulong)shmem, align ) ) ) return NULL;
  fd_memset( shmem, 0, footprint );
  return shmem;
}

static inline void *
fd_platform_stub_object_join( void * shobj,
                              ulong  align ) {
  if( FD_UNLIKELY( !shobj ) ) return NULL;
  if( FD_UNLIKELY( !fd_ulong_is_aligned( (ulong)shobj, align ) ) ) return NULL;
  return shobj;
}

static inline void *
fd_platform_stub_object_leave( void * obj ) {
  return obj;
}

static inline void *
fd_platform_stub_object_delete( void * shobj,
                                ulong  align ) {
  if( FD_UNLIKELY( !shobj ) ) return NULL;
  if( FD_UNLIKELY( !fd_ulong_is_aligned( (ulong)shobj, align ) ) ) return NULL;
  return shobj;
}

#endif /* HEADER_fd_src_util_fd_platform_stub_object_h */
