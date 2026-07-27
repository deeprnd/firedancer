const clap = @import("clap");
const demo = @import("investment_demo");
const doctor_output = @import("doctor_output");
const std = @import("std");
const version = @import("version");

const MainCommand = enum {
    demo,
    version,
    doctor,
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
    \\-h, --help     Display this help and exit.
    \\    --version  Display Tickoni version information and exit.
    \\<command>
    \\
);

const demo_params = clap.parseParamsComptime(
    \\-h, --help  Display this help and exit.
    \\<command>
    \\
);

const doctor_params = clap.parseParamsComptime(
    \\-h, --help   Display this help and exit.
    \\    --json   Emit machine-readable JSON.
    \\    --plain  Emit human-readable text output.
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

    if (res.args.version != 0) {
        try printVersion(init.io, gpa);
        return;
    }

    if (res.args.help != 0 or res.positionals[0] == null) {
        try clap.helpToFile(init.io, std.Io.File.stderr(), clap.Help, &main_params, .{});
        return;
    }

    switch (res.positionals[0].?) {
        .demo => try demoMain(gpa, init.io, &iter),
        .version => try printVersion(init.io, gpa),
        .doctor => try doctorMain(gpa, init.io, &iter),
    }
}

fn printVersion(io: std.Io, gpa: std.mem.Allocator) !void {
    var info = try version.VersionInfo.init(gpa);
    defer info.deinit(gpa);

    var buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try version.formatVersionInfo(info, &writer);
    try std.Io.File.writeStreamingAll(std.Io.File.stdout(), io, writer.buffered());
}

fn doctorMain(gpa: std.mem.Allocator, io: std.Io, iter: *std.process.Args.Iterator) !void {
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &doctor_params, clap.parsers.default, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        try diag.reportToFile(io, std.Io.File.stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try clap.helpToFile(io, std.Io.File.stderr(), clap.Help, &doctor_params, .{});
        return;
    }

    const format: doctor_output.Format = if (res.args.json != 0) .json else .text;
    var buf: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try doctor_output.runAndFormat(io, gpa, format, &writer);
    try std.Io.File.writeStreamingAll(std.Io.File.stdout(), io, writer.buffered());
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
