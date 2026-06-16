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
    const audit_tile_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/audit/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "audit_cabi", .module = audit_cabi_mod },
            .{ .name = "audit_fixtures_gen", .module = audit_fixtures_gen_mod },
        },
    });
    const thesis_cabi_mod = b.addModule("thesis_cabi", .{
        .root_source_file = b.path("src/tickoni/c_abi/thesis_codec.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tiles_mod = b.addModule("tiles", .{
        .root_source_file = b.path("src/tickoni/tiles/payment_pipeline/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "audit_tile", .module = audit_tile_mod },
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
        "src/tickoni/tiles/payment_pipeline/mod.zig",
    }) |path| {
        const t_mod = if (std.mem.eql(u8, path, "src/tickoni/tiles/audit/mod.zig"))
            b.createModule(.{
                .root_source_file = b.path(path),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "audit_cabi", .module = audit_cabi_mod },
                    .{ .name = "audit_fixtures_gen", .module = audit_fixtures_gen_mod },
                },
            })
        else if (std.mem.eql(u8, path, "src/tickoni/tiles/payment_pipeline/mod.zig"))
            b.createModule(.{
                .root_source_file = b.path(path),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "audit_tile", .module = audit_tile_mod },
                },
            })
        else
            b.createModule(.{
                .root_source_file = b.path(path),
                .target = target,
                .optimize = optimize,
            });
        const t = b.addTest(.{ .root_module = t_mod });
        if (std.mem.eql(u8, path, "src/tickoni/tiles/audit/mod.zig") or
            std.mem.eql(u8, path, "src/tickoni/tiles/payment_pipeline/mod.zig"))
        {
            linkTickoniCodec(b, t, fd_lib_dir);
        }
        const t_run = b.addRunArtifact(t);
        test_step.dependOn(&t_run.step);
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
    const thesis_run = b.addRunArtifact(thesis_test);
    test_step.dependOn(&thesis_run.step);

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
    const catalog_run = b.addRunArtifact(catalog_test);
    test_step.dependOn(&catalog_run.step);

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
    const basket_run = b.addRunArtifact(basket_test);
    test_step.dependOn(&basket_run.step);

    // portfolio.zig imports basket.zig, which imports thesis.zig / thesis_cabi.
    const portfolio_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/portfolio.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "thesis_cabi", .module = thesis_cabi_mod }},
        }),
    });
    linkTickoniCodec(b, portfolio_test, fd_lib_dir);
    const portfolio_run = b.addRunArtifact(portfolio_test);
    test_step.dependOn(&portfolio_run.step);

    // model tile: unit tests use MockBackend only, no network calls.
    const model_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/tiles/model/mod.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const model_run = b.addRunArtifact(model_test);
    test_step.dependOn(&model_run.step);

    const thesis_adapter_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/thesis.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "thesis_cabi", .module = thesis_cabi_mod }},
    });
    const basket_adapter_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/basket.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "thesis_cabi", .module = thesis_cabi_mod },
            .{ .name = "thesis.zig", .module = thesis_adapter_test_mod },
        },
    });
    const portfolio_adapter_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/portfolio.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket.zig", .module = basket_adapter_test_mod },
        },
    });
    const trade_ticket_adapter_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/trade_ticket.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_adapter_test_mod },
            .{ .name = "portfolio", .module = portfolio_adapter_test_mod },
            .{ .name = "thesis", .module = thesis_adapter_test_mod },
        },
    });
    const adapter_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/tiles/adapter/mod.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = basket_adapter_test_mod },
                .{ .name = "portfolio", .module = portfolio_adapter_test_mod },
                .{ .name = "trade_ticket", .module = trade_ticket_adapter_test_mod },
            },
        }),
    });
    const adapter_run = b.addRunArtifact(adapter_test);
    test_step.dependOn(&adapter_run.step);

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
    const sup_run = b.addRunArtifact(sup_test);
    test_step.dependOn(&sup_run.step);

    // ---------------------------------------------------------------------------
    // Integration-test step — simple lane tests
    // Run with: zig build integration-test
    // ---------------------------------------------------------------------------
    const integration_step = b.step("integration-test", "Run investment demo integration tests");

    // Schema modules for the integration test.
    //
    // thesis.zig, basket.zig, and portfolio.zig use relative file imports
    // (@import("thesis.zig"), @import("basket.zig")) internally.  When each
    // schema file is simultaneously the root of its own named module AND a
    // relative-file import target inside another module, Zig rejects the build
    // with "file exists in modules X and Y".
    //
    // The fix is to register each relative import target as a *named* import
    // inside the module that would otherwise pick it up as a file.  When a
    // named import matches the path string passed to @import(), Zig uses the
    // module instead of the file, so each .zig file belongs to exactly one
    // module.
    //
    // Ownership chain:
    //   thesis_int_mod   owns thesis.zig (needs thesis_cabi)
    //   basket_int_mod   owns basket.zig (needs thesis_cabi; "thesis.zig" → thesis_int_mod
    //                    so basket.zig's @import("thesis.zig") and catalog.zig's
    //                    @import("thesis.zig") both resolve to thesis_int_mod)
    //   portfolio_int_mod owns portfolio.zig ("basket.zig" → basket_int_mod so
    //                    portfolio.zig's @import("basket.zig") resolves to basket_int_mod)
    const thesis_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/thesis.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "thesis_cabi", .module = thesis_cabi_mod }},
    });
    const basket_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/basket.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "thesis_cabi", .module = thesis_cabi_mod },
            .{ .name = "thesis.zig", .module = thesis_int_mod },
        },
    });
    const portfolio_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/portfolio.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket.zig", .module = basket_int_mod },
        },
    });
    const trade_ticket_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/trade_ticket.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_int_mod },
            .{ .name = "portfolio", .module = portfolio_int_mod },
            .{ .name = "thesis", .module = thesis_int_mod },
        },
    });

    const ai_infrastructure_allowed_trade_fixture_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/fixtures/investment/ai_infrastructure_allowed_trade.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "thesis", .module = thesis_int_mod },
                .{ .name = "basket", .module = basket_int_mod },
                .{ .name = "portfolio", .module = portfolio_int_mod },
            },
        }),
    });
    linkTickoniCodec(b, ai_infrastructure_allowed_trade_fixture_test, fd_lib_dir);
    const ai_infrastructure_fixture_run = b.addRunArtifact(ai_infrastructure_allowed_trade_fixture_test);
    integration_step.dependOn(&ai_infrastructure_fixture_run.step);

    const model_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/model/mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    const adapter_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/adapter/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_int_mod },
            .{ .name = "portfolio", .module = portfolio_int_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_int_mod },
        },
    });
    const tool_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/tool/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "basket", .module = basket_int_mod },
            .{ .name = "portfolio", .module = portfolio_int_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_int_mod },
        },
    });
    const replay_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/replay/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_int_mod },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_int_mod },
        },
    });
    const investment_audit_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/audit/investment_demo.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "audit_tile", .module = audit_tile_mod },
            .{ .name = "basket", .module = basket_int_mod },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "portfolio", .module = portfolio_int_mod },
            .{ .name = "replay", .module = replay_int_mod },
            .{ .name = "thesis", .module = thesis_int_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_int_mod },
        },
    });
    const allowed_trade_e2e_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/e2e/allowed_trade.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "adapter", .module = adapter_int_mod },
                .{ .name = "audit_tile", .module = audit_tile_mod },
                .{ .name = "basket", .module = basket_int_mod },
                .{ .name = "investment_audit", .module = investment_audit_int_mod },
                .{ .name = "model", .module = model_int_mod },
                .{ .name = "portfolio", .module = portfolio_int_mod },
                .{ .name = "replay", .module = replay_int_mod },
                .{ .name = "thesis", .module = thesis_int_mod },
                .{ .name = "tool", .module = tool_int_mod },
                .{ .name = "trade_ticket", .module = trade_ticket_int_mod },
            },
        }),
    });
    linkTickoniCodec(b, allowed_trade_e2e_test, fd_lib_dir);
    const allowed_trade_e2e_run = b.addRunArtifact(allowed_trade_e2e_test);
    integration_step.dependOn(&allowed_trade_e2e_run.step);

    // model tile integration tests: require a running llama.cpp server.
    // Run with: zig build integration-test-live-model
    const live_model_step = b.step("integration-test-live-model", "Run live tkmodl llama.cpp smoke tests");
    const model_http_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/model_tile_http.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "model", .module = model_int_mod }},
        }),
    });
    model_http_test.root_module.link_libc = true;
    const model_http_run = b.addRunArtifact(model_http_test);
    live_model_step.dependOn(&model_http_run.step);

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
        .{ "test-payment-pipeline", "src/tickoni/tiles/payment_pipeline/mod.zig" },
    }) |entry| {
        const t = b.addTest(.{
            .name = entry[0],
            .root_module = if (std.mem.eql(u8, entry[1], "src/tickoni/tiles/audit/mod.zig"))
                b.createModule(.{
                    .root_source_file = b.path(entry[1]),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "audit_cabi", .module = audit_cabi_mod },
                        .{ .name = "audit_fixtures_gen", .module = audit_fixtures_gen_mod },
                    },
                })
            else if (std.mem.eql(u8, entry[1], "src/tickoni/tiles/payment_pipeline/mod.zig"))
                b.createModule(.{
                    .root_source_file = b.path(entry[1]),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "audit_tile", .module = audit_tile_mod },
                    },
                })
            else
                b.createModule(.{
                    .root_source_file = b.path(entry[1]),
                    .target = target,
                    .optimize = optimize,
                }),
        });
        if (std.mem.eql(u8, entry[1], "src/tickoni/tiles/audit/mod.zig") or
            std.mem.eql(u8, entry[1], "src/tickoni/tiles/payment_pipeline/mod.zig"))
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

    // portfolio coverage binary.
    const portfolio_cov_test = b.addTest(.{
        .name = "test-portfolio",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/portfolio.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "thesis_cabi", .module = thesis_cabi_mod }},
        }),
    });
    linkTickoniCodec(b, portfolio_cov_test, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(portfolio_cov_test, .{
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
