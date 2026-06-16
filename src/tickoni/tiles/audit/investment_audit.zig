const std = @import("std");
const audit = @import("audit_tile");
const basket = @import("basket");
const model = @import("model");
const portfolio = @import("portfolio");
const replay = @import("replay");
const thesis = @import("thesis");
const trade_ticket = @import("trade_ticket");

pub const allowed_trade_event_count: usize = 9;
pub const oversized_trade_blocked_event_count: usize = 10;
pub const restricted_instrument_blocked_event_count: usize = 6;

pub const AllowedTradeAuditChain = struct {
    events: [allowed_trade_event_count]audit.AuditEvent,

    pub fn slice(self: *const AllowedTradeAuditChain) []const audit.AuditEvent {
        return &self.events;
    }
};

pub const OversizedTradeBlockedAuditChain = struct {
    events: [oversized_trade_blocked_event_count]audit.AuditEvent,

    pub fn slice(self: *const OversizedTradeBlockedAuditChain) []const audit.AuditEvent {
        return &self.events;
    }
};

pub const RestrictedInstrumentBlockedAuditChain = struct {
    events: [restricted_instrument_blocked_event_count]audit.AuditEvent,

    pub fn slice(self: *const RestrictedInstrumentBlockedAuditChain) []const audit.AuditEvent {
        return &self.events;
    }
};

const policy_version = "tickoni.v1_1_demo";
const source_system = "tkapi_demo";
const source_event_type = "investment_intent";
const canonical_event_type = "investment.intent";
const model_backend_id = "fixture.ai_infra";
const proposal_type = "trading_order.propose";
const replay_capsule_id = "replay_capsule_ai_infra";

fn parseFixedAsciiBytes(comptime N: usize, value: []const u8) [N]u8 {
    if (value.len > N) @panic("fixed ASCII field too long");
    var out = [_]u8{0} ** N;
    for (value, 0..) |byte, idx| {
        if (byte < 0x20 or byte > 0x7e) @panic("non-ASCII byte in fixed field");
        out[idx] = byte;
    }
    return out;
}

fn updateValue(hasher: *std.hash.Wyhash, value: anytype) void {
    var copy = value;
    hasher.update(std.mem.asBytes(&copy));
}

fn hashBytes(bytes: []const u8) u64 {
    return std.hash.Wyhash.hash(0, bytes);
}

fn hashQuoteSnapshot(snapshot: *const trade_ticket.QuoteSnapshot) u64 {
    var hasher = std.hash.Wyhash.init(0);
    updateValue(&hasher, snapshot.as_of_ns);
    updateValue(&hasher, snapshot.quote_count);
    for (snapshot.quotes[0..snapshot.quote_count]) |quote| {
        hasher.update(quote.tickerSlice());
        updateValue(&hasher, quote.venue);
        updateValue(&hasher, quote.bid_cents);
        updateValue(&hasher, quote.ask_cents);
        updateValue(&hasher, quote.last_cents);
    }
    return hasher.final();
}

fn hashAffordability(result: portfolio.AffordabilityResult) u64 {
    var hasher = std.hash.Wyhash.init(0);
    updateValue(&hasher, result.outcome);
    updateValue(&hasher, result.requested_notional_cents);
    updateValue(&hasher, result.max_affordable_cents);
    updateValue(&hasher, result.cash_available_cents);
    updateValue(&hasher, result.buying_power_cents);
    updateValue(&hasher, result.remaining_daily_notional_cents);
    updateValue(&hasher, result.remaining_monthly_notional_cents);
    return hasher.final();
}

