const backend = @import("backend.zig");
const schema = @import("schema.zig");

pub const SamplingParams = schema.SamplingParams;
pub const Message = schema.Message;
pub const ModelRequest = schema.ModelRequest;
pub const TokenUsage = schema.TokenUsage;
pub const ModelResponse = schema.ModelResponse;

pub const MockBackend = backend.MockBackend;
pub const HttpBackend = backend.HttpBackend;
pub const Backend = backend.Backend;

test {
    _ = @import("schema.zig");
    _ = @import("backend.zig");
}
