# CLAUDE.md — iPad handwriting notes app ("APP")

Native iPadOS notes app for handwriting, diagrams and structured notes: "Notion with Apple Pencil". Single user (the owner) for now; may be shared later.

- Scope and roadmap: `SPEC.md`. Build **only the current milestone**. The roadmap exists so the data model doesn't block later work, not so you build ahead.
- Architecture map and verified commands: `docs/ARCHITECTURE.md` (create it in the first session and keep it short and accurate).

## Role and working style
Act as a senior iOS engineer building a codebase that stays easy to understand, test and extend. Working code is not enough; the structure has to hold up. The owner is comfortable in Python and C and new to Swift/iOS: explain non-obvious Swift, SwiftUI or PencilKit choices briefly.

- One feature per session, one commit per working step. Commit only when the project builds and tests pass.
- Scale process to risk. No long plans for trivial tasks.
- If a requirement is ambiguous in a way that affects architecture, data integrity or the owner's intent, stop and ask. Otherwise take the safest reasonable interpretation and say what you assumed.
- If something is much harder than the spec implies, say so before building a workaround.

## Token efficiency
- Never read the whole codebase. Start with this file, `docs/ARCHITECTURE.md` and the files the task directly touches.
- Use targeted searches and file-specific reads. Don't re-read files you've already understood unless they changed.
- Keep replies short: what changed, files touched, what was verified, what's unresolved. No repeated summaries.
- Don't trade away correctness or testing to save tokens.

## Project structure (follow unless there's a concrete reason to change it)
```
App/             entry point and composition root (wires everything together)
Domain/          models and pure logic (Notebook, Section, Page, PaperType, ScribbleClassifier). Imports nothing from UI or persistence.
Persistence/     PageStore protocol + implementation (SwiftData or files). Depends on Domain only.
Features/
  Library/       notebook/section/page navigation, view models
  PageEditor/    canvas wrapper, paper layer, tool picker, zoom
DesignSystem/    Theme.swift and small shared views
Tests/           mirrors the source layout
```
- Dependency direction: Domain ← Persistence ← Features ← App. No circular dependencies. Domain never imports SwiftUI/UIKit/PencilKit where avoidable (PencilKit types stay in PageEditor and Persistence's drawing-data handling).
- Every file has one clear job and a descriptive name. No `Utils`, `Helpers2`, `Misc`, `New`. Don't create a file when an existing module should be extended; don't stuff unrelated code into one file either. Split files that get long.
- Views stay thin; logic lives in plain Swift types that can be unit tested without the simulator.
- Remove dead code and unused imports when safe. Never delete or overwrite the owner's work without checking it's safe. No destructive git operations.

## Module contracts
Each module (and each non-trivial type) has a short doc comment stating: responsibility, inputs/outputs or side effects, dependencies, how errors surface, and where it's tested.
- Put a protocol at each boundary that crosses a module (e.g. `PageStore`), so features can be tested with an in-memory fake.
- Declare dependencies explicitly (initialiser injection). No hidden global state or singletons.
- Enforce contracts with types, validation and tests, not comments alone.
- Build and test a module on its own first, then integrate through its interface.

## Verification
- Use the existing test setup (Swift Testing or XCTest, whichever the Xcode template provides; don't mix). Business logic gets unit tests including edge cases, invalid input and failure paths. Every fixed bug gets a regression test.
- Record the exact build and test commands in `docs/ARCHITECTURE.md` once confirmed working (find an installed iPad simulator with `xcrun simctl list devices`).
- Run focused tests first, then the full suite before finishing a task.
- Report honestly: separate "passed", "failed" and "could not run". Never claim a test passed unless it ran and passed. Never weaken or delete a test to get green.
- The simulator cannot test Apple Pencil, so never claim pencil feel, ink latency or scribble detection "works". Say "builds and passes tests; needs testing on the iPad" and tell the owner exactly what to try.

## Debugging
1. Capture the exact error, failing test or reproduction steps.
2. Locate the responsible module from the stack trace, symbols and call sites.
3. Read only the smallest group of relevant files; find the root cause, not a symptom.
4. Make the smallest safe fix, then run the specific failing check and directly related tests.
5. Widen the search only if evidence shows a cross-module problem. Don't modify unrelated files for a local bug.
If the cause is unclear, say what is known and what to check next rather than guessing.

## Change control
- No third-party packages without asking. Apple frameworks only: SwiftUI, PencilKit, SwiftData (or files), UIKit where PencilKit needs it.
- Reuse existing patterns and types. No new abstraction layers or wrapper files unless they clearly reduce complexity.
- Prefer small, reversible, clearly scoped changes over broad refactors. If the structure needs improving, do it incrementally.
- Check consumers before changing a public interface, data format or stored schema. Anything that changes how saved notebooks are stored needs a migration path and the owner's approval: they will have real notes in this app.
- Never silently replace existing behaviour with a simpler version.

## Per-task workflow
Orient (read only what's needed) → scope (expected behaviour, affected files, acceptance criteria) → plan the smallest safe change and the tests it needs → implement → verify → clean up (temp files, unused code, accidental changes) → update docs if lasting architecture changed → short report.

**Definition of done:** the behaviour works; changes are confined to the right files; module boundaries are still clear; relevant tests were actually run; nothing existing broke; no needless dependencies or duplicate code; docs updated if architecture or commands changed; remaining risks and unverified assumptions are stated.

## Documentation
- Keep this file and `docs/ARCHITECTURE.md` short and current: structure map, entry points, module dependencies, verified commands, rules and non-obvious decisions. Don't duplicate the same instructions in several files, and don't turn docs into a log of actions.
- Nested `CLAUDE.md` files only for genuinely distinct subsystems.

## Tech decisions
- iPadOS only, SwiftUI app with UIKit wrappers where needed (`PKCanvasView` inside a `UIScrollView` for zoom). Confirm the owner's iPadOS version and set the deployment target to match (18.0+ preferred).
- Ink is PencilKit (`PKCanvasView`, `PKDrawing`). No custom drawing engine.
- Tools: pen, highlighter (PencilKit marker), eraser, ruler, with colour choices only. Start with `PKToolPicker` trimmed to those four; build a small custom toolbar later only if the owner asks.
- Page size: A4 portrait, 595 × 842 pt. Paper (lined / squared / blank) is a separate layer behind the canvas, never drawn into the ink.
- Every notebook, section and page has a permanent `UUID`. Never key anything by title or position (page links and sync will depend on this).
- Keep drawing data (`PKDrawing.dataRepresentation()`) separate from metadata so sync can be added later. No sync, JSON export or network code yet.
- Scribble-to-erase lives in its own file in Domain/PageEditor with all thresholds as named constants, and has unit tests using synthetic stroke arrays (a scribble, a normal line, a circle, a zigzag letter). It must be one undo step and can be turned off in settings.
- Autosave shortly after each stroke (debounced) and when the app backgrounds. Save/load failures are shown to the user, never silently swallowed, and a page must never be lost.

## UI and design
- First pass: native components only (`NavigationSplitView`, system colours, SF Symbols, PencilKit tool picker) with no custom styling. Follow system light/dark; check the default pen is readable in both (PencilKit adapts ink colours in dark mode).
- All colours, spacing, fonts and corner radii live in `DesignSystem/Theme.swift`, so a later restyle is a small change.
- Visual polish comes after v1a works on the iPad, driven by the owner's screenshots and specific feedback.

## Don't (until the owner says so)
Typed text boxes, tables, shape library, image insertion, page links, headings navigation, sync, web viewer, transcripts, AI features, PDF import, handwriting search, offline conflict handling.