fn hashTicket(ticket: *const trade_ticket.TradeTicket) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(ticket.ticketIdSlice());
    updateValue(&hasher, ticket.account_id);
    updateValue(&hasher, ticket.side);
    updateValue(&hasher, ticket.order_type);
    updateValue(&hasher, ticket.target_notional_cents);
    updateValue(&hasher, ticket.estimated_cost_cents);
    updateValue(&hasher, ticket.policy_outcome);
    updateValue(&hasher, ticket.affordability_result.max_affordable_cents);
    updateValue(&hasher, ticket.affordability_result.effective_max_paper_trade_cents);
    updateValue(&hasher, ticket.line_item_count);
    for (ticket.line_items[0..ticket.line_item_count]) |line| {
        hasher.update(line.tickerSlice());
        updateValue(&hasher, line.quantity_micros);
        updateValue(&hasher, line.price_cents);
        updateValue(&hasher, line.line_notional_cents);
    }
    updateValue(&hasher, ticket.blocked_reason_count);
    for (ticket.blocked_reasons[0..ticket.blocked_reason_count]) |reason| {
        updateValue(&hasher, reason.code);
        updateValue(&hasher, reason.failed_scope_dim);
        updateValue(&hasher, reason.requested_cents);
        updateValue(&hasher, reason.limit_cents);
    }
    return hasher.final();
}

fn hashPaperResult(result: *const trade_ticket.PaperExecutionResult) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(result.paperOrderIdSlice());
    hasher.update(result.ticketIdSlice());
    updateValue(&hasher, result.account_id);
    updateValue(&hasher, result.status);
    updateValue(&hasher, result.total_filled_cents);
    updateValue(&hasher, result.fill_count);
    for (result.fills[0..result.fill_count]) |fill| {
        hasher.update(fill.tickerSlice());
        updateValue(&hasher, fill.quantity_micros);
        updateValue(&hasher, fill.fill_price_cents);
        updateValue(&hasher, fill.filled_notional_cents);
    }
    updateValue(&hasher, result.resulting_account_snapshot.cash_cents);
    updateValue(&hasher, result.resulting_account_snapshot.buying_power_cents);
    updateValue(&hasher, result.resulting_account_snapshot.day_notional_used_cents);
    updateValue(&hasher, result.resulting_account_snapshot.month_notional_used_cents);
    return hasher.final();
}

fn capabilityEnvelopeId(thesis_input: *const thesis.ThesisInput, proposed_basket: *const basket.Basket) u128 {
    return (@as(u128, thesis.computeThesisInputHash(thesis_input.*)) << 64) | @as(u128, proposed_basket.basket_id);
}

fn header(
    seq: u64,
    tile_id: []const u8,
    logical_actor_id: u64,
    capability_envelope_id: u128,
    prev_hash: u64,
) audit.Header {
    return .{
        .schema_version = audit.audit_schema_version,
        .seq = seq,
        .source_offset = seq + 1,
        .tile_id = parseFixedAsciiBytes(6, tile_id),
        .logical_actor_id = logical_actor_id,
        .policy_version = parseFixedAsciiBytes(32, policy_version),
        .capability_envelope_id = capability_envelope_id,
        .timestamp_ns = 0,
        .prev_hash = prev_hash,
        .record_hash = 0,
    };
}

