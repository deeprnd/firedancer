/// Doctor check functions — individual platform/environment/tool checks.
///
/// Each check returns a `DoctorResult` with status pass/warn/fail.
/// Scaffold only — returns hardcoded values. T6 implements real logic.
const std = @import("std");

/// Check status for a doctor result.
pub const Status = enum {
    pass,
    warn,
    fail,
};

/// Result of a single doctor check.
pub const Result = struct {
    name: []const u8,
    status: Status,
    message: []const u8,

    pub fn toString(self: Result, w: *std.Io.Writer) !void {
        const icon = switch (self.status) {
            .pass => "[PASS]",
            .warn => "[WARN]",
            .fail => "[FAIL]",
        };
        try w.print("  {s} {s}: {s}\n", .{ icon, self.name, self.message });
    }
};

/// OS/environment check group.
pub const OsChecks = struct {
    /// Check host OS and version.
    pub fn checkOS() Result {
        return Result{
            .name = "os",
            .status = .warn, // TODO: implement — returns real OS info
            .message = "scaffold — not implemented",
        };
    }

    /// Check architecture and CPU features.
    pub fn checkArchitecture() Result {
        return Result{
            .name = "architecture",
            .status = .warn, // TODO: implement — returns real arch/feature info
            .message = "scaffold — not implemented",
        };
    }

    /// Check if running in container, WSL2, VM, or native environment.
    pub fn checkEnvironment() Result {
        return Result{
            .name = "environment",
            .status = .warn, // TODO: implement — detect container/WSL2/VM/native
            .message = "scaffold — not implemented",
        };
    }
};

/// Tool availability check group.
pub const ToolChecks = struct {
    /// Check if Zig compiler is available.
    pub fn checkZig() Result {
        return Result{
            .name = "zig",
            .status = .warn, // TODO: implement — which zig + version
            .message = "scaffold — not implemented",
        };
    }

    /// Check if git is available.
    pub fn checkGit() Result {
        return Result{
            .name = "git",
            .status = .warn, // TODO: implement — which git + version
            .message = "scaffold — not implemented",
        };
    }

    /// Check if make is available.
    pub fn checkMake() Result {
        return Result{
            .name = "make",
            .status = .warn, // TODO: implement — which make + version
            .message = "scaffold — not implemented",
        };
    }
};

/// Fixture and mode check group.
pub const ModeChecks = struct {
    /// Check if fixture directory exists and is readable.
    pub fn checkFixtures() Result {
        return Result{
            .name = "fixtures",
            .status = .warn, // TODO: implement — check ~/.tickoni/fixtures
            .message = "scaffold — not implemented",
        };
    }

    /// Check model/mock mode status.
    pub fn checkModelMode() Result {
        return Result{
            .name = "model_mode",
            .status = .warn, // TODO: implement — check mock provider config
            .message = "scaffold — not implemented",
        };
    }

    /// Check if local storage paths are writable.
    pub fn checkStorage() Result {
        return Result{
            .name = "storage",
            .status = .warn, // TODO: implement — check ~/.tickoni writable
            .message = "scaffold — not implemented",
        };
    }

    /// Check if live execution is disabled (must be true on retail tiers).
    pub fn checkLiveExecutionDisabled() Result {
        return Result{
            .name = "live_execution",
            .status = .pass, // Retail tiers always disable live execution
            .message = "disabled",
        };
    }

    /// Check if built from unsupported direct source (non-tagged commit).
    pub fn checkSourceBuild() Result {
        return Result{
            .name = "source_build",
            .status = .warn, // TODO: implement — check if built from non-tagged commit
            .message = "scaffold — not implemented",
        };
    }
};

/// Run all doctor checks into the provided result slice.
/// Returns the number of results written (up to results.len).
pub fn runAll(results: []Result) usize {
    var idx: usize = 0;

    // OS checks
    {
        const r = OsChecks.checkOS();
        if (idx < results.len) results[idx] = r;
        idx += 1;
    }
    {
        const r = OsChecks.checkArchitecture();
        if (idx < results.len) results[idx] = r;
        idx += 1;
    }
    {
        const r = OsChecks.checkEnvironment();
        if (idx < results.len) results[idx] = r;
        idx += 1;
    }

    // Tool checks
    {
        const r = ToolChecks.checkZig();
        if (idx < results.len) results[idx] = r;
        idx += 1;
    }
    {
        const r = ToolChecks.checkGit();
        if (idx < results.len) results[idx] = r;
        idx += 1;
    }
    {
        const r = ToolChecks.checkMake();
        if (idx < results.len) results[idx] = r;
        idx += 1;
    }

    // Mode checks
    {
        const r = ModeChecks.checkFixtures();
        if (idx < results.len) results[idx] = r;
        idx += 1;
    }
    {
        const r = ModeChecks.checkModelMode();
        if (idx < results.len) results[idx] = r;
        idx += 1;
    }
    {
        const r = ModeChecks.checkStorage();
        if (idx < results.len) results[idx] = r;
        idx += 1;
    }
    {
        const r = ModeChecks.checkLiveExecutionDisabled();
        if (idx < results.len) results[idx] = r;
        idx += 1;
    }
    {
        const r = ModeChecks.checkSourceBuild();
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
    const result = Result{
        .name = "test_check",
        .status = .pass,
        .message = "test message",
    };
    try result.toString(&w);
    const output = w.buffered();
    try std.testing.expect(std.mem.startsWith(u8, output, "  [PASS]"));
    try std.testing.expect(std.mem.indexOf(u8, output, "test_check") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "test message") != null);
}

test "Result.warn status" {
    var buf: [256]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    const result = Result{
        .name = "warn_check",
        .status = .warn,
        .message = "warning",
    };
    try result.toString(&w);
    const output = w.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "warn_check") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "warning") != null);
}

test "Result.fail status" {
    var buf: [256]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    const result = Result{
        .name = "fail_check",
        .status = .fail,
        .message = "failure",
    };
    try result.toString(&w);
    const output = w.buffered();
    try std.testing.expect(std.mem.startsWith(u8, output, "  [FAIL]"));
}

test "checkLiveExecutionDisabled returns pass" {
    const r = ModeChecks.checkLiveExecutionDisabled();
    try std.testing.expectEqual(Status.pass, r.status);
    try std.testing.expectEqualStrings("disabled", r.message);
}

test "other checks return warn (scaffold)" {
    try std.testing.expectEqual(Status.warn, OsChecks.checkOS().status);
    try std.testing.expectEqual(Status.warn, OsChecks.checkArchitecture().status);
    try std.testing.expectEqual(Status.warn, OsChecks.checkEnvironment().status);
    try std.testing.expectEqual(Status.warn, ToolChecks.checkZig().status);
    try std.testing.expectEqual(Status.warn, ToolChecks.checkGit().status);
    try std.testing.expectEqual(Status.warn, ToolChecks.checkMake().status);
    try std.testing.expectEqual(Status.warn, ModeChecks.checkFixtures().status);
    try std.testing.expectEqual(Status.warn, ModeChecks.checkModelMode().status);
    try std.testing.expectEqual(Status.warn, ModeChecks.checkStorage().status);
    try std.testing.expectEqual(Status.warn, ModeChecks.checkSourceBuild().status);
}

test "runAll fills results array" {
    var results: [20]Result = undefined;
    const count = runAll(&results);
    try std.testing.expectEqual(@as(usize, 11), count);
    // Check first result is OS check
    try std.testing.expectEqualStrings("os", results[0].name);
    // Check last result is source_build
    try std.testing.expectEqualStrings("source_build", results[count - 1].name);
}
