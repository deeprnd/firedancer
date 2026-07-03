/// Bounded-poll wait tuning shared by the reliable link Producer/Consumer,
/// replacing an unconditional fixed nanosleep on every miss.
///
/// Matches src/tango/mcache/fd_mcache.h's FD_MCACHE_WAIT convention for the
/// fast path: spin-pause (FD_SPIN_PAUSE, wrapped as c_abi.boot.spinPause)
/// between polls instead of sleeping, so a fragment that arrives within the
/// spin budget is picked up with no sleep latency.
///
/// Deliberate deviation from Firedancer once the spin budget is exhausted:
/// FD_MCACHE_WAIT times out and returns control to the caller's own run
/// loop on an isolated, pinned core. Tickoni's process/thread-mode tiles are
/// not core-isolated (thread-mode topologies run many tiles as ordinary
/// threads on shared cores), so spinning unbounded while genuinely idle
/// would peg a core per idle link. Once poll_max is exhausted this loop
/// falls back to a bounded sleep before re-entering the spin phase, which
/// is also the housekeeping/stop-check point.
pub const spin_poll_max: u32 = 4096;
pub const idle_sleep_ns: u64 = 100_000;
