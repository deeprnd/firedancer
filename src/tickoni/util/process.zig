/// Generic monotonic clock, self-exe path resolution, and blocking sleep.
/// Cross-platform via os_api shim — unified API, platform-specific C code.
/// Linux: native syscalls in os.c
/// macOS: _NSGetExecutablePath + sysctl in os.c
const os_api = @import("os_api.zig");

pub const monotonicNanos = os_api.monotonicNanos;
pub const selfExePath = os_api.selfExePath;
pub const sleepNanos = os_api.sleepNanos;
