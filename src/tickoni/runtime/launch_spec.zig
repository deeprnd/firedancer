/// Versioned handoff record from the V1.14 process-mode supervisor to a
/// self-exec'd tile child process. Written once by the supervisor before
/// spawning the child and read exactly once by src/app/tickoni/tile_main.zig.
///
/// This is not a durable or cross-version wire format: writer and reader are
/// always the same build of the same binary (self-exec), so a plain
/// fixed-size struct round-tripped through std.mem.asBytes is sufficient.
/// The magic/version/length checks below exist to fail closed on a stray,
/// truncated, or foreign file rather than to support format evolution.
const std = @import("std");
const tile = @import("tile.zig");
const cpu_placement = @import("cpu_placement.zig");
const link = @import("link.zig");

pub const magic: u32 = 0x544b5350; // "TKSP"
pub const version: u16 = 1;

pub const shmem_path_cap: usize = 128;

pub const LaunchSpec = struct {
    magic_field: u32 = magic,
    version_field: u16 = version,
    tile_idx: u32,
    tile_id: tile.TileId,
    cpu_placement: cpu_placement.CpuPlacement,
    workspace_name: link.WorkspaceName,
    /// Global address of this tile's pre-formatted cnc object inside
    /// workspace_name, as returned by fd_wksp_gaddr in the supervisor.
    cnc_gaddr: usize,
    /// Zeroed (depth==0) when this tile has no upstream/downstream
    /// correctness link, e.g. tkings has no input and tkaudt has no
    /// output in the current 5-stage core chain.
    has_input_link: bool = false,
    input_link: link.LinkHandles = .{},
    has_output_link: bool = false,
    output_link: link.LinkHandles = .{},
    shmem_path_buf: [shmem_path_cap]u8 = [_]u8{0} ** shmem_path_cap,
    shmem_path_len: u16,
    heartbeat_interval_ns: u64,
    /// Test-only hook (V1.14.S1.T12 crash isolation): if > 0, the tile
    /// self-exits(1) after this many heartbeats instead of waiting for
    /// SIGTERM. 0 means run normally until signaled.
    crash_after_heartbeats: u32,
    /// Payment pipeline behavior shared by every tile so process-mode and
    /// thread-mode runs make the same decisions for the same input; see
    /// tiles/payment_pipeline/runtime.zig's PaymentPipelineConfig.
    event_count: u64 = 0,
    policy_limit_cents: i64 = 0,
    inject_duplicate: bool = false,
    inject_malformed: bool = false,

    pub fn init(fields: struct {
        tile_idx: u32,
        tile_id: tile.TileId,
        cpu_placement: cpu_placement.CpuPlacement,
        workspace_name: link.WorkspaceName,
        cnc_gaddr: usize,
        shmem_path: []const u8,
        heartbeat_interval_ns: u64,
        crash_after_heartbeats: u32 = 0,
        input_link: ?link.LinkHandles = null,
        output_link: ?link.LinkHandles = null,
        event_count: u64 = 0,
        policy_limit_cents: i64 = 0,
        inject_duplicate: bool = false,
        inject_malformed: bool = false,
    }) error{ShmemPathTooLong}!LaunchSpec {
        if (fields.shmem_path.len > shmem_path_cap) return error.ShmemPathTooLong;
        var spec = LaunchSpec{
            .tile_idx = fields.tile_idx,
            .tile_id = fields.tile_id,
            .cpu_placement = fields.cpu_placement,
            .workspace_name = fields.workspace_name,
            .cnc_gaddr = fields.cnc_gaddr,
            .shmem_path_len = @intCast(fields.shmem_path.len),
            .heartbeat_interval_ns = fields.heartbeat_interval_ns,
            .crash_after_heartbeats = fields.crash_after_heartbeats,
            .has_input_link = fields.input_link != null,
            .input_link = fields.input_link orelse .{},
            .has_output_link = fields.output_link != null,
            .output_link = fields.output_link orelse .{},
            .event_count = fields.event_count,
            .policy_limit_cents = fields.policy_limit_cents,
            .inject_duplicate = fields.inject_duplicate,
            .inject_malformed = fields.inject_malformed,
        };
        @memcpy(spec.shmem_path_buf[0..fields.shmem_path.len], fields.shmem_path);
        return spec;
    }

    pub fn shmemPath(self: *const LaunchSpec) []const u8 {
        return self.shmem_path_buf[0..self.shmem_path_len];
    }

    pub fn writeToFile(self: *const LaunchSpec, io: std.Io, dir: std.Io.Dir, sub_path: []const u8) !void {
        var file = try dir.createFile(io, sub_path, .{});
        defer file.close(io);
        try file.writePositionalAll(io, std.mem.asBytes(self), 0);
    }

    pub fn readFromFile(io: std.Io, dir: std.Io.Dir, sub_path: []const u8) !LaunchSpec {
        var file = try dir.openFile(io, sub_path, .{});
        defer file.close(io);
        var spec: LaunchSpec = undefined;
        const buf = std.mem.asBytes(&spec);
        const n = try file.readPositionalAll(io, buf, 0);
        if (n != @sizeOf(LaunchSpec)) return error.LaunchSpecTruncated;
        if (spec.magic_field != magic) return error.LaunchSpecBadMagic;
        if (spec.version_field != version) return error.LaunchSpecUnsupportedVersion;
        if (spec.shmem_path_len > shmem_path_cap) return error.LaunchSpecMalformed;
        return spec;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "LaunchSpec round-trips through a file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const spec = try LaunchSpec.init(.{
        .tile_idx = 3,
        .tile_id = try tile.TileId.parse("tkpoly"),
        .cpu_placement = .{ .exclusive = 2 },
        .workspace_name = try link.WorkspaceName.parse("tkpay0"),
        .cnc_gaddr = 4096,
        .shmem_path = "/tmp/tickoni-run",
        .heartbeat_interval_ns = 50_000_000,
        .crash_after_heartbeats = 7,
    });
    try spec.writeToFile(std.testing.io, tmp.dir, "tile.spec");

    const read_back = try LaunchSpec.readFromFile(std.testing.io, tmp.dir, "tile.spec");
    try std.testing.expectEqual(@as(u32, 3), read_back.tile_idx);
    try std.testing.expectEqualStrings("tkpoly", read_back.tile_id.slice());
    try std.testing.expectEqual(cpu_placement.CpuPlacement{ .exclusive = 2 }, read_back.cpu_placement);
    try std.testing.expectEqualStrings("tkpay0", read_back.workspace_name.slice());
    try std.testing.expectEqual(@as(usize, 4096), read_back.cnc_gaddr);
    try std.testing.expectEqualStrings("/tmp/tickoni-run", read_back.shmemPath());
    try std.testing.expectEqual(@as(u64, 50_000_000), read_back.heartbeat_interval_ns);
    try std.testing.expectEqual(@as(u32, 7), read_back.crash_after_heartbeats);
}

