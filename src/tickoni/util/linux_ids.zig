const std = @import("std");

/// Conventional Linux nobody uid/gid used for least-privilege tile identity.
pub const nobody_uid: u32 = 65534;
pub const nobody_gid: u32 = 65534;

test "nobody uid and gid share the conventional Linux id" {
    try std.testing.expectEqual(nobody_uid, nobody_gid);
    try std.testing.expectEqual(@as(u32, 65534), nobody_uid);
}
