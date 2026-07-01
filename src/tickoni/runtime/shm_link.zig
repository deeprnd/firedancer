/// V1.14.S1 Tango-backed bounded channel: pairs a joined mcache+dcache for
/// the payload with a joined fseq for consumer progress, giving process-mode
/// tiles the same bounded, backpressuring producer/consumer contract as the
/// thread-mode heap ring in
/// src/tickoni/tiles/payment_pipeline/queue.zig's BoundedQueue.
///
/// Ownership: `create` is called exactly once, by the supervisor (the sole
/// creator of shared objects — see doc/execution/contribution/tickoni.md's
/// "one writer for hot mutable state" rule). Producer and Consumer only
/// join pre-formatted objects; they never format memory.
const std = @import("std");
const c_abi = @import("c_abi");

/// Fixed-size, POD handle set embeddable directly in
/// src/tickoni/runtime/launch_spec.zig's LaunchSpec.
pub const LinkHandles = struct {
    mcache_gaddr: usize = 0,
    dcache_gaddr: usize = 0,
    fseq_gaddr: usize = 0,
    depth: usize = 0,
    mtu: usize = 0,
};

const wksp_tag: usize = 2;

/// Formats a new mcache+dcache+fseq triplet in `wksp` for one channel of
/// depth `depth` (power of two) and payload size up to `mtu` bytes.
/// Supervisor-only; producers/consumers only ever join the result.
pub fn create(wksp: *c_abi.wksp.Wksp, depth: usize, mtu: usize) !LinkHandles {
    std.debug.assert(std.math.isPowerOfTwo(depth));

    const mcache_footprint = c_abi.queue.fd_mcache_footprint(depth, 0);
    if (mcache_footprint == 0) return error.InvalidDepth;
    const mcache_gaddr = c_abi.wksp.alloc(wksp, c_abi.queue.mcache_align, mcache_footprint, wksp_tag);
    if (mcache_gaddr == 0) return error.McacheAllocFailed;
    const mcache_laddr = c_abi.wksp.fd_wksp_laddr(wksp, mcache_gaddr) orelse return error.McacheLaddrFailed;
    _ = c_abi.queue.fd_mcache_new(mcache_laddr, depth, 0, 0) orelse return error.McacheNewFailed;

    const data_sz = c_abi.dcache.dcacheReqDataSz(mtu, depth, 1, false);
    if (data_sz == 0) return error.InvalidMtu;
    const dcache_footprint = c_abi.dcache.fd_dcache_footprint(data_sz, 0);
    if (dcache_footprint == 0) return error.InvalidMtu;
    const dcache_gaddr = c_abi.wksp.alloc(wksp, c_abi.dcache.dcache_align, dcache_footprint, wksp_tag);
    if (dcache_gaddr == 0) return error.DcacheAllocFailed;
    const dcache_laddr = c_abi.wksp.fd_wksp_laddr(wksp, dcache_gaddr) orelse return error.DcacheLaddrFailed;
    _ = c_abi.dcache.fd_dcache_new(dcache_laddr, data_sz, 0) orelse return error.DcacheNewFailed;

    const fseq_footprint = c_abi.fseq.fd_fseq_footprint();
    const fseq_gaddr = c_abi.wksp.alloc(wksp, c_abi.fseq.fseq_align, fseq_footprint, wksp_tag);
    if (fseq_gaddr == 0) return error.FseqAllocFailed;
    const fseq_laddr = c_abi.wksp.fd_wksp_laddr(wksp, fseq_gaddr) orelse return error.FseqLaddrFailed;
    _ = c_abi.fseq.fd_fseq_new(fseq_laddr, 0) orelse return error.FseqNewFailed;

    return .{ .mcache_gaddr = mcache_gaddr, .dcache_gaddr = dcache_gaddr, .fseq_gaddr = fseq_gaddr, .depth = depth, .mtu = mtu };
}

