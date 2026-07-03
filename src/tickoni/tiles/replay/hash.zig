/// Replay-critical proposal/result hash helpers (quote snapshot,
/// affordability, trade ticket, paper execution result), split out of
/// mod.zig's verification orchestration — see finding 22 in
/// doc/strategy/roadmap/backlog/audits/tech_debt.md.
const std = @import("std");
const c_abi = @import("c_abi");
const portfolio = @import("portfolio");
const trade_ticket = @import("trade_ticket");

/// Firedancer-backed SipHash13 domain for replay-critical proposal/result
/// hashes. One shared runtime hash boundary per CLAUDE.md's hash-boundary
/// contract, instead of a separate ad hoc std.hash.Wyhash mix per call site.
const replay_hash_k0: u64 = 0x0000_4c50_4552_4b54; // "TKREPL\0\0" LE
const replay_hash_k1: u64 = 1; // replay hash boundary version

fn updateValue(sip: *c_abi.ballet.Siphash13, value: anytype) void {
    var copy = value;
    c_abi.ballet.siphashAppend(sip, std.mem.asBytes(&copy));
}

fn initReplaySip() c_abi.ballet.Siphash13 {
    var sip: c_abi.ballet.Siphash13 = .{};
    c_abi.ballet.siphashInit(&sip, replay_hash_k0, replay_hash_k1);
    return sip;
}

pub fn hashBytes(bytes: []const u8) u64 {
    var sip = initReplaySip();
    c_abi.ballet.siphashAppend(&sip, bytes);
    return c_abi.ballet.siphashFini(&sip);
}

pub fn hashQuoteSnapshot(snapshot: *const trade_ticket.QuoteSnapshot) u64 {
    var sip = initReplaySip();
    updateValue(&sip, snapshot.as_of_ns);
    updateValue(&sip, snapshot.quote_count);
    for (snapshot.quotes[0..snapshot.quote_count]) |quote| {
        c_abi.ballet.siphashAppend(&sip, quote.tickerSlice());
        updateValue(&sip, quote.venue);
        updateValue(&sip, quote.bid_cents);
        updateValue(&sip, quote.ask_cents);
        updateValue(&sip, quote.last_cents);
    }
    return c_abi.ballet.siphashFini(&sip);
}

pub fn hashAffordability(result: portfolio.AffordabilityResult) u64 {
    var sip = initReplaySip();
    updateValue(&sip, result.outcome);
    updateValue(&sip, result.requested_notional_cents);
    updateValue(&sip, result.max_affordable_cents);
    updateValue(&sip, result.cash_available_cents);
    updateValue(&sip, result.buying_power_cents);
    updateValue(&sip, result.remaining_daily_notional_cents);
    updateValue(&sip, result.remaining_monthly_notional_cents);
    return c_abi.ballet.siphashFini(&sip);
}

pub fn hashTicket(ticket: *const trade_ticket.TradeTicket) u64 {
    var sip = initReplaySip();
    c_abi.ballet.siphashAppend(&sip, ticket.ticketIdSlice());
    updateValue(&sip, ticket.account_id);
    updateValue(&sip, ticket.side);
    updateValue(&sip, ticket.order_type);
    updateValue(&sip, ticket.target_notional_cents);
    updateValue(&sip, ticket.estimated_cost_cents);
    updateValue(&sip, ticket.policy_outcome);
    updateValue(&sip, ticket.affordability_result.max_affordable_cents);
    updateValue(&sip, ticket.affordability_result.effective_max_paper_trade_cents);
    updateValue(&sip, ticket.line_item_count);
    for (ticket.line_items[0..ticket.line_item_count]) |line| {
        c_abi.ballet.siphashAppend(&sip, line.tickerSlice());
        updateValue(&sip, line.quantity_micros);
        updateValue(&sip, line.price_cents);
        updateValue(&sip, line.line_notional_cents);
    }
    updateValue(&sip, ticket.blocked_reason_count);
    for (ticket.blocked_reasons[0..ticket.blocked_reason_count]) |reason| {
        updateValue(&sip, reason.code);
        updateValue(&sip, reason.failed_scope_dim);
        updateValue(&sip, reason.requested_cents);
        updateValue(&sip, reason.limit_cents);
    }
    return c_abi.ballet.siphashFini(&sip);
}

pub fn hashPaperResult(result: *const trade_ticket.PaperExecutionResult) u64 {
    var sip = initReplaySip();
    c_abi.ballet.siphashAppend(&sip, result.paperOrderIdSlice());
    c_abi.ballet.siphashAppend(&sip, result.ticketIdSlice());
    updateValue(&sip, result.account_id);
    updateValue(&sip, result.status);
    updateValue(&sip, result.total_filled_cents);
    updateValue(&sip, result.fill_count);
    for (result.fills[0..result.fill_count]) |fill| {
        c_abi.ballet.siphashAppend(&sip, fill.tickerSlice());
        updateValue(&sip, fill.quantity_micros);
        updateValue(&sip, fill.fill_price_cents);
        updateValue(&sip, fill.filled_notional_cents);
    }
    updateValue(&sip, result.resulting_account_snapshot.cash_cents);
    updateValue(&sip, result.resulting_account_snapshot.buying_power_cents);
    updateValue(&sip, result.resulting_account_snapshot.day_notional_used_cents);
    updateValue(&sip, result.resulting_account_snapshot.month_notional_used_cents);
    return c_abi.ballet.siphashFini(&sip);
}
