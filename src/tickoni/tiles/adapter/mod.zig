const schema = @import("messages.zig");
const backend = @import("backend.zig");

pub const AdapterOperation = schema.AdapterOperation;
pub const AdapterRequest = schema.AdapterRequest;
pub const AdapterResult = schema.AdapterResult;
pub const BackendError = schema.BackendError;

pub const MockBackend = backend.MockBackend;
pub const QuoteLoader = backend.QuoteLoader;
pub const FixtureBackend = backend.FixtureBackend;
pub const Backend = backend.Backend;

pub const FixtureBackendError = schema.BackendError;
pub const FixtureAdapter = backend.FixtureBackend;

test {
    _ = @import("messages.zig");
    _ = @import("mock.zig");
    _ = @import("backend.zig");
}
