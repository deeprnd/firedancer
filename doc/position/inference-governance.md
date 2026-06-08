# Tickoni Inference Governance

## Purpose

This document owns product requirements for model access, LLM-server
integration, token budgets, retry limits, and inference auditability.

Tile ownership is limited to one rule: all model access flows through `tkmodl`.
The topology reference for that rule lives in [`tile-plan.md`](tile-plan.md).

## Governance Principles

1. Agents do not call model providers directly.
2. Agents do not call local or development LLM servers directly.
3. Model access must be policy-checked, budgeted, attributed, audited, and
   replay-substitutable.
4. Local/dev model access is a development backend, not a permission shortcut.
5. Replay never invokes model providers, local LLM servers, or local GPU
   inference.

## Supported Backend Categories

| Backend | Product use | Governance requirement |
| --- | --- | --- |
| Cloud API | Production or demo model access through OpenAI, Anthropic, Qwen, or DeepSeek | API key configured, provider enabled, budget enforced, request audited |
| Local/dev LLM server | Phase 1 demos and local development | Endpoint configured, timeout enforced, request audited, no direct agent access |
| Local GPU | Future local inference for open-weight Qwen or DeepSeek models | Weight path configured, context size enforced, GPU ownership isolated to `tkmodl` |
| Deterministic stub | Tests and offline demos | Response fixture selected by request id or model id, audited like real inference |

## Provider Requirements

| Provider | API style | Configuration |
| --- | --- | --- |
| OpenAI | OpenAI chat completions | base URL, API key, model allowlist |
| Anthropic | Anthropic Messages API | base URL, API key, model allowlist |
| Qwen cloud | OpenAI-compatible | base URL, API key, model allowlist |
| DeepSeek cloud | OpenAI-compatible | base URL, API key, model allowlist |
| Local/dev LLM server | OpenAI-compatible by default | endpoint URL, optional API key, timeout, model allowlist |
| Local GPU | llama.cpp C API path | GGUF weight path, context size, CUDA setting, model allowlist |

## Model Identifier Format

Model identifiers select a configured backend:

```text
openai:gpt-4o
anthropic:claude-opus-4-8
qwen:qwen2.5-72b-instruct
qwen:local
deepseek:deepseek-chat
deepseek:local
llm-server:local
stub:deterministic
```

Unknown or unconfigured identifiers must fail closed before any outbound call.

## Budget Controls

Each model request must carry:

- actor id
- role
- workflow
- case id or synthetic run id
- policy version
- model identifier
- budget id
- max output tokens
- retry limit
- context limit

The runtime must enforce:

- per-run model-call limit
- per-role model-call limit
- per-case or synthetic-run token budget
- retry limit
- context-size limit
- loop step limit

Budget exhaustion is a policy-relevant event and must be audited.

## Audit Requirements

Each model call must audit:

- request id
- actor id and role
- workflow
- case id or synthetic run id
- model identifier
- backend category
- prompt or prompt reference
- response or response reference
- token usage, estimated when provider usage is unavailable
- retry count
- latency
- policy decision id
- budget id
- replay substitution id

Replay must use captured model output or deterministic fixtures. Replay must
not invoke cloud APIs, local LLM servers, or GPU inference.

## Phase 1 Acceptance

Phase 1 closes only when:

1. deterministic stub inference works without network access
2. at least one local/dev LLM server path can be configured through `tkmodl`
3. unconfigured providers fail closed
4. token and retry limits are enforced
5. model request and response records appear in the audit chain
6. replay substitutes model outputs without external calls
