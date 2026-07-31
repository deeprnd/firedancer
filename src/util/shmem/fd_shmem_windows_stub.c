#include "fd_shmem.h"
#include "../fd_platform_runtime_caps.h"
#include <errno.h>

#if FD_HAS_WINDOWS

int
fd_cstr_to_shmem_lg_page_sz( char const * cstr ) {
  if( !cstr ) return FD_SHMEM_UNKNOWN_LG_PAGE_SZ;
  if( !fd_cstr_casecmp( cstr, "normal"   ) ) return FD_SHMEM_NORMAL_LG_PAGE_SZ;
  if( !fd_cstr_casecmp( cstr, "huge"     ) ) return FD_SHMEM_HUGE_LG_PAGE_SZ;
  if( !fd_cstr_casecmp( cstr, "gigantic" ) ) return FD_SHMEM_GIGANTIC_LG_PAGE_SZ;
  return FD_SHMEM_UNKNOWN_LG_PAGE_SZ;
}

char const *
fd_shmem_lg_page_sz_to_cstr( int lg_page_sz ) {
  switch( lg_page_sz ) {
  case FD_SHMEM_NORMAL_LG_PAGE_SZ:   return "normal";
  case FD_SHMEM_HUGE_LG_PAGE_SZ:     return "huge";
  case FD_SHMEM_GIGANTIC_LG_PAGE_SZ: return "gigantic";
  default:                           return "unknown";
  }
}

ulong
fd_cstr_to_shmem_page_sz( char const * cstr ) {
  if( !cstr ) return FD_SHMEM_UNKNOWN_PAGE_SZ;
  if( !fd_cstr_casecmp( cstr, "normal"   ) ) return FD_SHMEM_NORMAL_PAGE_SZ;
  if( !fd_cstr_casecmp( cstr, "huge"     ) ) return FD_SHMEM_HUGE_PAGE_SZ;
  if( !fd_cstr_casecmp( cstr, "gigantic" ) ) return FD_SHMEM_GIGANTIC_PAGE_SZ;
  return FD_SHMEM_UNKNOWN_PAGE_SZ;
}

char const *
fd_shmem_page_sz_to_cstr( ulong page_sz ) {
  switch( page_sz ) {
  case FD_SHMEM_NORMAL_PAGE_SZ:   return "normal";
  case FD_SHMEM_HUGE_PAGE_SZ:     return "huge";
  case FD_SHMEM_GIGANTIC_PAGE_SZ: return "gigantic";
  default:                        return "unknown";
  }
}

void *
fd_shmem_join( char const * name,
               int mode,
               int dump,
               fd_shmem_joinleave_func_t join_func,
               void * context,
               fd_shmem_join_info_t * opt_info ) {
  (void)name; (void)mode; (void)dump; (void)join_func; (void)context; (void)opt_info;
  FD_WINDOWS_RUNTIME_CAPS_LOG_WARNING( "fd_shmem_join" );
  return fd_windows_unsupported_null();
}

int
fd_shmem_leave( void * join,
                fd_shmem_joinleave_func_t leave_func,
                void * context ) {
  (void)join; (void)leave_func; (void)context;
  FD_WINDOWS_RUNTIME_CAPS_LOG_WARNING( "fd_shmem_leave" );
  return fd_windows_unsupported_enotsup();
}

int fd_shmem_join_query_by_name( char const * name, fd_shmem_join_info_t * opt_info ) { (void)name; (void)opt_info; return fd_windows_unsupported_enoent(); }
int fd_shmem_join_query_by_join( void const * join, fd_shmem_join_info_t * opt_info ) { (void)join; (void)opt_info; return fd_windows_unsupported_enoent(); }
int fd_shmem_join_query_by_addr( void const * addr, ulong sz, fd_shmem_join_info_t * opt_info ) { (void)addr; (void)sz; (void)opt_info; return fd_windows_unsupported_enoent(); }

int
fd_shmem_join_anonymous( char const * name,
                         int mode,
                         void * join,
                         void * mem,
                         ulong page_sz,
                         ulong page_cnt ) {
  (void)name; (void)mode; (void)join; (void)mem; (void)page_sz; (void)page_cnt;
  FD_WINDOWS_RUNTIME_CAPS_LOG_WARNING( "fd_shmem_join_anonymous" );
  return fd_windows_unsupported_enotsup();
}

