/* Thin, non-inline wrappers around Firedancer functions. Zig binds only to
   Tickoni-owned `tk_*` symbols, regardless of whether the underlying
   Firedancer function is already exported or is `static inline`/macro-only.
   Each wrapper only calls the real Firedancer API; no algorithm lives here.
   Firedancer's own headers are not modified. See doc/knowledge/architecture.md. */

#include "../../../tango/mcache/fd_mcache.h"
#include "../../../tango/dcache/fd_dcache.h"
#include "../../../tango/fseq/fd_fseq.h"
#include "../../../tango/cnc/fd_cnc.h"
#include "../../../util/fd_util.h"
#include "../../../util/wksp/fd_wksp.h"
#include "../../../util/sandbox/fd_sandbox.h"

ulong tk_mcache_align( void ) { return fd_mcache_align(); }
ulong tk_mcache_footprint( ulong depth, ulong app_sz ) { return fd_mcache_footprint( depth, app_sz ); }
void * tk_mcache_new( void * shmem, ulong depth, ulong app_sz, ulong seq0 ) { return fd_mcache_new( shmem, depth, app_sz, seq0 ); }
fd_frag_meta_t * tk_mcache_join( void * shcache ) { return fd_mcache_join( shcache ); }
void * tk_mcache_leave( fd_frag_meta_t const * mcache ) { return fd_mcache_leave( mcache ); }
void * tk_mcache_delete( void * shcache ) { return fd_mcache_delete( shcache ); }
ulong tk_mcache_depth( fd_frag_meta_t const * mcache ) { return fd_mcache_depth( mcache ); }
ulong tk_mcache_seq0( fd_frag_meta_t const * mcache ) { return fd_mcache_seq0( mcache ); }
ulong * tk_mcache_seq_laddr( fd_frag_meta_t * mcache ) { return fd_mcache_seq_laddr( mcache ); }
ulong const * tk_mcache_seq_laddr_const( fd_frag_meta_t const * mcache ) { return fd_mcache_seq_laddr_const( mcache ); }

ulong
tk_mcache_line_idx( ulong seq,
                    ulong depth ) {
  return fd_mcache_line_idx( seq, depth );
}

void
tk_mcache_publish( fd_frag_meta_t * mcache,
                   ulong            depth,
                   ulong            seq,
                   ulong            sig,
                   ulong            chunk,
                   ulong            sz,
                   ulong            ctl,
                   ulong            tsorig,
                   ulong            tspub ) {
  fd_mcache_publish( mcache, depth, seq, sig, chunk, sz, ctl, tsorig, tspub );
}

ulong
tk_frag_meta_seq_query( fd_frag_meta_t const * meta ) {
  return fd_frag_meta_seq_query( meta );
}

ulong tk_dcache_slot_footprint( ulong mtu ) { return FD_DCACHE_SLOT_FOOTPRINT( mtu ); }
ulong tk_dcache_req_data_sz( ulong mtu, ulong depth, ulong burst, int compact ) { return fd_dcache_req_data_sz( mtu, depth, burst, compact ); }
ulong tk_dcache_align( void ) { return fd_dcache_align(); }
ulong tk_dcache_footprint( ulong data_sz, ulong app_sz ) { return fd_dcache_footprint( data_sz, app_sz ); }
void * tk_dcache_new( void * shmem, ulong data_sz, ulong app_sz ) { return fd_dcache_new( shmem, data_sz, app_sz ); }
uchar * tk_dcache_join( void * shdcache ) { return fd_dcache_join( shdcache ); }
void * tk_dcache_leave( uchar const * dcache ) { return fd_dcache_leave( dcache ); }
void * tk_dcache_delete( void * shdcache ) { return fd_dcache_delete( shdcache ); }
ulong tk_dcache_data_sz( uchar const * dcache ) { return fd_dcache_data_sz( dcache ); }
ulong tk_dcache_app_sz( uchar const * dcache ) { return fd_dcache_app_sz( dcache ); }
uchar * tk_dcache_app_laddr( uchar * dcache ) { return fd_dcache_app_laddr( dcache ); }
uchar const * tk_dcache_app_laddr_const( uchar const * dcache ) { return fd_dcache_app_laddr_const( dcache ); }
int tk_dcache_compact_is_safe( void const * base, void const * dcache, ulong mtu, ulong depth ) { return fd_dcache_compact_is_safe( base, dcache, mtu, depth ); }

ulong tk_fseq_align( void ) { return fd_fseq_align(); }
ulong tk_fseq_footprint( void ) { return fd_fseq_footprint(); }
void * tk_fseq_new( void * shmem, ulong seq0 ) { return fd_fseq_new( shmem, seq0 ); }
ulong * tk_fseq_join( void * shfseq ) { return fd_fseq_join( shfseq ); }
void * tk_fseq_leave( ulong const * fseq ) { return fd_fseq_leave( fseq ); }
void * tk_fseq_delete( void * shfseq ) { return fd_fseq_delete( shfseq ); }

ulong
tk_fseq_query( ulong const * fseq ) {
  return fd_fseq_query( fseq );
}

void
tk_fseq_update( ulong * fseq,
                 ulong   seq ) {
  fd_fseq_update( fseq, seq );
}

