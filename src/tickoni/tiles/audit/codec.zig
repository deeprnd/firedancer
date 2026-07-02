const codec = @import("audit_codec");

pub const max_binary_len = codec.max_binary_len;
pub const ParsedBinary = codec.ParsedBinary;
pub const buildEvent = codec.buildEvent;
pub const computeRecordHash = codec.computeRecordHash;
pub const auditEventsEql = codec.auditEventsEql;
pub const checkSchemaVersion = codec.checkSchemaVersion;
pub const parseRecordType = codec.parseRecordType;
pub const peekBinaryLen = codec.peekBinaryLen;
pub const formatBinary = codec.formatBinary;
pub const parseBinary = codec.parseBinary;
pub const formatJsonLine = codec.formatJsonLine;
