const std = @import("std");

/// Fixed-size, POD handle set embeddable directly in
/// src/tickoni/runtime/launch_spec.zig's LaunchSpec.
pub const LinkHandles = struct {
    mcache_gaddr: usize = 0,
    dcache_gaddr: usize = 0,
    fseq_gaddr: usize = 0,
    depth: usize = 0,
    mtu: usize = 0,
};

test "LinkHandles defaults to zeroed/empty" {
    const h = LinkHandles{};
    try std.testing.expectEqual(@as(usize, 0), h.mcache_gaddr);
    try std.testing.expectEqual(@as(usize, 0), h.depth);
}