pub fn buildAllowedTradeChain(
    thesis_input: *const thesis.ThesisInput,
    proposed_basket: *const basket.Basket,
    quote_snapshot: *const trade_ticket.QuoteSnapshot,
    affordability: portfolio.AffordabilityResult,
    model_response: *const model.ModelResponse,
    ticket: *const trade_ticket.TradeTicket,
    paper_result: *const trade_ticket.PaperExecutionResult,
    replay_result: *const replay.ReplayVerification,
) AllowedTradeAuditChain {
    const raw_hash = thesis.computeThesisInputHash(thesis_input.*);
    const normalized_hash = proposed_basket.basket_id;
    const model_response_hash = hashBytes(model_response.content);
    const capability_id = capabilityEnvelopeId(thesis_input, proposed_basket);
    const quote_response_hash = hashQuoteSnapshot(quote_snapshot);
    const proposal_hash = hashTicket(ticket);
    const paper_response_hash = hashPaperResult(paper_result);

    var events: [allowed_trade_event_count]audit.AuditEvent = undefined;
    var prev_hash: u64 = 0;

    events[0] = audit.buildEvent(header(0, "tkings", thesis_input.account_id, capability_id, prev_hash), .{
        .source_event = .{
            .source_system = parseFixedAsciiBytes(16, source_system),
            .event_type = parseFixedAsciiBytes(32, source_event_type),
            .raw_hash = raw_hash,
        },
    });
    prev_hash = events[0].header.record_hash;

    events[1] = audit.buildEvent(header(1, "tknorm", thesis_input.account_id, capability_id, prev_hash), .{
        .normalization = .{
            .source_event_hash = raw_hash,
            .normalized_hash = normalized_hash,
            .canonical_event_type = parseFixedAsciiBytes(32, canonical_event_type),
        },
    });
    prev_hash = events[1].header.record_hash;

    events[2] = audit.buildEvent(header(2, "tkpoly", thesis_input.account_id, capability_id, prev_hash), .{
        .policy_decision = .{
            .outcome = if (ticket.policy_outcome == .allow) .allow else .deny,
            .rule_id = 1101,
            .failed_scope_dim = parseFixedAsciiBytes(32, if (ticket.policy_outcome == .allow) "" else "per_order_notional"),
            .source_event_hash = normalized_hash,
        },
    });
    prev_hash = events[2].header.record_hash;

    events[3] = audit.buildEvent(header(3, "tkmodl", thesis_input.account_id, capability_id, prev_hash), .{
        .model_call = .{
            .model_id = parseFixedAsciiBytes(32, model_backend_id),
            .prompt_hash = raw_hash,
            .response_hash = model_response_hash,
            .token_estimate = model_response.token_usage.total_tokens,
            .retry_count = 0,
        },
    });
    prev_hash = events[3].header.record_hash;

    events[4] = audit.buildEvent(header(4, "tkadpt", thesis_input.account_id, capability_id, prev_hash), .{
        .financial_adapter_call = .{
            .adapter_id = parseFixedAsciiBytes(16, "portfolio_demo"),
            .request_hash = hashBytes("portfolio.read"),
            .response_hash = hashAffordability(affordability),
            .fixture_id = 1,
        },
    });
    prev_hash = events[4].header.record_hash;

    events[5] = audit.buildEvent(header(5, "tkadpt", thesis_input.account_id, capability_id, prev_hash), .{
        .financial_adapter_call = .{
            .adapter_id = parseFixedAsciiBytes(16, "quotes_demo"),
            .request_hash = normalized_hash,
            .response_hash = quote_response_hash,
            .fixture_id = 2,
        },
    });
    prev_hash = events[5].header.record_hash;

    events[6] = audit.buildEvent(header(6, "tkagnt", thesis_input.account_id, capability_id, prev_hash), .{
        .proposal = .{
            .proposal_type = parseFixedAsciiBytes(32, proposal_type),
            .proposal_hash = proposal_hash,
            .approval_state = 0,
        },
    });
    prev_hash = events[6].header.record_hash;

    events[7] = audit.buildEvent(header(7, "tkadpt", thesis_input.account_id, capability_id, prev_hash), .{
        .financial_adapter_call = .{
            .adapter_id = parseFixedAsciiBytes(16, "paper_fill_demo"),
            .request_hash = proposal_hash,
            .response_hash = paper_response_hash,
            .fixture_id = 3,
        },
    });
    prev_hash = events[7].header.record_hash;

    events[8] = audit.buildEvent(header(8, "tkrepl", thesis_input.account_id, capability_id, prev_hash), .{
        .replay_result = .{
            .capsule_id = hashBytes(replay_capsule_id),
            .divergences = replay_result.divergence_count,
            .first_divergent_seq = replay_result.first_divergent_seq,
        },
    });

    return .{ .events = events };
}

