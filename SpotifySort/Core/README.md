# Core

Platform-agnostic logic and data. UI should **never** reach into `Core/Network` directly — go via `Core/Services` and `UI/ViewModels`.

- **Auth/** — Auth state & flows (e.g., PKCE), tokens, user session.
- **Models/** — Plain data types (`Track`, `Playlist`, etc.). No logic.
- **Network/** — Raw HTTP/Spotify client implementations.
- **Persistence/** — UserDefaults/Keychain/disk caches.
- **Playback/** — Audio playback + waveform generation/caching.
- **Logic/** — Pure, deterministic helpers (ranking, paging math, duplicate detection).
- **Services/** — Use-cases/actors that orchestrate Network + Persistence + Logic for the app.
