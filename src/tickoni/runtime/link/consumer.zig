const std = @import("std");
const c_abi = @import("c_abi");
const process = @import("util").process;
const LinkHandles = @import("handles.zig").LinkHandles;
const join_mod = @import("join.zig");

/// Bounded consumer side of a link: blocks until the next sequence number is
/// published, then publishes its own progress via fseq.
pub const Consumer = struct {
    wksp: *c_abi.wksp.Wksp,
    mcache: [*]c_abi.queue.FragMeta,
    fseq: [*]volatile u64,
    depth: usize,
    mtu: usize,
    next_seq: u64 = 0,

    pub fn join(wksp: *c_abi.wksp.Wksp, handles: LinkHandles) !Consumer {
        const joined = try join_mod.joinTriplet(wksp, handles);
        return .{
            .wksp = wksp,
            .mcache = joined.mcache,
            .fseq = joined.fseq,
            .depth = handles.depth,
            .mtu = handles.mtu,
        };
    }

    pub fn leave(self: *Consumer) void {
        _ = c_abi.queue.mcacheLeave(self.mcache);
        _ = c_abi.fseq.fseqLeave(@volatileCast(self.fseq));
    }

    pub fn consume(self: *Consumer, out_buf: []u8, stop: *const std.atomic.Value(bool)) ?usize {
        while (true) {
            if (self.tryConsume(out_buf)) |sz| return sz;
            if (stop.load(.acquire)) return null;
            process.sleepNanos(100_000);
        }
    }

    pub fn tryConsume(self: *Consumer, out_buf: []u8) ?usize {
        const line = c_abi.queue.mcacheLineIdx(self.next_seq, self.depth);
        const meta: *const volatile c_abi.queue.FragMeta = @ptrCast(&self.mcache[line]);
        const seq_found = c_abi.queue.fragMetaSeqQuery(meta);
        if (seq_found != self.next_seq) return null;

        const sz = meta.sz;
        const chunk = meta.chunk;
        const laddr = c_abi.wksp.wkspLaddr(self.wksp, @as(usize, chunk) * c_abi.dcache.chunk_align) orelse return null;
        const src: [*]const u8 = @ptrCast(laddr);
        @memcpy(out_buf[0..sz], src[0..sz]);

        // Re-check after copying: guards against a slow copy racing a fast
        // producer wraparound overwriting this line mid-read.
        if (c_abi.queue.fragMetaSeqQuery(meta) != self.next_seq) return null;

        self.next_seq += 1;
        c_abi.fseq.fseqUpdate(self.fseq, self.next_seq);
        return sz;
    }
};
