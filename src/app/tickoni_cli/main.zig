const clap = @import("clap");
const demo = @import("v1_demo");
const std = @import("std");

const MainCommand = enum {
    demo,
};

const DemoCommand = enum {
    v1_1,
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
        var stderr_buffer: [4096]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buffer);
        diag.report(&stderr_writer.interface, err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0 or res.positionals[0] == null) {
        var stderr_buffer: [4096]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buffer);
        try clap.help(&stderr_writer.interface, clap.Help, &main_params, .{});
        return;
    }

    switch (res.positionals[0].?) {
        .demo => try demoMain(gpa, init.io, &iter),
    }
}

fn demoMain(gpa: std.mem.Allocator, io: std.Io, iter: *std.process.Args.Iterator) !void {
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &demo_params, demo_parsers, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
        .terminating_positional = 0,
    }) catch |err| {
        var stderr_buffer: [4096]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buffer);
        diag.report(&stderr_writer.interface, err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0 or res.positionals[0] == null) {
        var stderr_buffer: [4096]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buffer);
        try clap.help(&stderr_writer.interface, clap.Help, &demo_params, .{});
        return;
    }

    switch (res.positionals[0].?) {
        .v1_1 => try v1Main(gpa, io, iter),
    }
}

fn v1Main(gpa: std.mem.Allocator, io: std.Io, iter: *std.process.Args.Iterator) !void {
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &v1_params, clap.parsers.default, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        var stderr_buffer: [4096]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buffer);
        diag.report(&stderr_writer.interface, err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        var stderr_buffer: [4096]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buffer);
        try clap.help(&stderr_writer.interface, clap.Help, &v1_params, .{});
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
    }, thesis_text);
    defer report.deinit(gpa);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    if (res.args.json != 0) {
        try demo.writeCliReportJson(gpa, &stdout_writer.interface, report);
        return;
    }
    try demo.writeCliReportText(&stdout_writer.interface, report);
}
