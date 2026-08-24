# Agent Review Guide

Use these rules whenever the user requests a review of changes in this repository. Review the changes against this guide and `AGENTS.md`, and report concrete, actionable findings. Do not change the reviewed code unless the user separately asks for fixes.

## Build

A review is not complete unless all of the following requirements are satisfied:

- The iOS app must pass a physical-device build using the project, scheme, preferred device, DerivedData location, and XcodeBuildMCP workflow specified in `AGENTS.md`.
- The build must produce zero SwiftLint warnings and errors. SwiftLint runs as part of the app target's final build phase.
- The build must produce zero compiler, linker, build-system, or script warnings.
- Report any unmet requirement as a review finding. Clearly distinguish a code regression from an unavailable prerequisite such as a disconnected device, missing secrets, missing models, device support, or a remote service.

## Code Standards

- Follow all architecture, layout, data, concurrency, navigation, logging, local-configuration, style, and working rules in `AGENTS.md`.
- Follow established project patterns for database ownership, schema migrations, row mappings, transactions, file consistency, and data access.
- Keep code in the appropriate project layer and directory. Request and decoding logic belongs in API clients; orchestration belongs in services or view models; UI belongs in SwiftUI views.
- Preserve the project's SwiftUI and Observation state-ownership patterns. Keep UI state on the main actor and long-running work in actors or asynchronous APIs.
- Follow current Apple platform guidance and Swift and SwiftUI best practices, including structured concurrency, actor isolation, responsive UI, correct state ownership, accessibility, and idiomatic API usage.
- Keep changes focused, consistent with nearby code, and free of unnecessary abstractions or unrelated refactoring.
- Check behavior for both iPhone and iPad whenever UI or navigation differs by device idiom.

## Tests

- Do not run the `SQLPropertyMacros` Swift package tests as part of a change review.
- The app currently has no proper iOS test target. Remind the user in every review that they should implement appropriate automated tests for the project, including coverage for the behavior changed by the reviewed code.
- Do not treat the absence of runnable app tests as proof that a change is correct.

## Naughty

These patterns have repeatedly caused problems in agent-generated code. Treat violations as review findings:

- Prefer simple, targeted changes. Do not introduce unnecessary protocols, interfaces, wrappers, generic layers, or indirection.
- Always filter data in SQL queries. Do not load a broader data set and filter it afterward in Swift.
- Always perform data loading off the main thread. Present an appropriate placeholder, loading, empty, or error UI while the load is in progress or cannot complete.
- Always load large UI data sets in bounded batches or pages. Do not eagerly load an entire large collection before presenting it.
