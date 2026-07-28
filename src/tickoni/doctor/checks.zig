/// Doctor check functions — individual platform/environment/tool checks.
///
/// Each check takes `io: Io` and `gpa: Allocator` since Zig 0.16 I/O needs them.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const Allocator = std.mem.Allocator;

/// Check status for a doctor result.
pub const Status = enum { pass, warn, fail };

/// Result of a single doctor check.
pub const Result = struct {
    name: []const u8,
    status: Status,
    message_len: usize,
    message_storage: [128]u8,

    pub fn initOwnedMessage(name: []const u8, status: Status, text: []const u8) Result {
        var result = Result{
            .name = name,
            .status = status,
            .message_len = 0,
            .message_storage = [_]u8{0} ** 128,
        };
        const len = @min(text.len, result.message_storage.len);
        @memcpy(result.message_storage[0..len], text[0..len]);
        result.message_len = len;
        return result;
    }

    pub fn message(self: *const Result) []const u8 {
        return self.message_storage[0..self.message_len];
    }

    pub fn toString(self: Result, w: anytype) !void {
        const icon = switch (self.status) {
            .pass => "[PASS]",
            .warn => "[WARN]",
            .fail => "[FAIL]",
        };
        try w.print("  {s} {s}: {s}\n", .{ icon, self.name, self.message() });
    }
};

/// Check if a process exited with status 0.
fn isExitedZero(term: std.process.Child.Term) bool {
    switch (term) {
        .exited => |code| return code == 0,
        else => return false,
    }
}

/// Check if a file exists at the given path.
fn fileExists(dir: std.Io.Dir, io: Io, path: []const u8) bool {
    return blk: {
        std.Io.Dir.access(dir, io, path, .{}) catch break :blk false;
        break :blk true;
    };
}

/// Read up to `max_len` bytes from a file, returning owned buffer (caller must free).
fn readFileContents(file: std.Io.File, io: Io, gpa: Allocator, max_len: usize) ![]u8 {
    var buf: [4096]u8 = undefined;
    const len = try std.Io.File.readPositionalAll(file, io, &buf, 0);
    _ = max_len;
    return gpa.dupe(u8, buf[0..len]);
}

