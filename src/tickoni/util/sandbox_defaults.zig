const std = @import("std");
const linux_ids = @import("linux_ids.zig");
const sizes = @import("sizes.zig");

/// Unprivileged nobody uid/gid, used as the default sandbox identity.
pub const nobody_uid: u32 = linux_ids.nobody_uid;
pub const nobody_gid: u32 = linux_ids.nobody_gid;

/// Default cap on open file descriptors for a sandboxed tile.
pub const rlimit_file_cnt: u64 = 64;

/// Default virtual address-space cap for a sandboxed tile.
pub const rlimit_address_space: u64 = sizes.gib_1;

/// Minimum virtual address-space cap tests and callers may rely on.
pub const min_rlimit_address_space: u64 = sizes.mib_256;

/// Default resident data-segment cap for a sandboxed tile.
pub const rlimit_data: u64 = sizes.mib_256;

test "sandbox memory defaults use shared Tickoni byte-size constants" {
    try std.testing.expectEqual(sizes.gib_1, rlimit_address_space);
    try std.testing.expectEqual(sizes.mib_256, min_rlimit_address_space);
    try std.testing.expectEqual(sizes.mib_256, rlimit_data);
}

test "sandbox identity defaults use shared Linux identity constants" {
    try std.testing.expectEqual(linux_ids.nobody_uid, nobody_uid);
    try std.testing.expectEqual(linux_ids.nobody_gid, nobody_gid);
}
