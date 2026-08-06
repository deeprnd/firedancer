---
adr: "04"
title: "Adopt constrained MVVM and a tk_ui tile architecture for the Qt terminal"
status: "proposed"
date: "2026-08-05"
authors: deeprnd
tags:
  - "terminal-ui"
  - "qt"
  - "qml"
  - "architecture"
  - "performance"
  - "shared-memory"
  - "tiles"
supersedes: []
superseded_by: []
related:
  - "ADR-03: Choose Qt for the Tickoni desktop terminal UI"
  - "V2.19: Tickoni Native Investment Terminal"
---

# ADR-04: Adopt constrained MVVM and a tk_ui tile architecture for the Qt terminal

## Decision Summary

In the context of Tickoni's Qt desktop terminal, facing QML performance sensitivity,
large live datasets, multiple windows, long-running sessions, and a strict requirement
that financial authority remain in the Zig runtime, it was decided to use:

- constrained MVVM/Presentation Model at the QML boundary;
- Qt Model/View for large and streaming collections;
- explicit application use cases and feature projection stores;
- unidirectional state flow;
- bounded command, response, correctness-event, latest-value, bulk-payload, diagnostic,
  and GUI-patch channels;
- a composite `tk_ui` tile containing the Qt application;
- Firedancer-style shared-memory channels between `tk_ui` and the semantic `tk_api`
  tile;
- a separate network gateway tile for remote HTTP, WebSocket, QUIC, or other external
  transports.

We will not use textbook MVC, unrestricted textbook MVVM, or Smalltalk-style MVC as the
standing application architecture. We will not place HTTP or WebSocket between the local
Qt terminal and the local Tickoni runtime. We will not allow QML controls, delegates,
pages, or presentation models to open sockets, parse wire messages, or call runtime
endpoints directly.

The local HTTP option is rejected because it introduces avoidable serialization,
framing, buffer-copying, kernel-network-stack, scheduling, allocation, parsing, and
event-loop overhead on a same-machine path. Tickoni is not an HFT execution terminal,
and the GUI is not part of an exchange-critical order path. The performance concern is
nevertheless material: thousands of changing cells can amplify every incoming update
into decoding, object allocation, model notifications, binding evaluation, delegate
work, layout, and rendering. A design that delivers one network message or one Qt event
per tick or per cell will exhaust the GUI frame budget even when the raw network
round-trip appears small.

Shared memory is therefore necessary but not sufficient. The chosen design also requires
topic-specific batching, coalescing, revision checks, bounded queues, incremental model
patches, and controlled GUI-thread drain budgets.

## Context and Problem Statement

ADR-03 chooses Qt 6 Quick/QML for the official Tickoni desktop terminal. That decision
does not define how QML, C++, Tickoni tiles, shared memory, threads, commands, streams,
bindings, and model updates are organized.

The intended terminal has an unusually demanding desktop workload:

- many simultaneously visible panels;
- large tables, watchlists, blotters, and audit timelines;
- thousands of changing values;
- multiple windows and monitors;
- keyboard-first operation;
- long-running operator sessions;
- policy, proposal, approval, execution, audit, and replay state that must not be lost,
  reordered, guessed, or silently overwritten.

QML is effective when it remains a declarative presentation layer. It can become
unpredictable and expensive when application logic is spread across bindings, event
handlers, delegates, global singletons, dynamically created objects, or network-aware
components. A button that performs a request, a delegate that subscribes to a global
stream, or a page that parses wire JSON creates hidden dependencies and bypasses the
application's correctness, backpressure, retry, sequencing, and audit rules.

Qt's performance guidance recommends asynchronous processing, batching backend
operations, proper C++ models where needed, simple delegates, few bindings in hot
delegates, item reuse, and profiling. `QAbstractItemModel` is not thread-safe; a model
connected to a view is operated from the GUI thread, so background work must be converted
into queued GUI-thread updates rather than direct model mutation.

Firedancer's architecture provides the relevant systems model: tiles communicate
through shared-memory queues, workspaces are preallocated shared memory regions, and
queue behavior must explicitly account for backpressure or dropped data. Tickoni will
reuse those architectural principles while providing portable channel and sandbox
implementations for Linux, macOS, and Windows.

### Why localhost HTTP is not the local UI boundary

HTTP is a valid external interoperability protocol. It is not the selected internal
desktop data path.

A local HTTP/WebSocket path would add work that has no semantic value when `tk_ui` and
`tk_api` are on the same machine:

- request and response framing;
- socket buffer management;
- kernel transitions and scheduler wake-ups;
- byte-stream parsing;
- serialization and deserialization;
- temporary allocations and copies;
- connection, heartbeat, and reconnect state;
- conversion from transport messages into another in-process queue;
- duplicate observability and error models for the network and UI paths.

Any one of these costs may be small in isolation. The architecture rejects their
multiplication across a dense live terminal.

The UI is not HFT:

- it does not compete on microsecond exchange latency;
- it does not render every market event;
- it does not place an exchange order directly from a QML handler;
- it does not make policy or execution decisions.

However, the UI still has a hard presentation budget. At 60 frames per second, the GUI
has approximately 16.7 ms per frame; at 120 frames per second, approximately 8.3 ms.
Incoming data must share that budget with input handling, binding evaluation, model
notifications, layout, scene-graph preparation, rendering, accessibility, and window
management.

A single market update can fan out into:

```text
wire or bus message
  -> decode and validation
  -> projection-store mutation
  -> model patch
  -> dataChanged/row notification
  -> QML role reads
  -> binding re-evaluation
  -> delegate changes
  -> layout and render work
```

Thousands of independently delivered cell updates can therefore consume much more CPU
than their payload size suggests. The primary UI risk is update amplification, not only
wire latency.

The design must consequently separate:

- every event the runtime receives;
- every authoritative state transition the UI must preserve;
- every latest value the UI may coalesce;
- every frame the user can actually perceive.

The runtime may process and retain every required event. The GUI receives lossless
correctness events and coalesced latest-value projections at a bounded, human-useful
cadence.

### Semantic API versus network API

`tk_api` is defined as a semantic API tile, not as an HTTP server.

It owns or fronts:

- request validation;
- subscriptions;
- capability negotiation;
- revision and freshness contracts;
- governed command routing;
- query and command responses;
- access to policy, audit, replay, adapter, and execution services.

A separate `tk_gateway` or `tk_gateway_client` tile owns external network protocols.

The topology is:

```text
local native terminal:

tk_ui
  -> shared-memory command channel
  -> tk_api
  -> runtime tiles

runtime state
  -> tk_api
  -> shared-memory event/value channels
  -> tk_ui


remote access:

remote client
  -> HTTP / WebSocket / QUIC
  -> tk_gateway
  -> internal tile channels
  -> tk_api


native terminal connected to remote runtime:

tk_ui
  -> local shared-memory channels
  -> tk_gateway_client
  -> external network protocol
  -> remote tk_gateway
  -> internal channels
  -> remote tk_api
```

This preserves one invariant:

> `tk_ui` and QML never speak a network protocol, even when the runtime is remote.

**Decision question:** Which application pattern and communication model should the Qt
terminal use so QML remains performant, the UI behaves as a Tickoni tile, financial
state remains authoritative, and all commands, events, queues, and cross-thread updates
follow explicit rules?

This decision matters now because the first QML panels, models, tile links, and queue
types will establish conventions that are expensive to reverse after multiple terminal
functions depend on them.

## Scope

### In scope

- The standing application architecture for the Qt terminal.
- The definition of `tk_ui` as a composite edge tile and sandbox boundary.
- Responsibilities of QML views, C++ view models, feature stores, item models, use
  cases, bus bridges, and tile links.
- The allowed communication channels between QML, C++, threads, `tk_ui`, and `tk_api`.
- Shared-memory ring and workspace semantics for local Tickoni communication.
- Portable macOS and Windows implementations that preserve the same tile-channel
  contract.
- Queue classes and delivery semantics for commands, responses, correctness events,
  latest-value data, bulk snapshots, diagnostics, and GUI patches.
- Binding and delegate rules required for QML performance.
- State ownership, revisions, freshness, process generations, resynchronization, and
  command reconciliation.
- The separation of internal tile communication from external network gateways.
- Tests and performance gates that enforce the decision.

### Out of scope

- Selection of the desktop UI framework; ADR-03 chooses Qt.
- The exact binary layout of every message and workspace object.
- The exact platform notification primitive on Linux, macOS, or Windows.
- Server-side market-data ingestion, policy, execution, audit, and replay implementation.
- The final chart renderer.
- The external gateway protocol.
- Direct broker, venue, provider, or exchange connectivity from the UI.
- Visual styling, colors, typography, and screen layout.

