/// V1.14.S1 CPU placement policy: exclusive/shared/floating, validated
/// against this host's live CPU set. Tickoni-owned policy layered on top
/// of Firedancer substrate, not a Firedancer validator auto-layout concept
/// (see doc/knowledge/tile-topology.md's "Process And Core Placement
/// Boundary"). Combines util.cpu's live-host affinity primitive with
/// topology.zig's static schema; neither of those two depends on the
/// other or on this file.
///
/// Topology.validate() (topology.zig) already covers the static,
/// host-independent structural checks: two tiles claiming the same
/// exclusive id, or claiming the same id where either side does not
/// declare `shared`. This module adds the check that needs live host
/// information — whether a declared CPU id actually exists in this
/// process's affinity mask — and reports the resulting layout shape for
/// supervisor/diagnostics visibility (V1.14.S1.T14: shared-core placement
/// must stay explicit, not an implicit auto-layout).
const std = @import("std");
const cpu = @import("util").cpu;
const topology = @import("topology.zig");

pub const Topology = topology.Topology;

/// Per-tile placement counts and whether the layout uses shared-core
/// placement, for supervisor/CLI/diagnostics visibility.
pub const PlacementReport = struct {
    exclusive_count: usize = 0,
    shared_count: usize = 0,
    floating_count: usize = 0,
    /// True when at least two tiles declare `shared` on the same CPU id.
    /// Exclusive collisions can never reach here — topo.validate()
    /// already rejects those before this field is computed.
    shared_core: bool = false,
};

/// Fail-closed CPU placement validation: static structural checks via
/// topo.validate(), then every exclusive/shared tile's CPU id must be set
/// in `available_cpus` (this process's own affinity mask — the practical
/// stand-in for "exists on this host" without requiring root or a
/// separate host-topology query). Returns a PlacementReport once
/// validation passes; spawns nothing itself.
pub fn validate(topo: Topology, available_cpus: *const cpu.CpuSet) !PlacementReport {
    try topo.validate();

    var report = PlacementReport{};
    for (topo.tiles) |t| {
        switch (t.cpu_placement) {
            .exclusive => |c| {
                report.exclusive_count += 1;
                try requireAvailable(available_cpus, c);
            },
            .shared => |c| {
                report.shared_count += 1;
                try requireAvailable(available_cpus, c);
            },
            .floating => report.floating_count += 1,
        }
    }

    for (topo.tiles, 0..) |a, i| {
        const a_cpu = switch (a.cpu_placement) {
            .shared => |c| c,
            else => continue,
        };
        for (topo.tiles[i + 1 ..]) |b| {
            const b_cpu = switch (b.cpu_placement) {
                .shared => |c| c,
                else => continue,
            };
            if (a_cpu == b_cpu) {
                report.shared_core = true;
                break;
            }
        }
        if (report.shared_core) break;
    }

    return report;
}

/// cpu.isSet() asserts its cpu argument is in range — appropriate for call
/// sites that already validated the value themselves, but a declared tile
/// CPU id is external/config data (a plain u16 from topology.zig's
/// CpuPlacement union), not an internal invariant. This is the
/// fail-closed boundary check CLAUDE.md's Hard Constraints require ("CPU
/// placement fails closed for malformed or unavailable CPU ids"):
/// out-of-range ids are malformed, in-range-but-absent ids are
/// unavailable, and neither should reach an `unreachable`-backed assert.
fn requireAvailable(available_cpus: *const cpu.CpuSet, cpu_id: u16) !void {
    if (cpu_id >= cpu.cpu_set_bytes * 8) return error.CpuIdMalformed;
    if (!cpu.isSet(available_cpus, cpu_id)) return error.CpuUnavailable;
}

// ---------------------------------------------------------------------------
// Tests — pure logic against synthetic CpuSet values; no real host
// affinity queried (matches util/cpu.zig's own test style).
// ---------------------------------------------------------------------------

const TileId = topology.TileId;

