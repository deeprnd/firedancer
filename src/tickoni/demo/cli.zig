const std = @import("std");

pub const OutputFormat = enum { plain, json };

pub const Command = struct {
    scenario: []const u8,
    manifest_path: []const u8,
    format: OutputFormat = .plain,
};

pub const ParseError = error{
    MissingScenario,
    UnsupportedScenario,
    MissingManifestPath,
    DuplicateManifestPath,
    DuplicateFormat,
    UnknownArgument,
};

pub fn parseDemoArgs(args: []const []const u8) ParseError!Command {
    if (args.len == 0) return ParseError.MissingScenario;
    const scenario = args[0];
    if (!std.mem.eql(u8, scenario, "investment")) return ParseError.UnsupportedScenario;

    var manifest_path: ?[]const u8 = null;
    var format: ?OutputFormat = null;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--manifest")) {
            if (manifest_path != null) return ParseError.DuplicateManifestPath;
            i += 1;
            if (i >= args.len) return ParseError.MissingManifestPath;
            manifest_path = args[i];
            continue;
        }
        if (std.mem.eql(u8, arg, "--json")) {
            if (format != null) return ParseError.DuplicateFormat;
            format = .json;
            continue;
        }
        if (std.mem.eql(u8, arg, "--plain")) {
            if (format != null) return ParseError.DuplicateFormat;
            format = .plain;
            continue;
        }
        return ParseError.UnknownArgument;
    }

    return Command{
        .scenario = scenario,
        .manifest_path = manifest_path orelse return ParseError.MissingManifestPath,
        .format = format orelse .plain,
    };
}

test "parseDemoArgs accepts investment manifest json contract" {
    const cmd = try parseDemoArgs(&.{ "investment", "--json", "--manifest", "demo.manifest.json" });
    try std.testing.expectEqualStrings("investment", cmd.scenario);
    try std.testing.expectEqualStrings("demo.manifest.json", cmd.manifest_path);
    try std.testing.expectEqual(OutputFormat.json, cmd.format);
}

test "parseDemoArgs defaults to plain output" {
    const cmd = try parseDemoArgs(&.{ "investment", "--manifest", "demo.manifest.json" });
    try std.testing.expectEqual(OutputFormat.plain, cmd.format);
}

test "parseDemoArgs rejects missing manifest path" {
    try std.testing.expectError(ParseError.MissingManifestPath, parseDemoArgs(&.{ "investment", "--manifest" }));
}

test "parseDemoArgs rejects unsupported scenario" {
    try std.testing.expectError(ParseError.UnsupportedScenario, parseDemoArgs(&.{ "payments", "--manifest", "demo.manifest.json" }));
}

test "parseDemoArgs rejects duplicate format flags" {
    try std.testing.expectError(ParseError.DuplicateFormat, parseDemoArgs(&.{ "investment", "--json", "--plain", "--manifest", "demo.manifest.json" }));
}

test "parseDemoArgs rejects unknown arguments" {
    try std.testing.expectError(ParseError.UnknownArgument, parseDemoArgs(&.{ "investment", "--fixture", "--manifest", "demo.manifest.json" }));
}
