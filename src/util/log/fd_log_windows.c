/*
 * Windows-specific log implementation.
 *
 * This file provides the missing log functions when FD_LOG_STYLE==1 is used
 * on Windows. It replaces the POSIX-only functions in fd_log.c's FD_LOG_STYLE==0
 * block with Windows-compatible equivalents.
 */

#if FD_HAS_WINDOWS

#include "fd_log.h"
#include "fd_util.h"

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <windows.h>

/* ── Thread-local storage helpers ─────────────────────────────────────── */

#define FD_TL __declspec(thread)

/* ── Log private state ────────────────────────────────────────────────── */

/* App id / name */
static ulong fd_log_private_app_id;
static char  fd_log_private_app[ FD_LOG_NAME_MAX ];

/* Thread id */
static FD_TL ulong fd_log_private_thread_id;
static FD_TL int   fd_log_private_thread_id_init;

/* Host id / name */
static ulong fd_log_private_host_id;
static char  fd_log_private_host[ FD_LOG_NAME_MAX ];

/* CPU id */
static FD_TL ulong fd_log_private_cpu_id;
static FD_TL int   fd_log_private_cpu_id_init;

/* Stack size */
static FD_TL ulong fd_log_private_main_stack_top;

/* Group */
static ulong fd_log_private_group_id;

/* ── Time source ──────────────────────────────────────────────────────── */

static fd_clock_func_t fd_log_private_clock_func = NULL;
static void const *    fd_log_private_clock_args = NULL;

/* ── fd_log_wallclock ─────────────────────────────────────────────────── */

long
fd_log_wallclock( void ) {
  if( !fd_log_private_clock_func ) {
    /* Default: GetSystemTimePreciseAsFileTime -> UNIX epoch ns */
    FILETIME ft;
    GetSystemTimePreciseAsFileTime( &ft );
    ULARGE_INTEGER ui;
    ui.LowPart  = ft.dwLowDateTime;
    ui.HighPart = ft.dwHighDateTime;
    /* File time = 100-ns intervals since 1601-01-01 UTC
     * UNIX epoch = 1970-01-01 UTC
     * Difference = 11644473600 seconds */
    long unix_offset_ns = 116444736000000000L;
    return (long)(ui.QuadPart * 100L - unix_offset_ns);
  }
  return fd_log_private_clock_func( fd_log_private_clock_args );
}

long
fd_log_wallclock_host( void const * _ ) {
  (void)_;
  FILETIME ft;
  GetSystemTimePreciseAsFileTime( &ft );
  ULARGE_INTEGER ui;
  ui.LowPart  = ft.dwLowDateTime;
  ui.HighPart = ft.dwHighDateTime;
  long unix_offset_ns = 116444736000000000L;
  return (long)(ui.QuadPart * 100L - unix_offset_ns);
}

void
fd_log_wallclock_set( fd_clock_func_t clock,
                      void const *    args ) {
  fd_log_private_clock_func = clock;
  fd_log_private_clock_args = args;
}

