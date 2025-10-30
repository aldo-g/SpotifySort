# UI

Declarative SwiftUI. Views are **thin**; ViewModels hold state & call `Core/Services`.

- **Screens/** — Route-level screens (Sort, Login, History, etc.).
- **Components/** — Reusable UI pieces (SwipeCard, RemoteImage, etc.).
- **ViewModels/** — Screen/component state + orchestration (no raw HTTP here).
