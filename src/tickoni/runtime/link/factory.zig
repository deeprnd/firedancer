const std = @import("std");
const c_abi = @import("c_abi");
const LinkHandles = @import("handles.zig").LinkHandles;

const wksp_tag: usize = 2;

/// Formats a new mcache+dcache+fseq triplet in `wksp` for one channel of
/// depth `depth` (power of two) and payload size up to `mtu` bytes.
/// Supervisor-only; producers/consumers only ever join the result.
pub fn create(wksp: *c_abi.wksp.Wksp, depth: usize, mtu: usize) !LinkHandles {
    std.debug.assert(std.math.isPowerOfTwo(depth));

    const mcache_footprint = c_abi.queue.mcacheFootprint(depth, 0);
    if (mcache_footprint == 0) return error.InvalidDepth;
    const mcache_gaddr = c_abi.wksp.wkspAlloc(wksp, c_abi.queue.mcache_align, mcache_footprint, wksp_tag);
    if (mcache_gaddr == 0) return error.McacheAllocFailed;
    const mcache_laddr = c_abi.wksp.wkspLaddr(wksp, mcache_gaddr) orelse return error.McacheLaddrFailed;
    _ = c_abi.queue.mcacheNew(mcache_laddr, depth, 0, 0) orelse return error.McacheNewFailed;

    const data_sz = c_abi.dcache.dcacheReqDataSz(mtu, depth, 1, false);
    if (data_sz == 0) return error.InvalidMtu;
    const dcache_footprint = c_abi.dcache.dcacheFootprint(data_sz, 0);
    if (dcache_footprint == 0) return error.InvalidMtu;
    const dcache_gaddr = c_abi.wksp.wkspAlloc(wksp, c_abi.dcache.dcache_align, dcache_footprint, wksp_tag);
    if (dcache_gaddr == 0) return error.DcacheAllocFailed;
    const dcache_laddr = c_abi.wksp.wkspLaddr(wksp, dcache_gaddr) orelse return error.DcacheLaddrFailed;
    _ = c_abi.dcache.dcacheNew(dcache_laddr, data_sz, 0) orelse return error.DcacheNewFailed;

    const fseq_footprint = c_abi.fseq.fseqFootprint();
    const fseq_gaddr = c_abi.wksp.wkspAlloc(wksp, c_abi.fseq.fseq_align, fseq_footprint, wksp_tag);
    if (fseq_gaddr == 0) return error.FseqAllocFailed;
    const fseq_laddr = c_abi.wksp.wkspLaddr(wksp, fseq_gaddr) orelse return error.FseqLaddrFailed;
    _ = c_abi.fseq.fseqNew(fseq_laddr, 0) orelse return error.FseqNewFailed;

    return .{ .mcache_gaddr = mcache_gaddr, .dcache_gaddr = dcache_gaddr, .fseq_gaddr = fseq_gaddr, .depth = depth, .mtu = mtu };
}