## Decision Drivers

- Keep QML declarative and presentation-only.
- Make the native UI a first-class Tickoni tile and sandbox participant.
- Prevent buttons, delegates, pages, and view models from performing transport
  operations.
- Preserve Zig and `tk_api` as the source of financial truth.
- Avoid localhost HTTP overhead on a same-machine, high-update-volume path.
- Keep correctness-bearing events ordered and lossless.
- Coalesce superseded latest-value updates before they reach QML.
- Avoid one message, signal, binding, or delegate update per market tick.
- Avoid unbounded queues and uncontrolled Qt event-loop growth.
- Make backpressure, overflow, and resynchronization explicit.
- Apply all QML-visible model changes on the GUI thread.
- Keep bindings simple, local, one-directional, and measurable.
- Use `QAbstractItemModel` for large or streaming collections.
- Avoid giant global view models, global event buses, and stringly typed messages.
- Support multiple windows without duplicating command submission or tile links.
- Permit deterministic fixtures and replay through the same bus-facing interfaces.
- Keep external network protocols in a separate gateway tile.
- Make performance and architecture violations detectable in review and CI.
- Preserve a portable architecture across Linux, macOS, and Windows even where the
  exact Firedancer implementation is not directly reusable.

Quality attributes affected:

- Correctness: authoritative state changes only after validated runtime responses or
  ordered events.
- Maintainability: responsibilities, channel ownership, queue behavior, and process
  boundaries are explicit.
- Portability: the bus contract is stable while shared-memory and wake primitives are
  platform-specific.
- Performance: local text/network framing is removed; high-volume state is batched,
  coalesced, and applied incrementally.
- Operability/testability: queue depth, lag, sequence gaps, process generations, and
  model-update costs are observable.
- Security/compliance: `tk_ui` has no direct broker/provider network authority and QML
  cannot bypass governed channels.

## Constraints and Assumptions

- `tk_ui` is a separate process and sandbox from the Zig runtime tiles.
- `tk_ui` is a composite edge tile rather than a strict one-thread/one-core busy-loop
  tile.
- `tk_api` is a semantic API tile.
- Local `tk_ui` to `tk_api` communication uses bounded shared-memory channels and
  workspace-backed payloads.
- External network protocols terminate in `tk_gateway` or `tk_gateway_client`, not in
  QML or the Qt application layer.
- QML runs on the GUI thread.
- QML-visible `QAbstractItemModel` instances are owned and mutated on the GUI thread.
- The bus ingress/egress thread owns shared-memory polling, publication, sequence
  validation, and wake handling.
- Parsing, decompression, schema validation, snapshot transformation, and patch
  construction may run in worker threads.
- Cross-thread communication uses immutable or move-safe C++ value objects.
- No application-level or tile-level queue is unbounded.
- Correctness-bearing events are never silently dropped or coalesced.
- Latest-value data may be coalesced only when its topic contract explicitly permits it.
- Bulk payload descriptors use workspace identifiers and offsets/handles, not process
  pointers.
- The architecture does not depend on Qt network classes, JSON, HTTP, WebSocket, QUIC,
  protobuf, or any other external transport type.
- QML JavaScript is limited to small presentation transformations and input handling.
- Runtime-owned financial state is never represented as writable two-way-bound QML
  state.
- View-local state such as focus, expansion, temporary input, and panel geometry may be
  held in QML or a focused view model.
- Queue capacities, batching intervals, and GUI drain budgets are configuration
  constants with documented defaults and tested failure behavior.
- The desktop bus may use a hybrid poll/park strategy; it does not dedicate a fully busy
  CPU core by default.
- The local bus removes avoidable protocol overhead but does not eliminate the need for
  coalescing, batching, or GUI performance discipline.
- Linux may reuse Firedancer/Tango primitives more directly. macOS and Windows may use
  Tickoni-owned compatible implementations while preserving the same ABI and delivery
  semantics.

## Considered Options

1. **Textbook MVC with service calls.** Models hold state, views render it, and
   controllers receive UI input and coordinate service calls.
2. **Textbook MVVM with view-model transport access.** QML views bind to view-model
   properties and invoke view-model commands; view models may call services directly.
3. **Smalltalk-style MVC with observable client-domain models.** Views observe mutable
   domain objects while controllers map input onto those objects.
4. **Constrained Qt MVVM over localhost HTTP/WebSocket.** QML remains passive and C++
   models are disciplined, but the local Qt process communicates with `tk_api` through a
   network protocol.
5. **Constrained Qt MVVM inside `tk_ui` over internal tile channels.** QML remains
   passive, C++ models expose projections, and `tk_ui` communicates with `tk_api` through
   bounded shared-memory channels and workspace-backed payloads.

## Option Analysis

### Option 1: Textbook MVC with service calls

A controller would mediate between QML views and models. Controllers might create views,
handle signals from controls, call services, and update models.

Good, because:

- The separation between view, controller, and model is familiar.
- User-input handling can be explicit.
- Controllers can keep some imperative behavior outside QML.

Bad, because:

- QML already provides declarative bindings and event handlers, so adding a controller
  per view often duplicates framework behavior.
- Controllers tend to manipulate QML objects imperatively, increasing coupling between
  C++ and the visual hierarchy.
- Model observation and controller updates can create multiple paths to the same state.
- A large multi-window terminal tends to accumulate controller-to-controller
  coordination and unclear ownership.
- MVC alone does not specify channel capacities, event ordering, coalescing,
  backpressure, workspace ownership, or GUI-patch budgets.
- Controllers commonly become convenient places for direct HTTP calls, encouraging
  feature-specific request paths.
- A controller-per-event design risks converting each incoming update into a separate
  GUI operation.

Neutral or conditional:

- Small local controllers remain useful for application startup, window lifecycle, or a
  platform-specific host, but not as the primary feature pattern.

Validation needed:

- A prototype would need to prove that controllers can avoid direct QML manipulation and
  still preserve one state-update path. No evidence currently makes that complexity
  preferable.

### Option 2: Textbook MVVM with view-model transport access

Each QML view binds to a view model. The view model exposes properties, collections, and
commands. State may be synchronized through broad or two-way bindings, and the view
model may invoke HTTP or service clients directly.

Good, because:

- QML naturally binds to `QObject` properties and C++ models.
- Views can be tested against mock view models.
- Presentation logic can remain outside QML.
- It maps well to function- or panel-specific UI surfaces.

Bad, because:

- Unrestricted MVVM encourages oversized view models that own transport, navigation,
  persistence, domain projections, and every command.
- Broad two-way binding obscures which side owns authoritative state.
- Binding chains can re-evaluate large visual trees after small changes.
- Exposing large `QVariantMap` or JavaScript object graphs makes dependency tracking and
  update cost difficult to predict.
- A view model that calls HTTP directly can bypass the central command queue, revision
  checks, idempotency, ordering, sandbox, and resynchronization rules.
- A view-model-per-panel network client duplicates connections, subscriptions, buffers,
  and retry behavior.
- It does not distinguish lossless correctness events from coalescible latest-value
  streams.
- It can turn every decoded network message into a property notification, amplifying
  transport traffic into binding and delegate work.

Neutral or conditional:

- MVVM is the closest textbook pattern to QML, but it requires stricter rules than
  textbook descriptions normally provide.

Validation needed:

- The architecture must prove that view models remain narrow, bindings remain one-way,
  and transport is outside view models.

### Option 3: Smalltalk-style MVC with observable client-domain models

Views observe models directly and render their state. Controllers interpret input and
send operations to models. Models notify observers when state changes.

Good, because:

- Domain models can be reused by multiple views.
- Input handling is conceptually distinct from rendering.
- It works well for interactive object systems with local mutable state.

Bad, because:

- Tickoni's authoritative domain model is in another process, not an in-process mutable
  object graph.
- Direct view observation of domain models creates wide notification fan-out.
- Observer cascades are difficult to bound under thousands of live updates.
- It encourages views to understand domain mutation and lifecycle details.
- It does not naturally express shared-memory sequence gaps, workspace generations,
  freshness, command idempotency, or resynchronization.
- It conflicts with the requirement that QML see read-optimized projections rather than
  runtime domain objects.
- The notification model provides no natural distinction between a lossless audit event
  and a replaceable quote value.

Neutral or conditional:

- Qt's signals and slots resemble observer mechanisms, but using that mechanism does not
  require adopting Smalltalk-style MVC.

Validation needed:

- It would require a separate mutable client-domain object layer and evidence that
  notification fan-out remains bounded. That layer is not justified.

