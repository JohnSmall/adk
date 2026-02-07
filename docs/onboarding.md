# Onboarding Guide: Elixir ADK Project

## For New AI Agents / Developers

This document provides everything needed to pick up the Elixir ADK project.

---

## 1. What Is This Project?

We are building an **Elixir/OTP port of Google's Agent Development Kit (ADK)** and the **Agent-to-Agent (A2A) protocol**. The Google ADK is a framework for building AI agents that can use tools, orchestrate sub-agents, manage sessions, and communicate with other agents.

Google provides the ADK in Python (reference), TypeScript, Go, and Java. We are creating the Elixir implementation.

---

## 2. Current Status

**Phase 1 (Foundation) is COMPLETE.** The project lives at `/workspace/adk/`.

### What's Built

| Module | Purpose | File |
|--------|---------|------|
| `ADK.Types.Blob` | Binary data with MIME type | `lib/adk/types.ex` |
| `ADK.Types.FunctionCall` | LLM function call request | `lib/adk/types.ex` |
| `ADK.Types.FunctionResponse` | Function call response | `lib/adk/types.ex` |
| `ADK.Types.Part` | Tagged union: text/fc/fr/blob | `lib/adk/types.ex` |
| `ADK.Types.Content` | Message with role + parts | `lib/adk/types.ex` |
| `ADK.Types` | Helper functions for Content | `lib/adk/types.ex` |
| `ADK.Event.Actions` | Side-effects: state_delta, transfer, escalate | `lib/adk/event.ex` |
| `ADK.Event` | Core event struct with new/1, final_response?/1 | `lib/adk/event.ex` |
| `ADK.Session` | Session struct (id, app_name, user_id, state, events) | `lib/adk/session.ex` |
| `ADK.Session.State` | Prefix-based state scoping utilities | `lib/adk/session/state.ex` |
| `ADK.Session.Service` | Behaviour for session storage backends | `lib/adk/session/service.ex` |
| `ADK.Session.InMemory` | GenServer + 3 ETS tables session implementation | `lib/adk/session/in_memory.ex` |
| `ADK.RunConfig` | Runtime config (streaming_mode, save_blobs) | `lib/adk/run_config.ex` |
| `ADK.Agent` | Agent behaviour (name, description, run, sub_agents) | `lib/adk/agent.ex` |
| `ADK.Agent.InvocationContext` | Immutable execution context | `lib/adk/agent/invocation_context.ex` |
| `ADK.Agent.CallbackContext` | Callback context with state access | `lib/adk/agent/callback_context.ex` |
| `ADK.Agent.Config` | Configuration struct for custom agents | `lib/adk/agent/config.ex` |
| `ADK.Agent.CustomAgent` | Custom agent with before/after callbacks | `lib/adk/agent/custom_agent.ex` |
| `ADK.Agent.Tree` | Agent tree: find, parent_map, validate | `lib/adk/agent/tree.ex` |

### Test Coverage
- 75 tests passing
- Credo: clean
- Dialyzer: clean

### What's Next
Phase 2: Runner, Tool System, LLM Agent (see `docs/implementation-plan.md`)

---

## 3. Key Resources

### Local Files

| Resource | Location |
|----------|----------|
| **This project (Elixir ADK)** | `/workspace/adk/` |
| **Google ADK Go source (PRIMARY ref)** | `/workspace/adk-go/` |
| **Google ADK Python source** | `/workspace/google-adk-venv/lib/python3.13/site-packages/google/adk/` |
| **A2A Go SDK** | `/workspace/a2a-go/` |
| **A2A samples** | `/workspace/a2a-samples/` |
| **PRD** | `/workspace/adk/docs/prd.md` |
| **Implementation plan** | `/workspace/adk/docs/implementation-plan.md` |
| **This guide** | `/workspace/adk/docs/onboarding.md` |
| **Project memory** | `/home/dev/.claude/projects/-workspace-agent-hub/memory/MEMORY.md` |

### External Documentation

| Resource | URL |
|----------|-----|
| Google ADK docs | https://google.github.io/adk-docs/ |
| A2A protocol spec | https://github.com/a2aproject/A2A |

---

## 4. Architecture Quick Reference

### Core Execution Model

```
User Message -> Runner -> Agent -> Flow -> LLM
                  |                  |       |
                  |               [tool calls loop]
                  |                  |
               [commits events + state to Session]
                  |
               [yields Events to application]
```

### Agent Types

| Type | Purpose | Elixir Implementation |
|------|---------|----------------------|
| CustomAgent | User-defined run function | `ADK.Agent.CustomAgent` (done) |
| LlmAgent | LLM-powered with tools | Phase 2 |
| SequentialAgent | Run sub-agents in order | Phase 3 |
| ParallelAgent | Run sub-agents concurrently | Phase 3 |
| LoopAgent | Repeat sub-agents until termination | Phase 3 |

### State Prefixes

| Prefix | Scope | Persisted? |
|--------|-------|------------|
| (none) | Session-local | Yes |
| `app:` | Shared across all users/sessions | Yes |
| `user:` | Shared across user's sessions | Yes |
| `temp:` | Current invocation only | No (discarded) |

### 6 Callback Points (to be implemented in Phase 2-3)

1. `before_agent` - Before agent execution (can skip)
2. `after_agent` - After agent execution (can replace output)
3. `before_model` - Before LLM call
4. `after_model` - After LLM response
5. `before_tool` - Before tool execution
6. `after_tool` - After tool execution

---

## 5. Project Structure

