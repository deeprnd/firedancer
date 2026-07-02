sandbox.zig
pub const SandboxConfig = struct {
    desired_uid: u32 = 65534, // nobody !!!!into constatns
    desired_gid: u32 = 65534, // nogroup
    keep_host_networking: bool = false,
    allow_connect: bool = false,
    allow_renameat: bool = false,
    keep_controlling_terminal: bool = false,
    dumpable: bool = false,
    rlimit_file_cnt: u64 = 64,
    rlimit_address_space: u64 = 1 << 30, // 1 GiB !!!!into constatns
    rlimit_data: u64 = 1 << 28, // 256 MiB  !!!!into constatns

topology.zig
pub const TileDescriptor = struct {
    id: TileId,
    /// Human-readable name used in logs and diagnostics.
    name: []const u8,
    /// Phase from the tile plan: 0=core, 1=case, 2=agent, 3=api, 4=exec. !!! use enums
    phase: u8,
    /// Defaults to floating: existing thread-mode topologies do not pin
    /// CPUs. Process-mode topologies set this explicitly.
    cpu_placement: CpuPlacement = .floating,
};

topology.zig
test "TileId equality" {
    const a = try TileId.parse("tknorm");  !!! use constants
    const b = try TileId.parse("tknorm");
    const c = try TileId.parse("tkdedu");
    try std.testing.expect(a.eql(b));
    try std.testing.expect(!a.eql(c));
}


wksp.zig
pub const shmem_normal_page_sz: usize = 4096;  !!! can we use firedancer values given it's the same memory topology
