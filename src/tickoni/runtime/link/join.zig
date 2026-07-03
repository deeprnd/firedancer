const c_abi = @import("c_abi");
const LinkHandles = @import("handles.zig").LinkHandles;

pub const JoinedTriplet = struct {
    mcache: [*]c_abi.queue.FragMeta,
    dcache_base: [*]u8,
    fseq: [*]volatile u64,
};

pub fn joinTriplet(wksp: *c_abi.wksp.Wksp, handles: LinkHandles) !JoinedTriplet {
    const mcache_laddr = c_abi.wksp.wkspLaddr(wksp, handles.mcache_gaddr) orelse return error.McacheLaddrFailed;
    const mcache = c_abi.queue.mcacheJoin(mcache_laddr) orelse return error.McacheJoinFailed;
    const dcache_laddr = c_abi.wksp.wkspLaddr(wksp, handles.dcache_gaddr) orelse return error.DcacheLaddrFailed;
    const dcache_base = c_abi.dcache.dcacheJoin(dcache_laddr) orelse return error.DcacheJoinFailed;
    const fseq_laddr = c_abi.wksp.wkspLaddr(wksp, handles.fseq_gaddr) orelse return error.FseqLaddrFailed;
    const fseq = c_abi.fseq.fseqJoin(fseq_laddr) orelse return error.FseqJoinFailed;
    return .{ .mcache = mcache, .dcache_base = dcache_base, .fseq = fseq };
}