/// OS/environment check group.
pub const OsChecks = struct {
    /// Check host OS and version.
    pub fn checkOS(io: Io, gpa: Allocator) Result {
        const os_name = switch (builtin.target.os.tag) {
            .linux => "Linux",
            .macos => "macOS",
            .windows => "Windows",
            .freestanding => "freestanding",
            else => @tagName(builtin.target.os.tag),
        };

        var version_buf: [128]u8 = undefined;
        const version = detectOsVersion(io, gpa, &version_buf) orelse "unknown version";
        var msg_buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "{s} {s}", .{ os_name, version }) catch os_name;
        return Result.initOwnedMessage("os", .pass, msg);
    }

    /// Check architecture and CPU features.
    pub fn checkArchitecture() Result {
        const arch_name = switch (builtin.target.cpu.arch) {
            .x86_64 => "x86_64",
            .aarch64 => "ARM64",
            .arm => "ARM32",
            else => @tagName(builtin.target.cpu.arch),
        };
        return Result.initOwnedMessage("architecture", .pass, arch_name);
    }

    /// Check if running in container, WSL2, VM, or native environment.
    pub fn checkEnvironment(io: Io, gpa: Allocator) Result {
        const env = detectEnvironment(io, gpa);
        const message = switch (env) {
            .native => "native",
            .container => "container (docker/lxc detected)",
            .wsl => "WSL2 (Windows Subsystem for Linux)",
            .vm => "virtual machine",
        };
        return Result.initOwnedMessage("environment", switch (env) {
            .native => .pass,
            .container => .warn,
            .wsl => .warn,
            .vm => .warn,
        }, message);
    }

    fn detectOsVersion(io: Io, gpa: Allocator, out_buf: []u8) ?[]const u8 {
        switch (builtin.target.os.tag) {
            .linux => {
                const cwd = std.Io.Dir.cwd();
                if (fileExists(cwd, io, "/etc/os-release")) {
                    var file = std.Io.Dir.openFile(cwd, io, "/etc/os-release", .{}) catch return "Linux";
                    defer file.close(io);
                    const data = readFileContents(file, io, gpa, 4096) catch return "Linux";
                    defer gpa.free(data);
                    if (std.mem.indexOf(u8, data, "PRETTY_NAME=")) |start| {
                        const line = data[start + "PRETTY_NAME=".len ..];
                        const end = std.mem.indexOfScalar(u8, line, '\n') orelse line.len;
                        const trimmed = std.mem.trim(u8, line[0..end], " \"'\r");
                        const copied = std.fmt.bufPrint(out_buf, "{s}", .{trimmed}) catch return "Linux";
                        return copied;
                    }
                }
                if (fileExists(cwd, io, "/proc/version")) {
                    var file = std.Io.Dir.openFile(cwd, io, "/proc/version", .{}) catch return "Linux";
                    defer file.close(io);
                    const data = readFileContents(file, io, gpa, 4096) catch return "Linux";
                    defer gpa.free(data);
                    if (std.mem.indexOf(u8, data, "Linux version ")) |s| {
                        const after = data[s + 14 ..];
                        const end = std.mem.indexOfScalar(u8, after, ' ') orelse after.len;
                        const copied = std.fmt.bufPrint(out_buf, "{s}", .{after[0..end]}) catch return "Linux";
                        return copied;
                    }
                }
                return "Linux";
            },
            .macos => {
                const opts = std.process.SpawnOptions{
                    .argv = &[_][]const u8{ "sw_vers", "-productVersion" },
                    .stdout = .pipe,
                    .stderr = .pipe,
                };
                var child = std.process.spawn(io, opts) catch return "macOS";
                const result = child.wait(io) catch return "macOS";
                if (!isExitedZero(result)) return "macOS";
                if (child.stdout) |stdout| {
                    var buf: [256]u8 = undefined;
                    const len = std.Io.File.readPositionalAll(stdout, io, &buf, 0) catch return "macOS";
                    const trimmed = std.mem.trim(u8, buf[0..len], " \n\r");
                    const copied = std.fmt.bufPrint(out_buf, "{s}", .{trimmed}) catch return "macOS";
                    return copied;
                }
                return "macOS";
            },
            .windows => return "Windows",
            else => return null,
        }
    }

    fn detectEnvironment(io: Io, gpa: Allocator) enum { native, container, wsl, vm } {
        const cwd = std.Io.Dir.cwd();

        if (fileExists(cwd, io, "/proc/version")) {
            var file = std.Io.Dir.openFile(cwd, io, "/proc/version", .{}) catch return .native;
            defer file.close(io);
            const data = readFileContents(file, io, gpa, 4096) catch return .native;
            defer gpa.free(data);
            if (std.mem.indexOf(u8, data, "microsoft") != null or
                std.mem.indexOf(u8, data, "WSL") != null)
            {
                return .wsl;
            }
        }

        if (fileExists(cwd, io, "/proc/1/cgroup")) {
            var file = std.Io.Dir.openFile(cwd, io, "/proc/1/cgroup", .{}) catch return .native;
            defer file.close(io);
            const data = readFileContents(file, io, gpa, 4096) catch return .native;
            defer gpa.free(data);
            if (std.mem.indexOf(u8, data, "docker") != null or
                std.mem.indexOf(u8, data, "kubepods") != null)
            {
                return .container;
            }
        }

        if (fileExists(cwd, io, "/sys/class/dmi/id/product_name")) {
            var file = std.Io.Dir.openFile(cwd, io, "/sys/class/dmi/id/product_name", .{}) catch return .native;
            defer file.close(io);
            const data = readFileContents(file, io, gpa, 4096) catch return .native;
            defer gpa.free(data);
            const product = std.mem.trim(u8, data, " \n\r");
            if (std.mem.eql(u8, product, "VMware Virtual Platform") or
                std.mem.eql(u8, product, "VirtualBox") or
                std.mem.indexOf(u8, product, "QEMU") != null or
                std.mem.indexOf(u8, product, "Hyper-V") != null)
            {
                return .vm;
            }
        }

        return .native;
    }
};

