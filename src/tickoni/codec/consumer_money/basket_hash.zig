const basket = @import("basket");
const thesis = @import("thesis");

pub const schema_version = basket.basket_schema_version;

pub fn basketHash(value: *const basket.Basket) u64 {
    return basket.computeBasketHash(value);
}

test "basketHash matches canonical basket schema hash" {
    const input = thesis.fixtures.ai_infrastructure;
    const intent = try thesis.normalize(input);
    var built = try basket.build(intent, thesis.computeThesisInputHash(input));
    try std.testing.expectEqual(basket.computeBasketHash(&built), basketHash(&built));
}

const std = @import("std");