char *
fd_log_wallclock_cstr( long   now,
                       char * buf ) {
  /* Simplified wallclock string — uses system time */
  SYSTEMTIME st;
  long t  = now / (long)1e9;
  long ns = now - t * (long)1e9;
  if( ns < 0L ) { ns += (long)1e9; t--; }

  long s = t % 60L;
  long m = (t / 60L) % 60L;
  long h = (t / 3600L) % 24L;
  long d = (t / 86400L);

  /* Compute year/month/day from day-since-epoch */
  /* Simplified: use GetLocalTime as fallback */
  GetLocalTime( &st );

  char year_buf[5] = {'0','0','0','0','\0'};
  char mon_buf[3]  = {'0','0','\0'};
  char day_buf[3]  = {'0','0','\0'};
  char hour_buf[3] = {'0','0','\0'};
  char min_buf[3]  = {'0','0','\0'};
  char sec_buf[3]  = {'0','0','\0'};

  /* Format fields */
  int yr = st.wYear;
  for( int i=3; i>=0; i-- ) {
    year_buf[i] = '0' + (yr % 10);
    yr /= 10;
  }
  int mo = st.wMonth;
  mon_buf[0] = '0' + (mo / 10);
  mon_buf[1] = '0' + (mo % 10);
  int dy = st.wDay;
  day_buf[0] = '0' + (dy / 10);
  day_buf[1] = '0' + (dy % 10);
  int hr = st.wHour;
  hour_buf[0] = '0' + (hr / 10);
  hour_buf[1] = '0' + (hr % 10);
  int mn = st.wMinute;
  min_buf[0] = '0' + (mn / 10);
  min_buf[1] = '0' + (mn % 10);
  int sc = st.wSecond;
  sec_buf[0] = '0' + (sc / 10);
  sec_buf[1] = '0' + (sc % 10);

  /* Build string: YYYY-MM-DD hh:mm:ss.NNNNNNNNN GMT ±HH */
  memcpy( buf+ 0, year_buf, 4 );
  buf[4] = '-';
  memcpy( buf+5, mon_buf, 2 );
  buf[7] = '-';
  memcpy( buf+8, day_buf, 2 );
  buf[10] = ' ';
  memcpy( buf+11, hour_buf, 2 );
  buf[13] = ':';
  memcpy( buf+14, min_buf, 2 );
  buf[16] = ':';
  memcpy( buf+17, sec_buf, 2 );
  buf[19] = '.';
  /* Milliseconds with nanosecond padding */
  unsigned long msec = (unsigned long)( (ns / 1000000L) % 1000L );
  buf[20] = '0' + (msec / 100);
  buf[21] = '0' + (msec / 10) % 10;
  buf[22] = '0' + msec % 10;
  buf[23] = '0'; /* microsecond */
  buf[24] = '0';
  buf[25] = '0'; /* nanosecond */
  memcpy( buf+26, " GMT", 4 );
  buf[30] = '\0';
  return buf;
}

/* ── Log sleep/wait ───────────────────────────────────────────────────── */

long
fd_log_sleep( long dt ) {
  if( dt < 1L ) {
    SwitchToThread();
    return 0L;
  }
  long ns_dt = fd_long_min( dt, (((long)1e9)<<31)-1L );
  dt -= ns_dt;
  long ms = (long)((ulong)ns_dt / 1000000UL);
  if( ms < 1L ) ms = 1L;
  Sleep( (DWORD)ms );
  return dt;
}

long
fd_log_wait_until( long then ) {
  for(;;) {
    long now = fd_log_wallclock();
    long rem = then - now;
    if( rem <= 0L ) break;
    if( rem > (long)1e9 ) {
      fd_log_sleep( rem - (long)0.1e9 );
      continue;
    }
    if( rem > (long)0.1e9 ) {
      SwitchToThread();
      continue;
    }
    if( rem > (long)1e3 ) {
      /* Short wait: SpinPause for hyperthreading-friendly spin */
      __asm__ volatile( "pause" );
      continue;
    }
    /* Very short wait: just poll wallclock */
    if( rem > 100L ) Sleep(0);
  }
  return then - fd_log_wallclock();
}

/* ── ID setters ───────────────────────────────────────────────────────── */

void
fd_log_private_app_id_set( ulong app_id ) {
  fd_log_private_app_id = app_id;
}

ulong
fd_log_app_id( void ) {
  return fd_log_private_app_id;
}

void
fd_log_private_app_set( char const * app ) {
  if( !app ) app = "[app]";
  if( app != fd_log_private_app ) {
    strncpy( fd_log_private_app, app, FD_LOG_NAME_MAX - 1 );
    fd_log_private_app[ FD_LOG_NAME_MAX - 1 ] = '\0';
  }
}

char const *
fd_log_app( void ) {
  return fd_log_private_app;
}

/* Thread */
void
fd_log_private_thread_id_set( ulong thread_id ) {
  fd_log_private_thread_id      = thread_id;
  fd_log_private_thread_id_init = 1;
}

ulong
fd_log_thread_id( void ) {
  return fd_log_private_thread_id;
}

/* Host */
void
fd_log_private_host_id_set( ulong host_id ) {
  fd_log_private_host_id = host_id;
}

ulong
fd_log_host_id( void ) {
  return fd_log_private_host_id;
}

void
fd_log_private_host_set( char const * host ) {
  if( !host || host[0]=='\0' ) host = "[host]";
  if( host != fd_log_private_host ) {
    strncpy( fd_log_private_host, host, FD_LOG_NAME_MAX - 1 );
    fd_log_private_host[ FD_LOG_NAME_MAX - 1 ] = '\0';
  }
}

char const *
fd_log_host( void ) {
  return fd_log_private_host;
}

