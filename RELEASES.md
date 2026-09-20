# Release Notes

## v20-dev (2026-09-20) — DEVELOPMENT / UNSTABLE

> ⚠️ **This is a development version.** It contains experimental features and may not work correctly on all systems. Use the `main` branch for stable releases.

### New features
- **Hardware detection** — parses the TBS source tree (`tbsecp3-core.c`, `saa716x_budget.c`) to detect installed PCIe cards and displays them before build; zero hardcoded maps - works with any new card TBS adds

### Changes
- Build core is byte-identical to `main` (v18); only `detect_tbs_cards` is added