pub fn buildOversizedTradeBlockedChain(
    thesis_input: *const thesis.ThesisInput,
    proposed_basket: *const basket.Basket,
    quote_snapshot: *const trade_ticket.QuoteSnapshot,
    affordability: portfolio.AffordabilityResult,
    model_response: *const model.ModelResponse,
    ticket: *const trade_ticket.TradeTicket,
    replay_result: *const replay.ReplayVerification,
) OversizedTradeBlockedAuditChain {
    const raw_hash = thesis.computeThesisInputHash(thesis_input.*);
    const normalized_hash = proposed_basket.basket_id;
    const model_response_hash = hashBytes(model_response.content);
    const capability_id = capabilityEnvelopeId(thesis_input, proposed_basket);
    const quote_response_hash = hashQuoteSnapshot(quote_snapshot);
    const proposal_hash = hashTicket(ticket);
    const blocked_reason = ticket.blocked_reasons[0];

    var events: [oversized_trade_blocked_event_count]audit.AuditEvent = undefined;
    var prev_hash: u64 = 0;

    events[0] = audit.buildEvent(header(0, "tkings", thesis_input.account_id, capability_id, prev_hash), .{
        .source_event = .{
            .source_system = parseFixedAsciiBytes(16, source_system),
            .event_type = parseFixedAsciiBytes(32, source_event_type),
            .raw_hash = raw_hash,
        },
    });
    prev_hash = events[0].header.record_hash;

    events[1] = audit.buildEvent(header(1, "tknorm", thesis_input.account_id, capability_id, prev_hash), .{
        .normalization = .{
            .source_event_hash = raw_hash,
            .normalized_hash = normalized_hash,
            .canonical_event_type = parseFixedAsciiBytes(32, canonical_event_type),
        },
    });
    prev_hash = events[1].header.record_hash;

    events[2] = audit.buildEvent(header(2, "tkpoly", thesis_input.account_id, capability_id, prev_hash), .{
        .policy_decision = .{
            .outcome = .deny,
            .rule_id = 1101,
            .failed_scope_dim = parseFixedAsciiBytes(32, blocked_reason.failed_scope_dim.label()),
            .source_event_hash = normalized_hash,
        },
    });
    prev_hash = events[2].header.record_hash;

    events[3] = audit.buildEvent(header(3, "tkmodl", thesis_input.account_id, capability_id, prev_hash), .{
        .model_call = .{
            .model_id = parseFixedAsciiBytes(32, model_backend_id),
            .prompt_hash = raw_hash,
            .response_hash = model_response_hash,
            .token_estimate = model_response.token_usage.total_tokens,
            .retry_count = 0,
        },
    });
    prev_hash = events[3].header.record_hash;

    events[4] = audit.buildEvent(header(4, "tkadpt", thesis_input.account_id, capability_id, prev_hash), .{
        .financial_adapter_call = .{
            .adapter_id = parseFixedAsciiBytes(16, "portfolio_demo"),
            .request_hash = hashBytes("portfolio.read"),
            .response_hash = hashAffordability(affordability),
            .fixture_id = 1,
        },
    });
    prev_hash = events[4].header.record_hash;

    events[5] = audit.buildEvent(header(5, "tkadpt", thesis_input.account_id, capability_id, prev_hash), .{
        .financial_adapter_call = .{
            .adapter_id = parseFixedAsciiBytes(16, "quotes_demo"),
            .request_hash = normalized_hash,
            .response_hash = quote_response_hash,
            .fixture_id = 2,
        },
    });
    prev_hash = events[5].header.record_hash;

    events[6] = audit.buildEvent(header(6, "tkagnt", thesis_input.account_id, capability_id, prev_hash), .{
        .proposal = .{
            .proposal_type = parseFixedAsciiBytes(32, proposal_type),
            .proposal_hash = proposal_hash,
            .approval_state = 0,
        },
    });
    prev_hash = events[6].header.record_hash;

    events[7] = audit.buildEvent(header(7, "tkpoly", thesis_input.account_id, capability_id, prev_hash), .{
        .limit_check = .{
            .limit_type = .amount,
            .value = blocked_reason.requested_cents,
            .limit = blocked_reason.limit_cents,
            .outcome = .deny,
        },
    });
    prev_hash = events[7].header.record_hash;

    events[8] = audit.buildEvent(header(8, "tkpoly", thesis_input.account_id, capability_id, prev_hash), .{
        .denial = .{
            .action_class = parseFixedAsciiBytes(32, "trading_order.place"),
            .reason_code = @intFromEnum(blocked_reason.code),
            .failed_scope_dim = parseFixedAsciiBytes(32, blocked_reason.failed_scope_dim.label()),
        },
    });
    prev_hash = events[8].header.record_hash;

    events[9] = audit.buildEvent(header(9, "tkrepl", thesis_input.account_id, capability_id, prev_hash), .{
        .replay_result = .{
            .capsule_id = hashBytes("replay_capsule_ai_infra_oversized_25000"),
            .divergences = replay_result.divergence_count,
            .first_divergent_seq = replay_result.first_divergent_seq,
        },
    });

    return .{ .events = events };
}