test "LaunchSpec readFromFile rejects a truncated file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile(std.testing.io, "short.spec", .{});
    try file.writePositionalAll(std.testing.io, &[_]u8{ 1, 2, 3, 4 }, 0);
    file.close(std.testing.io);

    try std.testing.expectError(error.LaunchSpecTruncated, LaunchSpec.readFromFile(std.testing.io, tmp.dir, "short.spec"));
}

test "LaunchSpec readFromFile rejects a bad magic" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var spec = try LaunchSpec.init(.{
        .tile_idx = 0,
        .tile_id = try tile.TileId.parse("tkings"),
        .cpu_placement = .floating,
        .workspace_name = try link.WorkspaceName.parse("tkpay0"),
        .cnc_gaddr = 0,
        .shmem_path = "/tmp",
        .heartbeat_interval_ns = 1,
    });
    spec.magic_field = 0xdeadbeef;
    try spec.writeToFile(std.testing.io, tmp.dir, "bad_magic.spec");

    try std.testing.expectError(error.LaunchSpecBadMagic, LaunchSpec.readFromFile(std.testing.io, tmp.dir, "bad_magic.spec"));
}

test "LaunchSpec init rejects an over-long shmem path" {
    const too_long = [_]u8{'a'} ** (shmem_path_cap + 1);
    try std.testing.expectError(error.ShmemPathTooLong, LaunchSpec.init(.{
        .tile_idx = 0,
        .tile_id = try tile.TileId.parse("tkings"),
        .cpu_placement = .floating,
        .workspace_name = try link.WorkspaceName.parse("tkpay0"),
        .cnc_gaddr = 0,
        .shmem_path = &too_long,
        .heartbeat_interval_ns = 1,
    }));
}
