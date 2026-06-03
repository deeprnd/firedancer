/// Zig build for the Tickoni supervisor and its unit tests.
///
/// Build the supervisor:
///   zig build
///
/// Run Zig unit tests (separate from 'make run-unit-test'):
///   zig build test
///
/// The existing GNUmakefile (C/Firedancer build) is unchanged.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Shared modules used by both the exe and test binaries.
    const runtime_mod = b.addModule("runtime", .{
        .root_source_file = b.path("src/tickoni/runtime/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tiles_mod = b.addModule("tiles", .{
        .root_source_file = b.path("src/tickoni/tiles/synthetic.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Supervisor executable.
    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/app/tickoni/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "runtime", .module = runtime_mod },
            .{ .name = "tiles", .module = tiles_mod },
        },
    });
    const exe = b.addExecutable(.{
        .name = "tickoni-supervisor",
        .root_module = main_mod,
    });
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    if (b.args) |argv| run_exe.addArgs(argv);
    const run_step = b.step("run", "Run tickoni-supervisor");
    run_step.dependOn(&run_exe.step);

    // ---------------------------------------------------------------------------
    // Test step — not wired into 'make run-unit-test'
    // Run with: zig build test
    // ---------------------------------------------------------------------------
    const test_step = b.step("test", "Run Tickoni Zig unit tests");

    // Files with no cross-module imports: standalone test binaries.
    for ([_][]const u8{
        "src/tickoni/runtime/topology.zig",
        "src/tickoni/runtime/tile.zig",
        "src/tickoni/c_abi/queue.zig",
        "src/tickoni/c_abi/sandbox.zig",
        "src/tickoni/tiles/synthetic.zig",
    }) |path| {
        const t_mod = b.createModule(.{
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
        });
        const t = b.addTest(.{ .root_module = t_mod });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }

    // supervisor.zig imports runtime and tiles modules.
    const sup_mod = b.createModule(.{
        .root_source_file = b.path("src/app/tickoni/supervisor.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "runtime", .module = runtime_mod },
            .{ .name = "tiles", .module = tiles_mod },
        },
    });
    const sup_test = b.addTest(.{ .root_module = sup_mod });
    test_step.dependOn(&b.addRunArtifact(sup_test).step);
}
