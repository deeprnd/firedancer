/// Compatibility facade: runtime-owned shared-memory link APIs now live under
/// src/tickoni/runtime/link/*.zig, but existing callers can keep importing
/// `rt.shm_link` until they are migrated deliberately.
const link = @import("link.zig");

pub const LinkHandles = link.LinkHandles;
pub const Producer = link.Producer;
pub const Consumer = link.Consumer;
pub const create = link.create;
