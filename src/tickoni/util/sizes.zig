const std = @import("std");

/// Common binary byte-size constants used across Tickoni code.
pub const kib: u64 = 1024;
pub const mib: u64 = 1024 * kib;
pub const gib: u64 = 1024 * mib;

pub const mib_8: u64 = 8 * mib;
pub const mib_16: u64 = 16 * mib;
pub const mib_32: u64 = 32 * mib;
pub const mib_64: u64 = 64 * mib;
pub const mib_128: u64 = 128 * mib;
pub const mib_256: u64 = 256 * mib;
pub const mib_512: u64 = 512 * mib;

pub const gib_1: u64 = 1 * gib;
pub const gib_2: u64 = 2 * gib;
pub const gib_4: u64 = 4 * gib;
pub const gib_8: u64 = 8 * gib;

test "common binary byte-size constants cover the standard Tickoni range" {
    try std.testing.expectEqual(@as(u64, 8_388_608), mib_8);
    try std.testing.expectEqual(@as(u64, 268_435_456), mib_256);
    try std.testing.expectEqual(@as(u64, 1_073_741_824), gib_1);
    try std.testing.expectEqual(@as(u64, 8_589_934_592), gib_8);
}
