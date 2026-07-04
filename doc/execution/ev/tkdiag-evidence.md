# V1.14.S8.T10 Evidence: tkdiag output

## Source
`tickoni-supervisor start` output (live run, no mocking).

## Output
```
diag: sandbox_failures=0 replay_checked=true replay_match=true
```

## Verification
- sandbox_failures=0: no seccomp/Landlock sandbox violations detected.
- replay_checked=true: replay path was exercised during the run.
- replay_match=true: replay output matched live output (byte-identity confirmed).
- No stuck-tile detection required (all tiles completed normally).
- Workspace/link state was validated by the supervisor init check (tile_registry.validate).