### Option 4: Constrained Qt MVVM over localhost HTTP/WebSocket

QML remains passive and focused C++ view models use disciplined application services and
models. The Qt process communicates with a local `tk_api` HTTP/WebSocket server.

Good, because:

- The local and remote clients can initially share one protocol.
- HTTP tooling, proxies, captures, and test clients are mature.
- Process isolation is straightforward.
- A prototype can be built quickly.
- External API schemas may generate client DTOs.

Bad, because:

- The local path pays network framing and byte-stream costs despite both endpoints being
  part of the same Tickoni topology.
- Each message may require serialization, socket-buffer copies, scheduler wakeups,
  parsing, allocation, validation, and conversion into another internal representation.
- WebSocket delivery encourages a message-per-event design that can flood the Qt event
  loop or application queues.
- Local HTTP requires network permissions in the UI sandbox.
- Connection state, heartbeats, reconnects, TLS configuration, and endpoint identity are
  duplicated for a local topology that already has process lifecycle and shared memory.
- Large snapshots require copying and parsing rather than publishing workspace-backed
  payload descriptors.
- Backpressure is expressed through sockets and application buffering rather than the
  declared tile-link contract.
- A convenient URL-based client makes it easier for view models or components to bypass
  central command admission.
- The same wire protocol for local and remote use appears simpler but couples the native
  terminal to the lowest-common-denominator external boundary.
- The overhead is unacceptable for Tickoni's required local path because it is avoidable
  and multiplied by dense live-update fan-out.

Why this matters despite Tickoni not being HFT:

- the GUI does not need microsecond exchange latency;
- the GUI does need predictable input response and frame pacing;
- thousands of cells can receive changes within one market-data burst;
- every message may cause decode, store, model, binding, delegate, layout, and render work;
- network efficiency does not prevent QML update amplification;
- one event per tick or cell can consume the frame budget even when localhost round-trip
  time looks acceptable;
- batching after HTTP parsing is less efficient than publishing already grouped or
  workspace-backed projections through the internal bus.

Neutral or conditional:

- HTTP/WebSocket remains appropriate for `tk_gateway` and non-local clients.
- It may remain useful for diagnostics and compatibility tests, but not as the native
  local terminal's primary data path.

Validation needed:

- Keep a benchmark implementation only as a baseline. Compare CPU, allocations,
  end-to-end latency, queue growth, snapshot cost, and frame pacing against the internal
  bus. It is not the release architecture.

### Option 5: Constrained Qt MVVM inside tk_ui over internal tile channels

The Qt application runs inside the `tk_ui` composite tile sandbox. QML views bind
one-way to focused C++ presentation models. Collection data is exposed through
`QAbstractItemModel`. Presentation models call typed application use cases. `tk_ui`
publishes commands to `tk_api` through bounded shared-memory links and consumes
responses, correctness events, latest-value state, bulk descriptors, and diagnostics
through separate links.

Good, because:

- It matches QML's declarative strengths without permitting unrestricted bindings.
- It makes the UI a first-class Tickoni topology participant.
- It gives every layer and tile link a narrow, enforceable responsibility.
- It separates view-local state from authoritative runtime state.
- It prevents QML components and view models from opening sockets or parsing wire data.
- It removes unnecessary local HTTP framing and parsing.
- It supports low-copy bulk snapshots through workspace descriptors.
- It makes commands, responses, correctness events, latest values, backpressure,
  sequence gaps, process generations, and resynchronization explicit.
- It uses Qt's native item-model machinery for large collections.
- It gives high-frequency data a coalescing path separate from lossless domain events.
- It supports multiple windows over shared stores and one command dispatcher.
- It gives `tk_ui` a narrow sandbox without arbitrary network authority.
- It preserves the same semantic API for remote clients through a separate gateway tile.
- It supports deterministic fixture, replay, and test bus implementations.
- It provides clear performance review rules for bindings, delegates, patch queues, and
  GUI drain budgets.

Bad, because:

- It introduces more C++ and systems infrastructure than a small QML application.
- A portable shared-memory bus and wake mechanism must be maintained for Linux, macOS,
  and Windows.
- Queue ownership, capacities, workspace lifecycle, metrics, and shutdown must be
  engineered explicitly.
- Developers must understand Qt thread affinity and Tickoni tile-link semantics.
- Generated or carefully maintained typed DTOs and binary message contracts are required.
- `tk_ui` needs a desktop-specific sandbox profile for window-system, GPU, font,
  clipboard, accessibility, and shared-memory access.
- Shared memory does not remove the need for copying into Qt models or for careful QML
  update control.

Neutral or conditional:

- The architecture uses MVVM vocabulary at the QML boundary but is not pure textbook
  MVVM. It also uses Presentation Model, Qt Model/View, CQRS-like command/read
  separation, and ports/adapters at the bus boundary.
- `tk_ui` is a composite edge tile with several threads, not a strict always-busy
  one-thread/one-core tile.
- Exact wake primitives and shared-memory APIs may differ by platform while the channel
  contract remains stable.

Validation needed:

- Representative shared-memory, queue-overflow, process-restart, multi-window,
  10,000-row, burst-update, and eight-hour soak tests must confirm the design.

## Comparison

| Criterion | Weight | Textbook MVC | Textbook MVVM | Smalltalk-style MVC | Constrained MVVM over HTTP | Constrained MVVM in `tk_ui` |
| --- | ---: | --- | --- | --- | --- | --- |
| Natural fit with QML bindings | High | Medium | Strong | Medium | Strong | Strong |
| Clear authority for financial state | High | Medium | Medium | Weak/Medium | Strong | Strong |
| Prevents networking from components | High | Not inherent | Not inherent | Not inherent | Explicit but easy to bypass | Enforced by layer and sandbox |
| Native Tickoni tile integration | High | Weak | Weak | Weak | Weak/Medium | Strong |
| Same-machine latency and CPU efficiency | High | Depends | Depends | Depends | Weak/Medium | Strong |
| Large collection support | High | Depends on model | Depends on VM/model | Depends on model | `QAbstractItemModel` | `QAbstractItemModel` |
| Binding-cost control | High | Medium | Weak without constraints | Medium | Explicit | Explicit |
| Backpressure and bounded queues | High | Not inherent | Not inherent | Not inherent | Application-level only | Tile and GUI channels |
| Lossless versus coalescing streams | High | Not inherent | Not inherent | Not inherent | Explicit but after wire decode | Explicit before GUI fan-out |
| Bulk snapshot efficiency | High | Weak/Medium | Weak/Medium | Weak/Medium | Copy and parse | Workspace descriptor |
| Cross-thread ownership | High | Not inherent | Not inherent | Not inherent | Explicit | Explicit |
| Multiple windows/shared state | High | Controller coordination | VM coordination | Observer fan-out | Shared stores | Shared stores |
| Remote interoperability | Medium | Depends | Depends | Depends | Direct | Through gateway tile |
| Sandbox minimization | High | Weak/Medium | Weak/Medium | Weak/Medium | UI needs network | UI has no arbitrary network |
| Testability | High | Medium/Strong | Strong | Medium | Strong | Strong |
| Initial implementation effort | Medium | Medium | Low/Medium | Medium | Medium | High |
| Long-term terminal maintainability | High | Medium | Medium | Weak/Medium | Medium | Strong |

## Decision

**We will use constrained Qt MVVM inside the `tk_ui` composite edge tile, with
Firedancer-style shared-memory links to the semantic `tk_api` tile.**

The full standing rule is:

> QML renders and collects local user intent. Focused C++ presentation models expose
> read-only projections and typed actions. `tk_ui` feature stores and item models receive
> validated state through bounded internal tile channels. `tk_ui` publishes governed
> commands to `tk_api` through a separate bounded command link. External network
> protocols terminate in gateway tiles and are never visible to QML, view models, or
> Qt collection models.

This is the architecture for every native Qt terminal function and window. It is not a
suggested style. New UI work must follow the layer, tile, channel, queue, binding,
delegate, and sandbox rules in this ADR unless an approved deviation applies.

The decisive factor is that QML performance and financial correctness both require
controlled state flow, and the native terminal should participate in Tickoni's internal
topology without paying an avoidable network-protocol tax. Textbook patterns describe
object responsibilities but do not define the delivery semantics required by a dense
live terminal. The chosen architecture adds those semantics explicitly.

The latency decision is intentionally scoped:

- HTTP is not declared unsuitable for finance generally.
- HTTP remains valid for remote APIs and interoperability.
- Tickoni is not claiming HFT execution through the GUI.
- HTTP is rejected for the local `tk_ui` to `tk_api` path because its avoidable work is
  multiplied by high-volume projection updates and competes with the GUI frame budget.
