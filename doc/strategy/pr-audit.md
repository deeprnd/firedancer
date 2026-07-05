THE SHIFT

    From: "High-throughput AI harness for agentic finance" — broad, technical, TPS-as-hero
    To: "Trading agent with hard architectural limits" — focused, human, safety-as-hero

    The TPS thing needs to disappear from branding. Nobody reads "high-throughput" and thinks "I need this for my trading." They think "this is infrastructure" and keep scrolling. What you actually have is: agents that can analyze, recommend, and paper-trade, but literally cannot lose your money or buy anything you didn't approve. That's the hook.

    THE WHY

    "AI agents can analyze markets and find opportunities faster than any human. But they shouldn't be able to drain your account or buy a meme coin at 3am. Trading AI needs hard limits—imposed by architecture, not configurable by policy."

    Short version: "AI that trades your brain, not your money."

    Or more direct: "Trading AI that can't hurt you."

    THE HOW (the differentiator)

    This is where Tickoni actually beats every trading bot and AI trading tool:

    Generic AI Trading: Agent writes a script, calls the exchange API, executes
    Tickoni: Agent proposes a trade. It cannot place it.
    ────────────────────────────────────────
    Generic AI Trading: Limits are policy files you can edit
    Tickoni: Limits are architectural—compiled into the capability model
    ────────────────────────────────────────
    Generic AI Trading: "Self-healing" agents that adapt their own behavior
    Tickoni: Agents are proposal-first. Execution requires your approval.
    ────────────────────────────────────────
    Generic AI Trading: You find out something went wrong from your bank statement
    Tickoni: Every trade, every block, every resize is audited before it leaves the sandbox
    ────────────────────────────────────────
    Generic AI Trading: Agent goes rogue → money gone
    Tickoni: Agent goes rogue → paper trade and a denial record

    The key insight: safety by construction, not by configuration. You don't need to trust that the trader configured the right limits. The architecture enforces them. Even if the agent is maximally creative at finding loopholes, it cannot cross the architectural boundary. That's the brand position.

    THE WHAT (narrowed)

    Cut everything that isn't trading:

    Cut: Payment exception workflows
    Why: Not trading
    ────────────────────────────────────────
    Cut: Reconciliation breaks
    Why: Not trading
    ────────────────────────────────────────
    Cut: Fraud/risk triage
    Why: Not trading
    ────────────────────────────────────────
    Cut: M6: Social thesis feed
    Why: Distraction from core promise
    ────────────────────────────────────────
    Cut: M5: Broker sandbox execution (keep only as "approved paper trading")
    Why: Execution is dangerous; paper-only is safer for V1
    ────────────────────────────────────────
    Cut: M7: Guarded money movement
    Why: Not trading

    Keep:

    Milestone: M1: Safe Money Decisions
    Keep?: Keep, rename to "Safe Trading"
    Why: Core loop: thesis → basket → ticket → paper trade
    ────────────────────────────────────────
    Milestone: M2: Governed Harness Runtime
    Keep?: Keep, reframe as "Hard Safety Runtime"
    Why: This IS the differentiator
    ────────────────────────────────────────
    Milestone: M3: Crypto Guard
    Keep?: Evaluate
    Why: Crypto trading is a trading use case, but crypto transfers (M7) are not
    ────────────────────────────────────────
    Milestone: M4: Proof And Trust
    Keep?: Keep, rename to "Audit-Ready Trading"
    Why: Every trade needs a paper trail
    ────────────────────────────────────────
    Milestone: M5-M7
    Keep?: Cut or defer
    Why: Payment and money movement are different products

    RESTRUCTURE THE MILESTONES

    M1: Safe Trading — Agent analyzes markets, proposes trades, user reviews and approves. Paper only. Cash impact visible. Portfolio exposure tracked.

    M2: Hard Limits — The architecture itself enforces safety. Limits can't be bypassed, edited by agents, or configuration-drifted. If the agent tries to place a disallowed order, it doesn't get a policy rejection—it gets a compile-time capability denial. This is the hero milestone.

    M3: Trust Surface — Every trade, block, and resize is auditable. Partners (exchanges, custody, regulators) can inspect the proof. The agent can't hide what it did.

    M4: Live-Ready Sandbox — Approved paper trades can be forwarded to a broker sandbox. Real execution still requires human approval. The sandbox proves the full pipeline works without risk.

    Four milestones, not seven. Each one serves the core promise.

    TAGLINE OPTIONS

    From most conservative to most direct:

    1. "Trading AI with architectural guardrails."
    2. "AI trading analysis. Human execution. Hard limits."
    3. "Trading agents that can't drain your account."
    4. "The trading agent that's safe by design, not by configuration."

    Option 3 is the clearest. It tells you what it is and why you should care in 8 words. It's also the only one a non-technical trader would understand.

    BRAND VOICE

    Current voice: Technical, exhaustive, specification-like
    New voice: Direct, confident, focused
    ────────────────────────────────────────
    Current voice: "High-throughput AI harness for agentic finance"
    New voice: "Trading AI that can't hurt you"
    ────────────────────────────────────────
    Current voice: Capability catalogs and scope dimensions
    New voice: Simple statements: "This agent can propose trades. It cannot place them."
    ────────────────────────────────────────
    Current voice: Competitive bullet tables
    New voice: Clear contrast: "Generic AI agents execute. Our agents propose. You approve."
    ────────────────────────────────────────
    Current voice: 7-milestone roadmap
    New voice: 4-milestone roadmap
    ────────────────────────────────────────
    Current voice: "Tickoni wins by being narrower"
    New voice: "Tickoni exists to make trading AI safe by construction"

    WHAT CHANGES WHERE

    README: Replace badge row at top with a single-line tagline + one-sentence WHY. Move badges to bottom. Replace the 12-row capability table with 4-5 statements about what agents can/cannot do. Lead with the trading loop: thesis → proposal → review → (paper) execution.

    positioning.md: Cut 60% of the competitive landscape. OpenClaw, Hermes, Ruflo, Cognitum, Amp, OpenCode are not the relevant comparison. The relevant comparison is: trading platforms with AI assistants (TradingView + AI, TrendSpider, various retail AI tools) vs. Tickoni. The distinction is: they give AI execution access. You don't.

    capabilities.md: Keep the capability model—it's good architecture documentation. But reframe the examples around trading, not payments/reconciliation/crypto transfers. The capability catalog is reference docs, not branding.

    milestones/: Cut M5, M6, M7. Renumber and rename M1-M4 as above. Delete the non-trading epics (V1.2 payment guard, V1.6 broker/payments sandbox, V1.13 non-investment ops, V1.20 crypto transfers, V1.4 social thesis).

    THE ONE-LINER THAT REPLACES ALL OF IT

    Every page, every doc, every conversation should answer: "What is Tickoni?" with:

    > "Tickoni is a trading agent framework where safety is enforced by architecture, not by policy. Agents can analyze markets, find opportunities, and propose trades. They cannot execute, bypass limits, or make discretionary decisions. Everything is audited. Nothing is autonomous."
