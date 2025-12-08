#define _GNU_SOURCE
#include "fd_backtrace.h"
#include "../fd_util_base.h"
#include "../log/fd_log.h"
#include "../scratch/fd_scratch.h"

#include <unistd.h>
#include <string.h>
#include <dlfcn.h>
#include <link.h>
#include <stdio.h>

void
fd_backtrace_log( void ** addrs,
                  ulong   addrs_cnt ) {
  if( FD_UNLIKELY( !addrs_cnt ) ) return;

  typedef struct {
    void const * addr;
    char const * fname;
    char const * sname;
    void const * saddr;
    ulong       rel;
    int         have_info;
    int         binary_idx;
    char        sign;
    long        offset;
    char *      line; /* points into line_buf */
    int         has_line;
  } frame_t;

  frame_t * frames = fd_alloca( alignof(frame_t), addrs_cnt * sizeof(frame_t) );
  char const ** binaries = fd_alloca( alignof(char const *), addrs_cnt * sizeof(char const *) );
  ulong bin_cnt = 0UL;

  char * line_buf = fd_alloca( 1UL, addrs_cnt * 512UL );

  /* First pass: collect dladdr info and group frames by binary path. */
  for( ulong i=0UL; i<addrs_cnt; i++ ) {
    frames[ i ].addr      = addrs[ i ];
    frames[ i ].fname     = NULL;
    frames[ i ].sname     = NULL;
    frames[ i ].saddr     = NULL;
    frames[ i ].rel       = 0UL;
    frames[ i ].have_info = 0;
    frames[ i ].binary_idx= -1;
    frames[ i ].sign      = '+';
    frames[ i ].offset    = 0L;
    frames[ i ].line      = line_buf + 512UL * i;
    frames[ i ].line[0]   = '\0';
    frames[ i ].has_line  = 0;

    Dl_info info;
    void * _map = NULL;
    if( FD_UNLIKELY( !dladdr1( addrs[ i ], &info, &_map, RTLD_DL_LINKMAP ) ) ) continue;
    if( FD_UNLIKELY( !info.dli_fname || info.dli_fname[0]=='\0' ) ) continue;

    struct link_map * map = _map;
    info.dli_fbase = (void *)map->l_addr;
    if( FD_UNLIKELY( !info.dli_sname ) ) info.dli_saddr = info.dli_fbase;

    frames[ i ].have_info = 1;
    frames[ i ].fname     = info.dli_fname;
    frames[ i ].sname     = info.dli_sname;
    frames[ i ].saddr     = info.dli_saddr;
    frames[ i ].rel       = (ulong)((ulong)frames[ i ].addr - (ulong)info.dli_fbase);

    if( FD_UNLIKELY( !frames[ i ].sname && !frames[ i ].saddr ) ) {
      frames[ i ].sign   = '+';
      frames[ i ].offset = 0L;
    } else if( frames[ i ].addr >= frames[ i ].saddr ) {
      frames[ i ].sign   = '+';
      frames[ i ].offset = (long)( (ulong)frames[ i ].addr - (ulong)frames[ i ].saddr );
    } else {
      frames[ i ].sign   = '-';
      frames[ i ].offset = (long)( (ulong)frames[ i ].saddr - (ulong)frames[ i ].addr );
    }

    /* Track unique binaries. */
    int idx = -1;
    for( ulong j=0UL; j<bin_cnt; j++ ) {
      if( 0==strcmp( binaries[ j ], info.dli_fname ) ) { idx = (int)j; break; }
    }
    if( idx<0 ) { binaries[ bin_cnt ] = info.dli_fname; idx = (int)bin_cnt; bin_cnt++; }
    frames[ i ].binary_idx = idx;
  }

  /* Second pass: resolve file:line information with one addr2line
     invocation per binary. */
  ulong * frame_idx = fd_alloca( alignof(ulong), addrs_cnt * sizeof(ulong) );
  for( ulong b=0UL; b<bin_cnt; b++ ) {
    ulong frame_cnt = 0UL;
    for( ulong i=0UL; i<addrs_cnt; i++ ) {
      if( frames[ i ].binary_idx==(int)b ) frame_idx[ frame_cnt++ ] = i;
    }
    if( FD_UNLIKELY( !frame_cnt ) ) continue;

    /* Build command: addr2line -Cfpe <binary> <addr>... */
    ulong cmd_len = 17UL + strlen( binaries[ b ] ); /* base command */
    cmd_len += frame_cnt * 24UL; /* generous headroom per address */
    char * cmd = fd_alloca( 1UL, cmd_len + 1UL );
    char * cur = cmd;
    int   cur_len = snprintf( cur, cmd_len + 1UL, "addr2line -Cfpe %s", binaries[ b ] );
    if( FD_UNLIKELY( cur_len<0 || (ulong)cur_len>=cmd_len+1UL ) ) continue;
    cur += cur_len;
    cmd_len -= (ulong)cur_len;

    for( ulong j=0UL; j<frame_cnt; j++ ) {
      int n = snprintf( cur, cmd_len + 1UL, " %#lx", frames[ frame_idx[ j ] ].rel );
      if( FD_UNLIKELY( n<0 || (ulong)n>=cmd_len+1UL ) ) { cmd = NULL; break; }
      cur     += n;
      cmd_len -= (ulong)n;
    }

    if( FD_UNLIKELY( !cmd ) ) continue;

    FILE * fp = popen( cmd, "r" );
    if( FD_UNLIKELY( !fp ) ) continue;

    for( ulong j=0UL; j<frame_cnt; j++ ) {
      ulong idx = frame_idx[ j ];
      char * line = frames[ idx ].line;
      if( FD_UNLIKELY( !fgets( line, 512, fp ) ) ) break;
      ulong len = strnlen( line, 512 );
      while( len && (line[ len-1 ]=='\n' || line[ len-1 ]=='\r') ) line[ --len ] = '\0';
      frames[ idx ].has_line = 1;
    }

    pclose( fp );
  }

  /* Final pass: print frames with optional line information appended. */
  for( ulong i=0UL; i<addrs_cnt; i++ ) {
    frame_t * f = frames + i;
    char const * line_info = (f->has_line && f->line[0]) ? f->line : NULL;

    if( FD_LIKELY( f->have_info ) ) {
      if( FD_UNLIKELY( !f->sname && !f->saddr ) ) {
        fd_log_private_fprintf_0( STDERR_FILENO, "%s(%s) [%p]%s%s\n",
                                  f->fname ? f->fname : "", f->sname ? f->sname : "", f->addr,
                                  line_info ? " at " : "", line_info ? line_info : "" );
      } else {
        fd_log_private_fprintf_0( STDERR_FILENO, "%s(%s%c%#lx) [%p]%s%s\n",
                                  f->fname ? f->fname : "", f->sname ? f->sname : "",
                                  f->sign, (ulong)f->offset, f->addr,
                                  line_info ? " at " : "", line_info ? line_info : "" );
      }
    } else {
      fd_log_private_fprintf_0( STDERR_FILENO, "%p%s%s\n",
                                f->addr, line_info ? " at " : "", line_info ? line_info : "" );
    }
  }
}
