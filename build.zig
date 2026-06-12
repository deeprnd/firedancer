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
    const fd_lib_dir = b.option([]const u8, "fd-lib-dir", "Firedancer lib dir (default: build/native/gcc/lib)") orelse "build/native/gcc/lib";

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
    const audit_fixtures_gen_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/audit_fixtures_gen.zig"),
        .target = target,
        .optimize = optimize,
    });
    const thesis_cabi_mod = b.addModule("thesis_cabi", .{
        .root_source_file = b.path("src/tickoni/c_abi/thesis_codec.zig"),
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
    linkTickoniCodec(b, exe, fd_lib_dir);
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
        "src/tickoni/tiles/audit/mod.zig",
        "src/tickoni/tiles/payment_pipeline.zig",
    }) |path| {
        const t_mod = b.createModule(.{
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
            .imports = if (std.mem.eql(u8, path, "src/tickoni/tiles/audit/mod.zig") or
                std.mem.eql(u8, path, "src/tickoni/tiles/payment_pipeline.zig"))
                &.{
                    .{ .name = "audit_cabi", .module = audit_cabi_mod },
                    .{ .name = "audit_fixtures_gen", .module = audit_fixtures_gen_mod },
                }
            else
                &.{},
        });
        const t = b.addTest(.{ .root_module = t_mod });
        if (std.mem.eql(u8, path, "src/tickoni/tiles/audit/mod.zig") or
            std.mem.eql(u8, path, "src/tickoni/tiles/payment_pipeline.zig"))
        {
            linkTickoniCodec(b, t, fd_lib_dir);
        }
        test_step.dependOn(&b.addRunArtifact(t).step);
    }

    // thesis.zig imports thesis_cabi: dedicated test binary with codec link.
    const thesis_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/thesis.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "thesis_cabi", .module = thesis_cabi_mod }},
        }),
    });
    linkTickoniCodec(b, thesis_test, fd_lib_dir);
    test_step.dependOn(&b.addRunArtifact(thesis_test).step);

    // catalog.zig imports thesis.zig which imports thesis_cabi.
    const catalog_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/catalog.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "thesis_cabi", .module = thesis_cabi_mod }},
        }),
    });
    linkTickoniCodec(b, catalog_test, fd_lib_dir);
    test_step.dependOn(&b.addRunArtifact(catalog_test).step);

    // basket.zig imports catalog.zig and thesis.zig which imports thesis_cabi.
    const basket_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/basket.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "thesis_cabi", .module = thesis_cabi_mod }},
        }),
    });
    linkTickoniCodec(b, basket_test, fd_lib_dir);
    test_step.dependOn(&b.addRunArtifact(basket_test).step);

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
    linkTickoniCodec(b, sup_test, fd_lib_dir);
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
        .{ "test-audit", "src/tickoni/tiles/audit/mod.zig" },
        .{ "test-payment-pipeline", "src/tickoni/tiles/payment_pipeline.zig" },
    }) |entry| {
        const t = b.addTest(.{
            .name = entry[0],
            .root_module = b.createModule(.{
                .root_source_file = b.path(entry[1]),
                .target = target,
                .optimize = optimize,
                .imports = if (std.mem.eql(u8, entry[1], "src/tickoni/tiles/audit/mod.zig") or
                    std.mem.eql(u8, entry[1], "src/tickoni/tiles/payment_pipeline.zig"))
                    &.{
                        .{ .name = "audit_cabi", .module = audit_cabi_mod },
                        .{ .name = "audit_fixtures_gen", .module = audit_fixtures_gen_mod },
                    }
                else
                    &.{},
            }),
        });
        if (std.mem.eql(u8, entry[1], "src/tickoni/tiles/audit/mod.zig") or
            std.mem.eql(u8, entry[1], "src/tickoni/tiles/payment_pipeline.zig"))
        {
            linkTickoniCodec(b, t, fd_lib_dir);
        }
        cov_step.dependOn(&b.addInstallArtifact(t, .{
            .dest_dir = .{ .override = .{ .custom = "cov" } },
        }).step);
    }

    // thesis coverage binary.
    const thesis_cov_test = b.addTest(.{
        .name = "test-thesis",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/thesis.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "thesis_cabi", .module = thesis_cabi_mod }},
        }),
    });
    linkTickoniCodec(b, thesis_cov_test, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(thesis_cov_test, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    // catalog coverage binary.
    const catalog_cov_test = b.addTest(.{
        .name = "test-catalog",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/catalog.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "thesis_cabi", .module = thesis_cabi_mod }},
        }),
    });
    linkTickoniCodec(b, catalog_cov_test, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(catalog_cov_test, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    // basket coverage binary.
    const basket_cov_test = b.addTest(.{
        .name = "test-basket",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/basket.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "thesis_cabi", .module = thesis_cabi_mod }},
        }),
    });
    linkTickoniCodec(b, basket_cov_test, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(basket_cov_test, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

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
    linkTickoniCodec(b, sup_cov_test, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(sup_cov_test, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);
}

fn linkTickoniCodec(b: *std.Build, step: *std.Build.Step.Compile, fd_lib_dir: []const u8) void {
    step.root_module.link_libc = true;
    step.root_module.addIncludePath(b.path("src"));
    step.root_module.addCSourceFiles(.{
        .files = &.{
            "src/tickoni/codec/audit_pb.c",
            "src/tickoni/codec/thesis_hash.c",
        },
        .flags = &.{ "-std=c17", "-U__BMI2__", "-U__LZCNT__" },
    });
    step.root_module.addLibraryPath(b.path(fd_lib_dir));
    step.root_module.linkSystemLibrary("fd_util", .{});
    step.root_module.linkSystemLibrary("fd_ballet", .{});
    step.root_module.linkSystemLibrary("stdc++", .{});
}
