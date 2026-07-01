const schema = @import("adapter_messages");
const backend = @import("backend.zig");

pub const AdapterOperation = schema.AdapterOperation;
pub const AdapterRequest = schema.AdapterRequest;
pub const AdapterResult = schema.AdapterResult;
pub const BackendError = schema.BackendError;

pub const QuoteLoader = backend.QuoteLoader;
pub const FixtureBackend = backend.FixtureBackend;
pub const Backend = backend.Backend;

pub const FixtureBackendError = schema.BackendError;
pub const FixtureAdapter = backend.FixtureBackend;

test {
    _ = @import("backend.zig");
}