- Shared memory is not treated as a substitute for batching, coalescing, and simple QML.

Rejected alternatives:

- Textbook MVC: rejected because controller-driven view manipulation and multiple update
  paths conflict with declarative QML and do not solve tile-link or stream semantics.
- Textbook MVVM: rejected as a complete rule because unrestricted view models and
  two-way bindings permit hidden state ownership, direct service calls, and binding
  storms.
- Smalltalk-style MVC: rejected because direct model observation does not fit a
  process-separated authoritative runtime and creates uncontrolled notification fan-out.
- Constrained MVVM over localhost HTTP/WebSocket: rejected as the native local path
  because it adds avoidable serialization, scheduling, parsing, and socket buffering
  before the same data must still pass through bounded stores and GUI patch queues.

## Normative Architecture

### Topology and layer model

The native topology is:

```text
┌──────────────────── tk_ui tile sandbox ────────────────────┐
│                                                            │
│  QML Views                                                 │
│      │                                                     │
│      ▼                                                     │
│  C++ Presentation Models / ViewModels                      │
│      │                                                     │
│      ▼                                                     │
│  Application Use Cases + Feature Projection Stores         │
│      │                                                     │
│      ├── UI command admission                              │
│      └── GUI model-patch queue                             │
│                                                            │
│  tk_ui Bus Bridge                                          │
│      ├── command publisher                                 │
│      ├── response/event consumers                          │
│      ├── revision and generation checks                    │
│      └── workspace-handle resolver                         │
│                                                            │
└───────────────┬────────────────────────────────────────────┘
                │
                │ shared-memory rings + workspaces
                │ platform wake/park primitive
                ▼
┌──────────────────── tk_api tile sandbox ───────────────────┐
│ semantic queries, subscriptions, capabilities, revisions,  │
│ governed command routing, responses, event projections     │
└───────────────┬────────────────────────────────────────────┘
                │
                ▼
        Tickoni runtime tiles
```

For remote operation:

```text
tk_ui
  -> local internal bus
  -> tk_gateway_client
  -> external protocol
  -> remote tk_gateway
  -> remote internal bus
  -> remote tk_api
```

The application-layer dependency direction is:

```text
QML
  -> Presentation Model
  -> Application Use Case / Feature Store
  -> tk_ui Bus Port
  -> Internal Tile Channel
  -> tk_api
```

The inbound state direction is:

```text
tk_api
  -> Internal Tile Channel
  -> tk_ui Bus Bridge
  -> Decode / Validate / Project
  -> GUI ModelPatch Queue
  -> QAbstractItemModel / ViewModel
  -> QML
```

A lower layer must not import or depend on a higher visual layer.

### Tile definitions

#### `tk_ui`

`tk_ui` is the native desktop edge tile.

It owns:

- the Qt process and desktop sandbox;
- QML, windows, presentation models, and item models;
- user command admission;
- UI feature projection stores;
- internal bus ingress and egress;
- GUI patch batching;
- workspace and layout persistence;
- UI-specific diagnostics.

It does not own:

- policy truth;
- portfolio truth;
- buying-power truth;
- proposal or approval authority;
- execution routing;
- audit truth;
- replay truth;
- broker or provider sockets;
- external API credentials.

#### `tk_api`

`tk_api` is the semantic API tile.

It owns or fronts:

- capability negotiation;
- subscriptions;
- request validation;
- expected-revision validation;
- governed command routing;
- query and command response semantics;
- state revisions and freshness;
- event projection contracts;
- routing to policy, audit, replay, adapter, and execution tiles.

`tk_api` is not defined by HTTP.

#### `tk_gateway`

`tk_gateway` is the optional external network-facing tile.

It translates:

```text
HTTP / WebSocket / QUIC / other external protocol
    <->
typed internal tk_api messages
```

It owns network authentication, sockets, external framing, remote reconnect behavior,
and external rate limits.

#### `tk_bus`

`tk_bus` is the portable internal channel/workspace abstraction.

Its contract includes:

- bounded rings or mailboxes;
- sequence counters;
- producer and consumer ownership;
- workspace-backed bulk payloads;
- process generation;
- flow-control and overflow behavior;
- metrics;
- a platform wake/park mechanism.

Linux may map this contract onto Firedancer/Tango primitives. macOS and Windows may use
different operating-system primitives but must preserve the same semantic contract.

### Responsibilities

#### QML views

QML owns:

- visual composition and styling;
- layouts, focus, keyboard routing, and accessibility presentation;
- temporary input fields before submission;
- local expansion, selection, hover, and panel state;
- small display-only formatting;
- forwarding user intent to a local presentation model.

QML does not own:

- shared-memory channels or workspace handles;
- process generations or sequence counters;
- network clients or sockets;
- HTTP, WebSocket, QUIC, JSON, protobuf, or authentication;
- filesystem, shell, provider, adapter, broker, or execution access;
- policy, portfolio, buying-power, audit, or replay calculations;
- command retry, idempotency, sequencing, or resynchronization;
- large list transformations;
- shared financial state;
- application-wide navigation or workspace services.

A QML control may call only a typed method on its focused presentation model or emit a
local signal handled by that model.

The following is prohibited:

```qml
Button {
    onClicked: {
        http.post("/v1/proposals/17/approve")
    }
}
```

The following is also prohibited:

```qml
Button {
    onClicked: {
        TkBus.publish("approve", proposalId)
    }
}
```

The required shape is:

```qml
Button {
    enabled: proposalViewModel.canApprove
    onClicked: proposalViewModel.requestApproval()
}
```

`requestApproval()` creates a typed application command and submits it through the
central command admission path. It does not publish directly to a tile link.

#### Presentation models

Presentation models are focused C++ `QObject` types associated with a function, panel,
or workflow.

Examples:

```text
CaseViewModel
PolicyViewModel
ImpactViewModel
ProofViewModel
CommandBarViewModel
SystemViewModel
WorkspaceViewModel
```

A presentation model:

- exposes typed, mostly read-only `Q_PROPERTY` values;
- exposes explicit user-intent methods;
- owns local presentation state;
- reads from one or more feature projection stores;
- submits commands and queries through application use cases;
- exposes loading, stale, unavailable, denied, resynchronizing, and error states;
- never exposes shared-memory descriptors, ring cursors, raw payloads, or transport
  headers;
- never becomes the source of financial truth.

There is no global `AppViewModel`. Shared services are injected into focused view models.
Global QML singletons are limited to immutable design tokens and narrowly scoped
read-only build metadata.

#### Feature projection stores

A feature store owns the terminal's current read-optimized client projection of one
domain area, for example:

```text
CaseStore
PolicyStore
PortfolioStore
ProposalStore
AuditStore
ReplayStore
MarketStore
SystemStore
```

A store:

- applies validated snapshots and ordered events;
- tracks source revision, sequence, freshness, and process generation;
- rejects deltas with an incompatible base revision;
- produces small immutable `ModelPatch` objects for GUI-thread application;
- is shared by multiple presentation models and windows;
- does not submit commands;
- does not contain visual styling.

Stores distinguish authoritative data from view-local state. A selected row or expanded
panel is not part of a financial store.

#### Collection models

Large or changing collections use subclasses of:

- `QAbstractTableModel`;
- `QAbstractListModel`;
- `QAbstractItemModel`.

Production market, basket, proposal, audit, position, and case collections must not use
QML `ListModel`, arbitrary JavaScript arrays, or large `QVariantList`/`QVariantMap`
graphs as their primary representation.

Model roles are typed and semantic:

```text
instrumentId
ticker
displayPrice
sourceRevision
freshnessState
policyOutcome
policyReason
actionAvailability
```

Roles do not encode visual styling such as `red`, `green`, `bold`, or `largeFont`.

Models apply the smallest correct update:

- `dataChanged()` for changed cells or roles;
- insert/remove notifications for structural changes;
- layout changes only when ordering changes;
- `modelReset()` only when dataset identity or complete structure changes.

All model API calls occur on the GUI thread.

#### Application use cases

Application use cases are typed C++ operations such as:

```text
LoadCase
RunAnalysis
CreateProposal
RequestApproval
RejectProposal
PlacePaperOrder
RunReplay
SaveWorkspace
```

Use cases:

- validate client-side preconditions that are presentation or protocol concerns;
- allocate request, correlation, and idempotency identifiers;
- enqueue a command or query;
- expose an asynchronous result;
- never infer a successful financial state before runtime confirmation.

Use cases do not contain QML types, shared-memory offsets, or tile-link cursors.

#### Application controller