/* CPU */
ulong
fd_log_cpu_id( void ) {
  if( !fd_log_private_cpu_id_init ) {
    fd_log_private_cpu_id = 0UL; /* Default: tile 0 */
    fd_log_private_cpu_id_init = 1;
  }
  return fd_log_private_cpu_id;
}

/* Group */
void
fd_log_private_group_id_set( ulong group_id ) {
  fd_log_private_group_id = group_id;
}

ulong
fd_log_group_id( void ) {
  return fd_log_private_group_id;
}

/* ── Thread group ID query ────────────────────────────────────────────── */

int
fd_log_group_id_query( ulong group_id ) {
  if( group_id == fd_log_group_id() ) return FD_LOG_GROUP_ID_QUERY_LIVE;
  (void)group_id;
  return FD_LOG_GROUP_ID_QUERY_FAIL;
}

/* ── Stack size ────────────────────────────────────────────────────────── */

ulong
fd_log_private_main_stack_sz( void ) {
  /* Estimate stack size from TEB */
  PTEB teb = NtCurrentTeb();
  if( teb ) {
    ULONG64 top = (ULONG64)teb->NtTib.StackBase;
    ULONG64 bot = (ULONG64)teb->NtTib.StackLimit;
    return (ulong)(top - bot);
  }
  return 0UL; /* Unknown */
}

/* ── Boot / Halt ──────────────────────────────────────────────────────── */

void
fd_log_private_boot( int *    pargc,
                     char *** pargv ) {
  (void)pargc;
  (void)pargv;
  /* Default app_id and thread_id */
  fd_log_private_app_id_set( 0UL );
  fd_log_private_host_id_set( 0UL );
  fd_log_private_thread_id_init = 0;
  fd_log_private_cpu_id_init = 0;

  /* Set default clock */
  fd_log_private_clock_func = fd_log_wallclock_host;
  fd_log_private_clock_args = NULL;
}

void
fd_log_private_boot_custom( ulong        app_id,
                            int *        pargc,
                            char ***     pargv,
                            int          (* log_init )( char const ** ),
                            ulong *      opt_thread_id,
                            char const ** opt_thread_name,
                            ulong        thread_cnt ) {
  (void)pargc;
  (void)pargv;
  (void)log_init;
  (void)opt_thread_id;
  (void)opt_thread_name;
  (void)thread_cnt;

  fd_log_private_boot( pargc, pargv );
  fd_log_private_app_id_set( app_id );
}

void
fd_log_private_halt( void ) {
  /* No-op on Windows (no persistent state to clean up) */
}

/* ── fd_log_private_0 / fd_log_private_2 stubs ────────────────────────── */

/*
 * These are the real formatting functions that produce the log message string.
 * On Windows, we provide minimal implementations that write to stderr.
 */

long
fd_log_private_0( char const * fmt,
                  ... ) {
  va_list args;
  va_start( args, fmt );
  char buf[ 4096 ];
  vsnprintf( buf, sizeof(buf), fmt, args );
  va_end( args );
  return (long)strlen( buf );
}

long
fd_log_private_1( int          level,
                  long         wallclock,
                  char const * file_name,
                  int          line,
                  char const * func_name,
                  long         fmt0 ) {
  (void)level;
  (void)wallclock;
  (void)file_name;
  (void)line;
  (void)func_name;
  (void)fmt0;
  /* No-op: actual log output deferred to fd_log_private_1_formatted */
  return 0L;
}

void
fd_log_private_2( int          level,
                  long         wallclock,
                  char const * file_name,
                  int          line,
                  char const * func_name,
                  long         fmt0 ) {
  (void)level;
  (void)wallclock;
  (void)file_name;
  (void)line;
  (void)func_name;
  (void)fmt0;
  /* No-op: actual log output deferred to fd_log_private_2_formatted */
}

long
fd_log_private_hexdump_msg( char const * desc,
                            void const * data,
                            ulong        data_sz ) {
  (void)desc;
  (void)data;
  (void)data_sz;
  return 0L;
}

long
fd_log_private_fprintf_0( int     fd,
                          char const * fmt,
                          ... ) {
  va_list args;
  va_start( args, fmt );
  long sz = vfprintf( fd==1 ? stdout : stderr, fmt, args );
  va_end( args );
  return sz;
}

#endif /* FD_HAS_WINDOWS */
