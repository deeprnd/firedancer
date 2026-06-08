/// Zig build for the Tickoni supervisor and its unit tests.
///
/// Build the supervisor:
///   zig build
///
/// Run harness unit tests (separate from 'make run-unit-test'):
///   zig build test
///
/// Install Zig test binaries for kcov coverage (used by just test-cov-tk):
///   zig build cov
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
    const audit_cabi_mod = b.addModule("audit_cabi", .{
        .root_source_file = b.path("src/tickoni/c_abi/audit_codec.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tiles_mod = b.addModule("tiles", .{
        .root_source_file = b.path("src/tickoni/tiles/payment_pipeline.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "audit_cabi", .module = audit_cabi_mod },
        },
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
    linkTickoniAuditCodec(b, exe);
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    if (b.args) |argv| run_exe.addArgs(argv);
    const run_step = b.step("run", "Run tickoni-supervisor");
    run_step.dependOn(&run_exe.step);

    // ---------------------------------------------------------------------------
    // Test step — not wired into 'make run-unit-test'
    // Run with: zig build test
    // ---------------------------------------------------------------------------
    const test_step = b.step("test", "Run harness unit tests");

    // Files with no cross-module imports: standalone test binaries.
    for ([_][]const u8{
        "src/tickoni/runtime/topology.zig",
        "src/tickoni/runtime/tile.zig",
        "src/tickoni/c_abi/queue.zig",
        "src/tickoni/c_abi/sandbox.zig",
        "src/tickoni/tiles/audit.zig",
        "src/tickoni/tiles/payment_pipeline.zig",
    }) |path| {
        const t_mod = b.createModule(.{
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
            .imports = if (std.mem.eql(u8, path, "src/tickoni/tiles/audit.zig") or
                std.mem.eql(u8, path, "src/tickoni/tiles/payment_pipeline.zig"))
                &.{.{ .name = "audit_cabi", .module = audit_cabi_mod }}
            else
                &.{},
        });
        const t = b.addTest(.{ .root_module = t_mod });
        if (std.mem.eql(u8, path, "src/tickoni/tiles/audit.zig") or
            std.mem.eql(u8, path, "src/tickoni/tiles/payment_pipeline.zig"))
        {
            linkTickoniAuditCodec(b, t);
        }
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
    linkTickoniAuditCodec(b, sup_test);
    test_step.dependOn(&b.addRunArtifact(sup_test).step);

    // ---------------------------------------------------------------------------
    // Coverage step — install test binaries to zig-out/cov/ for kcov
    // Run with: zig build cov
    // Then: bash contrib/coverage.sh coverage-tk
    // ---------------------------------------------------------------------------
    const cov_step = b.step("cov", "Install Zig test binaries to zig-out/cov/ for kcov coverage");

    for ([_][2][]const u8{
        .{ "test-topology", "src/tickoni/runtime/topology.zig" },
        .{ "test-tile", "src/tickoni/runtime/tile.zig" },
        .{ "test-queue", "src/tickoni/c_abi/queue.zig" },
        .{ "test-sandbox", "src/tickoni/c_abi/sandbox.zig" },
        .{ "test-audit", "src/tickoni/tiles/audit.zig" },
        .{ "test-payment-pipeline", "src/tickoni/tiles/payment_pipeline.zig" },
    }) |entry| {
        const t = b.addTest(.{
            .name = entry[0],
            .root_module = b.createModule(.{
                .root_source_file = b.path(entry[1]),
                .target = target,
                .optimize = optimize,
                .imports = if (std.mem.eql(u8, entry[1], "src/tickoni/tiles/audit.zig") or
                    std.mem.eql(u8, entry[1], "src/tickoni/tiles/payment_pipeline.zig"))
                    &.{.{ .name = "audit_cabi", .module = audit_cabi_mod }}
                else
                    &.{},
            }),
        });
        if (std.mem.eql(u8, entry[1], "src/tickoni/tiles/audit.zig") or
            std.mem.eql(u8, entry[1], "src/tickoni/tiles/payment_pipeline.zig"))
        {
            linkTickoniAuditCodec(b, t);
        }
        cov_step.dependOn(&b.addInstallArtifact(t, .{
            .dest_dir = .{ .override = .{ .custom = "cov" } },
        }).step);
    }

    const sup_cov_test = b.addTest(.{
        .name = "test-supervisor",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/app/tickoni/supervisor.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "runtime", .module = runtime_mod },
                .{ .name = "tiles", .module = tiles_mod },
            },
        }),
    });
    linkTickoniAuditCodec(b, sup_cov_test);
    cov_step.dependOn(&b.addInstallArtifact(sup_cov_test, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);
}

fn linkTickoniAuditCodec(b: *std.Build, step: *std.Build.Step.Compile) void {
    step.root_module.link_libc = true;
    step.root_module.addIncludePath(b.path("src"));
    step.root_module.addCSourceFiles(.{
        .files = &.{
            "src/tickoni/codec/audit_pb.c",
            "src/tickoni/codec/audit_json.c",
            "src/ballet/pb/fd_pb_tokenize.c",
            "src/ballet/json/cJSON.c",
        },
        .flags = &.{ "-std=c17", "-U__BMI2__", "-U__LZCNT__" },
    });
}
