const demo = @import("investment_demo");
const support = @import("investment_support");
const std = @import("std");

test "investment_decision_cards_integration: allowed demo exposes persisted thesis and money proposal cards" {
    const result = try demo.runAllowedTradeScenario(std.testing.allocator, std.testing.io, support.operationsThesisInput());

    try std.testing.expectEqual(result.basket.basket_id, result.decision_cards.thesis_card.basket_id);
    try std.testing.expect(result.decision_cards.thesis_card.linked_position_count > 0);
    try std.testing.expect(result.decision_cards.thesis_card.linked_positions[0].evidence_hash != 0);
    try std.testing.expectEqualStrings("supplier_acme_us", result.decision_cards.money_proposal_card.beneficiarySlice());
    try std.testing.expectEqualStrings("payment_failed", result.decision_cards.money_proposal_card.sourceEventSlice());
    try std.testing.expectEqualStrings("USD", result.decision_cards.money_proposal_card.currencySlice());
    try std.testing.expect(result.decision_cards.money_proposal_card.evidence_hash != 0);

    const json = try demo.cards.allocDecisionCardsJson(std.testing.allocator, &result.decision_cards);
    defer std.testing.allocator.free(json);

    const ContractWire = struct {
        schema_version: u16,
        thesis_card: struct {
            linked_positions: []const struct {
                ticker: []const u8,
                rationale: []const u8,
                evidence_hash: u64,
                allocation_cents: i64,
            },
            current_exposure_bp: u32,
        },
        money_proposal_card: struct {
            beneficiary: []const u8,
            source_event: []const u8,
            rail: []const u8,
            approval_state: []const u8,
            evidence_hash: u64,
        },
    };

    const parsed = try std.json.parseFromSlice(ContractWire, std.testing.allocator, json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u16, 1), parsed.value.schema_version);
    try std.testing.expectEqual(@as(usize, result.decision_cards.thesis_card.linked_position_count), parsed.value.thesis_card.linked_positions.len);
    try std.testing.expectEqualStrings("supplier_acme_us", parsed.value.money_proposal_card.beneficiary);
    try std.testing.expectEqualStrings("payment_failed", parsed.value.money_proposal_card.source_event);
    try std.testing.expectEqualStrings("ach", parsed.value.money_proposal_card.rail);
    try std.testing.expectEqualStrings("pending", parsed.value.money_proposal_card.approval_state);
}
