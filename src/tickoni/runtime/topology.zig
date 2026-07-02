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

/// V1.14 CPU placement policy for a tile process. Tickoni-owned; not a
/// Firedancer validator auto-layout field. `exclusive`/`shared` carry the
/// pinned CPU id. `shared` is the only mode where two tiles may declare the
/// same CPU id (see Topology.validate).
pub const CpuPlacement = union(enum) {
    exclusive: u16,
    shared: u16,
    floating,
};

/// Bounded name of the Firedancer workspace (src/util/wksp) backing a
/// correctness-bearing link's mcache/dcache/fseq/cnc objects in process
/// mode. 32 bytes is generous for a Tickoni-chosen name; fd_wksp itself has
/// no such limit, but topology identifiers stay fixed-capacity like TileId.
pub const WorkspaceName = struct {
    bytes: [32]u8 = [_]u8{0} ** 32,

    pub fn parse(s: []const u8) error{WorkspaceNameTooLong}!WorkspaceName {
        if (s.len > 32) return error.WorkspaceNameTooLong;
        var w = WorkspaceName{};
        @memcpy(w.bytes[0..s.len], s);
        return w;
    }

    pub fn slice(self: *const WorkspaceName) []const u8 {
        const end = std.mem.indexOfScalar(u8, &self.bytes, 0) orelse 32;
        return self.bytes[0..end];
    }

    pub fn isEmpty(self: *const WorkspaceName) bool {
        return self.slice().len == 0;
    }
};

/// Static description of one tile in a topology.
pub const TileDescriptor = struct {
    id: TileId,
    /// Human-readable name used in logs and diagnostics.
    name: []const u8,
    /// Phase from the tile plan: 0=core, 1=case, 2=agent, 3=api, 4=exec.
    phase: u8,
    /// Defaults to floating: existing thread-mode topologies do not pin
    /// CPUs. Process-mode topologies set this explicitly.
    cpu_placement: CpuPlacement = .floating,
};

/// Which substrate backs a channel's payload transport.
pub const LinkBacking = enum {
    /// Heap-backed in-process ring (dev/test thread-mode lane only).
    heap_dev,
    /// Firedancer Tango mcache/dcache/fseq shared memory (process mode).
    tango_shm,
};

pub const LinkReliability = enum { reliable, lossy };

/// Directed channel between two tiles: exactly one producer, one consumer.
pub const Channel = struct {
    src_idx: u32,
    dst_idx: u32,
    /// Ring-buffer depth — must be a power of two.
    depth: u32,
    /// Max fragment size in bytes; 0 means no dcache.
    mtu: u32,
    /// Defaults to heap_dev: existing topologies use the in-process ring.
    backing: LinkBacking = .heap_dev,
    /// Defaults to reliable: correctness-bearing links backpressure instead
    /// of dropping. Only telemetry links should be lossy.
    reliability: LinkReliability = .reliable,
    /// Required (non-empty) when backing == .tango_shm.
    workspace_name: WorkspaceName = .{},
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
            if (ch.backing == .tango_shm) {
                var name = ch.workspace_name;
                if (name.isEmpty()) return error.ChannelWorkspaceNameMissing;
            }
        }
        try validateCpuPlacement(self.tiles);
    }
};

