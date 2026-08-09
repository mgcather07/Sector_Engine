# Sector Engine

The single source of truth for Sector's shooting-conditions scoring — extracted
from the iOS app so iOS, Android, and any future client render identical results.

Pure Swift, no UI. Runs in the app today and (Phase 3) as a server behind an API.

## Layout
- `Sources/SectorEngine/Engine/` — the pure engine (aggregator, gates, factors, config, astronomy)
- `Sources/SectorEngine/Fetchers/` — weather / water / temp / alerts data sources
- `Sources/SectorEngine/Forecast/` — 7-night outlook + tonight's window + snapshot
- `Sources/SectorEngine/Support/` — value-type support (coordinate, lake directory, result shapes)
- `Sources/SectorEngineServer/` — thin Hummingbird HTTP server (`GET /conditions`, `GET /health`)
- `Sources/SectorEngine/API/` — `SectorEngineAPI`, the one public entry point every client calls
- `Tests/` — the engine's regression suite

## Build & test (macOS)
```
swift build
swift test
swift run SectorEngineServer      # serves http://localhost:8080
```
`CoreLocationShim.swift` supplies the coordinate/distance types on Linux, where
CoreLocation doesn't exist, so the exact same engine compiles for the server.

## Deploy (Cloud Run)
Runs in the same GCP project as Firebase (`sector-9393c`). No local Docker needed —
Cloud Build compiles the `Dockerfile` server-side.
```
# one-time
gcloud auth login
gcloud config set project sector-9393c
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com
# every deploy
./deploy.sh
```
Change the engine → `./deploy.sh` → both phones pick up the new numbers on their
next call. No App Store release required.

## Roadmap
- **Phase 0 ✅** — engine extracted, builds standalone, 74/74 tests green.
- **Phase 1 ✅** — thin HTTP server (`/conditions`, `/health`).
- **Phase 2 ✅** — iOS A/B: app's local engine == server for the same coordinate.
- **Phase 3 ▶** — Linux-ready + Cloud Run deploy (this commit).
- **Phase 4** — iOS points at the live URL behind a flag; retire the in-app engine.
- **Phase 5** — Android points at the live URL; delete the Kotlin engine.
- **Phase 6** — Firebase Remote Config drives the tuning knobs (zero-deploy tuning).
