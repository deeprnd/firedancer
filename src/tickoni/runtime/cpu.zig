/// CPU affinity bindings, cpu-set bit manipulation, and CPU placement
/// policy for Tickoni's V1.14 process-mode tile supervisor and tiles
/// (src/app/tickoni/*). Tickoni-owned policy and Linux syscall bindings,
/// not a Firedancer bridge.
///
/// Firedancer has an internal fd_cpuset_t affinity wrapper
/// (src/util/tile/fd_tile_private.h), but that header documents itself as
/// "intended for internal use within fd_tile" and layers a macro-templated
/// bitset (`fd_set.c` with `SET_MAX FD_TILE_MAX`) that has no stable,
/// independently-linkable layout outside fd_tile's own translation unit.
/// Per the "drop to a more explicit lower-level path" guidance in
/// doc/execution/contribution/tickoni.md, this wraps the POSIX
/// sched_getaffinity/sched_setaffinity syscalls directly instead.
///
/// PlacementReport/validate below are CPU placement policy layered on top
/// of Firedancer substrate, not a Firedancer validator auto-layout concept
/// (see doc/knowledge/tile-topology.md's "Process And Core Placement
/// Boundary"). topology.zig's Topology.validate() already covers the
/// static, host-independent structural checks: two tiles claiming the
/// same exclusive id, or claiming the same id where either side does not
/// declare `shared`. validate() here adds the check that needs live host
/// information — whether a declared CPU id actually exists in this
/// process's affinity mask — and reports the resulting layout shape for
/// supervisor/diagnostics visibility (V1.14.S1.T14: shared-core placement
/// must stay explicit, not an implicit auto-layout).
///
/// Link requirements: none beyond libc (glibc exposes sched_*affinity
/// directly).
const std = @import("std");
const topology = @import("topology.zig");

pub const Topology = topology.Topology;

/// Matches glibc's default cpu_set_t size (CPU_SETSIZE=1024 bits).
pub const cpu_set_bytes: usize = 128;
pub const CpuSet = [cpu_set_bytes]u8;

/// Clears every bit in `cpu_set`.
pub fn zero(cpu_set: *CpuSet) void {
    @memset(cpu_set, 0);
}

/// Sets the bit for `cpu` in `cpu_set`. Asserts `cpu` is in range
/// (`< cpu_set_bytes * 8`); callers with externally-sourced cpu ids must
/// range-check first (see requireAvailable below for the fail-closed
/// version of that check).
pub fn set(cpu_set: *CpuSet, cpu: usize) void {
    std.debug.assert(cpu < cpu_set_bytes * 8);
    cpu_set[cpu / 8] |= @as(u8, 1) << @intCast(cpu % 8);
}

/// Returns whether the bit for `cpu` is set in `cpu_set`. Asserts `cpu`
/// is in range, matching set().
pub fn isSet(cpu_set: *const CpuSet, cpu: usize) bool {
    std.debug.assert(cpu < cpu_set_bytes * 8);
    return (cpu_set[cpu / 8] & (@as(u8, 1) << @intCast(cpu % 8))) != 0;
}

/// Returns the number of set bits in `cpu_set`.
pub fn count(cpu_set: *const CpuSet) usize {
    var n: usize = 0;
    for (cpu_set) |byte| n += @popCount(byte);
    return n;
}

extern "c" fn sched_getaffinity(pid: c_int, cpusetsize: usize, mask: *anyopaque) c_int;
extern "c" fn sched_setaffinity(pid: c_int, cpusetsize: usize, mask: *const anyopaque) c_int;

/// Reads the current CPU affinity mask for `pid` into `cpu_set`. pid==0
/// means the calling thread.
pub fn getAffinity(pid: c_int, cpu_set: *CpuSet) !void {
    if (sched_getaffinity(pid, cpu_set_bytes, cpu_set) != 0) return error.SchedGetAffinityFailed;
}

