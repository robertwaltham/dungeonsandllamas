# Dungeons and Llamas — Contributor Guide

## Project overview

This repository contains an iOS app that pairs SwiftUI drawing/photo workflows with remote LLM, Stable Diffusion, and ComfyUI services. The app uses SwiftUI, Observation, Swift Concurrency, SwiftData, PencilKit, and a coordinator-based navigation flow.

The primary app target is `DungeonsAndLlamas`. It is an iOS 27.0 / Swift 6.0 project. `SQLPropertyMacros/` is a local Swift Package dependency that provides the `SQLPropertyMacros` library.

## Repository layout

- `DungeonsAndLlamas/DungeonsAndLlamasApp.swift`: app entry point and startup wiring.
- `DungeonsAndLlamas/Views/`: SwiftUI screens; `Views/Drawing/` contains PencilKit flows and `Views/Test Views/` contains development/test screens.
- `DungeonsAndLlamas/Navigation/`: `ContentLink` destinations and `ContentFlowCoordinator` navigation state.
- `DungeonsAndLlamas/Service/`: app state, persistence, photos/files, ML support, logging, and tokenization.
- `DungeonsAndLlamas/API/`: remote service clients; `API/ComfyUI/Workflows/` holds JSON workflow templates.
- `DungeonsAndLlamas/Assets.xcassets/`: app assets.
- `SQLPropertyMacros/`: local macro package and its tests.
- `sample.conf`: example nginx configuration for routing to the model host.

## Local configuration and secrets

- `DungeonsAndLlamas/API/Secrets.swift` is intentionally Git-ignored. Do not add it to Git, print it, or put credentials in source, logs, tests, screenshots, or documentation.
- The app expects `Secrets` to provide `host`, `authorization`, `username`, and `password`; see `README.md` for the local-only template.
- Downloaded model artifacts (such as `.mlpackage` and `.aimodel`) are also Git-ignored. Do not commit generated model data or build products.

## Code conventions

- Follow the surrounding Swift style: four-space indentation, braces on the same line, and `//MARK: - Section` markers for larger types.
- Prefer SwiftUI + Observation. Shared app state is owned by `GenerationService` (`@MainActor`, `@Observable`) and supplied through the environment from the app entry point.
- Keep UI rendering on the main actor. For asynchronous work that changes observable UI state, mirror the existing `Task { @MainActor ... }` and `async` patterns.
- Put new navigation destinations in `ContentLink` and handle each supported device idiom in `ContentFlowCoordinator`.
- Keep remote request construction, decoding, and transport errors in the relevant API client; keep UI orchestration in a view model/service rather than in a view body.
- Treat ComfyUI workflow JSON node IDs and field names as external contracts. Change them only with a corresponding workflow/server validation.
- Use `LoggingService` for diagnostics. Never log tokens, authorization headers, passwords, image contents, or other sensitive request data.
- Preserve the existing `LargeLangageModelClient` spelling when referencing the current type; do not rename it incidentally in unrelated work.

## Database and data models

Persistence is implemented with SQLite.swift in `DungeonsAndLlamas/Service/DatabaseService.swift`; it is separate from the app's use of SwiftData imports. The production database is `db.sqlite3` in the app Documents directory. Always access it through `DatabaseService` after `setup()` has run; use `setupForTesting(fileService:)` only for in-memory previews/test data.

- `ImageHistoryModel` is the generation-history record and owns its related `LoraHistoryModel` rows. `PhotoIndexModel` tracks indexed Photos assets and their derived files. Keep the model struct, table definition, save/load mapping, and any targeted update method in sync.
- Use `@SqlProperty` for SQLite-compatible scalar fields. The local `SQLPropertyMacros` package derives a fileprivate `SQLite.Expression` named `<property>Exp` and converts camelCase properties to snake_case column names.
- Collections need explicit storage. Existing embeddings are stored as `Data` containing `Float` values; image paths and photo categories use JSON encoding. Preserve the matching encoding/decoding, including malformed-data fallbacks, and do not change a persisted representation without a migration.
- `ImageHistoryModel.inputFilePaths`, output/drawing/depth paths, and `PhotoIndexModel` file paths refer to files managed by `FileService` or `PhotoLibraryService`; they are not blobs in SQLite. When deleting or replacing records, coordinate database updates with file cleanup so stale files and dangling paths are not created.
- Add schema changes in `DatabaseService.migrateDatabase()` as a new, ordered `userVersion` step. Make each migration safe for an existing install (for example, check whether a column exists before adding it) and advance `db.userVersion` only after the step succeeds. Do not modify or reorder already-released migration steps.
- Add newly persisted fields to `createTable()` as well as the migration path, so both new and existing installations reach the same schema. Use `insert(or: .replace)` only for models where replacing the complete row is intended; keep related records consistent.
- Preserve primary-key and relationship invariants: `ImageHistoryModel.id` is the history key and `LoraHistoryModel.historyModelId` refers to it. Generate IDs before saving dependent records.
- Surface persistence failures through `DatabaseService` logging and a safe fallback instead of exposing the raw SQLite connection to views. Use an atomic transaction when a future change must update multiple database rows as one unit.

## Build and test

Use XcodeBuildMCP for iOS project discovery, simulator builds, launches, and tests. Configure the session with the project, scheme, simulator, and the repository-local DerivedData directory before building:

- Project: `DungeonsAndLlamas.xcodeproj`
- Scheme: `DungeonsAndLlamas`
- DerivedData: `.derivedData/`

Use `session_show_defaults` before the first build/test call, then `session_set_defaults` if the project, scheme, simulator, or DerivedData path is missing or incorrect. Use `build_sim` for compile-only verification and `build_run_sim` when launching the app. Do not invoke `xcodebuild` directly when XcodeBuildMCP is available. The project does not currently include a shared scheme, so use the `DungeonsAndLlamas` scheme and an installed iOS 27.0 Simulator.

For the local macro package:

```sh
swift test --package-path SQLPropertyMacros
```

Do not treat a build failure caused by missing local secrets, model files, a simulator runtime, or unavailable remote AI services as a code regression. State the missing local prerequisite clearly.

## Change and verification checklist

1. Keep edits focused; do not overwrite unrelated working-tree changes.
2. For UI/navigation changes, verify phone and iPad behavior when the destination differs by idiom.
3. For API/workflow changes, exercise the affected request against a configured local service when available and verify user-facing error handling when it is not.
4. Run the narrowest relevant test/build command and report what was or was not verifiable locally.
5. Do not edit `.xcodeproj/project.pbxproj` by hand unless adding/removing project resources or targets; use Xcode when practical and keep project-file diffs minimal.
