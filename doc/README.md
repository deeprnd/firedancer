# SEK / PRINCE2 Documentation Model

This repository uses a lightweight documentation model based on **SEK**:

* **S — Strategy**
* **E — Execution**
* **K — Knowledge**

The model is compatible with common **PRINCE2** project management concepts.

## Purpose

The goal is to organize project and technical documentation by purpose:

* **Strategy** explains why the project exists and what direction it follows.
* **Execution** explains how the project is delivered and controlled.
* **Knowledge** captures reusable information, decisions, standards, and lessons learned.

## Mapping to PRINCE2

| SEK Area  | PRINCE2-Compatible Concept                       | Purpose                                                    |
| --------- | ------------------------------------------------ | ---------------------------------------------------------- |
| Strategy  | Business Case / Continued Business Justification | Align the project with business value and objectives       |
| Execution | Plans, Stages, Progress, Risk, Quality, Issues   | Manage delivery, control work, and track progress          |
| Knowledge | Learn from Experience / Lessons Log              | Capture and reuse project learning and technical knowledge |

## Documentation Categories

### Strategy → [`strategy/`](strategy/)

Strategy documents define direction and priorities.

Examples:

* Business case
* Product vision
* Project objectives
* Target architecture
* Technical roadmap
* Quality strategy
* Key constraints and assumptions

### Execution → [`execution/`](execution/)

Execution documents support delivery, coordination, and control.

Examples:

* Project plan
* Sprint or release plan
* Build process
* CI/CD pipeline documentation
* Test plan
* Deployment runbook
* Release checklist
* Risk and issue logs

### Knowledge → [`knowledge/`](knowledge/)

Knowledge documents capture reusable understanding.

Examples:

* System architecture overview
* Architecture Decision Records (ADRs)
* API documentation
* Engineering standards
* Troubleshooting guides
* Lessons learned
* Historical defects and fixes

## Practical Rule

Classify documents by their main purpose:

* If it explains **why** → Strategy
* If it explains **how delivery happens** → Execution
* If it captures **what we know or learned** → Knowledge

Some documents may belong to more than one area. In that case, place the document where it is most useful and link to it from the other relevant sections.

## Firedancer Engine Reference

Files at the root of this directory (not under `strategy/`, `execution/`, or
`knowledge/`) are Firedancer engine reference material carried over from
upstream Firedancer infrastructure:

* [`Firedancer build-system.md`](build-system.md)
* [`codeql.md`](codeql.md)
* [`Firedancer testing.md`](testing.md)
* [`organization.txt`](organization.txt)
