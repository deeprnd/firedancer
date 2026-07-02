/* Thin, non-inline wrappers around Firedancer Tango functions declared
   `static inline` in their headers, so Zig's `extern fn` has a real symbol
   to bind to. Each wrapper only calls the real inline function; no
   algorithm lives in this file. Firedancer's own headers are not modified.
   See doc/knowledge/architecture.md. */

#include "../../../tango/mcache/fd_mcache.h"
#include "../../../tango/fseq/fd_fseq.h"

ulong
tickoni_mcache_line_idx( ulong seq,
                          ulong depth ) {
  return fd_mcache_line_idx( seq, depth );
}

void
tickoni_mcache_publish( fd_frag_meta_t * mcache,
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
tickoni_frag_meta_seq_query( fd_frag_meta_t const * meta ) {
  return fd_frag_meta_seq_query( meta );
}

ulong
tickoni_fseq_query( ulong const * fseq ) {
  return fd_fseq_query( fseq );
}

void
tickoni_fseq_update( ulong * fseq,
                      ulong   seq ) {
  fd_fseq_update( fseq, seq );
}