A small application controller owns:

- dependency construction;
- startup mode;
- attachment to the local Tickoni topology;
- local runtime process lifecycle when enabled;
- top-level windows;
- global shutdown;
- fatal protocol, ABI, or workspace compatibility errors.

It does not contain feature business logic or function as a global service locator.

#### Bus bridge

The `tk_ui` bus bridge owns:

- attachment to allowed shared-memory workspaces;
- inbound and outbound channel cursors;
- message ABI and schema validation;
- process-generation validation;
- sequence-gap detection;
- publication of typed commands;
- consumption of responses and events;
- resolution of bulk payload descriptors;
- conversion into typed C++ values;
- bounded handoff to feature stores and the GUI patch queue.

The bus bridge is not exposed to QML.

### Communication protocols between layers

| Boundary | Allowed protocol | Prohibited protocol |
| --- | --- | --- |
| QML → ViewModel | typed method call or local signal | HTTP, WebSocket, bus publish, shell, filesystem, global string event |
| ViewModel → Use case | typed C++ value | raw JSON, URL, ring descriptor, workspace offset |
| Use case → Command admission | typed command/query envelope | direct tile-link publication |
| Command admission → `ui_cmd` | fixed/versioned internal message | arbitrary string event |
| `ui_rsp`/`ui_evt`/`ui_lval` → Bus bridge | fixed descriptor + optional workspace handle | process pointer or Qt object |
| Bus bridge → Store | typed snapshot/event/error | unvalidated bytes or variant blob |
| Store/worker → GUI model | bounded immutable `ModelPatch` batch | cross-thread model mutation |
| Model/ViewModel → QML | properties, roles, narrow signals | callback into bus or runtime types |

Stringly typed global event buses are prohibited. Every cross-layer and cross-process
message has a C/C++ type, protocol version, schema version, owner, and delivery rule.

### State-flow rule

Authoritative state flows in one direction:

```text
runtime
  -> tk_api
  -> internal tile link
  -> tk_ui bus bridge
  -> decode/validate
  -> feature store
  -> GUI model or presentation model
  -> QML binding
```

User intent flows in the opposite direction:

```text
QML
  -> presentation model
  -> application use case
  -> command admission
  -> ui_cmd channel
  -> tk_api
```

The command response returns through the authoritative state path. The view model does
not directly set a proposal to `approved`, an order to `placed`, or a policy to
`allowed` after sending a command.

Optimistic updates are allowed only for view-local state. A financial state may show
`queued`, `submitting`, or `awaiting confirmation`, but not the final runtime result.

## Internal Channels and Queues

### General queue rules

Every application and tile queue is:

- bounded;
- owned by a declared producer and consumer;
- instrumented;
- assigned an overflow policy;
- drained in bounded batches;
- stoppable during shutdown;
- covered by saturation and restart tests.

Qt's event queue and queued signal delivery are not substitutes for application-level
backpressure. Queued signals may wake the GUI thread or deliver low-rate control
messages, but high-volume streams use explicit bounded queues or keyed mailboxes.

At most one GUI wake-up should be pending for a non-empty GUI patch queue. A quote burst
must not produce one queued Qt signal per quote.

### Channel A: `ui_cmd`

Direction:

```text
tk_ui -> tk_api
```

Carries:

- governed commands;
- explicit queries;
- subscription changes;
- capability requests;
- resynchronization requests.

Properties:

- bounded FIFO;
- never silently drops;
- each entry has request ID, correlation ID, command type, process generation, and
  optional idempotency key;
- command admission fails closed when the channel is full;
- duplicate governed commands are detected before publication where possible;
- publication never blocks the GUI thread.

Overflow behavior:

- reject the new command with a typed `client_busy` result;
- leave authoritative state unchanged;
- show the operator that submission did not occur;
- emit queue-saturation telemetry.

### Channel B: `ui_rsp`

Direction:

```text
tk_api -> tk_ui
```

Carries:

- query results;
- command admission results;
- command completion results;
- typed errors;
- resynchronization responses.

Properties:

- ordered by request and publication sequence;
- never silently drops;
- correlates to the originating request;
- may reference a bulk workspace payload.

Overflow behavior:

- mark unresolved request outcomes as unknown;
- stop admitting governed commands when safe reconciliation is impossible;
- trigger controlled resynchronization;
- record the channel fault.

### Channel C: `ui_evt`

Direction:

```text
tk_api -> tk_ui
```

Carries correctness-bearing events:

- policy outcomes;
- proposal state;
- approval state;
- execution and paper-execution state;
- account and buying-power revisions;
- audit records;
- replay divergence and completion;
- entitlement, session, and authorization changes.

Properties:

- ordered by topic/entity sequence and revision;
- never coalesced;
- never silently dropped;
- duplicate events may be ignored only after identity/revision validation;
- gaps trigger resynchronization.

Overflow behavior:

- stop declaring affected stores current;
- mark affected projections stale or resynchronizing;
- suspend governed actions that require current state;
- request cursor resume or a fresh snapshot;
- record the overflow and resync reason.

### Channel D: `ui_lval`

Direction:

```text
tk_api -> tk_ui
```

Carries only topics whose contract permits replacement by a newer value:

- indicative quote;
- top-of-book display value;
- calculated display metric;
- queue-depth sample;
- non-audit health sample.

Properties:

- bounded keyed mailbox or overwrite-capable latest-value structure;
- newest update replaces an older pending update for the same key;
- each value retains revision and `asOf`;
- the bus/store path drains a bounded batch;
- coalescing count and oldest pending age are observable.

The mailbox must not carry policy, approval, execution, audit, replay, or account-state
events.

### Channel E: `ui_bulk`

Direction:

```text
tk_api <-> tk_ui
```

Carries descriptors for large snapshots or payloads.

The ring contains a descriptor such as:

```text
workspaceId
workspaceGeneration
payloadOffset
payloadLength
payloadType
schemaVersion
revision
checksum
```

The payload remains in a shared workspace or arena.

Rules:

- no raw process pointer crosses the link;
- consumers validate range, type, schema, generation, and checksum;
- ownership and release semantics are explicit;
- inbound mappings are read-only where possible;
- large payloads are transformed outside the GUI thread;
- a descriptor is invalid after its declared workspace generation or lifetime.

### Channel F: `ui_diag`

Direction:

```text
tk_ui <-> tk_api/topology diagnostics
```

Carries low-rate control and diagnostics:

- heartbeat;
- process and workspace generation;
- channel depth and lag;
- protocol/ABI compatibility;
- tile health;
- resync reason;
- dropped/coalesced latest-value counts;
- GUI patch lag.

Diagnostics do not carry correctness-bearing financial state.

### Channel G: GUI model-patch queue

Direction:

```text
worker/store preparation -> GUI thread
```

Carries immutable `ModelPatch` batches.

Properties:

- bounded;
- applied only on the GUI thread;
- patch size is limited;
- one drain operation has a count and time budget;
- remaining work is deferred to a later event-loop turn;
- patches retain source revision and process generation;
- an obsolete-generation patch is discarded before model mutation.

Overflow behavior:

- latest-value patches may be superseded by newer patches for the same key;
- correctness patches are not dropped;
- an inability to preserve correctness patches makes the model stale and triggers
  resynchronization;
- the GUI is not allowed to block the bus producer indefinitely.

### Internal message envelope

Cross-process requests, responses, and events use a fixed, versioned semantic envelope
containing at least:

```text
protocolVersion
schemaVersion
messageType
flags
messageId
requestId
correlationId
sessionId
processGeneration
topic
entityId
sequence
baseRevision
resultRevision
timestamp
asOf
freshUntil
workspaceId
payloadOffset
payloadLength
payloadType
checksum
```

Governed commands additionally contain:

```text
actor
accountId
proposalId
expectedRevision
idempotencyKey
policyContextReference
```

The ABI uses:

- fixed-width integer fields;
- explicit byte order;
- explicit alignment and size checks;
- no C++ classes;
- no Qt types;
- no Zig slices;
- no raw pointers;
- no implicit compiler-layout dependency.

### Backpressure policy

Backpressure differs by channel:

- `ui_cmd`: fail admission rather than block the GUI.
- `ui_rsp`: preserve; if preservation fails, reconcile and suspend unsafe commands.
- `ui_evt`: preserve; if a gap occurs, mark stale and resynchronize.
- `ui_lval`: coalesce by key.
- `ui_bulk`: bound outstanding payload ownership and reject new bulk work when full.
- GUI patch queue: coalesce latest-value patches; preserve correctness or resynchronize.
- `ui_diag`: may sample or replace older diagnostics.

