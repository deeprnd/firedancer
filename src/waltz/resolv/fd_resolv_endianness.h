#ifndef HEADER_fd_src_waltz_resolv_fd_resolv_endianness_h
#define HEADER_fd_src_waltz_resolv_fd_resolv_endianness_h

#include "../../util/fd_util_base.h"

/* Portable endian byte-order helper.
 *
 * On Linux: includes <endian.h> for byteorder macros.
 * On macOS: includes <machine/endian.h>. */

#if FD_HAS_LINUX
#include <endian.h>
#else
#include <machine/endian.h>
#endif

#endif /* HEADER_fd_src_waltz_resolv_fd_resolv_endianness_h */
