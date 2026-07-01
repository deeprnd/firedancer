const schema = @import("types.zig");
const codec = @import("codec.zig");

pub const audit_schema_version = schema.audit_schema_version;
pub const PolicyOutcome = schema.PolicyOutcome;
pub const LimitType = schema.LimitType;
pub const RecordType = schema.RecordType;
pub const SourceEventPayload = schema.SourceEventPayload;
pub const NormalizationPayload = schema.NormalizationPayload;
pub const PolicyDecisionPayload = schema.PolicyDecisionPayload;
pub const ModelCallPayload = schema.ModelCallPayload;
pub const FinancialAdapterCallPayload = schema.FinancialAdapterCallPayload;
pub const ProposalPayload = schema.ProposalPayload;
pub const DestinationCheckPayload = schema.DestinationCheckPayload;
pub const LimitCheckPayload = schema.LimitCheckPayload;
pub const ApprovalRequiredPayload = schema.ApprovalRequiredPayload;
pub const DenialPayload = schema.DenialPayload;
pub const TelemetryCheckpointPayload = schema.TelemetryCheckpointPayload;
pub const ReplayResultPayload = schema.ReplayResultPayload;
pub const DeduplicationPayload = schema.DeduplicationPayload;
pub const CaseCreationPayload = schema.CaseCreationPayload;
pub const Header = schema.Header;
pub const AuditEvent = schema.AuditEvent;

pub const max_binary_len = codec.max_binary_len;
pub const ParsedBinary = codec.ParsedBinary;
pub const buildEvent = codec.buildEvent;
pub const computeRecordHash = codec.computeRecordHash;
pub const auditEventsEql = codec.auditEventsEql;
pub const checkSchemaVersion = codec.checkSchemaVersion;
pub const parseRecordType = codec.parseRecordType;
pub const peekBinaryLen = codec.peekBinaryLen;
pub const formatBinary = codec.formatBinary;
pub const formatJsonLine = codec.formatJsonLine;
pub const parseBinary = codec.parseBinary;

test {
    _ = @import("fixture_events.zig");
}
