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
    const c_abi_mod = b.addModule("c_abi", .{
        .root_source_file = b.path("src/tickoni/c_abi/c_abi.zig"),
        .target = target,
        .optimize = optimize,
    });
    const runtime_mod = b.addModule("runtime", .{
        .root_source_file = b.path("src/tickoni/runtime/runtime.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c_abi", .module = c_abi_mod },
        },
    });
    const audit_codec_mod = b.addModule("audit_codec", .{
        .root_source_file = b.path("src/tickoni/codec/audit_codec.zig"),
        .target = target,
        .optimize = optimize,
    });
    const fixture_audit_gen_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/fixtures/fixture_audit_gen.zig"),
        .target = target,
        .optimize = optimize,
    });
    const audit_tile_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/audit/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "audit_codec", .module = audit_codec_mod },
            .{ .name = "fixture_audit_gen", .module = fixture_audit_gen_mod },
        },
    });
    const thesis_codec_mod = b.addModule("thesis_codec", .{
        .root_source_file = b.path("src/tickoni/codec/thesis_codec.zig"),
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
        .root_source_file = b.path("src/tickoni/schema/consumer_money/thesis.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "thesis_codec", .module = thesis_codec_mod },
            .{ .name = "classification", .module = classification_mod },
        },
    });
    const catalog_mod = b.addModule("catalog", .{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/catalog.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "thesis", .module = thesis_mod },
        },
    });
    const basket_mod = b.addModule("basket", .{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/basket.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "thesis_codec", .module = thesis_codec_mod },
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
    const fixture_portfolio_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/fixtures/portfolio/fixture_portfolio.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "basket", .module = basket_mod },
        },
    });
    const trade_ticket_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/trade_ticket.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "fixture_portfolio", .module = fixture_portfolio_mod },
            .{ .name = "thesis", .module = thesis_mod },
        },
    });
    const impact_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/impact.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
        },
    });
    const cards_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/cards.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "impact", .module = impact_mod },
        },
    });
    const drift_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/drift.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "cards", .module = cards_mod },
        },
    });

    // Tile-local message types promoted to singleton modules solely so that
    // src/tickoni/test/mocks/*_mock.zig (pure test doubles, not part of a
    // tile's production surface) can reference the exact same request/response
    // types used by each tile's own Backend union, without an import cycle.
    const model_messages_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/model/messages.zig"),
        .target = target,
        .optimize = optimize,
    });
    const mock_model_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/mocks/mock_model.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "model_messages", .module = model_messages_mod },
        },
    });
    const adapter_messages_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/adapter/messages.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });
    const mock_adapter_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/mocks/mock_adapter.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "fixture_portfolio", .module = fixture_portfolio_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
            .{ .name = "adapter_messages", .module = adapter_messages_mod },
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
            .{ .name = "c_abi", .module = c_abi_mod },
        },
    });
    const exe = b.addExecutable(.{
        .name = "tickoni-supervisor",
        .root_module = main_mod,
    });
    linkTickoniCodec(b, exe, fd_lib_dir);
    linkTickoniTango(b, exe, fd_lib_dir);
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
        "src/tickoni/c_abi/dcache.zig",
        "src/tickoni/c_abi/fseq.zig",
        "src/tickoni/c_abi/cnc.zig",
        "src/tickoni/c_abi/wksp.zig",
        "src/tickoni/c_abi/process.zig",
        "src/tickoni/c_abi/boot.zig",
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
                    .{ .name = "audit_codec", .module = audit_codec_mod },
                    .{ .name = "fixture_audit_gen", .module = fixture_audit_gen_mod },
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
        if (std.mem.eql(u8, path, "src/tickoni/c_abi/queue.zig") or
            std.mem.eql(u8, path, "src/tickoni/c_abi/dcache.zig") or
            std.mem.eql(u8, path, "src/tickoni/c_abi/fseq.zig") or
            std.mem.eql(u8, path, "src/tickoni/c_abi/cnc.zig"))
        {
            // These tests call real Firedancer substrate through the tk_ shim
            // layer, not native Zig mirrors or direct fd_* externs.
            linkTickoniTango(b, t, fd_lib_dir);
        }
        const t_run = b.addRunArtifact(t);
        test_step.dependOn(&t_run.step);
    }

    // thesis.zig: fresh root module (not the shared thesis_mod) so that
    // linkTickoniCodec adds C sources only to this binary's root module.
    const thesis_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/consumer_money/thesis.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "thesis_codec", .module = thesis_codec_mod },
                .{ .name = "classification", .module = classification_mod },
            },
        }),
    });
    linkTickoniCodec(b, thesis_test, fd_lib_dir);
    test_step.dependOn(&b.addRunArtifact(thesis_test).step);

    const catalog_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/consumer_money/catalog.zig"),
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
            .root_source_file = b.path("src/tickoni/schema/consumer_money/basket.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "thesis_codec", .module = thesis_codec_mod },
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

    const fixture_portfolio_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/fixtures/portfolio/fixture_portfolio.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "portfolio", .module = portfolio_mod },
                .{ .name = "basket", .module = basket_mod },
            },
        }),
    });
    linkTickoniCodec(b, fixture_portfolio_test, fd_lib_dir);
    test_step.dependOn(&b.addRunArtifact(fixture_portfolio_test).step);

    const model_messages_test = b.addTest(.{ .root_module = model_messages_mod });
    test_step.dependOn(&b.addRunArtifact(model_messages_test).step);

    // shm_link.zig imports c_abi; layout/shape tests only (no real
    // fd_wksp/fd_tango calls in the offline unit lane).
    const shm_link_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/runtime/shm_link.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "c_abi", .module = c_abi_mod },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(shm_link_test).step);

    // cpu_placement.zig imports c_abi for the live-CPU-set check.
    const cpu_placement_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/runtime/cpu_placement.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "c_abi", .module = c_abi_mod },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(cpu_placement_test).step);

    // launch_spec.zig embeds shm_link.LinkHandles, which imports c_abi.
    const launch_spec_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/runtime/launch_spec.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "c_abi", .module = c_abi_mod },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(launch_spec_test).step);

    // model tile: unit tests are mock/fixture-backed and must not start servers.
    const model_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/model/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "model_messages", .module = model_messages_mod },
            .{ .name = "mock_model", .module = mock_model_mod },
        },
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
            .{ .name = "fixture_portfolio", .module = fixture_portfolio_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
            .{ .name = "adapter_messages", .module = adapter_messages_mod },
            .{ .name = "mock_adapter", .module = mock_adapter_mod },
        },
    });
    const adapter_test = b.addTest(.{
        .root_module = adapter_test_mod,
    });
    test_step.dependOn(&b.addRunArtifact(adapter_test).step);

    const mock_adapter_test = b.addTest(.{ .root_module = mock_adapter_mod });
    test_step.dependOn(&b.addRunArtifact(mock_adapter_test).step);

    // trade_ticket.zig imports basket, portfolio, fixture_portfolio, and thesis.
    const trade_ticket_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/consumer_money/trade_ticket.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = basket_mod },
                .{ .name = "portfolio", .module = portfolio_mod },
                .{ .name = "fixture_portfolio", .module = fixture_portfolio_mod },
                .{ .name = "thesis", .module = thesis_mod },
            },
        }),
    });
    linkTickoniCodec(b, trade_ticket_test, fd_lib_dir);
    test_step.dependOn(&b.addRunArtifact(trade_ticket_test).step);

    // impact.zig: portfolio and cash impact model (V1.3.S1).
    const impact_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/consumer_money/impact.zig"),
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
            .root_source_file = b.path("src/tickoni/schema/consumer_money/cards.zig"),
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
            .root_source_file = b.path("src/tickoni/schema/consumer_money/drift.zig"),
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
            .root_source_file = b.path("src/tickoni/test/fixtures/investment/fixture_allowed_trade.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "thesis", .module = thesis_mod },
                .{ .name = "basket", .module = basket_mod },
                .{ .name = "portfolio", .module = portfolio_mod },
                .{ .name = "fixture_portfolio", .module = fixture_portfolio_mod },
            },
        }),
    });
    linkTickoniCodec(b, allowed_trade_fixture_test, fd_lib_dir);
    test_step.dependOn(&b.addRunArtifact(allowed_trade_fixture_test).step);

    const denied_trade_fixture_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/fixtures/investment/fixture_denied_trade.zig"),
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
            .{ .name = "fixture_portfolio", .module = fixture_portfolio_mod },
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
                .{ .name = "mock_adapter", .module = mock_adapter_mod },
                .{ .name = "basket", .module = basket_mod },
                .{ .name = "disp", .module = disp_unit_mod },
                .{ .name = "model", .module = model_test_mod },
                .{ .name = "mock_model", .module = mock_model_mod },
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

    // supervisor.zig imports runtime, tiles, and c_abi modules.
    const sup_mod = b.createModule(.{
        .root_source_file = b.path("src/app/tickoni/supervisor.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "runtime", .module = runtime_mod },
            .{ .name = "tiles", .module = tiles_mod },
            .{ .name = "c_abi", .module = c_abi_mod },
        },
    });
    // Named module (vs. sup_mod's anonymous instance above) so
    // src/tickoni/test/integration process-mode tests can import the
    // Supervisor type without a cross-tree relative path.
    const supervisor_named_mod = b.addModule("supervisor", .{
        .root_source_file = b.path("src/app/tickoni/supervisor.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "runtime", .module = runtime_mod },
            .{ .name = "tiles", .module = tiles_mod },
            .{ .name = "c_abi", .module = c_abi_mod },
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
        .imports = &.{
            .{ .name = "model_messages", .module = model_messages_mod },
            .{ .name = "mock_model", .module = mock_model_mod },
        },
    });
    const adapter_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/adapter/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "fixture_portfolio", .module = fixture_portfolio_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
            .{ .name = "adapter_messages", .module = adapter_messages_mod },
            .{ .name = "mock_adapter", .module = mock_adapter_mod },
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
            .{ .name = "fixture_portfolio", .module = fixture_portfolio_mod },
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
            .{ .name = "mock_adapter", .module = mock_adapter_mod },
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "disp", .module = disp_int_mod },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "mock_model", .module = mock_model_mod },
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
        .root_source_file = b.path("src/tickoni/test/demo/investment/audit_trace.zig"),
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
        .root_source_file = b.path("src/tickoni/test/demo/investment/support.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "thesis", .module = thesis_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });
    const investment_demo_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/demo/investment/mod.zig"),
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
        "src/tickoni/test/integration/test_investment_allowed_trade.zig",
        "src/tickoni/test/integration/test_investment_blocked_limits.zig",
        "src/tickoni/test/integration/test_investment_restricted_instrument.zig",
        "src/tickoni/test/integration/test_investment_input_policy_denials.zig",
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

    // Shared by every process-mode integration test below: each self-execs
    // zig-out/bin/tickoni-supervisor per tile (see
    // ProcessPipelineConfig.tile_exe_path). One shared install step, not
    // one addInstallArtifact(exe, .{}) call per test — three separate
    // install actions targeting the same destination file were the prime
    // suspect for a hang where one test's install raced another test's
    // already-spawned children exec'ing that same path.
    const process_mode_exe_install = b.addInstallArtifact(exe, .{});

    // V1.14.S1 process-mode payment pipeline: spawns real supervisor-managed
    // tile processes over Firedancer Tango shared memory. Tickoni internals
    // run for real; the "external tool" substituted per
    // doc/execution/testing-tickoni.md's integration-lane rule is the
    // operator-managed host workspace path, replaced by a scratch
    // FD_SHMEM_PATH directory under zig-cache/tmp. No huge pages or sudo.
    const process_pipeline_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/test_process_pipeline.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "runtime", .module = runtime_mod },
                .{ .name = "c_abi", .module = c_abi_mod },
                .{ .name = "supervisor", .module = supervisor_named_mod },
            },
        }),
    });
    linkTickoniCodec(b, process_pipeline_test, fd_lib_dir);
    linkTickoniTango(b, process_pipeline_test, fd_lib_dir);
    const run_process_pipeline_test = addPlainTestRun(b, process_pipeline_test);
    run_process_pipeline_test.step.dependOn(&process_mode_exe_install.step);
    integration_step.dependOn(&run_process_pipeline_test.step);

    // V1.14.S1 M5: explicit shared-core CPU placement and the
    // CPU-unavailable fail-closed path, both through the real supervisor.
    const process_cpu_placement_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/test_process_cpu_placement.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "runtime", .module = runtime_mod },
                .{ .name = "c_abi", .module = c_abi_mod },
                .{ .name = "supervisor", .module = supervisor_named_mod },
            },
        }),
    });
    linkTickoniCodec(b, process_cpu_placement_test, fd_lib_dir);
    linkTickoniTango(b, process_cpu_placement_test, fd_lib_dir);
    const run_process_cpu_placement_test = addPlainTestRun(b, process_cpu_placement_test);
    run_process_cpu_placement_test.step.dependOn(&process_mode_exe_install.step);
    integration_step.dependOn(&run_process_cpu_placement_test.step);

    // V1.14.S1 M6: process isolation (T13: one OS process per tile,
    // parented by the supervisor), crash isolation (T12: SIGKILL one
    // tile, siblings unaffected), and the remaining process-mode
    // fail-closed configuration checks.
    const process_topology_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/test_process_topology.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "runtime", .module = runtime_mod },
                .{ .name = "c_abi", .module = c_abi_mod },
                .{ .name = "supervisor", .module = supervisor_named_mod },
            },
        }),
    });
    linkTickoniCodec(b, process_topology_test, fd_lib_dir);
    linkTickoniTango(b, process_topology_test, fd_lib_dir);
    const run_process_topology_test = addPlainTestRun(b, process_topology_test);
    run_process_topology_test.step.dependOn(&process_mode_exe_install.step);
    integration_step.dependOn(&run_process_topology_test.step);

    // V1.14.S1 M6: demo/replay parity — floating vs. explicit shared-core
    // CPU placement must reach identical final pipeline metrics through the
    // real supervisor (T14).
    const process_demo_parity_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/test_process_demo_parity.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "runtime", .module = runtime_mod },
                .{ .name = "c_abi", .module = c_abi_mod },
                .{ .name = "supervisor", .module = supervisor_named_mod },
            },
        }),
    });
    linkTickoniCodec(b, process_demo_parity_test, fd_lib_dir);
    linkTickoniTango(b, process_demo_parity_test, fd_lib_dir);
    const run_process_demo_parity_test = addPlainTestRun(b, process_demo_parity_test);
    run_process_demo_parity_test.step.dependOn(&process_mode_exe_install.step);
    integration_step.dependOn(&run_process_demo_parity_test.step);

    // V1.14.S1 M6: shm_link fail-closed matrix (dcache bounds, missing link
    // objects) and backpressure visibility. Single-process — no tile spawn,
    // so no stdio-inheritance hang risk — uses the normal test-runner path.
    const shm_link_bounds_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/test_shm_link_bounds.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "runtime", .module = runtime_mod },
                .{ .name = "c_abi", .module = c_abi_mod },
            },
        }),
    });
    linkTickoniCodec(b, shm_link_bounds_test, fd_lib_dir);
    linkTickoniTango(b, shm_link_bounds_test, fd_lib_dir);
    integration_step.dependOn(&b.addRunArtifact(shm_link_bounds_test).step);

    // Mock HTTP servers (test/mocks): self-tests of the mock
    // infrastructure itself, no tile schema imports required. Wired to
    // test_step (not integration_step): src/tickoni/test/integration is the
    // integration-test boundary, and this root lives under test/mocks.
    const mock_http_support_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/mocks/mock_http_support.zig"),
        .target = target,
        .optimize = optimize,
    });
    const mock_broker_market_server_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/mocks/mock_broker_market_server.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "mock_http_support", .module = mock_http_support_mod },
        },
    });
    const mock_openai_server_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/mocks/mock_openai_server.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "mock_http_support", .module = mock_http_support_mod },
        },
    });
    const mock_servers_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/mocks/mock_servers.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "mock_http_support", .module = mock_http_support_mod },
                .{ .name = "mock_broker_market_server", .module = mock_broker_market_server_mod },
                .{ .name = "mock_openai_server", .module = mock_openai_server_mod },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(mock_servers_test).step);

    const model_tile_http_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/test_model_tile_http.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "model", .module = model_int_mod },
                .{ .name = "mock_http_support", .module = mock_http_support_mod },
                .{ .name = "mock_openai_server", .module = mock_openai_server_mod },
            },
        }),
    });
    integration_step.dependOn(&b.addRunArtifact(model_tile_http_test).step);

    const replay_integration_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/test_investment_replay.zig"),
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
            .root_source_file = b.path("src/tickoni/test/integration/test_investment_decision_cards.zig"),
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

    // System step — every root under src/tickoni/test/system, run with
    // `zig build system-test` (`just test-system-tk`). This includes both the
    // live `tkmodl` smoke proof and offline deterministic demo proofs; the
    // directory is the boundary, not per-file live/offline status.
    const system_step = b.step("system-test", "Run all src/tickoni/test/system proofs");
    const system_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/system/test_investment_demo_live.zig"),
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

    // V1.3.S4: combined portfolio/cash demo. Fixture-backed and deterministic
    // (no live model, broker, or execution), but lives under
    // src/tickoni/test/system so it runs as part of the system-test lane
    // alongside the live tkmodl proof.
    const portfolio_cash_demo_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/system/test_portfolio_cash_demo.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "investment_demo", .module = investment_demo_mod },
                .{ .name = "investment_support", .module = investment_support_int_mod },
            },
        }),
    });
    // investment_demo_mod already carries the thesis_hash/audit_pb C sources
    // from linkTickoniCodec above; only add the library path here to avoid
    // linking those C sources twice into this binary.
    portfolio_cash_demo_test.root_module.addLibraryPath(b.path(fd_lib_dir));
    portfolio_cash_demo_test.root_module.linkSystemLibrary("fd_util", .{});
    portfolio_cash_demo_test.root_module.linkSystemLibrary("fd_ballet", .{});
    portfolio_cash_demo_test.root_module.linkSystemLibrary("stdc++", .{});
    system_step.dependOn(&b.addRunArtifact(portfolio_cash_demo_test).step);

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
        .{ "test-dcache", "src/tickoni/c_abi/dcache.zig" },
        .{ "test-fseq", "src/tickoni/c_abi/fseq.zig" },
        .{ "test-cnc", "src/tickoni/c_abi/cnc.zig" },
        .{ "test-wksp", "src/tickoni/c_abi/wksp.zig" },
        .{ "test-process", "src/tickoni/c_abi/process.zig" },
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
                        .{ .name = "audit_codec", .module = audit_codec_mod },
                        .{ .name = "fixture_audit_gen", .module = fixture_audit_gen_mod },
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
        if (std.mem.eql(u8, entry[1], "src/tickoni/c_abi/queue.zig") or
            std.mem.eql(u8, entry[1], "src/tickoni/c_abi/dcache.zig") or
            std.mem.eql(u8, entry[1], "src/tickoni/c_abi/fseq.zig") or
            std.mem.eql(u8, entry[1], "src/tickoni/c_abi/cnc.zig"))
        {
            linkTickoniTango(b, t, fd_lib_dir);
        }
        cov_step.dependOn(&b.addInstallArtifact(t, .{
            .dest_dir = .{ .override = .{ .custom = "cov" } },
        }).step);
    }

    const thesis_cov_test = b.addTest(.{
        .name = "test-thesis",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/consumer_money/thesis.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "thesis_codec", .module = thesis_codec_mod },
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
            .root_source_file = b.path("src/tickoni/schema/consumer_money/catalog.zig"),
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

    const fixture_portfolio_cov_test = b.addTest(.{
        .name = "test-portfolio-fixtures",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/fixtures/portfolio/fixture_portfolio.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "portfolio", .module = portfolio_mod },
                .{ .name = "basket", .module = basket_mod },
            },
        }),
    });
    linkTickoniCodec(b, fixture_portfolio_cov_test, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(fixture_portfolio_cov_test, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const trade_ticket_cov_test = b.addTest(.{
        .name = "test-trade-ticket",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/consumer_money/trade_ticket.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = basket_mod },
                .{ .name = "portfolio", .module = portfolio_mod },
                .{ .name = "fixture_portfolio", .module = fixture_portfolio_mod },
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
            .root_source_file = b.path("src/tickoni/schema/consumer_money/impact.zig"),
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
            .root_source_file = b.path("src/tickoni/schema/consumer_money/basket.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "thesis_codec", .module = thesis_codec_mod },
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
                .{ .name = "c_abi", .module = c_abi_mod },
            },
        }),
    });
    linkTickoniCodec(b, sup_cov_test, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(sup_cov_test, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);
}

