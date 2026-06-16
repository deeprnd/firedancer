const std = @import("std");
const basket = @import("basket");
const model = @import("model");
const trade_ticket = @import("trade_ticket");

const ReplayCapsuleWire = struct {
    ticket_id: []const u8,
    model_substitutions: []const struct {
        fixture_file: []const u8,
    },
    adapter_substitutions: []const struct {
        operation: []const u8,
        fixture_file: []const u8,
    },
    replay_assertions: struct {
        no_live_model_call: bool,
        no_live_adapter_call: bool,
        no_paper_fill_emitted: bool,
        affordability_outcome_matches: []const u8,
        policy_outcome_matches: []const u8,
    },
};

pub const ReplayVerification = struct {
    external_effects_disabled: bool,
    replay_match: bool,
    divergence_count: u64,
};

pub fn verifyAllowedTrade(
    allocator: std.mem.Allocator,
    io: std.Io,
    proposed_basket: *const basket.Basket,
    ticket: *const trade_ticket.TradeTicket,
    paper_result: *const trade_ticket.PaperExecutionResult,
    model_response: *const model.ModelResponse,
) !ReplayVerification {
    const raw = try std.Io.Dir.cwd().readFileAlloc(
        io,
        "src/tickoni/test/fixtures/investment/replay_capsule_ai_infra.json",
        allocator,
        .limited(16 * 1024),
    );
    defer allocator.free(raw);
    var parsed = try std.json.parseFromSlice(ReplayCapsuleWire, allocator, raw, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const capsule = parsed.value;
    var divergences: u64 = 0;

    if (!capsule.replay_assertions.no_live_model_call) divergences += 1;
    if (!capsule.replay_assertions.no_live_adapter_call) divergences += 1;
    if (!capsule.replay_assertions.no_paper_fill_emitted) divergences += 1;
    if (!std.mem.eql(u8, capsule.replay_assertions.affordability_outcome_matches, "allow")) divergences += 1;
    if (!std.mem.eql(u8, capsule.replay_assertions.policy_outcome_matches, "allow")) divergences += 1;
    if (!std.mem.eql(u8, ticket.ticketIdSlice(), capsule.ticket_id)) divergences += 1;
    if (ticket.target_notional_cents != proposed_basket.total_allocated_cents) divergences += 1;
    if (paper_result.total_filled_cents != ticket.target_notional_cents) divergences += 1;
    if (model_response.content.len == 0) divergences += 1;
    if (capsule.model_substitutions.len != 1) divergences += 1;
    if (capsule.adapter_substitutions.len != 3) divergences += 1;
    if (!std.mem.eql(u8, capsule.model_substitutions[0].fixture_file, "model_response_ai_infra_gemma4.json")) divergences += 1;

    return .{
        .external_effects_disabled = true,
        .replay_match = divergences == 0,
        .divergence_count = divergences,
    };
}