/// Rejects two tiles pinned to the same CPU id unless both declare
/// `shared`. Available-CPU-id and oversubscription-against-the-live-host
/// checks belong to src/tickoni/runtime/cpu.zig, which has runtime
/// CPU-set information this static topology does not.
fn validateCpuPlacement(tiles: []const TileDescriptor) !void {
    for (tiles, 0..) |a, i| {
        const a_cpu = switch (a.cpu_placement) {
            .exclusive => |cpu| cpu,
            .shared => |cpu| cpu,
            .floating => continue,
        };
        const a_shared = a.cpu_placement == .shared;
        for (tiles[i + 1 ..]) |b| {
            const b_cpu = switch (b.cpu_placement) {
                .exclusive => |cpu| cpu,
                .shared => |cpu| cpu,
                .floating => continue,
            };
            if (a_cpu != b_cpu) continue;
            const b_shared = b.cpu_placement == .shared;
            if (!a_shared or !b_shared) return error.CpuPlacementConflict;
        }
    }
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

test "WorkspaceName parse and slice round-trip" {
    const w = try WorkspaceName.parse("tkpay0");
    try std.testing.expectEqualStrings("tkpay0", w.slice());
    try std.testing.expect(!w.isEmpty());
}

test "WorkspaceName parse rejects names longer than 32 chars" {
    try std.testing.expectError(error.WorkspaceNameTooLong, WorkspaceName.parse("a" ** 33));
}

test "WorkspaceName default is empty" {
    const w = WorkspaceName{};
    try std.testing.expect(w.isEmpty());
}

test "validate rejects tango_shm channel with missing workspace name" {
    const topo = Topology{
        .tiles = &.{
            .{ .id = TileId.parse("tkfoo") catch unreachable, .name = "foo", .phase = 0 },
            .{ .id = TileId.parse("tkbar") catch unreachable, .name = "bar", .phase = 0 },
        },
        .channels = &.{.{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128, .backing = .tango_shm }},
    };
    try std.testing.expectError(error.ChannelWorkspaceNameMissing, topo.validate());
}

test "validate accepts heap_dev channel with no workspace name" {
    const topo = Topology{
        .tiles = &.{
            .{ .id = TileId.parse("tkfoo") catch unreachable, .name = "foo", .phase = 0 },
            .{ .id = TileId.parse("tkbar") catch unreachable, .name = "bar", .phase = 0 },
        },
        .channels = &.{.{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128 }},
    };
    try topo.validate();
}

test "validate rejects two tiles pinned exclusive on the same cpu" {
    const topo = Topology{
        .tiles = &.{
            .{ .id = TileId.parse("tkfoo") catch unreachable, .name = "foo", .phase = 0, .cpu_placement = .{ .exclusive = 0 } },
            .{ .id = TileId.parse("tkbar") catch unreachable, .name = "bar", .phase = 0, .cpu_placement = .{ .exclusive = 0 } },
        },
        .channels = &.{},
    };
    try std.testing.expectError(error.CpuPlacementConflict, topo.validate());
}

test "validate rejects exclusive and shared colliding on the same cpu" {
    const topo = Topology{
        .tiles = &.{
            .{ .id = TileId.parse("tkfoo") catch unreachable, .name = "foo", .phase = 0, .cpu_placement = .{ .exclusive = 2 } },
            .{ .id = TileId.parse("tkbar") catch unreachable, .name = "bar", .phase = 0, .cpu_placement = .{ .shared = 2 } },
        },
        .channels = &.{},
    };
    try std.testing.expectError(error.CpuPlacementConflict, topo.validate());
}

test "validate accepts two tiles declaring shared on the same cpu" {
    const topo = Topology{
        .tiles = &.{
            .{ .id = TileId.parse("tkfoo") catch unreachable, .name = "foo", .phase = 0, .cpu_placement = .{ .shared = 3 } },
            .{ .id = TileId.parse("tkbar") catch unreachable, .name = "bar", .phase = 0, .cpu_placement = .{ .shared = 3 } },
        },
        .channels = &.{},
    };
    try topo.validate();
}

test "validate accepts distinct exclusive cpu ids and floating tiles" {
    const topo = Topology{
        .tiles = &.{
            .{ .id = TileId.parse("tkfoo") catch unreachable, .name = "foo", .phase = 0, .cpu_placement = .{ .exclusive = 0 } },
            .{ .id = TileId.parse("tkbar") catch unreachable, .name = "bar", .phase = 0, .cpu_placement = .{ .exclusive = 1 } },
            .{ .id = TileId.parse("tkbaz") catch unreachable, .name = "baz", .phase = 0 },
        },
        .channels = &.{},
    };
    try topo.validate();
}
