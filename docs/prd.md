# Product Requirements Document: Elixir ADK (Agent Development Kit)

## Document Info
- **Project**: Elixir ADK - An Elixir/OTP port of Google's Agent Development Kit
- **Version**: 0.1.0
- **Date**: 2026-02-07
- **Status**: Phase 1 Complete

---

## 1. Executive Summary

This project ports Google's Agent Development Kit (ADK) and Agent-to-Agent (A2A) protocol to Elixir/OTP. The Google ADK provides a framework for building AI agents with tools, multi-agent orchestration, session management, and inter-agent communication. Elixir's BEAM VM, with its native concurrency, fault tolerance, and message-passing primitives, is an ideal platform for agent systems.

The Elixir ADK is a standalone Mix project (hex package: `adk`) that provides idiomatic Elixir equivalents of all core ADK components while leveraging OTP patterns where they naturally fit.

---

## 2. Background and Motivation

### 2.1 Current State
- Google ADK exists in Python (reference), TypeScript, Go, and Java
- No Elixir implementation exists
- The A2A protocol is an open standard (https://github.com/a2aproject/A2A) for agent interoperability

### 2.2 Why Elixir?
- **BEAM processes** map naturally to agents (lightweight, isolated, concurrent)
- **OTP supervision trees** provide built-in fault tolerance for agent systems
- **GenServer** provides the yield/resume pattern needed by the ADK event loop
- **Task.async_stream / TaskSupervisor** handles parallel agent execution natively
- **Phoenix/Plug** provides a production-grade HTTP stack for A2A servers
- **ETS** provides fast in-memory state storage with concurrent reads
- **Stream** provides lazy enumerables matching the ADK's async generator pattern

### 2.3 Reference Materials
- **Google ADK Go source** (PRIMARY): `/workspace/adk-go/`
- **Google ADK Python source**: `/workspace/google-adk-venv/lib/python3.13/site-packages/google/adk/`
- **Google ADK docs**: https://google.github.io/adk-docs/
- **A2A Go SDK**: `/workspace/a2a-go/`
- **A2A samples**: `/workspace/a2a-samples/`

---

## 3. Goals and Non-Goals

### 3.1 Goals
1. **Feature parity with Google ADK core** - All agent types, runner, session, event, tool, and callback systems
2. **A2A protocol compliance** - Expose agents via A2A and consume remote A2A agents
3. **Idiomatic Elixir** - Use OTP patterns, behaviours, and conventions
4. **Multi-LLM support** - Gemini (primary), Claude (Anthropic), and extensible via behaviour
5. **Production-ready services** - In-memory + persistent implementations for sessions, artifacts, memory
6. **Comprehensive testing** - Unit tests, integration tests, dialyzer, credo

### 3.2 Non-Goals (for v1.0)
- Google Cloud-specific integrations (Vertex AI, GCS, Agent Engine)
- Web UI / CLI tool
- Streaming/BIDI audio/video support
- Evaluation framework

---

## 4. Core Architecture

```
User Message -> Runner -> Agent -> Flow -> LLM
                  |          |        |       |
                  |          |     [tool calls loop]
                  |          |        |
               [commits events + state to Session]
                  |
               [yields Events to application]
```

### Component Overview

| Component | Module | Status |
|-----------|--------|--------|
| Core types (Content, Part, etc.) | `ADK.Types.*` | Done |
| Event + Actions | `ADK.Event`, `ADK.Event.Actions` | Done |
| Session | `ADK.Session` | Done |
| Session State utilities | `ADK.Session.State` | Done |
| Session Service behaviour | `ADK.Session.Service` | Done |
| InMemory Session Service | `ADK.Session.InMemory` | Done |
| Run Config | `ADK.RunConfig` | Done |
| Agent behaviour | `ADK.Agent` | Done |
| Invocation Context | `ADK.Agent.InvocationContext` | Done |
| Callback Context | `ADK.Agent.CallbackContext` | Done |
| Custom Agent | `ADK.Agent.CustomAgent` | Done |
| Agent Config | `ADK.Agent.Config` | Done |
| Agent Tree utilities | `ADK.Agent.Tree` | Done |
| Runner | `ADK.Runner` | Phase 2 |
| LLM Agent | `ADK.Agent.LLM` | Phase 2 |
| Tool System | `ADK.Tool.*` | Phase 2 |
| LLM Abstraction | `ADK.Model.*` | Phase 3 |
| Flow (Auto/Single) | `ADK.Flow.*` | Phase 3 |
| Orchestration agents | `ADK.Agent.{Sequential,Parallel,Loop}` | Phase 4 |
| A2A Protocol | `ADK.A2A.*` | Phase 5 |
| Memory/Artifact services | `ADK.Memory.*`, `ADK.Artifact.*` | Phase 6 |

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Behaviours over inheritance | Elixir has no class inheritance; behaviours + structs provide contracts |
| GenServer + ETS for InMemorySession | Serialized writes via GenServer, concurrent reads via ETS |
| Stream for event iteration | Lazy enumerables match async generators |
| Structs for data models | Replaces Pydantic models; use typed structs |
| Modules defined before dependents | Nested structs must be compiled first (e.g., Event.Actions before Event) |
| Plain maps over MapSet for tracking | Avoids dialyzer opaque type issues with MapSet |

---

## 5. Detailed Requirements

### 5.1 Agent System
- Base agent behaviour defining `run/2` returning Enumerable of Events
- LLM agent with model, instruction, tools, sub_agents, callbacks
- SequentialAgent, ParallelAgent, LoopAgent
- Custom agent via Config struct with before/after callbacks
- Agent tree: find_agent/2, build_parent_map/1, validate_unique_names/1
- Agent transfer via `transfer_to_agent` action

### 5.2 Runner and Event Loop
- Runner managing user invocations
- Event processing: append to session, commit state_delta and artifact_delta
- Partial event forwarding without action processing
- RunConfig: streaming_mode, save_input_blobs_as_artifacts

### 5.3 Session Management
- Session struct: id, app_name, user_id, events, state, last_update_time
- SessionService behaviour: create, get, list, delete, append_event
- InMemorySessionService backed by 3 ETS tables (sessions, app_state, user_state)
- State prefix scoping: `app:`, `user:`, `temp:`, (none)=session
- State delta extraction and merge utilities

### 5.4 Event System
- Event struct with UUID auto-generation and timestamp
- EventActions: state_delta, artifact_delta, transfer_to_agent, escalate, skip_summarization
- final_response?/1 detection logic matching Go ADK

### 5.5 Tool System (Phase 2)
- Tool behaviour: name, description, declaration, run
- FunctionTool, AgentTool, LongRunningFunctionTool
- ToolContext with state access and artifact operations

### 5.6 LLM Abstraction (Phase 3)
- LLM behaviour: generate_content/2 returning Stream of responses
- Gemini and Claude implementations via direct REST API calls
- LLM Registry for model name resolution

### 5.7 A2A Protocol (Phase 5)
- A2A server (Plug endpoint) with agent card and JSON-RPC
- A2A client for consuming remote agents
- ADK <-> A2A format converters

---

## 6. Technical Constraints

- **Elixir version**: >= 1.17
- **OTP version**: >= 26
- **Dependencies**: jason, elixir_uuid (runtime); ex_doc, dialyxir, credo (dev)
- **No GenAI SDK**: Direct REST API calls for LLM providers
- **Testing**: ExUnit, dialyzer, credo

---

## 7. Success Criteria

1. All agent types work with real LLM providers
2. Sessions persist and restore across runner invocations
3. An agent can be exposed via A2A and consumed by another agent
4. All core behaviours have at least one in-memory implementation
5. Test suite passes, dialyzer clean, credo clean
