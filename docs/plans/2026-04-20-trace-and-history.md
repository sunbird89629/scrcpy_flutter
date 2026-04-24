# Sub-project #4: Trace System & History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a lightweight execution tracing system and a persistent conversation history manager in the Flutter Monorepo.

**Architecture:** 
- **Trace**: Add `TraceSpan` and `TraceManager` to `autoglm_core`. Uses in-memory collection and daily rolling file persistence (JSONL).
- **History**: Add `HistoryManager` and `ConversationRecord` models to `autoglm_core`. Uses a SQLite database (via `sqflite_common_ffi`) for desktop-grade performance and query capability.
- **UI**: Populate `apps/desktop/lib/pages/history_page.dart` with a searchable/filterable list of past sessions.

**Tech Stack:** Dart 3.5, `sqflite_common_ffi`, `uuid`, `path_provider`, `riverpod`.

---

## File Structure

```
autoglm-flutter/
├── packages/
│   └── autoglm_core/
│       ├── lib/src/
│       │   ├── models/
│       │   │   ├── trace.dart
│       │   │   └── history.dart
│       │   ├── trace/
│       │   │   ├── trace_manager.dart
│       │   │   └── trace_span.dart
│       │   └── history/
│       │       ├── history_database.dart
│       │       └── history_manager.dart
│       └── test/
│           ├── trace_test.dart
│           └── history_test.dart
└── apps/desktop/
    └── lib/
        ├── providers/
        │   ├── history_provider.dart
        │   └── trace_provider.dart
        └── pages/
            └── history_page.dart
```

---

## Task 1: Implement Trace System in `autoglm_core`

**Files:**
- Create: `packages/autoglm_core/lib/src/models/trace.dart`
- Create: `packages/autoglm_core/lib/src/trace/trace_span.dart`
- Create: `packages/autoglm_core/lib/src/trace/trace_manager.dart`

- [ ] **Step 1: Define Trace models**
Define `TraceRecord`, `SpanRecord`, and `TraceTimingSummary`.
- [ ] **Step 2: Implement `TraceSpan`**
Context-manager like class to record start/end times and attributes.
- [ ] **Step 3: Implement `TraceManager`**
Handle span lifecycle, stack management (for nesting), and file persistence.
- [ ] **Step 4: Verify with tests**

---

## Task 2: Implement History System (SQLite) in `autoglm_core`

**Files:**
- Create: `packages/autoglm_core/lib/src/models/history.dart`
- Create: `packages/autoglm_core/lib/src/history/history_database.dart`
- Create: `packages/autoglm_core/lib/src/history/history_manager.dart`

- [ ] **Step 1: Define History models**
`ConversationRecord`, `StepRecord`, etc.
- [ ] **Step 2: Setup SQLite Database**
Use `sqflite_common_ffi`. Define tables for `conversations` and `steps`.
- [ ] **Step 3: Implement `HistoryManager`**
CRUD operations for history records.
- [ ] **Step 4: Verify with tests**

---

## Task 3: UI Integration in Desktop App

**Files:**
- Create: `apps/desktop/lib/providers/history_provider.dart`
- Modify: `apps/desktop/lib/pages/history_page.dart`

- [ ] **Step 1: Wire Riverpod providers for history**
- [ ] **Step 2: Build History list UI**
Show a list of sessions with timestamps, device IDs, and task summaries.
- [ ] **Step 3: Implement search/filtering**
Filter by device ID or date range.
