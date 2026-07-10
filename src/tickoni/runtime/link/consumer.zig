const std = @import("std");
const c_abi = @import("c_abi");
const process = @import("util").process;
const LinkHandles = @import("handles.zig").LinkHandles;
const join_mod = @import("join.zig");
const wait = @import("wait.zig");

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

    /// Blocks until a fragment is available or stop is signalled. Polls with
    /// a bounded spin-pause budget before backing off to a bounded sleep;
    /// see runtime/link/wait.zig for why this deviates from Firedancer's
    /// non-sleeping hot receive path. idle_polls counts how many spin
    /// budgets were exhausted without a fragment, for backpressure/idle
    /// diagnostics.
    ///
    /// `cnc`, if non-null, gets a heartbeat and a halt-signal check on every
    /// idle-backoff iteration (v2.14.S8.T6) — see Producer.publish's
    /// matching doc comment for why.
    pub fn consume(self: *Consumer, out_buf: []u8, idle_polls: *std.atomic.Value(u64), stop: *const std.atomic.Value(bool), cnc: ?*c_abi.cnc.Cnc) ?usize {
        while (true) {
            var spins: u32 = 0;
            while (spins < wait.spin_poll_max) : (spins += 1) {
                if (self.tryConsume(out_buf)) |sz| return sz;
                c_abi.boot.spinPause();
            }
            _ = idle_polls.fetchAdd(1, .release);
            if (stop.load(.acquire)) return null;
            if (cnc) |c| {
                c_abi.cnc.heartbeat(c, process.monotonicNanos());
                if (c_abi.cnc.signalQuery(c) == c_abi.cnc.signal_halt) return null;
            }
            process.sleepNanos(wait.idle_sleep_ns);
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
        c_abi.fctl.rxCrReturn(self.fseq, self.next_seq);
        return sz;
    }
};
