const std = @import("std");
const c_abi = @import("c_abi");
const process = @import("util").process;
const LinkHandles = @import("handles.zig").LinkHandles;
const join_mod = @import("join.zig");
const wait = @import("wait.zig");

/// Bounded, backpressuring producer side of a reliable link: waits for the
/// consumer's fseq progress instead of dropping when the ring is full.
pub const Producer = struct {
    wksp: *c_abi.wksp.Wksp,
    mcache: [*]c_abi.queue.FragMeta,
    dcache_base: [*]u8,
    fseq: [*]volatile u64,
    depth: usize,
    mtu: usize,
    next_seq: u64 = 0,

    pub fn join(wksp: *c_abi.wksp.Wksp, handles: LinkHandles) !Producer {
        const joined = try join_mod.joinTriplet(wksp, handles);
        return .{
            .wksp = wksp,
            .mcache = joined.mcache,
            .dcache_base = joined.dcache_base,
            .fseq = joined.fseq,
            .depth = handles.depth,
            .mtu = handles.mtu,
        };
    }

    pub fn leave(self: *Producer) void {
        _ = c_abi.queue.mcacheLeave(self.mcache);
        _ = c_abi.dcache.dcacheLeave(self.dcache_base);
        _ = c_abi.fseq.fseqLeave(@volatileCast(self.fseq));
    }

    fn writeSlot(self: *Producer, payload: []const u8) !u32 {
        if (payload.len > self.mtu) return error.PayloadTooLarge;
        const line = c_abi.queue.mcacheLineIdx(self.next_seq, self.depth);
        const slot_footprint = c_abi.dcache.dcacheSlotFootprint(self.mtu);
        const slot = self.dcache_base[line * slot_footprint ..][0..slot_footprint];
        @memcpy(slot[0..payload.len], payload);
        const gaddr = c_abi.wksp.wkspGaddr(self.wksp, &slot[0]);
        return @intCast(gaddr / c_abi.dcache.chunk_align);
    }

    /// Blocks until the consumer has room or stop is signalled. Polls with a
    /// bounded spin-pause budget before backing off to a bounded sleep; see
    /// runtime/link/wait.zig for why this deviates from Firedancer's
    /// non-sleeping hot transmit path.
    pub fn publish(
        self: *Producer,
        payload: []const u8,
        backpressure_waits: *std.atomic.Value(u64),
        stop: *const std.atomic.Value(bool),
    ) error{ Stopped, PayloadTooLarge }!void {
        ready: while (true) {
            var spins: u32 = 0;
            while (spins < wait.spin_poll_max) : (spins += 1) {
                const consumer_seq = c_abi.fseq.fseqQuery(self.fseq);
                const lag = self.next_seq -% consumer_seq;
                if (lag < self.depth) break :ready;
                c_abi.boot.spinPause();
            }
            _ = backpressure_waits.fetchAdd(1, .release);
            if (stop.load(.acquire)) return error.Stopped;
            process.sleepNanos(wait.idle_sleep_ns);
        }

        const chunk = try self.writeSlot(payload);
        c_abi.queue.mcachePublish(self.mcache, self.depth, self.next_seq, 0, chunk, @intCast(payload.len), 0, 0, 0);
        self.next_seq += 1;
    }

    pub fn publishLossy(self: *Producer, payload: []const u8, dropped: *std.atomic.Value(u64)) error{PayloadTooLarge}!void {
        const consumer_seq = c_abi.fseq.fseqQuery(self.fseq);
        const lag = self.next_seq -% consumer_seq;
        if (lag >= self.depth) _ = dropped.fetchAdd(1, .release);

        const chunk = try self.writeSlot(payload);
        c_abi.queue.mcachePublish(self.mcache, self.depth, self.next_seq, 0, chunk, @intCast(payload.len), 0, 0, 0);
        self.next_seq += 1;
    }
};