/// b.addRunArtifact on a test binary always enables Zig's test-server
/// protocol (--listen=- plus .stdio = .zig_test), which communicates with
/// the build runner over the test binary's own stdin/stdout. A test that
/// spawns real child OS processes (V1.14 process-mode tests) risks those
/// children inheriting that stdout descriptor, which keeps the pipe's
/// write end open after the test itself finishes and hangs the build
/// runner waiting for EOF that never arrives. This builds the Run step by
/// hand instead, skipping std.Build.addRunArtifact's
/// enableTestRunnerMode call entirely (plain argv + exit-code check, real
/// stdio inherited, no IPC protocol for a spawned process to interfere
/// with).
fn addPlainTestRun(b: *std.Build, test_compile: *std.Build.Step.Compile) *std.Build.Step.Run {
    const run_step = std.Build.Step.Run.create(b, b.fmt("run {s} (plain)", .{test_compile.name}));
    run_step.producer = test_compile;
    run_step.addArtifactArg(test_compile);
    run_step.has_side_effects = true;
    return run_step;
}

/// Links src/tango (mcache/dcache/fseq/cnc) and src/util/wksp (fd_wksp)
/// substrate for V1.14 process-mode shared-memory links. Separate from
/// linkTickoniCodec because these callers do not need the audit_pb/
/// thesis_hash C codec sources. Also compiles shim/tango.c — see that
/// file and doc/knowledge/architecture.md's "How Firedancer Reuse
/// Actually Works" for why a shim exists instead of a native Zig mirror.
fn linkTickoniTango(b: *std.Build, step: *std.Build.Step.Compile, fd_lib_dir: []const u8) void {
    step.root_module.link_libc = true;
    step.root_module.addIncludePath(b.path("src"));
    step.root_module.addCSourceFiles(.{
        .files = &.{"src/tickoni/c_abi/shim/tango.c"},
        .flags = &.{ "-std=c17", "-U__BMI2__", "-U__LZCNT__" },
    });
    step.root_module.addLibraryPath(b.path(fd_lib_dir));
    step.root_module.linkSystemLibrary("fd_tango", .{});
    step.root_module.linkSystemLibrary("fd_util", .{});
    step.root_module.linkSystemLibrary("stdc++", .{});
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
