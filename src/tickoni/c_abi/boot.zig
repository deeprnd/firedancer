/// Narrow Zig bindings over src/util/fd_util.h's fd_boot/fd_halt lifecycle.
///
/// Every process that touches fd_shmem/fd_wksp/fd_tango substrate (the V1.14
/// process-mode supervisor and every spawned tile) must call fd_boot exactly
/// once before using it and fd_halt once at shutdown; fd_boot is what reads
/// --shmem-path/FD_SHMEM_PATH and brings the shared-memory subsystem online
/// (src/util/shmem/fd_shmem_admin.c).
///
/// fd_boot takes argc/argv by reference and expects Unix argv shape (a
/// NULL-terminated array with argv[0] as a program name); Tickoni's process
/// entrypoints do not need real command-line flags beyond --shmem-path, so
/// bootWithSyntheticArgv supplies a minimal well-formed argv instead of
/// plumbing the real one through. Confirmed against the actual fd_boot call
/// chain in a throwaway spike (fd_env_strip_cmdline_ulong dereferences argv
/// unconditionally; argc==0 with an undefined argv crashes). The path is
/// passed as a --shmem-path argv flag rather than the FD_SHMEM_PATH
/// environment variable because both the supervisor and its self-exec'd
/// tile children each boot their own process-local fd_shmem subsystem, and
/// only the supervisor's own process env is under its direct control here.
const std = @import("std");

extern fn tk_boot(pargc: *c_int, pargv: *[*][*:0]u8) void;
extern fn tk_halt() void;

pub fn halt() void {
    tk_halt();
}

var synthetic_prog_name = "tickoni-tile".*;
var flag_name = "--shmem-path".*;
var shmem_path_buf: [256]u8 = undefined;
var synthetic_argv: [4]?[*:0]u8 = .{ null, null, null, null };

/// Boots fd_util's substrate with a synthetic argv: program name only, or
/// program name + "--shmem-path <path>" when shmem_path is given. Must be
/// paired with fd_halt(). Not thread-safe to call concurrently with
/// itself; call once per process at startup.
pub fn bootWithSyntheticArgv(shmem_path: ?[]const u8) error{ShmemPathTooLong}!void {
    synthetic_argv[0] = &synthetic_prog_name;
    synthetic_argv[1] = null;
    var argc: c_int = 1;

    if (shmem_path) |path| {
        if (path.len >= shmem_path_buf.len) return error.ShmemPathTooLong;
        @memcpy(shmem_path_buf[0..path.len], path);
        shmem_path_buf[path.len] = 0;
        const path_z: [:0]u8 = shmem_path_buf[0..path.len :0];
        synthetic_argv[1] = &flag_name;
        synthetic_argv[2] = path_z.ptr;
        synthetic_argv[3] = null;
        argc = 3;
    }

    var argv: [*][*:0]u8 = @ptrCast(&synthetic_argv);
    tk_boot(&argc, &argv);
}

// ---------------------------------------------------------------------------
// Tests — synthetic argv shape only; fd_boot is not called (it has real
// side effects: log file creation, shmem subsystem init) and must not run
// in the offline unit lane.
// ---------------------------------------------------------------------------

test "synthetic argv without a shmem path is a valid single-element argv" {
    synthetic_argv[0] = &synthetic_prog_name;
    synthetic_argv[1] = null;
    try std.testing.expect(synthetic_argv[0] != null);
    try std.testing.expectEqual(@as(?[*:0]u8, null), synthetic_argv[1]);
    try std.testing.expectEqualStrings("tickoni-tile", &synthetic_prog_name);
}

test "synthetic argv shmem path buffer round-trips a short path" {
    const path = "/tmp/tickoni-run";
    @memcpy(shmem_path_buf[0..path.len], path);
    shmem_path_buf[path.len] = 0;
    const path_z: [:0]u8 = shmem_path_buf[0..path.len :0];
    try std.testing.expectEqualStrings(path, path_z);
}