A slow GUI must never stall policy, execution, audit, or unrelated runtime tiles
indefinitely.

## Update Amplification and Display Cadence

### Runtime event rate is not UI render rate

The following rates are distinct:

```text
runtime ingest rate
authoritative state-transition rate
projection publication rate
GUI model-patch rate
display frame rate
```

They must not be coupled one-to-one.

The runtime may receive every tick. `tk_api` may publish every correctness-bearing state
transition. `tk_ui` may coalesce display-only values by key. The GUI applies bounded
patch batches. QML renders according to the platform frame loop.

### Thousands of cells

A table with thousands of visible or cached cells is sensitive to:

- number of `dataChanged()` ranges;
- number of changed roles;
- number of bindings per delegate;
- delegate hierarchy depth;
- formatting allocations;
- layout invalidation;
- scene-graph updates;
- queued cross-thread notifications.

The UI must not interpret "10,000 rows" as permission to notify 10,000 rows for every
market-data burst.

Preferred update shape:

```text
many runtime updates
  -> keyed latest-value coalescing
  -> compact sorted ModelPatch batch
  -> minimal dataChanged ranges and roles
  -> one bounded GUI drain
```

Rejected update shape:

```text
one runtime tick
  -> one HTTP/WebSocket message
  -> one signal
  -> one property write
  -> one binding cascade
  -> one delegate update
```

### Human-useful cadence

Latest-value display cadence is configured by view and workload. It may be slower than
runtime ingest while preserving the latest validated value and its `asOf` timestamp.

The architecture must not hard-code one global refresh interval. A quote watchlist,
order book, audit timeline, policy state, and health metric have different semantics.

Correctness state is event-driven and ordered. Latest-value presentation is
coalesced and cadence-controlled.

### Performance budgets

The implementation must define and measure:

- bus publish-to-consume latency;
- bus consume-to-store latency;
- store-to-model-patch latency;
- model-patch queue age;
- GUI patch-application duration;
- number of changed rows and roles per drain;
- binding evaluation cost;
- delegate creation and reuse cost;
- frame time and input latency;
- allocations and copies per update;
- CPU usage during steady and burst load.

These are UI pipeline budgets, not HFT exchange-latency claims.

## Threading Model

`tk_ui` is a composite edge tile:

```text
tk_ui process
├── GUI thread
│   ├── QGuiApplication
│   ├── QML engine
│   ├── windows and presentation models
│   ├── QAbstractItemModel instances
│   └── bounded model-patch application
│
├── bus ingress/egress thread
│   ├── shared-memory attach
│   ├── channel polling and publication
│   ├── sequence and generation validation
│   ├── wake/park handling
│   └── bounded handoff
│
├── worker pool
│   ├── decompression
│   ├── schema decoding
│   ├── large snapshot validation
│   ├── projection construction
│   └── ModelPatch construction
│
└── Qt render thread
    └── managed by Qt Quick where applicable
```

Rules:

- no blocking bus or I/O operation on the GUI thread;
- no large snapshot parsing on the GUI thread;
- no model API calls outside the GUI thread;
- no direct method call into a `QObject` owned by another thread;
- cross-thread handoff uses queued wakeups plus bounded queues or immutable queued value
  messages;
- one queued wake-up may represent many pending patches;
- the bus thread never emits one GUI signal per market update;
- shutdown drains or invalidates queues in a declared order.

### Polling and wake behavior

A conventional Firedancer tile may own a CPU core and busy-poll continuously. The
desktop `tk_ui` tile must coexist with a window-system event loop, Qt rendering, laptop
power management, and ordinary workstation workloads.

The default bus strategy is hybrid:

1. poll aggressively for a bounded period after recent activity;
2. drain a bounded batch;
3. park when idle;
4. wake through a platform primitive when producers publish;
5. return to polling during bursts.

An optional low-latency workstation mode may dedicate more CPU to polling, but it is not
the default and must be measured.

### Shutdown order

The shutdown order is:

1. disable UI command admission;
2. stop new subscriptions;
3. preserve unresolved governed-command IDs;
4. publish detach/close intent where supported;
5. stop or detach bus publication;
6. stop worker decoding;
7. invalidate obsolete workspace handles;
8. drain or discard obsolete model patches;
9. destroy view models and stores;
10. destroy QML and windows;
11. detach shared-memory workspaces.

## Tile Bus Decision

### `TkUiBusPort`

The application depends on a bus-neutral C++ interface:

```cpp
class TkUiBusPort {
public:
    virtual ~TkUiBusPort() = default;

    virtual AttachResult attach(const TopologyDescriptor &) = 0;
    virtual void detach() = 0;

    virtual PublishResult publish(UiCommand) = 0;
    virtual PublishResult publish(UiQuery) = 0;
    virtual PublishResult subscribe(UiSubscription) = 0;
    virtual PublishResult unsubscribe(SubscriptionId) = 0;
};
```

Inbound values are delivered as typed C++ values after ABI and schema validation:

```text
UiResponse
UiCorrectnessEvent
UiLatestValue
UiBulkDescriptor
UiDiagnostic
UiResyncRequired
UiBusFault
```

No shared-memory implementation type crosses this interface into view models.

### Shared-memory data plane

The local data plane uses:

- bounded shared-memory rings for ordered messages;
- keyed shared-memory mailboxes or snapshot tables for latest values;
- shared workspaces/arenas for bulk payloads;
- workspace-relative offsets or stable handles;
- sequence and process-generation counters;
- explicit producer and consumer ownership;
- read-only consumer mappings where possible.

Shared memory reduces local serialization and copy overhead. It does not imply that QML
reads runtime memory directly. Data still passes through validation, projection stores,
and GUI-thread item-model updates.

### Notification plane

The notification plane wakes an idle `tk_ui` bus thread without defining the data
protocol.

Platform implementations may use appropriate native primitives, for example:

- Linux event or futex-like wake mechanisms;
- macOS Mach, semaphore, or kqueue-compatible mechanisms;
- Windows event, semaphore, or waitable-object mechanisms.

The exact primitive is not normative in this ADR. Its contract is:

- no lost wake-up;
- wake coalescing is allowed;
- data availability is determined from shared-memory sequence state, not from the wake
  count;
- shutdown and process death are detectable;
- the bus may poll without notifications in low-latency mode.

### Portable Firedancer semantics

Tickoni does not require macOS and Windows to run the unmodified Linux Firedancer
implementation.

They must preserve:

- tile identity;
- process isolation;
- fixed channel topology;
- bounded links;
- declared overflow/backpressure;
- shared workspaces;
- sequence and generation validation;
- metrics;
- sandbox permissions;
- crash-only recovery expectations where appropriate.

Platform-specific implementations are hidden behind `TkUiBusPort`.

### External gateway

HTTP, WebSocket, QUIC, and similar protocols remain available through gateway tiles.

The Qt application does not instantiate `QNetworkAccessManager`, `QWebSocket`, or a
QML network component for Tickoni runtime communication.

Remote mode uses:

```text
tk_ui
  -> TkUiBusPort
  -> tk_gateway_client tile
  -> external protocol
  -> remote tk_gateway
  -> remote tk_api
```

Changing the external protocol does not require changes to QML, presentation models,
collection models, use cases, or feature stores.

### QML and view-model bus prohibition

The following are prohibited anywhere in QML:

- `XMLHttpRequest`;
- QML WebSocket components;
- JavaScript fetch wrappers;
- direct URL construction for runtime APIs;
- authentication-token access;
- retry or reconnect loops;
- parsing runtime JSON or binary frames;
- direct creation or invocation of bus singletons;
- direct publication to shared-memory rings.

Presentation models are also prohibited from:

- holding ring or workspace handles;
- publishing directly to `TkUiBusPort`;
- implementing sequence, retry, or resynchronization policy;
- choosing a gateway or transport.

A QML component may display bus and topology state exposed by a view model, but it cannot
own or operate the bus.

## Sandbox Model

`tk_ui` runs in a desktop-specific sandbox.

Allowed capabilities include only what is required for:

- platform window-system communication;
- GPU/rendering access;
- font services;
- accessibility APIs;
- clipboard and notifications when enabled;
- approved workspace and layout files;
- Tickoni shared-memory workspaces;
- Tickoni wake/park primitives;
- local runtime lifecycle handles when managed by the terminal.

Denied by default:

- arbitrary network sockets;
- direct broker or venue connectivity;
- direct market-data provider connectivity;
- direct execution-adapter access;
- shell execution;
- unrestricted filesystem access;
- runtime credentials not intended for the UI;
- arbitrary mappings of other tile workspaces.

