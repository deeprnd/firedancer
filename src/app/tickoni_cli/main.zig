const clap = @import("clap");
const demo = @import("investment_demo");
const std = @import("std");
const tier = @import("tier");

/// Return compiler version string (clang, gcc, etc.) via __VERSION__.
pub extern "c" fn tickoni_compiler_version() [*:0]const u8;
pub fn compilerVersion() []const u8 {
    return std.mem.sliceTo(tickoni_compiler_version(), 0);
}

pub const version_str = "0.1.1";

const MainCommand = enum {
    demo,
    version,
};

const DemoCommand = enum {
    investment,
};

const main_parsers = .{
    .command = clap.parsers.enumeration(MainCommand),
};

const demo_parsers = .{
    .command = clap.parsers.enumeration(DemoCommand),
};

const main_params = clap.parseParamsComptime(
    \\-h, --help  Display this help and exit.
    \\<command>
    \\
);

const demo_params = clap.parseParamsComptime(
    \\-h, --help  Display this help and exit.
    \\<command>
    \\
);

const v1_params = clap.parseParamsComptime(
    \\-h, --help            Display this help and exit.
    \\    --thesis <str>    Plain-English demo thesis input.
    \\    --endpoint <str>  OpenAI-compatible endpoint. Defaults to TK_LLM_ENDPOINT or local llama.cpp.
    \\    --model <str>     Allowed model id. Defaults to TK_LLM_MODEL_ID or the demo default.
    \\    --json            Emit machine-readable JSON.
    \\    --fixture         Use deterministic fixture model response; no live LLM required.
    \\
);

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var iter = try std.process.Args.iterateAllocator(init.minimal.args, gpa);
    defer iter.deinit();
    _ = iter.next();

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &main_params, main_parsers, &iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
        .terminating_positional = 0,
    }) catch |err| {
        try diag.reportToFile(init.io, std.Io.File.stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0 or res.positionals[0] == null) {
        try clap.helpToFile(init.io, std.Io.File.stderr(), clap.Help, &main_params, .{});
        return;
    }

    switch (res.positionals[0].?) {
        .demo => try demoMain(gpa, init.io, &iter),
        .version => {
            var fmt_buf: [512]u8 = undefined;
            const line = std.fmt.bufPrint(&fmt_buf, "{s} {s} ({s} {s} {s})\n", .{
                version_str,
                tier.tierName(tier.detectTier()),
                tier.detectOsString(),
                tier.detectArchString(),
                compilerVersion(),
            }) catch unreachable;
            var write_buf: [256]u8 = undefined;
            var sw = std.Io.File.stdout().writer(init.io, &write_buf);
            try sw.interface.writeAll(line);
            try sw.flush();
        },
    }
}

fn demoMain(gpa: std.mem.Allocator, io: std.Io, iter: *std.process.Args.Iterator) !void {
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &demo_params, demo_parsers, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
        .terminating_positional = 0,
    }) catch |err| {
        try diag.reportToFile(io, std.Io.File.stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0 or res.positionals[0] == null) {
        try clap.helpToFile(io, std.Io.File.stderr(), clap.Help, &demo_params, .{});
        return;
    }

    switch (res.positionals[0].?) {
        .investment => try investmentMain(gpa, io, iter),
    }
}

fn investmentMain(gpa: std.mem.Allocator, io: std.Io, iter: *std.process.Args.Iterator) !void {
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &v1_params, clap.parsers.default, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        try diag.reportToFile(io, std.Io.File.stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try clap.helpToFile(io, std.Io.File.stderr(), clap.Help, &v1_params, .{});
        return;
    }

    const thesis_text = res.args.thesis orelse return error.MissingThesis;
    const endpoint = if (res.args.endpoint) |value|
        try gpa.dupe(u8, value)
    else
        try demo.envOrDefault(gpa, "TK_LLM_ENDPOINT", demo.default_endpoint);
    defer gpa.free(endpoint);

    const model_id = if (res.args.model) |value|
        try gpa.dupe(u8, value)
    else
        try demo.envOrDefault(gpa, "TK_LLM_MODEL_ID", demo.default_model_id);
    defer gpa.free(model_id);

    var report = try demo.runCliDemo(gpa, io, .{
        .endpoint = endpoint,
        .model_id = model_id,
        .use_fixture = res.args.fixture != 0,
    }, thesis_text);
    defer report.deinit(gpa);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    if (res.args.json != 0) {
        try demo.writeCliReportJson(gpa, &stdout_writer.interface, report);
    } else {
        try demo.writeCliReportText(&stdout_writer.interface, report);
    }
    try stdout_writer.flush();
}
