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

// Static backing arrays for syntheticPipeline — avoids returning pointers
// to stack-allocated data.
const synthetic_tiles = [_]TileDescriptor{
    .{ .id = TileId.parse("tksrce") catch unreachable, .name = "synthetic_source", .phase = 0 },
    .{ .id = TileId.parse("tksink") catch unreachable, .name = "synthetic_sink", .phase = 0 },
};
const synthetic_channels = [_]Channel{
    .{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 8 },
};

/// Two-tile in-process pipeline used to prove the supervisor lifecycle.
///
///   tksrce  -->  tksink
///
/// Neither tile is a Solana validator tile. tksrce emits sequential u64
/// payloads; tksink counts received payloads.
pub fn syntheticPipeline() Topology {
    return .{
        .tiles = &synthetic_tiles,
        .channels = &synthetic_channels,
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

test "syntheticPipeline has 2 tiles and 1 channel" {
    const topo = syntheticPipeline();
    try std.testing.expectEqual(@as(usize, 2), topo.tiles.len);
    try std.testing.expectEqual(@as(usize, 1), topo.channels.len);
    try std.testing.expectEqualStrings("tksrce", topo.tiles[0].id.slice());
    try std.testing.expectEqualStrings("tksink", topo.tiles[1].id.slice());
    try std.testing.expectEqual(@as(u32, 0), topo.channels[0].src_idx);
    try std.testing.expectEqual(@as(u32, 1), topo.channels[0].dst_idx);
}

test "syntheticPipeline passes validation" {
    try syntheticPipeline().validate();
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
