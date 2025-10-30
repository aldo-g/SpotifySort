# App

The composition and root of the SpotifySort application.

This layer wires everything together — it does **not** contain domain logic or UI details.

## Responsibilities
- App entry point (`SpotifySortApp.swift`)
- Environment setup (`AuthManager`, `SpotifyAPI`, `Router`, `Theme`)
- Dependency injection for `Core` and `UI`
- Global navigation and app-wide state management
- SwiftUI environment configuration (e.g., `.environmentObject`)

## Rules
- `App/` may depend on **any** lower layer (Core, UI).
- No other layer should depend on `App/`.
- Keep files in this directory minimal and declarative — avoid logic that could live in `Core` or a `ViewModel`.

## Typical files
- `SpotifySortApp.swift` — main entry point
- `RootView.swift` — root container and dependency graph
- `Router.swift` / `Routes.swift` — navigation control
- `Theme.swift` — shared color and style definitions