/// Pins `pid` (0 == calling thread) to the CPUs set in `cpu_set`.
pub fn setAffinity(pid: c_int, cpu_set: *const CpuSet) !void {
    if (sched_setaffinity(pid, cpu_set_bytes, cpu_set) != 0) return error.SchedSetAffinityFailed;
}

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
pub fn validate(topo: Topology, available_cpus: *const CpuSet) !PlacementReport {
    try topo.validate();

    var report = PlacementReport{};
    for (topo.tiles) |t| {
        switch (t.cpu_placement) {
            .exclusive => |cpu| {
                report.exclusive_count += 1;
                try requireAvailable(available_cpus, cpu);
            },
            .shared => |cpu| {
                report.shared_count += 1;
                try requireAvailable(available_cpus, cpu);
            },
            .floating => report.floating_count += 1,
        }
    }

    for (topo.tiles, 0..) |a, i| {
        const a_cpu = switch (a.cpu_placement) {
            .shared => |cpu| cpu,
            else => continue,
        };
        for (topo.tiles[i + 1 ..]) |b| {
            const b_cpu = switch (b.cpu_placement) {
                .shared => |cpu| cpu,
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

/// isSet() asserts its cpu argument is in range — appropriate for call
/// sites that already validated the value themselves, but a declared tile
/// CPU id is external/config data (a plain u16 from topology.zig's
/// CpuPlacement union), not an internal invariant. This is the
/// fail-closed boundary check CLAUDE.md's Hard Constraints require ("CPU
/// placement fails closed for malformed or unavailable CPU ids"):
/// out-of-range ids are malformed, in-range-but-absent ids are
/// unavailable, and neither should reach an `unreachable`-backed assert.
fn requireAvailable(available_cpus: *const CpuSet, cpu: u16) !void {
    if (cpu >= cpu_set_bytes * 8) return error.CpuIdMalformed;
    if (!isSet(available_cpus, cpu)) return error.CpuUnavailable;
}

// ---------------------------------------------------------------------------
// Tests — bit manipulation and placement validation are pure logic; no
// real host affinity queried (getAffinity/setAffinity are exercised by
// the process-mode integration tests instead).
// ---------------------------------------------------------------------------

test "zero clears all bits" {
    var cs: CpuSet = undefined;
    @memset(&cs, 0xff);
    zero(&cs);
    try std.testing.expectEqual(@as(usize, 0), count(&cs));
}

test "set and isSet round-trip for low and high cpu ids" {
    var cs: CpuSet = undefined;
    zero(&cs);
    set(&cs, 0);
    set(&cs, 63);
    set(&cs, 1023);
    try std.testing.expect(isSet(&cs, 0));
    try std.testing.expect(isSet(&cs, 63));
    try std.testing.expect(isSet(&cs, 1023));
    try std.testing.expect(!isSet(&cs, 1));
    try std.testing.expectEqual(@as(usize, 3), count(&cs));
}

const TileId = topology.TileId;

/// Builds a minimal TileDescriptor for placement-validation tests below.
fn tile(id: []const u8, placement: topology.CpuPlacement) topology.TileDescriptor {
    return .{ .id = TileId.parse(id) catch unreachable, .name = id, .phase = 0, .cpu_placement = placement };
}

test "validate rejects an out-of-range exclusive cpu id as malformed, not an assert" {
    var cpus: CpuSet = undefined;
    zero(&cpus);
    set(&cpus, 0);

    const topo = Topology{
        .tiles = &.{tile("tkfoo", .{ .exclusive = 65000 })},
        .channels = &.{},
    };
    try std.testing.expectError(error.CpuIdMalformed, validate(topo, &cpus));
}

test "validate rejects an exclusive cpu id not in available_cpus" {
    var cpus: CpuSet = undefined;
    zero(&cpus);
    set(&cpus, 0);

    const topo = Topology{
        .tiles = &.{tile("tkfoo", .{ .exclusive = 1 })},
        .channels = &.{},
    };
    try std.testing.expectError(error.CpuUnavailable, validate(topo, &cpus));
}

test "validate rejects a shared cpu id not in available_cpus" {
    var cpus: CpuSet = undefined;
    zero(&cpus);
    set(&cpus, 0);

    const topo = Topology{
        .tiles = &.{tile("tkfoo", .{ .shared = 5 })},
        .channels = &.{},
    };
    try std.testing.expectError(error.CpuUnavailable, validate(topo, &cpus));
}

test "validate propagates topo.validate()'s structural checks (duplicate exclusive)" {
    var cpus: CpuSet = undefined;
    zero(&cpus);
    set(&cpus, 0);

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
    var cpus: CpuSet = undefined;
    zero(&cpus);
    set(&cpus, 0);

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
    var cpus: CpuSet = undefined;
    zero(&cpus);
    set(&cpus, 0);

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
    var cpus: CpuSet = undefined;
    zero(&cpus);
    set(&cpus, 0);
    set(&cpus, 1);

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
