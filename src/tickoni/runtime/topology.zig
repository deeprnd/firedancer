const std = @import("std");

/// Six-character runtime ID for a tile (matches the fd_topo char name[7] constraint).
pub const TileId = struct {
    bytes: [6]u8 = [_]u8{0} ** 6,

    pub fn parse(s: []const u8) error{TileIdTooLong}!TileId {
        if (s.len > 6) return error.TileIdTooLong;
        var id = TileId{};
        @memcpy(id.bytes[0..s.len], s);
        return id;
    }

    pub fn slice(self: *const TileId) []const u8 {
        const end = std.mem.indexOfScalar(u8, &self.bytes, 0) orelse 6;
        return self.bytes[0..end];
    }

    pub fn eql(self: TileId, other: TileId) bool {
        return std.mem.eql(u8, &self.bytes, &other.bytes);
    }
};

/// Static description of one tile in a topology.
pub const TileDescriptor = struct {
    id: TileId,
    /// Human-readable name used in logs and diagnostics.
    name: []const u8,
    /// Phase from the tile plan: 0=core, 1=case, 2=agent, 3=api, 4=exec.
    phase: u8,
};

/// Directed channel between two tiles: exactly one producer, one consumer.
pub const Channel = struct {
    src_idx: u32,
    dst_idx: u32,
    /// Ring-buffer depth — must be a power of two.
    depth: u32,
    /// Max fragment size in bytes; 0 means no dcache.
    mtu: u32,
};

/// Immutable snapshot of all tiles and channels in a topology.
pub const Topology = struct {
    tiles: []const TileDescriptor,
    channels: []const Channel,

    pub fn validate(self: Topology) !void {
        for (self.tiles) |t| {
            if (t.id.slice().len == 0) return error.EmptyTileId;
        }
        for (self.channels) |ch| {
            if (ch.src_idx >= self.tiles.len) return error.ChannelSrcOutOfRange;
            if (ch.dst_idx >= self.tiles.len) return error.ChannelDstOutOfRange;
            if (ch.src_idx == ch.dst_idx) return error.ChannelSelfLoop;
            if (ch.depth == 0 or !std.math.isPowerOfTwo(ch.depth)) return error.ChannelDepthNotPowerOfTwo;
        }
    }
};

// Static backing arrays for paymentPipeline — avoids returning pointers to
// stack-allocated data.
const payment_tiles = [_]TileDescriptor{
    .{ .id = TileId.parse("tkings") catch unreachable, .name = "ingest_tile", .phase = 0 },
    .{ .id = TileId.parse("tknorm") catch unreachable, .name = "normalize_tile", .phase = 0 },
    .{ .id = TileId.parse("tkdedu") catch unreachable, .name = "dedupe_tile", .phase = 0 },
    .{ .id = TileId.parse("tkpoly") catch unreachable, .name = "policy_tile", .phase = 0 },
    .{ .id = TileId.parse("tkaudt") catch unreachable, .name = "audit_tile", .phase = 0 },
    .{ .id = TileId.parse("tkrepl") catch unreachable, .name = "replay_tile", .phase = 0 },
    .{ .id = TileId.parse("tkmetr") catch unreachable, .name = "metric_tile", .phase = 0 },
    .{ .id = TileId.parse("tkdiag") catch unreachable, .name = "diag_tile", .phase = 0 },
};
const payment_channels = [_]Channel{
    .{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128 },
    .{ .src_idx = 1, .dst_idx = 2, .depth = 64, .mtu = 128 },
    .{ .src_idx = 2, .dst_idx = 3, .depth = 64, .mtu = 128 },
    .{ .src_idx = 3, .dst_idx = 4, .depth = 64, .mtu = 128 },
};

/// Phase 0 in-process pipeline used by the Tickoni product supervisor.
///
///   tkings -> tknorm -> tkdedu -> tkpoly -> tkaudt
///   tkrepl, tkmetr, and tkdiag observe the deterministic run.
///
/// No Solana validator tiles are registered in this topology.
pub fn paymentPipeline() Topology {
    return .{
        .tiles = &payment_tiles,
        .channels = &payment_channels,
    };
}

test "TileId parse valid 6-char name" {
    const id = try TileId.parse("tkings");
    try std.testing.expectEqualStrings("tkings", id.slice());
}

test "TileId parse short name" {
    const id = try TileId.parse("tk");
    try std.testing.expectEqualStrings("tk", id.slice());
}

test "TileId parse rejects names longer than 6 chars" {
    try std.testing.expectError(error.TileIdTooLong, TileId.parse("toolong7"));
}

test "TileId equality" {
    const a = try TileId.parse("tknorm");
    const b = try TileId.parse("tknorm");
    const c = try TileId.parse("tkdedu");
    try std.testing.expect(a.eql(b));
    try std.testing.expect(!a.eql(c));
}

test "paymentPipeline has Phase 0 product tiles and channels" {
    const topo = paymentPipeline();
    try std.testing.expectEqual(@as(usize, 8), topo.tiles.len);
    try std.testing.expectEqual(@as(usize, 4), topo.channels.len);
    try std.testing.expectEqualStrings("tkings", topo.tiles[0].id.slice());
    try std.testing.expectEqualStrings("tkaudt", topo.tiles[4].id.slice());
    try std.testing.expectEqualStrings("tkdiag", topo.tiles[7].id.slice());
    try std.testing.expectEqual(@as(u32, 0), topo.channels[0].src_idx);
    try std.testing.expectEqual(@as(u32, 1), topo.channels[0].dst_idx);
}

test "paymentPipeline passes validation" {
    try paymentPipeline().validate();
}

test "validate rejects non-power-of-two channel depth" {
    const topo = Topology{
        .tiles = &.{
            .{ .id = TileId.parse("tkfoo") catch unreachable, .name = "foo", .phase = 0 },
            .{ .id = TileId.parse("tkbar") catch unreachable, .name = "bar", .phase = 0 },
        },
        .channels = &.{.{ .src_idx = 0, .dst_idx = 1, .depth = 7, .mtu = 0 }},
    };
    try std.testing.expectError(error.ChannelDepthNotPowerOfTwo, topo.validate());
}

test "validate rejects self-loop channel" {
    const topo = Topology{
        .tiles = &.{
            .{ .id = TileId.parse("tkfoo") catch unreachable, .name = "foo", .phase = 0 },
        },
        .channels = &.{.{ .src_idx = 0, .dst_idx = 0, .depth = 64, .mtu = 0 }},
    };
    try std.testing.expectError(error.ChannelSelfLoop, topo.validate());
}

test "validate rejects out-of-range channel src" {
    const topo = Topology{
        .tiles = &.{
            .{ .id = TileId.parse("tkfoo") catch unreachable, .name = "foo", .phase = 0 },
        },
        .channels = &.{.{ .src_idx = 99, .dst_idx = 0, .depth = 64, .mtu = 0 }},
    };
    try std.testing.expectError(error.ChannelSrcOutOfRange, topo.validate());
}
