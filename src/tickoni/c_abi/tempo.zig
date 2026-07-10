/// Narrow Zig bindings over src/tango/tempo/fd_tempo.h.
///
/// Tickoni uses only the housekeeping-scheduler helpers needed by v2.14.S8.T13.
/// The shim hides Firedancer's fd_rng_t requirement for async_reload behind a
/// thread-local RNG, so Zig callers stay on the Tickoni-owned `tk_*` surface.
const std = @import("std");

extern fn tk_tempo_tick_per_ns(opt_sigma: ?*f64) f64;
extern fn tk_tempo_lazy_default(cr_max: usize) i64;
extern fn tk_tempo_async_min(lazy: i64, event_cnt: usize, tick_per_ns: f32) usize;
extern fn tk_tempo_async_reload(async_min: usize) usize;

pub fn tickPerNs(opt_sigma: ?*f64) f64 {
    return tk_tempo_tick_per_ns(opt_sigma);
}

pub fn lazyDefault(cr_max: usize) i64 {
    return tk_tempo_lazy_default(cr_max);
}

pub fn asyncMin(lazy: i64, event_cnt: usize, tick_per_ns: f32) usize {
    return tk_tempo_async_min(lazy, event_cnt, tick_per_ns);
}

pub fn asyncReload(async_min: usize) usize {
    return tk_tempo_async_reload(async_min);
}

test "lazyDefault matches the documented formula for small cr_max" {
    try std.testing.expectEqual(@as(i64, 1), lazyDefault(0));
    try std.testing.expectEqual(@as(i64, 3), lazyDefault(1));
    try std.testing.expectEqual(@as(i64, 10), lazyDefault(4));
}

test "asyncMin returns a power of two for a valid scheduler configuration" {
    const value = asyncMin(225, 1, 1.0);
    try std.testing.expect(value > 0);
    try std.testing.expect(std.math.isPowerOfTwo(value));
}

test "asyncReload stays within the expected range" {
    const async_min: usize = 64;
    const value = asyncReload(async_min);
    try std.testing.expect(value >= async_min);
    try std.testing.expect(value < (2 * async_min));
}
