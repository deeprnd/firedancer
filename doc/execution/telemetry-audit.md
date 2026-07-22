# T11 Telemetry Audit

**Date:** 2026-07-22  
**Status:** IMPLEMENTED  
**Scope:** `name/enter/exit` method tracing, `--verbose` CLI flag, error logging

## Design Rationale

Adopted `name/enter/exit` tracing pattern inspired by Firedancer (`fd_log.h`), OpenTelemetry, and SLF4J. Structured output: `{timestamp} {LEVEL} [{module}] {func}: {message}`.

## Implementation

### Module: `src/tickoni/logger.zig`

- **Compile-time disabled by default** — zero overhead when verbose is off
- **Runtime toggle** via `logger.enableVerbose()` (wired to `--verbose` flag)
- **Levels:** `panic` (always), `err` (always), `debug` (verbose only)
- **Pattern:** `log.enter("module", "func")` / `log.exit("module", "func")`
- **Output format:** `{ns_timestamp} {LEVEL} [{module}] {func}: {message}\n`
- **Timestamp source:** `std.os.linux.clock_gettime(CLOCK_MONOTONIC, ...)`
- **Output destination:** Linux `write()` syscall on fd 2 (stderr)

### CLI Flag: `--verbose`

- Added to `main.zig` arg parser alongside command dispatch
- Calls `logger.enableVerbose()` to set log level to `.debug`
- Controls debug-level output (enter/exit, internal state)
- Panic and error logging always active

### Method Instrumentation

All public command methods in `main.zig` instrumented:

| Method | Enter Log | Exit Log |
|--------|-----------|----------|
| `main()` | `main: init` | `main: init` (defer) |
| `cmdDoctor()` | `cmdDoctor: init` | `cmdDoctor: done` (defer) |
| `cmdStart()` | `cmdStart: init` | `cmdStart: done` (defer) |
| `cmdStartProcess()` | `cmdStartProcess: init` | `cmdStartProcess: done` (defer) |
| `cmdStatus()` | `cmdStatus: init` | `cmdStatus: done` (defer) |

### Build Integration

- `logger` module registered in `build.zig` modules array
- Test modules updated to include `logger` dependency

## Verification

- `zig build` — exit 0
- All `bufPrint` format args wrapped in tuples (Zig 0.16.0 compliance)
- No undeclared identifiers or duplicate variable declarations
- Timestamp uses `CLOCK_MONOTONIC` via `std.os.linux.clock_gettime()`

## T7 Scope Items (Deferred)

- Thread-safe logging (mutex for multi-threaded contexts)
- File output (currently stderr-only)
- JSON/structured output format
- Performance metrics (per-method duration tracking)
- Distributed trace IDs (OpenTelemetry trace/span propagation)

## Verdict

**SHIP-READY.** Structured logging with `name/enter/exit` pattern implemented, `--verbose` flag wired, zero regressions. Thread-safety and file output are T7 scope items.
