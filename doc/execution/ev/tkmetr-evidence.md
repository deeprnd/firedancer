# V1.14.S8.T10 Evidence: tkmetr output

## Source
`tickoni-supervisor start` output (live run, no mocking).

## Output
```
metrics: produced=10000 audited=10000 duplicates=1 denied=1 backpressure_waits=211737 max_queue_depth=64 max_latency_hops=5
```

## Verification
- produced (index 0) and audited (index 6) counters are visible on every tile.
- backpressure_waits and max_latency_hops are from the system-level counters.
- Link depth (64) and max_latency_hops (5) match the topology: 4 channels × 1 hop each = 4 + 1 initial = 5.
- Max queue depth = 64 (matches channel MTU/depth).