ulong tk_cnc_align( void ) { return fd_cnc_align(); }
ulong tk_cnc_footprint( ulong app_sz ) { return fd_cnc_footprint( app_sz ); }
void * tk_cnc_new( void * shmem, ulong app_sz, ulong cnc_type, long now ) { return fd_cnc_new( shmem, app_sz, cnc_type, now ); }
fd_cnc_t * tk_cnc_join( void * shcnc ) { return fd_cnc_join( shcnc ); }
void * tk_cnc_leave( fd_cnc_t const * cnc ) { return fd_cnc_leave( cnc ); }
void * tk_cnc_delete( void * shcnc ) { return fd_cnc_delete( shcnc ); }
int tk_cnc_open( fd_cnc_t * cnc ) { return fd_cnc_open( cnc ); }
ulong tk_cnc_wait( fd_cnc_t const * cnc, ulong test_signal, long dt, long * opt_now ) { return fd_cnc_wait( cnc, test_signal, dt, opt_now ); }
char const * tk_cnc_strerror( int err ) { return fd_cnc_strerror( err ); }
ulong tk_cstr_to_cnc_signal( char const * cstr ) { return fd_cstr_to_cnc_signal( cstr ); }
char * tk_cnc_signal_cstr( ulong signal, char * buf ) { return fd_cnc_signal_cstr( signal, buf ); }
void * tk_cnc_app_laddr( fd_cnc_t * cnc ) { return fd_cnc_app_laddr( cnc ); }
long tk_cnc_heartbeat_query( fd_cnc_t const * cnc ) { return fd_cnc_heartbeat_query( cnc ); }
void tk_cnc_heartbeat( fd_cnc_t * cnc, long now ) { fd_cnc_heartbeat( cnc, now ); }
ulong tk_cnc_signal_query( fd_cnc_t const * cnc ) { return fd_cnc_signal_query( cnc ); }
void tk_cnc_signal( fd_cnc_t * cnc, ulong signal ) { fd_cnc_signal( cnc, signal ); }
void tk_cnc_close( fd_cnc_t * cnc ) { fd_cnc_close( cnc ); }

void tk_boot( int * pargc, char *** pargv ) { fd_boot( pargc, pargv ); }
void tk_halt( void ) { fd_halt(); }

int tk_wksp_new_named( char const * name, ulong page_sz, ulong sub_cnt, ulong const * sub_page_cnt, ulong const * sub_cpu_idx, ulong mode, uint seed, ulong opt_part_max ) {
  return fd_wksp_new_named( name, page_sz, sub_cnt, sub_page_cnt, sub_cpu_idx, mode, seed, opt_part_max );
}
int tk_wksp_delete_named( char const * name ) { return fd_wksp_delete_named( name ); }
fd_wksp_t * tk_wksp_attach( char const * name ) { return fd_wksp_attach( name ); }
int tk_wksp_detach( fd_wksp_t * wksp ) { return fd_wksp_detach( wksp ); }
ulong tk_wksp_alloc_at_least( fd_wksp_t * wksp, ulong alignment, ulong sz, ulong tag, ulong * lo, ulong * hi ) { return fd_wksp_alloc_at_least( wksp, alignment, sz, tag, lo, hi ); }
ulong tk_wksp_alloc( fd_wksp_t * wksp, ulong alignment, ulong sz, ulong tag ) { return fd_wksp_alloc( wksp, alignment, sz, tag ); }
void tk_wksp_free( fd_wksp_t * wksp, ulong gaddr ) { fd_wksp_free( wksp, gaddr ); }
void * tk_wksp_laddr( fd_wksp_t const * wksp, ulong gaddr ) { return fd_wksp_laddr( wksp, gaddr ); }
ulong tk_wksp_gaddr( fd_wksp_t const * wksp, void const * laddr ) { return fd_wksp_gaddr( wksp, laddr ); }

int tk_sandbox_requires_cap_sys_admin( uint desired_uid, uint desired_gid ) { return fd_sandbox_requires_cap_sys_admin( desired_uid, desired_gid ); }
void tk_sandbox_enter( uint desired_uid,
                       uint desired_gid,
                       int keep_host_networking,
                       int allow_connect,
                       int allow_renameat,
                       int keep_controlling_terminal,
                       int dumpable,
                       ulong rlimit_file_cnt,
                       ulong rlimit_address_space,
                       ulong rlimit_data,
                       ulong rlimit_nproc,
                       ulong allowed_file_descriptor_cnt,
                       int const * allowed_file_descriptor,
                       ulong seccomp_filter_cnt,
                       void * seccomp_filter ) {
  fd_sandbox_enter( desired_uid,
                    desired_gid,
                    keep_host_networking,
                    allow_connect,
                    allow_renameat,
                    keep_controlling_terminal,
                    dumpable,
                    rlimit_file_cnt,
                    rlimit_address_space,
                    rlimit_data,
                    rlimit_nproc,
                    allowed_file_descriptor_cnt,
                    allowed_file_descriptor,
                    seccomp_filter_cnt,
                    seccomp_filter );
}
void tk_sandbox_switch_uid_gid( uint desired_uid, uint desired_gid ) { fd_sandbox_switch_uid_gid( desired_uid, desired_gid ); }
int tk_sandbox_getpid( void ) { return fd_sandbox_getpid(); }
int tk_sandbox_gettid( void ) { return fd_sandbox_gettid(); }
