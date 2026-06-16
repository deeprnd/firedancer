const backend = @import("backend.zig");

pub const AdapterOperation = backend.AdapterOperation;
pub const AdapterRequest = backend.AdapterRequest;
pub const AdapterResult = backend.AdapterResult;

pub const FixtureBackendError = backend.FixtureBackendError;
pub const MockBackend = backend.MockBackend;
pub const QuoteLoader = backend.QuoteLoader;
pub const FixtureBackend = backend.FixtureBackend;
pub const Backend = backend.Backend;

pub const FixtureAdapterError = backend.FixtureBackendError;
pub const FixtureAdapter = backend.FixtureBackend;

test {
    _ = @import("backend.zig");
}
