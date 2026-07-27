# V2.21.S6 Quality Gate

## Focused verification performed

```bash
zig build -Dfd-lib-dir=build/fd-tickoni-fd/lib --summary all
bash contrib/test/run_cli_demo_tests.sh
/opt/zig/zig test -ODebug -Mroot=src/tickoni/demo/diagnostic.zig --cache-dir .zig-cache --global-cache-dir .zig-global-cache --zig-lib-dir /opt/zig/lib/
/opt/zig/zig test -ODebug --dep diagnostic -Mroot=src/tickoni/demo/conformance.zig -Mdiagnostic=src/tickoni/demo/diagnostic.zig --cache-dir .zig-cache --global-cache-dir .zig-global-cache --zig-lib-dir /opt/zig/lib/
```

## Current expected pass criteria

- `tickoni-supervisor` builds with FD libs available
- bare `demo` invocation fails closed with usage
- JSON suite output includes 4 scenarios
- plain-text suite output includes blocked/tampered diagnostics
- per-tier manifest isolation logic is active
- comparator and schema tests pass
