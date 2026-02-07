# Elixir ADK - Claude CLI Instructions

## Project Overview

Elixir/OTP port of Google's Agent Development Kit (ADK). This is the `adk` hex package providing agent orchestration, session management, tool use, and A2A protocol support.

## Quick Start

```bash
cd /workspace/adk
mix deps.get
mix test          # 75 tests
mix credo         # Static analysis
mix dialyzer      # Type checking
```

## Key Documentation

- **PRD**: `docs/prd.md`
- **Implementation Plan**: `docs/implementation-plan.md` (phase checklist)
- **Onboarding**: `docs/onboarding.md` (full context for new agents)
- **Project Memory**: `/home/dev/.claude/projects/-workspace-agent-hub/memory/MEMORY.md`

## Reference Codebases

- **Go ADK (PRIMARY)**: `/workspace/adk-go/` — Read corresponding Go file before implementing any module
- **Python ADK**: `/workspace/google-adk-venv/lib/python3.13/site-packages/google/adk/`
- **A2A Go SDK**: `/workspace/a2a-go/`

## Current Status

Phase 1 (Foundation) complete. Next: Phase 2 (Runner, Tools, LLM Agent).

## Critical Rules

1. **Compile order**: Define nested/referenced modules BEFORE parent modules in the same file (e.g., `Event.Actions` before `Event`)
2. **Avoid MapSet with dialyzer**: Use `%{key => true}` maps + `Map.has_key?/2` instead
3. **Credo nesting**: Max depth 2 — extract inner logic into helper functions
4. **All tests async**: Use `async: true` unless shared state requires otherwise
5. **Verify all changes**: Always run `mix test && mix credo && mix dialyzer`