`tk_ui` receives write access only to its declared outbound links and UI-local writable
areas. Inbound runtime state is mapped read-only where practical.

## QML Binding Rules

### Binding direction

Authoritative properties bind one way:

```text
C++ projection/view model -> QML
```

User edits remain local until an explicit action is submitted.

Broad two-way synchronization is prohibited. Assignment from QML must not mutate a
runtime-owned property directly.

### Binding shape

Hot-path bindings must be:

- side-effect free;
- local to the component;
- constant-time;
- based on a small number of typed properties or model roles;
- free of loops, bus access, disk access, logging, and allocation-heavy formatting.

The following are prohibited in hot delegates:

- JavaScript loops over model data;
- chained lookups through global singletons;
- construction of arrays or maps;
- JSON parsing;
- dynamic role-type changes;
- bindings whose evaluation submits commands or changes shared state;
- bindings that read clocks independently for every cell;
- formatting that allocates on every quote update.

Derived values needed by many delegates are computed once in C++ and exposed as roles.

### Property granularity

Do not expose a complete screen as one changing `QVariantMap`. Use typed properties and
stable model roles so a change invalidates only the bindings that depend on it.

Properties emit change signals only when their observable value actually changes.

### Signal handlers

QML signal handlers may:

- update local visual state;
- call one typed view-model method;
- open a local dialog;
- move focus.

They may not run large transformations, loops, retries, channel publication, or
cross-feature orchestration.

### Singletons

Allowed QML singletons:

- immutable design tokens;
- static icon/font metadata;
- narrow read-only build/version metadata.

Prohibited QML singletons:

- bus or transport clients;
- global mutable financial state;
- command dispatchers exposed directly to arbitrary components;
- giant application view models;
- cross-feature event buses.

## Delegate and View Rules

### Delegate complexity

Table, list, and tree delegates contain only the elements required to render the visible
cell or row.

A hot delegate must not contain:

- bus, network, or service objects;
- timers for each cell;
- independent animations for continuously updating values;
- loaders for simple content;
- nested general-purpose controls when a lightweight item suffices;
- charts, shaders, or complex effects;
- dialogs or popup ownership;
- stored authoritative state.

Additional detail is created outside the hot delegate, for example in a detail panel or
a lazily created editor.

### Reuse

`TableView`, `ListView`, and equivalent views use item reuse where supported and
appropriate.

Delegates must tolerate reuse:

- no authoritative state is stored in the delegate;
- local transient state is reset when reused;
- pooled delegates stop timers or expensive activity;
- role values completely describe the rendered data.

### Layout and visual effects

Hot delegates avoid:

- clipping unless required;
- opacity layers;
- unnecessary anchors or bindings;
- deep item hierarchies;
- implicit-size chains spanning multiple components;
- per-cell shadows, gradients, or effects.

### Collection updates

Market and system updates are batched before reaching the view.

Correctness-bearing changes are applied promptly in order. Latest-value presentation
updates are coalesced and may be limited to a human-useful cadence while the store
retains the most recent validated value.

The UI must not reset an entire table for a single quote or policy-role update.

A batch must identify the smallest affected rows, columns, and roles. The model should
merge adjacent compatible changes before emitting notifications.

## Command Semantics

A command lifecycle is explicit:

```text
notSubmitted
queued
published
accepted
rejected
completed
failed
outcomeUnknown
reconciling
```

A timeout, process death, or bus fault is not treated as rejection or success. The
application reconciles using the request ID, process generation, and idempotency key.

Buttons and commands are enabled from current projection state plus runtime-declared
capabilities. A previously enabled action is disabled when required state becomes stale,
detached, incompatible, or resynchronizing.

Unknown commands and unsupported capabilities fail closed.

## Process Failure and Resynchronization

On `tk_api`, gateway, or workspace-generation change:

1. the bus bridge publishes a new process/topology generation;
2. time-sensitive stores become stale;
3. governed actions requiring current state are disabled;
4. `tk_ui` reattaches only to compatible channels and workspaces;
5. subscriptions resume from confirmed cursors where supported;
6. otherwise `tk_ui` requests fresh snapshots;
7. stores validate sequence, revision, and generation;
8. only then do models become current.

Reattaching shared memory alone does not make the UI current.

Events, payload handles, and model patches from an older process or workspace generation
are rejected.

Network reconnection for a remote runtime is owned by `tk_gateway_client`; `tk_ui`
observes its semantic connection state through internal diagnostics and events.

## Consequences

### Positive consequences

- Every native UI feature follows one state and command path.
- QML remains small, declarative, and replaceable.
- `tk_ui` becomes a first-class topology and sandbox participant.
- QML and view models cannot bypass governed channels.
- The same-machine path avoids local HTTP framing, parsing, and socket buffering.
- High-frequency updates cannot silently flood the GUI through per-message Qt signals.
- Correctness events and coalescible values have different delivery semantics.
- Large snapshots can use workspace-backed payloads.
- Multiple windows share stores without duplicating command submission or tile links.
- Collection performance uses Qt's model/view strengths.
- External protocols can change in gateway tiles without changing the UI.
- Fixture and replay buses can reproduce the same typed behavior.
- Architecture and performance violations can be checked in review and tests.

### Negative consequences

- The terminal requires more C++ and systems infrastructure before the first screens
  appear.
- Tickoni must maintain a portable shared-memory bus and wake abstraction.
- Queue capacities, patch batching, workspace lifecycle, metrics, and shutdown behavior
  require maintenance.
- Contributors cannot implement complete features entirely in QML.
- Small panels must still follow application-use-case and command-admission boundaries.
- Typed message, DTO, and model-role changes require coordinated schema updates.
- Debugging spans QML, GUI models, stores, queues, workers, shared memory, and runtime
  tiles.
- Desktop sandboxing is more complex than a conventional unsandboxed Qt application.
- Shared memory failures can be more difficult to inspect than HTTP traces unless
  diagnostics and capture tools are built.

### Neutral consequences

- The pattern is called constrained MVVM at the QML boundary, but it deliberately
  incorporates Presentation Model, Qt Model/View, command/read separation, and
  ports/adapters.
- A later web, mobile, CLI, or TUI client may use a different presentation pattern while
  preserving `tk_api` semantics.
- HTTP remains supported for external clients through gateway tiles.
- `tk_ui` is a composite tile and does not follow the exact scheduling profile of a
  headless Firedancer compute tile.
- The choice optimizes the native local terminal, not every possible client.

### Risks and mitigations

| Risk | Likelihood | Impact | Mitigation | Owner |
| --- | --- | --- | --- | --- |
| View models grow into global application objects | Medium | High | One feature/panel responsibility, injected services, code-owner review | UI maintainers |
| Binding storms reduce frame rate | Medium | High | Typed narrow properties, profiler gates, binding-count review, no giant variant maps | UI maintainers |
| Delegates become visually rich and expensive | High | High | Delegate checklist, benchmark components, detail panels outside hot views | UI maintainers |
| Qt event delivery becomes an accidental unbounded queue | Medium | High | Explicit bounded patch queue; queued signal only as one wake-up | Platform maintainers |
| Correctness events are coalesced like quotes | Low/Medium | Critical | Topic classification allowlist, tests, fail-closed resync | Runtime/API maintainers |
| Queue overflow hides data loss | Medium | Critical | No silent correctness drop; stale/resync state; saturation telemetry | Platform maintainers |
| Latest-value traffic starves correctness events | Medium | High | Separate links/mailboxes and drain priorities | Platform maintainers |
| Shared-memory ABI differs across compilers/platforms | Medium | High | Fixed-width C ABI, static assertions, versioning, cross-build compatibility tests | Platform maintainers |
| Workspace handle is used after generation change | Medium | Critical | Generation checks, read-only mappings, bounded lifetimes | Platform maintainers |
| Cross-thread model mutation causes crashes | Medium | High | GUI-thread-only models, patch queue, thread-affinity assertions | UI maintainers |
| Multiple windows submit duplicate commands | Medium | High | One command dispatcher and idempotency registry per `tk_ui` process | UI maintainers |
| Stale state leaves actions enabled | Medium | Critical | Freshness-aware capability model and process-restart tests | UI/runtime maintainers |
| Busy polling harms desktop power and responsiveness | Medium | Medium/High | Hybrid poll/park default; configurable low-latency mode; CPU budgets | Platform maintainers |
| Portable bus underperforms or is unstable on one OS | Medium | High | Per-platform benchmarks, soak tests, implementation hidden behind `TkUiBusPort` | Platform maintainers |
| Local HTTP reappears as a shortcut | Medium | High | Sandbox denies sockets; CI scans; architecture review | Architecture maintainers |
| Over-architecture slows V2.19 | Medium | Medium | Implement minimum channels first; reuse same path for fixtures and live topology | Architecture maintainers |

