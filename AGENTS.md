# Dungeons and Llamas — Contributor Guide

## Project

`DungeonsAndLlamas` is a SwiftUI app for drawing and photo workflows backed by local ML and remote LLM, Stable Diffusion, and ComfyUI services. The app targets iOS 27.0 with Swift 6.0 and uses Observation, Swift Concurrency, PencilKit, Photos, CoreML/CoreAI, and SQLite.swift.

The repository contains one iOS app target and the local `SQLPropertyMacros` Swift package.

## Layout

- `DungeonsAndLlamas/DungeonsAndLlamasApp.swift`: startup and shared service injection.
- `DungeonsAndLlamas/Views/`: SwiftUI screens, drawing flows, and development views.
- `DungeonsAndLlamas/Navigation/`: destinations and coordinator state.
- `DungeonsAndLlamas/Service/`: app state, persistence, files, photos, ML, and logging.
- `DungeonsAndLlamas/API/`: remote clients and ComfyUI workflow JSON.
- `DungeonsAndLlamas/Models/`: local model artifacts; Git-ignored.
- `SQLPropertyMacros/`: SQLite property macro package and tests.

## Code conventions

- Follow nearby Swift style: four-space indentation, same-line braces, and `//MARK: - Section` for larger files.
- Use SwiftUI and Observation for UI state. `GenerationService` owns shared app state and is supplied through the environment.
- Keep UI state on the main actor. Use actors and async APIs for ML, network, and other long-running work.
- Keep request and decoding logic in API clients; keep orchestration in services or view models.
- Add navigation cases to `ContentLink` and resolve them in `ContentFlowCoordinator` for supported device idioms.
- Use `LoggingService` and OSLog privacy. Do not log credentials, tokens, image contents, or sensitive request data.

## Data

- `DatabaseService` owns the SQLite database in the app Documents directory. Media and drawings are stored by file services; database records store their paths.
- Keep model fields, table creation, row mappings, and migrations aligned. Add schema changes as new ordered migrations and preserve existing steps.
- Use `@SqlProperty` for supported scalar columns. Keep explicit encodings for collections and embeddings unless a migration changes them.
- Keep related database rows and files consistent; use transactions for atomic multi-row changes.

## Local configuration

- `DungeonsAndLlamas/API/Secrets.swift` and downloaded model artifacts are local-only and Git-ignored.
- `Secrets` provides `host`, `authorization`, `username`, and `password`; see `README.md`.
- Treat ComfyUI workflow JSON as a server contract and validate changes against the configured service.

## Build and test

Use XcodeBuildMCP for app discovery, builds, launches, and device tests. Check `session_show_defaults` and `list_devices` before the first operation.

- Project: `DungeonsAndLlamas.xcodeproj`
- Scheme: `DungeonsAndLlamas`
- Preferred device: Sirius (`5771124D-00F3-5E80-8696-403B3FD55716`)
- Device platform: `iOS`
- Device DerivedData: `/private/tmp/DungeonsAndLlamasDerivedData-Sirius`

Prefer Sirius when connected, then another suitable physical device. Use a simulator when the task requires simulator tooling or no suitable device is available. Use `build_device` for build verification and `build_run_device` to install and launch. Do not invoke `xcodebuild` directly when XcodeBuildMCP is available.
Keep physical-device DerivedData outside Documents because File Provider attributes can break code signing. The app project currently has no iOS test target. 
Missing local secrets, models, device support, or remote services are prerequisites rather than code regressions.

## Working rules

1. Keep changes focused and preserve unrelated worktree changes.
2. Verify phone and iPad behavior when UI or navigation differs.
3. Run the narrowest relevant build or test and report unverified prerequisites.
4. Avoid hand-editing `project.pbxproj` unless the project structure must change.
