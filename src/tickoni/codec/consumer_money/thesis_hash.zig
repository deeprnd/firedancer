const thesis = @import("thesis");

pub const schema_version = thesis.thesis_schema_version;

pub fn thesisInputHash(input: thesis.ThesisInput) u64 {
    return thesis.computeThesisInputHash(input);
}

test "thesisInputHash matches canonical thesis schema hash" {
    const fixtures = thesis.fixtures;
    try std.testing.expectEqual(
        thesis.computeThesisInputHash(fixtures.ai_infrastructure),
        thesisInputHash(fixtures.ai_infrastructure),
    );
}

const std = @import("std");