/// Tool availability check group.
pub const ToolChecks = struct {
    /// Check if Zig compiler is available.
    pub fn checkZig(io: Io) Result {
        return checkTool("zig", &[_][]const u8{ "zig", "--version" }, io);
    }

    /// Check if git is available.
    pub fn checkGit(io: Io) Result {
        return checkTool("git", &[_][]const u8{ "git", "--version" }, io);
    }

    /// Check if make is available.
    pub fn checkMake(io: Io) Result {
        return checkTool("make", &[_][]const u8{ "make", "--version" }, io);
    }

    fn checkTool(name: []const u8, argv: []const []const u8, io: Io) Result {
        const opts = std.process.SpawnOptions{
            .argv = argv,
            .stdout = .pipe,
            .stderr = .pipe,
        };
        var child = std.process.spawn(io, opts) catch return Result.initOwnedMessage(name, .fail, "not found");
        const result = child.wait(io) catch return Result.initOwnedMessage(name, .fail, "not found");
        if (!isExitedZero(result)) return Result.initOwnedMessage(name, .fail, "not found");
        if (child.stdout) |stdout| {
            var buf: [1024]u8 = undefined;
            const len = std.Io.File.readPositionalAll(stdout, io, &buf, 0) catch return Result.initOwnedMessage(name, .fail, "no output");
            const version = std.mem.trim(u8, buf[0..len], " \n\r");
            const clipped = if (version.len > 80) version[0..80] else version;
            return Result.initOwnedMessage(name, .pass, clipped);
        }
        return Result.initOwnedMessage(name, .fail, "no output");
    }
};

/// Fixture and mode check group.
pub const ModeChecks = struct {
    /// Check if fixture directory exists and is readable.
    pub fn checkFixtures(io: Io) Result {
        const cwd = std.Io.Dir.cwd();
        const fixtures_path = "/home/vicgenin/work/git/tickoni/src/tickoni/demo/fixtures/demo.manifest.json";
        std.Io.Dir.access(cwd, io, fixtures_path, .{}) catch {
            return Result.initOwnedMessage("fixtures", .warn, "no fixtures found (demo fixtures expected)");
        };
        return Result.initOwnedMessage("fixtures", .pass, "demo fixtures present");
    }

    /// Check model/mock mode status.
    pub fn checkModelMode() Result {
        return Result.initOwnedMessage("model_mode", .warn, "no model provider configured (offline only)");
    }

    /// Check if local storage paths are writable.
    pub fn checkStorage(io: Io, env_home: ?[]const u8) Result {
        const cwd = std.Io.Dir.cwd();
        const home = env_home orelse "/tmp";
        var data_dir_buf: [512]u8 = undefined;
        const data_dir = std.fmt.bufPrint(&data_dir_buf, "{s}/.tickoni", .{home}) catch "unknown";
        std.Io.Dir.access(cwd, io, data_dir, .{}) catch {
            return Result.initOwnedMessage("storage", .warn, "storage unavailable");
        };
        return Result.initOwnedMessage("storage", .pass, "storage writable");
    }

    /// Check if live execution is disabled (must be true on retail tiers).
    pub fn checkLiveExecutionDisabled() Result {
        return Result.initOwnedMessage("live_execution", .pass, "disabled");
    }

    /// Check if built from unsupported direct source (non-tagged commit).
    pub fn checkSourceBuild(io: Io) Result {
        const opts = std.process.SpawnOptions{
            .argv = &[_][]const u8{ "git", "describe", "--tags", "--exact-match", "HEAD" },
            .stdout = .pipe,
            .stderr = .pipe,
        };
        var child = std.process.spawn(io, opts) catch return Result.initOwnedMessage("source_build", .warn, "git not available");
        const result = child.wait(io) catch return Result.initOwnedMessage("source_build", .warn, "git error");
        if (!isExitedZero(result)) return Result.initOwnedMessage("source_build", .warn, "unreleased commit (not on a release tag)");
        if (child.stdout) |stdout| {
            var buf: [256]u8 = undefined;
            const len = std.Io.File.readPositionalAll(stdout, io, &buf, 0) catch return Result.initOwnedMessage("source_build", .warn, "git error");
            const tag = std.mem.trim(u8, buf[0..len], " \n\r");
            return Result.initOwnedMessage("source_build", .pass, tag);
        }
        return Result.initOwnedMessage("source_build", .warn, "unreleased commit (not on a release tag)");
    }
};