```
/workspace/adk/
  mix.exs                          # ADK.MixProject - deps: jason, elixir_uuid
  lib/
    adk.ex                         # Top-level module
    adk/
      application.ex               # OTP application
      types.ex                     # Content, Part, FunctionCall, FunctionResponse, Blob
      run_config.ex                # RunConfig struct
      event.ex                     # Event.Actions (first), then Event
      session.ex                   # Session struct
      session/
        state.ex                   # State prefix utilities
        service.ex                 # Session.Service behaviour
        in_memory.ex               # InMemorySessionService (GenServer + ETS)
      agent.ex                     # Agent behaviour
      agent/
        config.ex                  # Agent.Config struct
        custom_agent.ex            # CustomAgent implementation
        invocation_context.ex      # InvocationContext struct
        callback_context.ex        # CallbackContext struct
        tree.ex                    # Agent tree utilities
  test/
    test_helper.exs
    adk/
      types_test.exs
      event_test.exs
      session/
        state_test.exs
        in_memory_test.exs
      agent/
        custom_agent_test.exs
        tree_test.exs
  docs/
    prd.md                         # Product Requirements Document
    implementation-plan.md         # Phased TODO list
    onboarding.md                  # This file
```

---

## 6. Elixir/OTP Design Patterns Used

| ADK Concept | Elixir Equivalent | Why |
|-------------|-------------------|-----|
| BaseAgent (class) | `@behaviour` + struct | No inheritance in Elixir |
| Agent.Run() stream | `Enumerable.t()` (Stream) | Lazy evaluation, yield/resume |
| Session storage | GenServer + ETS | Serialized writes, concurrent reads |
| Async generators | `Stream.resource/3` | Produces events lazily |
| Pydantic models | `defstruct` + `@type` | Typed structs |
| Thread safety | GenServer `call` | Serialized access |
| State scoping | Prefix-based map keys | Simple, no extra tables |

### Critical Compile-Order Rule

**Define nested/referenced modules BEFORE the modules that reference them in the same file.** For example, in `event.ex`:
- `ADK.Event.Actions` is defined FIRST
- `ADK.Event` is defined SECOND (because it references `%ADK.Event.Actions{}` in its default struct)

Similarly in `types.ex`, all sub-types (Blob, FunctionCall, etc.) are defined before `ADK.Types`.

### Dialyzer Gotcha: MapSet Opaque Types

Avoid using `MapSet` with `in` operator or `MapSet.member?/2` — dialyzer treats MapSet internals as opaque and will emit warnings. Use plain `%{key => true}` maps with `Map.has_key?/2` instead.

---

## 7. How to Reference Go ADK Source

The Go ADK is the primary reference for implementation. Key patterns to study:

```bash
# Agent interface and custom agent
cat /workspace/adk-go/agent/agent.go

# Session structs, Event, EventActions, State prefixes
cat /workspace/adk-go/session/session.go

# Session service interface
cat /workspace/adk-go/session/service.go

# InMemory session implementation
cat /workspace/adk-go/session/inmemory.go

# State utilities (ExtractStateDeltas, MergeStates)
cat /workspace/adk-go/internal/sessionutils/utils.go

# Context interfaces (InvocationContext, CallbackContext)
cat /workspace/adk-go/agent/context.go

# RunConfig
cat /workspace/adk-go/agent/run_config.go

# Runner (for Phase 2)
cat /workspace/adk-go/runner/runner.go

# LLM Agent + Flow (for Phase 2)
cat /workspace/adk-go/agent/llm_agent.go
cat /workspace/adk-go/agent/flow.go

# Tools (for Phase 2)
cat /workspace/adk-go/tool/tool.go

# A2A integration (for Phase 4)
ls /workspace/adk-go/server/adka2a/
```

When implementing an Elixir module, always read the corresponding Go file first to understand:
1. The exact interface (methods, parameters, return types)
2. Edge cases handled
3. Error conditions
4. Integration points with other components

---

## 8. Development Workflow

### Running Tests
```bash
cd /workspace/adk
mix test              # Run all tests
mix test --trace      # Run with verbose output
mix credo             # Static analysis
mix dialyzer          # Type checking (first run builds PLT, takes ~1 min)
```

### Starting a New Phase
1. Read the implementation plan section for the phase
2. Read the corresponding Go ADK source files
3. Create modules in compile-safe order (dependencies first)
4. Write tests alongside implementation
5. Check off tasks in `docs/implementation-plan.md`
6. Verify: `mix test && mix credo && mix dialyzer`

### Conventions
- Module names: `ADK.Component.SubComponent` (e.g., `ADK.Agent.CustomAgent`)
- Behaviours: Define in dedicated files (e.g., `agent.ex`, `service.ex`)
- Structs: `defstruct` + `@type t :: %__MODULE__{}` typespecs
- Callbacks: Return `{Content.t() | nil, context}` — nil = continue, non-nil = short-circuit
- Errors: `{:ok, result}` / `{:error, reason}` tuples
- Tests: Mirror `lib/` structure under `test/`
- All tests should be `async: true` unless they share state

---

## 9. Quick Commands

```bash
# Run tests
cd /workspace/adk && mix test

# Static analysis
mix credo

# Type checking
mix dialyzer

# Interactive shell
iex -S mix

# Clean build
mix clean && mix compile
```

---

## 10. Key Contacts / Context

- **Project owner**: John Small (jds340@gmail.com)
- **Original project**: AgentHub at `/workspace/agent_hub/` (predates ADK alignment)
- **ADK Elixir project**: `/workspace/adk/`