fn joinTriplet(wksp: *c_abi.wksp.Wksp, handles: LinkHandles) !struct {
    mcache: [*]c_abi.queue.FragMeta,
    dcache_base: [*]u8,
    fseq: [*]volatile u64,
} {
    const mcache_laddr = c_abi.wksp.fd_wksp_laddr(wksp, handles.mcache_gaddr) orelse return error.McacheLaddrFailed;
    const mcache = c_abi.queue.fd_mcache_join(mcache_laddr) orelse return error.McacheJoinFailed;
    const dcache_laddr = c_abi.wksp.fd_wksp_laddr(wksp, handles.dcache_gaddr) orelse return error.DcacheLaddrFailed;
    const dcache_base = c_abi.dcache.fd_dcache_join(dcache_laddr) orelse return error.DcacheJoinFailed;
    const fseq_laddr = c_abi.wksp.fd_wksp_laddr(wksp, handles.fseq_gaddr) orelse return error.FseqLaddrFailed;
    const fseq = c_abi.fseq.fd_fseq_join(fseq_laddr) orelse return error.FseqJoinFailed;
    return .{ .mcache = mcache, .dcache_base = dcache_base, .fseq = fseq };
}

fn fseqQuery(fseq: [*]volatile u64) u64 {
    return fseq[0];
}

fn fseqUpdate(fseq: [*]volatile u64, seq: u64) void {
    fseq[0] = seq;
}

/// Bounded, backpressuring producer side of a reliable link (T4/T5): waits
/// for the consumer's fseq progress instead of dropping when the ring is
/// full at `depth`. Lossy telemetry links use publishLossy instead.
pub const Producer = struct {
    wksp: *c_abi.wksp.Wksp,
    mcache: [*]c_abi.queue.FragMeta,
    dcache_base: [*]u8,
    fseq: [*]volatile u64,
    depth: usize,
    mtu: usize,
    next_seq: u64 = 0,

    pub fn join(wksp: *c_abi.wksp.Wksp, handles: LinkHandles) !Producer {
        const j = try joinTriplet(wksp, handles);
        return .{ .wksp = wksp, .mcache = j.mcache, .dcache_base = j.dcache_base, .fseq = j.fseq, .depth = handles.depth, .mtu = handles.mtu };
    }

    pub fn leave(self: *Producer) void {
        _ = c_abi.queue.fd_mcache_leave(self.mcache);
        _ = c_abi.dcache.fd_dcache_leave(self.dcache_base);
        _ = c_abi.fseq.fd_fseq_leave(@volatileCast(self.fseq));
    }

    fn writeSlot(self: *Producer, payload: []const u8) !u32 {
        if (payload.len > self.mtu) return error.PayloadTooLarge;
        const line = c_abi.queue.mcacheLineIdx(self.next_seq, self.depth);
        const slot_footprint = c_abi.dcache.dcacheSlotFootprint(self.mtu);
        const slot = self.dcache_base[line * slot_footprint ..][0..slot_footprint];
        @memcpy(slot[0..payload.len], payload);
        const gaddr = c_abi.wksp.fd_wksp_gaddr(self.wksp, &slot[0]);
        return @intCast(gaddr / c_abi.dcache.chunk_align);
    }

    /// Reliable publish: spins with a bounded sleep while the consumer's
    /// published progress lags this link's depth, incrementing
    /// `backpressure_waits` each time, rather than overwriting unread
    /// data. Returns error.Stopped if `stop` is signalled while waiting.
    pub fn publish(
        self: *Producer,
        payload: []const u8,
        backpressure_waits: *std.atomic.Value(u64),
        stop: *const std.atomic.Value(bool),
    ) error{ Stopped, PayloadTooLarge }!void {
        while (true) {
            const consumer_seq = fseqQuery(self.fseq);
            const lag = self.next_seq -% consumer_seq;
            if (lag < self.depth) break;
            _ = backpressure_waits.fetchAdd(1, .release);
            if (stop.load(.acquire)) return error.Stopped;
            c_abi.process.sleepNanos(100_000);
        }

        const chunk = try self.writeSlot(payload);
        c_abi.queue.mcachePublish(self.mcache, self.depth, self.next_seq, 0, chunk, @intCast(payload.len), 0, 0, 0);
        self.next_seq += 1;
    }

    /// Lossy publish for telemetry links: never blocks. The mcache ring
    /// naturally overwrites the oldest unread entry once `depth` frags are
    /// outstanding; `dropped` is incremented whenever that happens so the
    /// loss is counted, matching the "telemetry links may be lossy only
    /// when explicitly declared and counted" rule.
    pub fn publishLossy(self: *Producer, payload: []const u8, dropped: *std.atomic.Value(u64)) error{PayloadTooLarge}!void {
        const consumer_seq = fseqQuery(self.fseq);
        const lag = self.next_seq -% consumer_seq;
        if (lag >= self.depth) _ = dropped.fetchAdd(1, .release);

        const chunk = try self.writeSlot(payload);
        c_abi.queue.mcachePublish(self.mcache, self.depth, self.next_seq, 0, chunk, @intCast(payload.len), 0, 0, 0);
        self.next_seq += 1;
    }
};

