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

const investment_tiles = [_]TileDescriptor{
    .{ .id = TileId.parse("tkings") catch unreachable, .name = "ingest_tile", .phase = 0 },
    .{ .id = TileId.parse("tknorm") catch unreachable, .name = "normalize_tile", .phase = 0 },
    .{ .id = TileId.parse("tkdedu") catch unreachable, .name = "dedupe_tile", .phase = 0 },
    .{ .id = TileId.parse("tkcase") catch unreachable, .name = "case_router_tile", .phase = 2 },
    .{ .id = TileId.parse("tkpoly") catch unreachable, .name = "policy_tile", .phase = 0 },
    .{ .id = TileId.parse("tkaudt") catch unreachable, .name = "audit_tile", .phase = 0 },
    .{ .id = TileId.parse("tkdisp") catch unreachable, .name = "agent_dispatch_tile", .phase = 1 },
    .{ .id = TileId.parse("tkagnt") catch unreachable, .name = "agent_worker_tile", .phase = 1 },
    .{ .id = TileId.parse("tkmodl") catch unreachable, .name = "model_gateway_tile", .phase = 1 },
    .{ .id = TileId.parse("tktool") catch unreachable, .name = "tool_broker_tile", .phase = 1 },
    .{ .id = TileId.parse("tkadpt") catch unreachable, .name = "adapter_tile", .phase = 1 },
    .{ .id = TileId.parse("tkrepl") catch unreachable, .name = "replay_tile", .phase = 0 },
    .{ .id = TileId.parse("tkmetr") catch unreachable, .name = "metric_tile", .phase = 0 },
    .{ .id = TileId.parse("tkdiag") catch unreachable, .name = "diag_tile", .phase = 0 },
};

const investment_channels = [_]Channel{
    .{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 256 },
    .{ .src_idx = 1, .dst_idx = 2, .depth = 64, .mtu = 256 },
    .{ .src_idx = 2, .dst_idx = 3, .depth = 64, .mtu = 256 },
    .{ .src_idx = 3, .dst_idx = 4, .depth = 64, .mtu = 256 },
    .{ .src_idx = 3, .dst_idx = 6, .depth = 32, .mtu = 256 },
    .{ .src_idx = 6, .dst_idx = 7, .depth = 32, .mtu = 256 },
    .{ .src_idx = 7, .dst_idx = 8, .depth = 32, .mtu = 1024 },
    .{ .src_idx = 7, .dst_idx = 9, .depth = 32, .mtu = 512 },
    .{ .src_idx = 9, .dst_idx = 10, .depth = 32, .mtu = 512 },
    .{ .src_idx = 4, .dst_idx = 5, .depth = 64, .mtu = 256 },
    .{ .src_idx = 8, .dst_idx = 5, .depth = 32, .mtu = 256 },
    .{ .src_idx = 9, .dst_idx = 5, .depth = 32, .mtu = 256 },
    .{ .src_idx = 10, .dst_idx = 5, .depth = 32, .mtu = 256 },
    .{ .src_idx = 7, .dst_idx = 5, .depth = 32, .mtu = 256 },
    .{ .src_idx = 5, .dst_idx = 11, .depth = 32, .mtu = 256 },
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

pub fn investmentWorkflow() Topology {
    return .{
        .tiles = &investment_tiles,
        .channels = &investment_channels,
    };
}

// V1.14.S1 process-mode variant of paymentPipeline: same 8 tiles and 4
// core channels, backed by Tango shared memory in one shared workspace
// instead of the heap-backed dev/test ring. All tiles are floating (no
// hard exclusive-core requirement); src/app/tickoni/supervisor.zig's
// process-mode start path assigns concrete CPU placement per config.
const payment_process_channels = [_]Channel{
    .{
        .src_idx = 0,
        .dst_idx = 1,
        .depth = 64,
        .mtu = 128,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    .{
        .src_idx = 1,
        .dst_idx = 2,
        .depth = 64,
        .mtu = 128,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    .{
        .src_idx = 2,
        .dst_idx = 3,
        .depth = 64,
        .mtu = 128,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    .{
        .src_idx = 3,
        .dst_idx = 4,
        .depth = 64,
        .mtu = 128,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
};

/// V1.14.S1 process-isolated variant of paymentPipeline(): the same tile
/// identities and channel shape, with every core channel backed by a
/// shared Tango workspace instead of a heap-backed ring. CPU placement
/// defaults to floating here; callers that need exclusive/shared pinning
/// build their own TileDescriptor slice with cpu_placement set.
pub fn paymentPipelineProcess() Topology {
    return .{
        .tiles = &payment_tiles,
        .channels = &payment_process_channels,
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

test "investmentWorkflow includes tkmodl tktool tkadpt and passes validation" {
    const topo = investmentWorkflow();
    try topo.validate();
    try std.testing.expectEqual(@as(usize, 14), topo.tiles.len);
    try std.testing.expectEqualStrings("tkmodl", topo.tiles[8].id.slice());
    try std.testing.expectEqualStrings("tktool", topo.tiles[9].id.slice());
    try std.testing.expectEqualStrings("tkadpt", topo.tiles[10].id.slice());
    try std.testing.expectEqualStrings("tkrepl", topo.tiles[11].id.slice());
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

test "paymentPipelineProcess has 8 tiles, 4 tango_shm channels, and passes validation" {
    const topo = paymentPipelineProcess();
    try topo.validate();
    try std.testing.expectEqual(@as(usize, 8), topo.tiles.len);
    try std.testing.expectEqual(@as(usize, 4), topo.channels.len);
    for (topo.channels) |ch| {
        try std.testing.expectEqual(LinkBacking.tango_shm, ch.backing);
        try std.testing.expectEqual(LinkReliability.reliable, ch.reliability);
        try std.testing.expectEqualStrings("tkpay0", ch.workspace_name.slice());
    }
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