int
fd_shmem_leave_anonymous( void * join,
                          fd_shmem_join_info_t * opt_info ) {
  (void)join; (void)opt_info;
  FD_WINDOWS_RUNTIME_CAPS_LOG_WARNING( "fd_shmem_leave_anonymous" );
  return fd_windows_unsupported_enotsup();
}

ulong fd_shmem_numa_cnt( void ) { return fd_windows_runtime_caps_singleton_cnt(); }
ulong fd_shmem_cpu_cnt ( void ) { return fd_windows_runtime_caps_singleton_cnt(); }
ulong fd_shmem_numa_idx( ulong cpu_idx ) { return fd_windows_runtime_caps_singleton_idx( cpu_idx ); }
ulong fd_shmem_cpu_idx ( ulong numa_idx ) { return fd_windows_runtime_caps_singleton_idx( numa_idx ); }
int fd_shmem_numa_validate( void const * mem, ulong page_sz, ulong page_cnt, ulong cpu_idx ) { (void)mem; (void)page_sz; (void)page_cnt; (void)cpu_idx; return 0; }

int
fd_shmem_create_multi( char const * name,
                       ulong page_sz,
                       ulong sub_cnt,
                       ulong const * sub_page_cnt,
                       ulong const * sub_cpu_idx,
                       ulong mode ) {
  (void)name; (void)page_sz; (void)sub_cnt; (void)sub_page_cnt; (void)sub_cpu_idx; (void)mode;
  FD_WINDOWS_RUNTIME_CAPS_LOG_WARNING( "fd_shmem_create_multi" );
  return fd_windows_unsupported_enotsup();
}

int
fd_shmem_update_multi( char const * name,
                       ulong page_sz,
                       ulong sub_cnt,
                       ulong const * sub_page_cnt,
                       ulong const * sub_cpu_idx,
                       ulong mode ) {
  (void)name; (void)page_sz; (void)sub_cnt; (void)sub_page_cnt; (void)sub_cpu_idx; (void)mode;
  FD_WINDOWS_RUNTIME_CAPS_LOG_WARNING( "fd_shmem_update_multi" );
  return fd_windows_unsupported_enotsup();
}

int fd_shmem_unlink( char const * name, ulong page_sz ) { (void)name; (void)page_sz; return fd_windows_unsupported_enotsup(); }
int fd_shmem_info( char const * name, ulong page_sz, fd_shmem_info_t * opt_info ) { (void)name; (void)page_sz; (void)opt_info; return fd_windows_unsupported_enoent(); }
void * fd_shmem_acquire_multi( ulong page_sz, ulong sub_cnt, ulong const * sub_page_cnt, ulong const * sub_cpu_idx ) { (void)page_sz; (void)sub_cnt; (void)sub_page_cnt; (void)sub_cpu_idx; return fd_windows_unsupported_null(); }
int fd_shmem_release( void * mem, ulong page_sz, ulong page_cnt ) { (void)mem; (void)page_sz; (void)page_cnt; return fd_windows_unsupported_enotsup(); }

ulong
fd_shmem_name_len( char const * name ) {
  if( FD_UNLIKELY( !name ) ) return 0UL;
  ulong len = strlen( name );
  return ((0UL<len) & (len<FD_SHMEM_NAME_MAX)) ? len : 0UL;
}

fd_shmem_join_info_t const * fd_shmem_iter_begin( void ) { return NULL; }
fd_shmem_join_info_t const * fd_shmem_iter_next( fd_shmem_join_info_t const * iter ) { (void)iter; return NULL; }

void
fd_shmem_private_boot( int * pargc,
                       char *** pargv ) {
  FD_LOG_INFO(( "fd_shmem: booting" ));
  (void)fd_env_strip_cmdline_cstr( pargc, pargv, "--shmem-path", "FD_SHMEM_PATH", "/mnt/.fd" );
  FD_LOG_INFO(( "fd_shmem: --shmem-path (ignored on Windows build lane)" ));
  FD_LOG_INFO(( "fd_shmem: boot success" ));
}

void
fd_shmem_private_halt( void ) {
  FD_LOG_INFO(( "fd_shmem: halting" ));
  FD_LOG_INFO(( "fd_shmem: halt success" ));
}

#endif
