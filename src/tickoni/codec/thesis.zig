const thesis_hash = @import("consumer_money/thesis_hash.zig");
const basket_hash = @import("consumer_money/basket_hash.zig");

pub const thesisSchemaVersion = thesis_hash.schema_version;
pub const basketSchemaVersion = basket_hash.schema_version;

pub const thesisInputHash = thesis_hash.thesisInputHash;
pub const basketHash = basket_hash.basketHash;

test {
    _ = thesis_hash;
    _ = basket_hash;
}
