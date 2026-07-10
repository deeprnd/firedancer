/// Narrow Zig bindings over src/util/fd_util.h's fd_boot/fd_halt lifecycle.
///
/// Every process that touches fd_shmem/fd_wksp/fd_tango substrate (the v2.14
/// process-mode supervisor and every spawned tile) must call fd_boot exactly
/// once before using it and fd_halt once at shutdown; fd_boot is what reads
/// --shmem-path/FD_SHMEM_PATH and brings the shared-memory subsystem online
/// (src/util/shmem/fd_shmem_admin.c). Synthetic-argv boot policy lives in
/// src/tickoni/runtime/boot.zig, which calls boot() below.
extern fn tk_boot(pargc: *c_int, pargv: *[*][*:0]u8) void;
extern fn tk_halt() void;

pub fn boot(pargc: *c_int, pargv: *[*][*:0]u8) void {
    tk_boot(pargc, pargv);
}

pub fn halt() void {
    tk_halt();
}

/// Wraps FD_SPIN_PAUSE (src/util/fd_util_base.h): yields the calling logical
/// core for one bounded-poll iteration without a scheduler-visible yield.
/// Used between polls in hot mcache-consumer wait loops, matching the
/// FD_MCACHE_WAIT pattern in src/tango/mcache/fd_mcache.h.
extern fn tk_spin_pause() void;

pub fn spinPause() void {
    tk_spin_pause();
}