## Implementation Plan

- Create the UI architecture modules:
  - `ui/application/`
  - `ui/projections/`
  - `ui/models/`
  - `ui/bus/`
  - `ui/protocol/`
  - `ui/qml/`
  - `ui/platform/`.
- Define `tk_ui`, `tk_api`, `tk_gateway`, and `tk_bus` topology roles.
- Define fixed/versioned request, response, correctness-event, latest-value, bulk,
  diagnostic, revision, freshness, and process-generation types.
- Define `TkUiBusPort`.
- Implement an in-process deterministic fixture bus.
- Implement a cross-process reference shared-memory bus.
- Implement the Linux bus using the chosen Firedancer/Tango-compatible primitives.
- Implement macOS and Windows bus backends preserving the same channel semantics.
- Implement platform wake/park adapters.
- Define and create `ui_cmd`, `ui_rsp`, `ui_evt`, `ui_lval`, `ui_bulk`, and `ui_diag`
  links.
- Add bounded GUI model-patch queue and single-wakeup drain mechanism.
- Add command admission, correlation, idempotency, and reconciliation services.
- Add feature stores for the first V2.19 workflow.
- Add focused C++ presentation models and `QAbstractItemModel` collection models.
- Register only the presentation types needed by each QML module.
- Create a desktop sandbox profile denying arbitrary sockets and direct adapter access.
- Add a QML architecture lint/review checklist prohibiting network, bus, raw JSON, global
  mutable singletons, and large JavaScript transformations.
- Build a localhost HTTP/WebSocket prototype only as a benchmark baseline, not as the
  release path.
- Benchmark the HTTP baseline against the internal bus for:
  - command enqueue-to-`tk_api` receive latency;
  - CPU and allocation cost;
  - snapshot delivery cost;
  - burst handling;
  - queue growth;
  - GUI frame pacing.
- Build representative table and event-stream benchmarks before implementing all screens.
- Profile bindings, delegate creation, scrolling, patch application, and memory growth.
- Document queue capacities, batch limits, latest-value cadence, GUI drain budget, and
  overflow behavior in configuration and tests.
- Add `SYSTEM` diagnostics for link depth, oldest age, sequence, process generation,
  workspace generation, coalesced values, resyncs, patch latency, frame time, and input
  latency.

Migration/backward compatibility:

- ADR-03 remains unchanged and continues to choose Qt.
- Existing runtime and CLI semantic contracts remain authoritative.
- `tk_api` is separated conceptually from any existing HTTP server implementation.
- Existing external HTTP/WS endpoints move behind or become owned by `tk_gateway`.
- Early QML prototypes that perform transport, bus publication, or JSON parsing must be
  rewritten to use the view-model, use-case, store, and `TkUiBusPort` path.
- Fixture and live bus implementations expose the same typed results to the UI.

Operational impact:

- The `SYSTEM` function displays topology attachment, link depth, sequence, process and
  workspace generation, freshness, coalescing, GUI-patch lag, frame time, and resync
  diagnostics.
- Crash reports and logs distinguish GUI, patch queue, decoder, bus, workspace, gateway,
  protocol, and runtime failures.
- Support procedures can force reattach, resync a topic, capture channel metrics, or
  switch to fixture/replay mode without changing QML.
- Remote networking diagnostics are reported by gateway tiles rather than collected
  directly by `tk_ui`.

## Confirmation

- Tests:
  - view-model unit tests;
  - store revision and process-generation tests;
  - model-role and incremental-notification tests;
  - channel saturation tests;
  - latest-value coalescing tests;
  - correctness-event sequence-gap tests;
  - workspace range and generation tests;
  - command idempotency and reconciliation tests;
  - stale-action tests;
  - process restart and bus reattach tests;
  - fixture/live bus equivalence tests;
  - QML component tests;
  - multi-window duplicate-command tests.
- Review gates:
  - UI architecture review for every new feature;
  - explicit review of every new QML singleton, direct service exposure, shared-memory
    type, queue, or high-frequency signal;
  - topology review for every new tile link.
- Build/CI checks:
  - QML linting and compilation;
  - forbidden-pattern scans for QML `XMLHttpRequest`, QML WebSocket, direct runtime URLs,
    bus singleton imports, and shared-memory APIs;
  - thread-affinity assertions in debug builds;
  - model-tester checks;
  - queue-capacity tests;
  - shared-memory ABI size/alignment assertions;
  - cross-compiler and cross-platform message compatibility tests.
- Observability:
  - `ui_cmd` depth and rejection count;
  - `ui_rsp` depth and unresolved request age;
  - `ui_evt` depth and sequence gaps;
  - `ui_lval` key count, coalescing count, and oldest age;
  - outstanding `ui_bulk` handles;
  - GUI patch depth, age, and application duration;
  - frame time, input latency, binding cost, and delegate count;
  - process/workspace generation;
  - reattach and resync count.

Minimum evidence before acceptance:

- A 10,000-row table remains interactive under representative batched updates.
- Delegate reuse does not leak row-local state.
- One-cell updates do not reset the table.
- Correctness events remain ordered during burst load and are never silently discarded.
- Latest-value updates coalesce by key and do not starve correctness events.
- Saturating each channel produces its documented fail-closed or coalescing behavior.
- Process death during a governed command reaches `outcomeUnknown` and reconciles by ID.
- Multiple windows share projections and one command dispatcher.
- An eight-hour soak shows no unbounded queue, event, object, mapping, or memory growth.
- Replacing the live bus with the fixture bus requires no QML changes.
- QML Profiler traces show no repeated expensive binding or delegate path in the accepted
  representative workspace.
- The internal bus has materially lower CPU, allocation, and latency cost than the
  localhost HTTP/WebSocket baseline under representative command, snapshot, and update
  loads.
- A market-data burst does not produce one queued Qt event or one QML update per runtime
  tick.
- `tk_ui` operates with arbitrary network access disabled.
- macOS, Windows x86_64/ARM64, and Linux x86_64/ARM64 pass the same channel-semantic,
  process-restart, and ABI compatibility suite.

## Deviation Criteria

A future implementation may deviate from this decision only when at least one of these
conditions applies:

- A measured feature cannot meet its SLO through the approved model, batching,
  coalescing, or shared-memory mechanisms.
- A platform integration requires a native Qt Widgets or C++ component that cannot use
  the QML presentation boundary.
- A platform cannot provide the required shared-memory isolation or wake semantics and a
  different internal IPC mechanism is demonstrated to preserve the same channel
  contract.
- A specialized chart or rendering engine requires a dedicated scene-graph data path;
  it must still not acquire command, policy, or execution authority.
- A separate product surface, such as mobile or web, has materially different framework
  constraints and records its own UI architecture ADR.
- A remote-only deployment has no local Tickoni topology; the native UI must still use a
  local gateway-client tile rather than exposing network protocols to QML.

Each deviation must record:

- why the default does not apply;
- which alternative is being used;
- which channels, ownership rules, and correctness guarantees remain;
- the measured latency, CPU, allocation, and frame-time evidence;
- who approved the deviation;
- how binding, queue, thread, sandbox, and transport behavior are verified;
- whether the deviation is temporary or permanent.

No deviation may permit a QML button, delegate, page, or focused view model to
communicate directly with a broker, provider, adapter, execution system, network
endpoint, or shared-memory ring.

## Related Decisions and References

- ADR-03: Choose Qt for the Tickoni desktop terminal UI.
- V2.19: Tickoni Native Investment Terminal.
- Tickoni - App Framework for Trading: desktop-terminal workload, Qt model/view fit,
  framework trade-offs, and chart isolation.
- Tickoni - CLI_GUI for Tickoni: one `tk_api` authority boundary and multiple thin
  clients.
- Qt 6.11, [Performance considerations and suggestions](https://doc.qt.io/qt-6/qtquick-performance.html).
- Qt 6.11, [QAbstractItemModel Class](https://doc.qt.io/qt-6/qabstractitemmodel.html).
- Qt 6.11, [Multi-threading in Qt](https://doc.qt.io/qt-6/threads.html).
- Qt 6.11, [Threads and QObjects](https://doc.qt.io/qt-6/threads-qobject.html).
- Firedancer, [Performance Tuning](https://docs.firedancer.io/guide/tuning.html).
- Firedancer, [Configuring](https://docs.firedancer.io/guide/configuring.html).
- Firedancer, [Net Tile](https://docs.firedancer.io/guide/internals/net_tile.html).