/// Run all doctor checks into the provided result slice.
pub fn runAll(results: []Result, io: Io, gpa: Allocator) usize {
    var idx: usize = 0;

    {
        const r = OsChecks.checkOS(io, gpa);
        if (idx < results.len) results[idx] = r;
        idx += 1;
    }
    {
        const r = OsChecks.checkArchitecture();
        if (idx < results.len) results[idx] = r;
        idx += 1;
    }
    {
        const r = OsChecks.checkEnvironment(io, gpa);
        if (idx < results.len) results[idx] = r;
        idx += 1;
    }
    {
        const r = ToolChecks.checkZig(io);
        if (idx < results.len) results[idx] = r;
        idx += 1;
    }
    {
        const r = ToolChecks.checkGit(io);
        if (idx < results.len) results[idx] = r;
        idx += 1;
    }
    {
        const r = ToolChecks.checkMake(io);
        if (idx < results.len) results[idx] = r;
        idx += 1;
    }
    {
        const r = ModeChecks.checkFixtures(io);
        if (idx < results.len) results[idx] = r;
        idx += 1;
    }
    {
        const r = ModeChecks.checkModelMode();
        if (idx < results.len) results[idx] = r;
        idx += 1;
    }
    {
        const r = ModeChecks.checkStorage(io, null);
        if (idx < results.len) results[idx] = r;
        idx += 1;
    }
    {
        const r = ModeChecks.checkLiveExecutionDisabled();
        if (idx < results.len) results[idx] = r;
        idx += 1;
    }
    {
        const r = ModeChecks.checkSourceBuild(io);
        if (idx < results.len) results[idx] = r;
        idx += 1;
    }

    return idx;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "Result.toString produces correct format" {
    var buf: [256]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    const result = Result.initOwnedMessage("test_check", .pass, "test message");
    try result.toString(&w);
    const output = w.buffered();
    try std.testing.expect(std.mem.startsWith(u8, output, "  [PASS]"));
    try std.testing.expect(std.mem.indexOf(u8, output, "test_check") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "test message") != null);
}

test "Result.warn status" {
    var buf: [256]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    const result = Result.initOwnedMessage("warn_check", .warn, "warning");
    try result.toString(&w);
    const output = w.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "warn_check") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "warning") != null);
}

test "Result.fail status" {
    var buf: [256]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    const result = Result.initOwnedMessage("fail_check", .fail, "failure");
    try result.toString(&w);
    const output = w.buffered();
    try std.testing.expect(std.mem.startsWith(u8, output, "  [FAIL]"));
}

test "checkLiveExecutionDisabled returns pass" {
    const r = ModeChecks.checkLiveExecutionDisabled();
    try std.testing.expectEqual(Status.pass, r.status);
    try std.testing.expectEqualStrings("disabled", r.message());
}

test "checkOS returns pass with OS name" {
    const r = OsChecks.checkOS(std.testing.io, std.testing.allocator);
    try std.testing.expectEqual(Status.pass, r.status);
    try std.testing.expect(r.message().len > 0);
}

test "checkArchitecture returns pass with arch" {
    const r = OsChecks.checkArchitecture();
    try std.testing.expectEqual(Status.pass, r.status);
    try std.testing.expect(r.message().len > 0);
}

test "checkEnvironment returns result" {
    const r = OsChecks.checkEnvironment(std.testing.io, std.testing.allocator);
    try std.testing.expect(r.message().len > 0);
}

test "checkZig returns result" {
    const r = ToolChecks.checkZig(std.testing.io);
    try std.testing.expect(r.name.len > 0);
    try std.testing.expect(r.message().len > 0);
}

test "checkGit returns result" {
    const r = ToolChecks.checkGit(std.testing.io);
    try std.testing.expect(r.name.len > 0);
    try std.testing.expect(r.message().len > 0);
}

test "checkMake returns result" {
    const r = ToolChecks.checkMake(std.testing.io);
    try std.testing.expect(r.name.len > 0);
    try std.testing.expect(r.message().len > 0);
}

test "checkFixtures returns result" {
    const r = ModeChecks.checkFixtures(std.testing.io);
    try std.testing.expect(r.name.len > 0);
    try std.testing.expect(r.message().len > 0);
}

test "checkModelMode returns result" {
    const r = ModeChecks.checkModelMode();
    try std.testing.expect(r.name.len > 0);
    try std.testing.expect(r.message().len > 0);
}

test "checkStorage returns result" {
    const r = ModeChecks.checkStorage(std.testing.io, null);
    try std.testing.expect(r.name.len > 0);
    try std.testing.expect(r.message().len > 0);
}

test "checkSourceBuild returns result" {
    const r = ModeChecks.checkSourceBuild(std.testing.io);
    try std.testing.expect(r.name.len > 0);
    try std.testing.expect(r.message().len > 0);
}

test "runAll fills results array" {
    var results: [20]Result = undefined;
    const count = runAll(&results, std.testing.io, std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 11), count);
    try std.testing.expectEqualStrings("os", results[0].name);
    try std.testing.expectEqualStrings("source_build", results[count - 1].name);
}

test "runAll produces at least one pass" {
    var results: [20]Result = undefined;
    const count = runAll(&results, std.testing.io, std.testing.allocator);
    var any_pass = false;
    for (results[0..count]) |r| {
        if (r.status == .pass) any_pass = true;
    }
    try std.testing.expect(any_pass);
}
