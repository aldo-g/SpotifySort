# SpotifySort — Architecture (1‑pager)

> Purpose: keep the app fast, tidy, and easy to reason about. Small, incremental changes only. This document freezes the layering rules we will enforce in PRs.

---

## Layering Rules (contracts)

**Layers:** `App/` → `UI/` → `Core/`

* **App/**

  * May depend on anything.
  * Bootstraps the app (composition root): dependency wiring, environment objects, app lifecycle, routing.
  * *Other layers must **not** import or reference `App/`.*

* **UI/**

  * Views, modifiers, and view-only components. Animation/gesture code lives here.
  * Talks to **Core** *only via* **ViewModels** and **Services**.
  * **Forbidden in UI:** raw HTTP, direct use of network clients, persistence writes, ad‑hoc business logic.

* **Core/**

  * Owns domain **Models**, **Services** (actors), **Network clients**, **Persistence**, **Playback**, and **Pure logic** utilities.
  * No SwiftUI or UIKit imports.
  * Exposes narrow protocols to UI/ViewModels.

### Allowed Dependency Direction

```
App  ─▶ UI  ─▶ Core
 ^            ▲
 └────────────┘ (App may talk to Core directly for wiring)
```

**Matrix (✔ allowed / ✖ forbidden)**

| From ↓ / To → | App | UI |                             Core |
| ------------- | --: | -: | -------------------------------: |
| **App**       |   ✔ |  ✔ |                                ✔ |
| **UI**        |   ✖ |  ✔ | ✔ (via ViewModels/Services only) |
| **Core**      |   ✖ |  ✖ |                                ✔ |

## Directory Roles

```
App/
  - SpotifySortApp.swift, RootView.swift, Router.swift, Theme.swift
UI/
  Components/, Screens/, ViewModels/
Core/
  Models/, Services/, Network/, Persistence/, Playback/, Logic/
```

## Communication & State

* **View ↔ ViewModel:** Inputs are intents (e.g., `swipe(.left)`), outputs are observable state.
* **ViewModel ↔ Services (Core):** Async calls; no direct HTTP.
* **Services ↔ Network/Persistence:** Services orchestrate paging, caching, and mutations; clients do the IO.
* **History/Undo:** Implemented in Core; UI triggers it but does not own it.

## Concurrency & Performance

* Services are `actor`s where shared mutable state exists (paging queues, caches).
* UI updates are `@MainActor`; heavy work (fetching, waveform generation) off main thread.
* Bounded memory: page sizes & deck top‑up thresholds are owned by Services.

## Error Handling

* No bare `print` in production pathways. Use a tiny `Log` wrapper.
* Surface user‑actionable errors to UI as typed states/messages; Core never presents alerts.

## Testing Guidance

* **Pure logic** (ranking, paging, dedupe) has unit tests in Core.
* Protocol seams for Network/Persistence to enable fakes in tests.
* UI snapshot/interaction tests are optional; prefer ViewModel tests.

## Naming & File Ownership

* **View** = `SomeScreen.swift`, **ViewModel** = `SomeScreenViewModel.swift` in `UI/ViewModels/`.
* **Service** = `XxxService.swift` in `Core/Services/` (single responsibility, async API).
* **Client** = `XxxClient.swift` in `Core/Network/`.
* **Store** (persistence/cache) = `XxxStore.swift` in `Core/Persistence/`.

## Forbidden

* UI importing `Core/Network` types directly.
* UI writing to persistence or `UserDefaults`.
* Core importing SwiftUI/UIKit or referencing `Router`/navigation.

## Enforcement (PR checklist)

* [ ] New code respects the dependency matrix.
* [ ] UI only talks to Core through ViewModels/Services.
* [ ] No SwiftUI/UIKit in Core; no network calls in UI.
* [ ] Added/changed Services expose async, testable APIs with protocols.
* [ ] Log/Errors follow the rules; no stray `print`.
* [ ] Smoke flow checklist passes locally.

---

**Acceptance**

* This file committed to repo root as `ARCHITECTURE.md`.
* CI lint/build passes.
* Team agrees to enforce via PR reviews and the checklist above.
