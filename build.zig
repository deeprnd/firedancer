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
    const clap_dep = b.dependency("clap", .{});
    const clap_mod = clap_dep.module("clap");

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

    // ---------------------------------------------------------------------------
    // Shared schema modules — single instances used across all test lanes.
    // All cross-module imports use named imports (@import("name")) so each
    // source file belongs to exactly one module instance, eliminating the
    // "file exists in modules X and Y" build constraint.
    // ---------------------------------------------------------------------------
    const classification_mod = b.addModule("classification", .{
        .root_source_file = b.path("src/tickoni/schema/classification/classification.zig"),
        .target = target,
        .optimize = optimize,
    });
    const thesis_mod = b.addModule("thesis", .{
        .root_source_file = b.path("src/tickoni/schema/investment/thesis.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "thesis_cabi", .module = thesis_cabi_mod },
            .{ .name = "classification", .module = classification_mod },
        },
    });
    const catalog_mod = b.addModule("catalog", .{
        .root_source_file = b.path("src/tickoni/schema/investment/catalog.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "thesis", .module = thesis_mod },
        },
    });
    const basket_mod = b.addModule("basket", .{
        .root_source_file = b.path("src/tickoni/schema/investment/basket.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "thesis_cabi", .module = thesis_cabi_mod },
            .{ .name = "thesis", .module = thesis_mod },
            .{ .name = "catalog", .module = catalog_mod },
        },
    });
    const portfolio_mod = b.addModule("portfolio", .{
        .root_source_file = b.path("src/tickoni/schema/portfolio/portfolio.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
        },
    });
    const portfolio_fixtures_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test_support/fixtures/portfolio_fixtures.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "basket", .module = basket_mod },
        },
    });
    const trade_ticket_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/investment/trade_ticket.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "portfolio_fixtures", .module = portfolio_fixtures_mod },
            .{ .name = "thesis", .module = thesis_mod },
        },
    });
    const impact_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/investment/impact.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
        },
    });
    const cards_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/investment/cards.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "impact", .module = impact_mod },
        },
    });
    const drift_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/investment/drift.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "cards", .module = cards_mod },
        },
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
    // Test step — offline Tickoni unit tests only.
    // Pure logic and fixture/mock-backed proofs belong here; no running servers.
    // Run with: zig build test
    // ---------------------------------------------------------------------------
    const test_step = b.step("test", "Run offline Tickoni unit tests");

    // Files with no cross-module imports: standalone test binaries.
    for ([_][]const u8{
        "src/tickoni/runtime/topology.zig",
        "src/tickoni/runtime/tile.zig",
        "src/tickoni/c_abi/queue.zig",
        "src/tickoni/c_abi/sandbox.zig",
        "src/tickoni/tiles/audit/mod.zig",
        "src/tickoni/tiles/payment_pipeline/mod.zig",
        "src/tickoni/tiles/case/mod.zig",
        "src/tickoni/tiles/disp/mod.zig",
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

    // thesis.zig: fresh root module (not the shared thesis_mod) so that
    // linkTickoniCodec adds C sources only to this binary's root module.
    const thesis_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/investment/thesis.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "thesis_cabi", .module = thesis_cabi_mod },
                .{ .name = "classification", .module = classification_mod },
            },
        }),
    });
    linkTickoniCodec(b, thesis_test, fd_lib_dir);
    test_step.dependOn(&b.addRunArtifact(thesis_test).step);

    const catalog_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/investment/catalog.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "thesis", .module = thesis_mod },
            },
        }),
    });
    linkTickoniCodec(b, catalog_test, fd_lib_dir);
    test_step.dependOn(&b.addRunArtifact(catalog_test).step);

    const basket_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/investment/basket.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "thesis_cabi", .module = thesis_cabi_mod },
                .{ .name = "thesis", .module = thesis_mod },
                .{ .name = "catalog", .module = catalog_mod },
            },
        }),
    });
    linkTickoniCodec(b, basket_test, fd_lib_dir);
    test_step.dependOn(&b.addRunArtifact(basket_test).step);

    const portfolio_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/portfolio/portfolio.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = basket_mod },
            },
        }),
    });
    linkTickoniCodec(b, portfolio_test, fd_lib_dir);
    test_step.dependOn(&b.addRunArtifact(portfolio_test).step);

    const portfolio_fixtures_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test_support/fixtures/portfolio_fixtures.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "portfolio", .module = portfolio_mod },
                .{ .name = "basket", .module = basket_mod },
            },
        }),
    });
    linkTickoniCodec(b, portfolio_fixtures_test, fd_lib_dir);
    test_step.dependOn(&b.addRunArtifact(portfolio_fixtures_test).step);

    // model tile: unit tests are mock/fixture-backed and must not start servers.
    const model_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/model/mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    const model_test = b.addTest(.{
        .root_module = model_test_mod,
    });
    test_step.dependOn(&b.addRunArtifact(model_test).step);

    const tkpoly_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/policy/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "thesis", .module = thesis_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });
    const adapter_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/adapter/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "portfolio_fixtures", .module = portfolio_fixtures_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });
    const adapter_test = b.addTest(.{
        .root_module = adapter_test_mod,
    });
    test_step.dependOn(&b.addRunArtifact(adapter_test).step);

    // trade_ticket.zig imports basket, portfolio, portfolio_fixtures, and thesis.
    const trade_ticket_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/investment/trade_ticket.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = basket_mod },
                .{ .name = "portfolio", .module = portfolio_mod },
                .{ .name = "portfolio_fixtures", .module = portfolio_fixtures_mod },
                .{ .name = "thesis", .module = thesis_mod },
            },
        }),
    });
    linkTickoniCodec(b, trade_ticket_test, fd_lib_dir);
    test_step.dependOn(&b.addRunArtifact(trade_ticket_test).step);

    // impact.zig: portfolio and cash impact model (V1.3.S1).
    const impact_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/investment/impact.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = basket_mod },
                .{ .name = "portfolio", .module = portfolio_mod },
            },
        }),
    });
    linkTickoniCodec(b, impact_test, fd_lib_dir);
    test_step.dependOn(&b.addRunArtifact(impact_test).step);

    // cards.zig: thesis and money proposal card schemas (V1.3.S2).
    const cards_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/investment/cards.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = basket_mod },
                .{ .name = "impact", .module = impact_mod },
            },
        }),
    });
    linkTickoniCodec(b, cards_test, fd_lib_dir);
    test_step.dependOn(&b.addRunArtifact(cards_test).step);

    // drift.zig: drift conditions, assessment, and suggestion generation (V1.3.S3).
    const drift_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/investment/drift.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = basket_mod },
                .{ .name = "cards", .module = cards_mod },
            },
        }),
    });
    linkTickoniCodec(b, drift_test, fd_lib_dir);
    test_step.dependOn(&b.addRunArtifact(drift_test).step);

    const allowed_trade_fixture_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/fixtures/investment/allowed_trade.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "thesis", .module = thesis_mod },
                .{ .name = "basket", .module = basket_mod },
                .{ .name = "portfolio", .module = portfolio_mod },
                .{ .name = "portfolio_fixtures", .module = portfolio_fixtures_mod },
            },
        }),
    });
    linkTickoniCodec(b, allowed_trade_fixture_test, fd_lib_dir);
    test_step.dependOn(&b.addRunArtifact(allowed_trade_fixture_test).step);

    const denied_trade_fixture_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/fixtures/investment/denied_trade.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "thesis", .module = thesis_mod },
                .{ .name = "basket", .module = basket_mod },
            },
        }),
    });
    linkTickoniCodec(b, denied_trade_fixture_test, fd_lib_dir);
    test_step.dependOn(&b.addRunArtifact(denied_trade_fixture_test).step);

    const tool_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/tool/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_test_mod },
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "portfolio_fixtures", .module = portfolio_fixtures_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });
    const tool_test = b.addTest(.{ .root_module = tool_test_mod });
    test_step.dependOn(&b.addRunArtifact(tool_test).step);

    const disp_unit_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/disp/mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    const agent_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/tiles/agent/mod.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "adapter", .module = adapter_test_mod },
                .{ .name = "basket", .module = basket_mod },
                .{ .name = "disp", .module = disp_unit_mod },
                .{ .name = "model", .module = model_test_mod },
                .{ .name = "portfolio", .module = portfolio_mod },
                .{ .name = "tkpoly", .module = tkpoly_test_mod },
                .{ .name = "tool", .module = tool_test_mod },
                .{ .name = "trade_ticket", .module = trade_ticket_mod },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(agent_test).step);

    const replay_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/tiles/replay/mod.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "adapter", .module = adapter_test_mod },
                .{ .name = "basket", .module = basket_mod },
                .{ .name = "drift", .module = drift_mod },
                .{ .name = "model", .module = model_test_mod },
                .{ .name = "portfolio", .module = portfolio_mod },
                .{ .name = "tkpoly", .module = tkpoly_test_mod },
                .{ .name = "trade_ticket", .module = trade_ticket_mod },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(replay_test).step);

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
    // Integration-test step — transport and boundary wiring against local mocks.
    // Local mock HTTP servers live here; this lane must stay deterministic.
    // Run with: zig build integration-test
    // ---------------------------------------------------------------------------
    const integration_step = b.step("integration-test", "Run Tickoni mock-backed integration tests");

    // Schema modules are shared (thesis_mod, basket_mod, portfolio_mod, etc.).
    // Integration tile modules are fresh instances so they don't inherit any
    // C source additions from the unit test lane.
    const tkpoly_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/policy/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "thesis", .module = thesis_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });

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
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "portfolio_fixtures", .module = portfolio_fixtures_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });
    const tool_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/tool/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "portfolio_fixtures", .module = portfolio_fixtures_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });
    const case_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/case/mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    const disp_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/disp/mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    const agent_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/agent/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "disp", .module = disp_int_mod },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "tkpoly", .module = tkpoly_int_mod },
            .{ .name = "tool", .module = tool_int_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });
    const replay_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/replay/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "drift", .module = drift_mod },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "tkpoly", .module = tkpoly_int_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });
    const investment_audit_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/audit/investment_audit.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "audit_tile", .module = audit_tile_mod },
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "drift", .module = drift_mod },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "replay", .module = replay_int_mod },
            .{ .name = "thesis", .module = thesis_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });
    const investment_support_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/integration/investment_support.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "thesis", .module = thesis_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });
    const investment_demo_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/demo/investment.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "cards", .module = cards_mod },
            .{ .name = "drift", .module = drift_mod },
            .{ .name = "impact", .module = impact_mod },
            .{ .name = "investment_support", .module = investment_support_int_mod },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "replay", .module = replay_int_mod },
            .{ .name = "thesis", .module = thesis_mod },
            .{ .name = "tkpoly", .module = tkpoly_int_mod },
            .{ .name = "tool", .module = tool_int_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });
    const investment_demo_test = b.addTest(.{ .root_module = investment_demo_mod });
    linkTickoniCodec(b, investment_demo_test, fd_lib_dir);
    test_step.dependOn(&b.addRunArtifact(investment_demo_test).step);
    for ([_][]const u8{
        "src/tickoni/test/integration/investment_allowed_trade.zig",
        "src/tickoni/test/integration/investment_blocked_limits.zig",
        "src/tickoni/test/integration/investment_restricted_instrument.zig",
        "src/tickoni/test/integration/investment_input_policy_denials.zig",
        "src/tickoni/test/integration/model_tile_http.zig",
        "src/tickoni/test/integration/mock_servers.zig",
    }) |path| {
        const integration_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(path),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "adapter", .module = adapter_int_mod },
                    .{ .name = "audit_tile", .module = audit_tile_mod },
                    .{ .name = "basket", .module = basket_mod },
                    .{ .name = "investment_audit", .module = investment_audit_int_mod },
                    .{ .name = "investment_support", .module = investment_support_int_mod },
                    .{ .name = "model", .module = model_int_mod },
                    .{ .name = "portfolio", .module = portfolio_mod },
                    .{ .name = "replay", .module = replay_int_mod },
                    .{ .name = "thesis", .module = thesis_mod },
                    .{ .name = "tkpoly", .module = tkpoly_int_mod },
                    .{ .name = "tool", .module = tool_int_mod },
                    .{ .name = "trade_ticket", .module = trade_ticket_mod },
                    .{ .name = "tkcase", .module = case_int_mod },
                    .{ .name = "tkdisp", .module = disp_int_mod },
                    .{ .name = "tkagnt", .module = agent_int_mod },
                },
            }),
        });
        linkTickoniCodec(b, integration_test, fd_lib_dir);
        integration_step.dependOn(&b.addRunArtifact(integration_test).step);
    }

    const replay_integration_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/investment_replay.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "adapter", .module = adapter_int_mod },
                .{ .name = "audit_tile", .module = audit_tile_mod },
                .{ .name = "basket", .module = basket_mod },
                .{ .name = "investment_demo", .module = investment_demo_mod },
                .{ .name = "investment_audit", .module = investment_audit_int_mod },
                .{ .name = "investment_support", .module = investment_support_int_mod },
                .{ .name = "model", .module = model_int_mod },
                .{ .name = "portfolio", .module = portfolio_mod },
                .{ .name = "replay", .module = replay_int_mod },
                .{ .name = "thesis", .module = thesis_mod },
                .{ .name = "tkpoly", .module = tkpoly_int_mod },
                .{ .name = "tool", .module = tool_int_mod },
                .{ .name = "trade_ticket", .module = trade_ticket_mod },
                .{ .name = "tkcase", .module = case_int_mod },
                .{ .name = "tkdisp", .module = disp_int_mod },
                .{ .name = "tkagnt", .module = agent_int_mod },
            },
        }),
    });
    replay_integration_test.root_module.addLibraryPath(b.path(fd_lib_dir));
    replay_integration_test.root_module.linkSystemLibrary("fd_util", .{});
    replay_integration_test.root_module.linkSystemLibrary("fd_ballet", .{});
    replay_integration_test.root_module.linkSystemLibrary("stdc++", .{});
    integration_step.dependOn(&b.addRunArtifact(replay_integration_test).step);

    const decision_cards_integration_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/investment_decision_cards.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "investment_demo", .module = investment_demo_mod },
                .{ .name = "investment_support", .module = investment_support_int_mod },
            },
        }),
    });
    decision_cards_integration_test.root_module.addLibraryPath(b.path(fd_lib_dir));
    decision_cards_integration_test.root_module.linkSystemLibrary("fd_util", .{});
    decision_cards_integration_test.root_module.linkSystemLibrary("fd_ballet", .{});
    decision_cards_integration_test.root_module.linkSystemLibrary("stdc++", .{});
    integration_step.dependOn(&b.addRunArtifact(decision_cards_integration_test).step);

    const system_step = b.step("system-test", "Run live V1.1 system/demo proofs");
    const system_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/system/investment_demo_live.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "investment_demo", .module = investment_demo_mod },
            },
        }),
    });
    system_test.root_module.addLibraryPath(b.path(fd_lib_dir));
    system_test.root_module.linkSystemLibrary("fd_util", .{});
    system_test.root_module.linkSystemLibrary("fd_ballet", .{});
    system_test.root_module.linkSystemLibrary("stdc++", .{});
    system_step.dependOn(&b.addRunArtifact(system_test).step);

    // Compatibility alias for the old live-model smoke command.
    const live_model_step = b.step("integration-test-live-model", "Alias for the live V1.1 system/demo lane");
    live_model_step.dependOn(system_step);

    const cli_main_mod = b.createModule(.{
        .root_source_file = b.path("src/app/tickoni_cli/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "clap", .module = clap_mod },
            .{ .name = "investment_demo", .module = investment_demo_mod },
        },
    });
    const cli_exe = b.addExecutable(.{
        .name = "tickoni",
        .root_module = cli_main_mod,
    });
    cli_exe.root_module.addLibraryPath(b.path(fd_lib_dir));
    cli_exe.root_module.linkSystemLibrary("fd_util", .{});
    cli_exe.root_module.linkSystemLibrary("fd_ballet", .{});
    cli_exe.root_module.linkSystemLibrary("stdc++", .{});
    b.installArtifact(cli_exe);

    const run_cli = b.addRunArtifact(cli_exe);
    if (b.args) |argv| run_cli.addArgs(argv);
    const run_cli_step = b.step("run-cli", "Run tickoni demo CLI");
    run_cli_step.dependOn(&run_cli.step);

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
        .{ "test-case", "src/tickoni/tiles/case/mod.zig" },
        .{ "test-disp", "src/tickoni/tiles/disp/mod.zig" },
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

    const thesis_cov_test = b.addTest(.{
        .name = "test-thesis",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/investment/thesis.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "thesis_cabi", .module = thesis_cabi_mod },
                .{ .name = "classification", .module = classification_mod },
            },
        }),
    });
    linkTickoniCodec(b, thesis_cov_test, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(thesis_cov_test, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const catalog_cov_test = b.addTest(.{
        .name = "test-catalog",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/investment/catalog.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "thesis", .module = thesis_mod },
            },
        }),
    });
    linkTickoniCodec(b, catalog_cov_test, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(catalog_cov_test, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const portfolio_cov_test = b.addTest(.{
        .name = "test-portfolio",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/portfolio/portfolio.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = basket_mod },
            },
        }),
    });
    linkTickoniCodec(b, portfolio_cov_test, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(portfolio_cov_test, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const portfolio_fixtures_cov_test = b.addTest(.{
        .name = "test-portfolio-fixtures",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test_support/fixtures/portfolio_fixtures.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "portfolio", .module = portfolio_mod },
                .{ .name = "basket", .module = basket_mod },
            },
        }),
    });
    linkTickoniCodec(b, portfolio_fixtures_cov_test, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(portfolio_fixtures_cov_test, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const trade_ticket_cov_test = b.addTest(.{
        .name = "test-trade-ticket",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/investment/trade_ticket.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = basket_mod },
                .{ .name = "portfolio", .module = portfolio_mod },
                .{ .name = "portfolio_fixtures", .module = portfolio_fixtures_mod },
                .{ .name = "thesis", .module = thesis_mod },
            },
        }),
    });
    linkTickoniCodec(b, trade_ticket_cov_test, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(trade_ticket_cov_test, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const impact_cov_test = b.addTest(.{
        .name = "test-impact",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/investment/impact.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = basket_mod },
                .{ .name = "portfolio", .module = portfolio_mod },
            },
        }),
    });
    linkTickoniCodec(b, impact_cov_test, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(impact_cov_test, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const basket_cov_test = b.addTest(.{
        .name = "test-basket",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/investment/basket.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "thesis_cabi", .module = thesis_cabi_mod },
                .{ .name = "thesis", .module = thesis_mod },
                .{ .name = "catalog", .module = catalog_mod },
            },
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
