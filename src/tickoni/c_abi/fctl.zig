/// Narrow Zig bindings over src/tango/fctl/fd_fctl.h.
///
/// The public Firedancer API mixes exported functions with static inline
/// helpers. Tickoni code binds only through Tickoni-owned `tk_*` shim symbols.
const std = @import("std");

pub const rx_max_max: usize = 65_535;
pub const fctl_align: usize = 8;

pub const FctlPrivateRx = extern struct {
    cr_max: i64,
    seq_laddr: ?[*]const u64,
    slow_laddr: ?[*]u64,
};

pub const FctlPrivate = extern struct {
    rx_max: u16,
    rx_cnt: u16,
    in_refill: i32,
    cr_burst: u64,
    cr_max: u64,
    cr_resume: u64,
    cr_refill: u64,
};

pub const single_rx_footprint: usize = fctlFootprint(1);

pub const Fctl = opaque {};

pub fn fctlFootprint(rx_max: usize) usize {
    if (rx_max > rx_max_max) return 0;
    const base = @sizeOf(FctlPrivate) + (rx_max * @sizeOf(FctlPrivateRx));
    return std.mem.alignForward(usize, base, fctl_align);
}

extern fn tk_fctl_new(shmem: *anyopaque, rx_max: usize) ?*anyopaque;
extern fn tk_fctl_join(shfctl: *anyopaque) ?*Fctl;
extern fn tk_fctl_leave(fctl: *Fctl) ?*anyopaque;
extern fn tk_fctl_delete(shfctl: *anyopaque) ?*anyopaque;
extern fn tk_fctl_cfg_rx_add(fctl: *Fctl, cr_max: usize, seq_laddr: ?[*]const u64, slow_laddr: [*]u64) ?*Fctl;
extern fn tk_fctl_cfg_done(fctl: *Fctl, cr_burst: usize, cr_max: usize, cr_resume: usize, cr_refill: usize) ?*Fctl;
extern fn tk_fctl_cr_query(fctl: *const Fctl, tx_seq: u64, rx_idx_slow: ?*usize) usize;
extern fn tk_fctl_rx_cr_return(rx_seq_laddr: [*]u64, rx_seq: u64) void;
extern fn tk_fctl_rx_cnt(fctl: *const Fctl) usize;
extern fn tk_fctl_cr_burst(fctl: *const Fctl) usize;
extern fn tk_fctl_cr_max(fctl: *const Fctl) usize;
extern fn tk_fctl_cr_resume(fctl: *const Fctl) usize;
extern fn tk_fctl_cr_refill(fctl: *const Fctl) usize;
extern fn tk_fctl_rx_cr_max(fctl: *const Fctl, rx_idx: usize) usize;

pub fn new(shmem: *anyopaque, rx_max: usize) ?*anyopaque {
    return tk_fctl_new(shmem, rx_max);
}

pub fn join(shfctl: *anyopaque) ?*Fctl {
    return tk_fctl_join(shfctl);
}

pub fn leave(fctl: *Fctl) ?*anyopaque {
    return tk_fctl_leave(fctl);
}

pub fn delete(shfctl: *anyopaque) ?*anyopaque {
    return tk_fctl_delete(shfctl);
}

pub fn cfgRxAdd(fctl: *Fctl, cr_max: usize, seq_laddr: ?[*]const u64, slow_laddr: [*]u64) ?*Fctl {
    return tk_fctl_cfg_rx_add(fctl, cr_max, seq_laddr, slow_laddr);
}

pub fn cfgDone(fctl: *Fctl, cr_burst: usize, cr_max: usize, cr_resume: usize, cr_refill: usize) ?*Fctl {
    return tk_fctl_cfg_done(fctl, cr_burst, cr_max, cr_resume, cr_refill);
}

pub fn crQuery(fctl: *const Fctl, tx_seq: u64, rx_idx_slow: ?*usize) usize {
    return tk_fctl_cr_query(fctl, tx_seq, rx_idx_slow);
}

pub fn rxCrReturn(rx_seq_laddr: [*]volatile u64, rx_seq: u64) void {
    tk_fctl_rx_cr_return(@volatileCast(rx_seq_laddr), rx_seq);
}

pub fn rxCnt(fctl: *const Fctl) usize {
    return tk_fctl_rx_cnt(fctl);
}

pub fn crBurst(fctl: *const Fctl) usize {
    return tk_fctl_cr_burst(fctl);
}

pub fn crMax(fctl: *const Fctl) usize {
    return tk_fctl_cr_max(fctl);
}

pub fn crResume(fctl: *const Fctl) usize {
    return tk_fctl_cr_resume(fctl);
}

pub fn crRefill(fctl: *const Fctl) usize {
    return tk_fctl_cr_refill(fctl);
}

pub fn rxCrMax(fctl: *const Fctl, rx_idx: usize) usize {
    return tk_fctl_rx_cr_max(fctl, rx_idx);
}

test "fctl layout constants match the header-derived layout" {
    try std.testing.expectEqual(@as(usize, 8), fctl_align);
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(FctlPrivateRx));
    try std.testing.expectEqual(@as(usize, 40), @sizeOf(FctlPrivate));
    try std.testing.expectEqual(@as(usize, 64), single_rx_footprint);
}

test "fctl config and credit query track one receiver" {
    var mem: [single_rx_footprint]u8 align(fctl_align) = undefined;
    const shmem = new(&mem, 1) orelse return error.FctlNewFailed;
    const fctl = join(shmem) orelse return error.FctlJoinFailed;
    defer _ = leave(fctl);
    defer _ = delete(shmem);

    var rx_seq: u64 = 0;
    var slow_count: u64 = 0;
    const rx_seq_laddr: [*]const u64 = @ptrCast(&rx_seq);
    const slow_laddr: [*]u64 = @ptrCast(&slow_count);

    _ = cfgRxAdd(fctl, 4, rx_seq_laddr, slow_laddr) orelse return error.FctlCfgRxAddFailed;
    _ = cfgDone(fctl, 1, 0, 0, 0) orelse return error.FctlCfgDoneFailed;

    try std.testing.expectEqual(@as(usize, 1), rxCnt(fctl));
    try std.testing.expectEqual(@as(usize, 1), crBurst(fctl));
    try std.testing.expectEqual(@as(usize, 4), crMax(fctl));
    try std.testing.expectEqual(@as(usize, 3), crResume(fctl));
    try std.testing.expectEqual(@as(usize, 2), crRefill(fctl));
    try std.testing.expectEqual(@as(usize, 4), rxCrMax(fctl, 0));

    var slow_idx: usize = std.math.maxInt(usize);
    try std.testing.expectEqual(@as(usize, 4), crQuery(fctl, 0, &slow_idx));
    try std.testing.expectEqual(std.math.maxInt(usize), slow_idx);

    rxCrReturn(@ptrCast(&rx_seq), 2);
    try std.testing.expectEqual(@as(usize, 4), crQuery(fctl, 2, null));
    try std.testing.expectEqual(@as(u64, 2), rx_seq);
}
