# Sector Engine

The single source of truth for Sector's shooting-conditions scoring — extracted
from the iOS app so iOS, Android, and any future client render identical results.

Pure Swift, no UI. Runs in the app today and (Phase 3) as a server behind an API.

## Layout
- `Sources/SectorEngine/Engine/` — the pure engine (aggregator, gates, factors, config, astronomy)
- `Sources/SectorEngine/Fetchers/` — weather / water / temp / alerts data sources
- `Sources/SectorEngine/Forecast/` — 7-night outlook + tonight's window + snapshot
- `Sources/SectorEngine/Support/` — value-type support (coordinate, lake directory, result shapes)
- `Tests/` — the engine's regression suite

## Build & test
```
swift build
swift test
```

## Status
Phase 0 — engine extracted, builds standalone, full test suite green (74/74).
Next: a thin HTTP server target (`/conditions`), then Cloud Run deploy.