/// Builds a minimal TileDescriptor for placement-validation tests below.
fn tile(id: []const u8, placement: topology.CpuPlacement) topology.TileDescriptor {
    return .{ .id = TileId.parse(id) catch unreachable, .name = id, .phase = 0, .cpu_placement = placement };
}

test "validate rejects an out-of-range exclusive cpu id as malformed, not an assert" {
    var cpus: cpu.CpuSet = undefined;
    cpu.zero(&cpus);
    cpu.set(&cpus, 0);

    const topo = Topology{
        .tiles = &.{tile("tkfoo", .{ .exclusive = 65000 })},
        .channels = &.{},
    };
    try std.testing.expectError(error.CpuIdMalformed, validate(topo, &cpus));
}

test "validate rejects an exclusive cpu id not in available_cpus" {
    var cpus: cpu.CpuSet = undefined;
    cpu.zero(&cpus);
    cpu.set(&cpus, 0);

    const topo = Topology{
        .tiles = &.{tile("tkfoo", .{ .exclusive = 1 })},
        .channels = &.{},
    };
    try std.testing.expectError(error.CpuUnavailable, validate(topo, &cpus));
}

test "validate rejects a shared cpu id not in available_cpus" {
    var cpus: cpu.CpuSet = undefined;
    cpu.zero(&cpus);
    cpu.set(&cpus, 0);

    const topo = Topology{
        .tiles = &.{tile("tkfoo", .{ .shared = 5 })},
        .channels = &.{},
    };
    try std.testing.expectError(error.CpuUnavailable, validate(topo, &cpus));
}

test "validate propagates topo.validate()'s structural checks (duplicate exclusive)" {
    var cpus: cpu.CpuSet = undefined;
    cpu.zero(&cpus);
    cpu.set(&cpus, 0);

    const topo = Topology{
        .tiles = &.{
            tile("tkfoo", .{ .exclusive = 0 }),
            tile("tkbar", .{ .exclusive = 0 }),
        },
        .channels = &.{},
    };
    try std.testing.expectError(error.CpuPlacementConflict, validate(topo, &cpus));
}

test "validate reports floating-only topology with shared_core false" {
    var cpus: cpu.CpuSet = undefined;
    cpu.zero(&cpus);
    cpu.set(&cpus, 0);

    const topo = Topology{
        .tiles = &.{ tile("tkfoo", .floating), tile("tkbar", .floating) },
        .channels = &.{},
    };
    const report = try validate(topo, &cpus);
    try std.testing.expectEqual(@as(usize, 0), report.exclusive_count);
    try std.testing.expectEqual(@as(usize, 0), report.shared_count);
    try std.testing.expectEqual(@as(usize, 2), report.floating_count);
    try std.testing.expect(!report.shared_core);
}

test "validate reports shared_core true when two tiles share a cpu id" {
    var cpus: cpu.CpuSet = undefined;
    cpu.zero(&cpus);
    cpu.set(&cpus, 0);

    const topo = Topology{
        .tiles = &.{
            tile("tkfoo", .{ .shared = 0 }),
            tile("tkbar", .{ .shared = 0 }),
            tile("tkbaz", .floating),
        },
        .channels = &.{},
    };
    const report = try validate(topo, &cpus);
    try std.testing.expectEqual(@as(usize, 2), report.shared_count);
    try std.testing.expectEqual(@as(usize, 1), report.floating_count);
    try std.testing.expect(report.shared_core);
}

test "validate reports shared_core false for distinct exclusive cpu ids" {
    var cpus: cpu.CpuSet = undefined;
    cpu.zero(&cpus);
    cpu.set(&cpus, 0);
    cpu.set(&cpus, 1);

    const topo = Topology{
        .tiles = &.{
            tile("tkfoo", .{ .exclusive = 0 }),
            tile("tkbar", .{ .exclusive = 1 }),
        },
        .channels = &.{},
    };
    const report = try validate(topo, &cpus);
    try std.testing.expectEqual(@as(usize, 2), report.exclusive_count);
    try std.testing.expect(!report.shared_core);
}