pub fn buildRestrictedInstrumentBlockedChain(
    thesis_input: *const thesis.ThesisInput,
    proposed_basket: *const basket.Basket,
    model_response: *const model.ModelResponse,
    replay_result: *const replay.ReplayVerification,
) RestrictedInstrumentBlockedAuditChain {
    const raw_hash = thesis.computeThesisInputHash(thesis_input.*);
    const normalized_hash = proposed_basket.basket_id;
    const model_response_hash = hashBytes(model_response.content);
    const capability_id = capabilityEnvelopeId(thesis_input, proposed_basket);

    var events: [restricted_instrument_blocked_event_count]audit.AuditEvent = undefined;
    var prev_hash: u64 = 0;

    events[0] = audit.buildEvent(header(0, "tkings", thesis_input.account_id, capability_id, prev_hash), .{
        .source_event = .{
            .source_system = parseFixedAsciiBytes(16, source_system),
            .event_type = parseFixedAsciiBytes(32, source_event_type),
            .raw_hash = raw_hash,
        },
    });
    prev_hash = events[0].header.record_hash;

    events[1] = audit.buildEvent(header(1, "tknorm", thesis_input.account_id, capability_id, prev_hash), .{
        .normalization = .{
            .source_event_hash = raw_hash,
            .normalized_hash = normalized_hash,
            .canonical_event_type = parseFixedAsciiBytes(32, canonical_event_type),
        },
    });
    prev_hash = events[1].header.record_hash;

    events[2] = audit.buildEvent(header(2, "tkpoly", thesis_input.account_id, capability_id, prev_hash), .{
        .policy_decision = .{
            .outcome = .deny,
            .rule_id = 1101,
            .failed_scope_dim = parseFixedAsciiBytes(32, "restricted_instrument"),
            .source_event_hash = normalized_hash,
        },
    });
    prev_hash = events[2].header.record_hash;

    events[3] = audit.buildEvent(header(3, "tkmodl", thesis_input.account_id, capability_id, prev_hash), .{
        .model_call = .{
            .model_id = parseFixedAsciiBytes(32, model_backend_id),
            .prompt_hash = raw_hash,
            .response_hash = model_response_hash,
            .token_estimate = model_response.token_usage.total_tokens,
            .retry_count = 0,
        },
    });
    prev_hash = events[3].header.record_hash;

    events[4] = audit.buildEvent(header(4, "tkpoly", thesis_input.account_id, capability_id, prev_hash), .{
        .denial = .{
            .action_class = parseFixedAsciiBytes(32, proposal_type),
            .reason_code = @intFromEnum(basket.RejectionReason.restricted_instrument),
            .failed_scope_dim = parseFixedAsciiBytes(32, "restricted_instrument"),
        },
    });
    prev_hash = events[4].header.record_hash;

    events[5] = audit.buildEvent(header(5, "tkrepl", thesis_input.account_id, capability_id, prev_hash), .{
        .replay_result = .{
            .capsule_id = hashBytes("replay_capsule_ai_infra_restricted_soxl"),
            .divergences = replay_result.divergence_count,
            .first_divergent_seq = replay_result.first_divergent_seq,
        },
    });

    return .{ .events = events };
}