/// Bounded consumer side of a link: blocks (bounded sleep) until the next
/// sequence number is published, then publishes its own progress via fseq
/// so the producer's backpressure check observes it.
pub const Consumer = struct {
    wksp: *c_abi.wksp.Wksp,
    mcache: [*]c_abi.queue.FragMeta,
    fseq: [*]volatile u64,
    depth: usize,
    mtu: usize,
    next_seq: u64 = 0,

    pub fn join(wksp: *c_abi.wksp.Wksp, handles: LinkHandles) !Consumer {
        const j = try joinTriplet(wksp, handles);
        return .{ .wksp = wksp, .mcache = j.mcache, .fseq = j.fseq, .depth = handles.depth, .mtu = handles.mtu };
    }

    pub fn leave(self: *Consumer) void {
        _ = c_abi.queue.fd_mcache_leave(self.mcache);
        _ = c_abi.fseq.fd_fseq_leave(@volatileCast(self.fseq));
    }

    /// Blocks until the next frag is available or `stop` is signalled.
    /// Returns the payload length copied into `out_buf`, or null on stop.
    pub fn consume(self: *Consumer, out_buf: []u8, stop: *const std.atomic.Value(bool)) ?usize {
        while (true) {
            if (self.tryConsume(out_buf)) |sz| return sz;
            if (stop.load(.acquire)) return null;
            c_abi.process.sleepNanos(100_000);
        }
    }

    /// Single non-blocking poll; null means nothing new is published yet.
    /// Used directly by lossy telemetry consumers, which never block.
    pub fn tryConsume(self: *Consumer, out_buf: []u8) ?usize {
        const line = c_abi.queue.mcacheLineIdx(self.next_seq, self.depth);
        const meta: *const volatile c_abi.queue.FragMeta = @ptrCast(&self.mcache[line]);
        const seq_found = c_abi.queue.fragMetaSeqQuery(meta);
        if (seq_found != self.next_seq) return null;

        const sz = meta.sz;
        const chunk = meta.chunk;
        const laddr = c_abi.wksp.fd_wksp_laddr(self.wksp, @as(usize, chunk) * c_abi.dcache.chunk_align) orelse return null;
        const src: [*]const u8 = @ptrCast(laddr);
        @memcpy(out_buf[0..sz], src[0..sz]);

        // Re-check after copying: guards against a slow copy racing a fast
        // producer wraparound overwriting this line mid-read.
        if (c_abi.queue.fragMetaSeqQuery(meta) != self.next_seq) return null;

        self.next_seq += 1;
        fseqUpdate(self.fseq, self.next_seq);
        return sz;
    }
};

// ---------------------------------------------------------------------------
// Tests — pure LinkHandles/type-shape checks only; create/join require real
// fd_wksp/fd_tango substrate and are exercised by the process-mode
// integration tests instead (no running servers/processes in the unit lane).
// ---------------------------------------------------------------------------

test "LinkHandles defaults to zeroed/empty" {
    const h = LinkHandles{};
    try std.testing.expectEqual(@as(usize, 0), h.mcache_gaddr);
    try std.testing.expectEqual(@as(usize, 0), h.depth);
}
