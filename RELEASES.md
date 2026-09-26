# Release Notes

## 2026-09-27-0001

### Fixes
- **rsync `mkdir ... include/media failed: File exists`** on header trees that ship `include/media` (or `uapi`) as a file/symlink: the entry is now detected, replaced with a real directory, and the build proceeds (reported on a non-Debian kernel/headers tree)

## v20-dev (2026-09-20) — DEVELOPMENT / UNSTABLE

> ⚠️ **This is a development version.** It contains experimental features and may not work correctly on all systems. Use the `main` branch for stable releases.

### New features
- **Family-filtered build** — when hardware is detected, only relevant targets are built (e.g. no `usb/dvb-usb` without USB cards, no `pci/saa716x` without SAA716x). Frontend/tuner/core dirs are always built (shared)
- **Ubuntu 26.04 compatibility** (user report): fallback detection for `linux-headers-x.y.z-a` (no `-generic` suffix) when `linux-headers-*-common` is absent; optional cleanup of stale modules in `/lib/modules/*/updates/` before install (prevents version-mismatch errors on module load)
- **USB tuner support** — added `usb/dvb-usb` target with 20 TBS USB modules: 5220, 5230, 5520, 5520SE, 5530, 5580, 5590, 5880, 5881, 5922SE, 5925, 5927, 5930, 5931, 5301, QBox, QBox2, QBox2CI, QBox22, QBoxS2. All object names verified against the TBS tree (`tbs-qbox.c` etc., not `tbsqbox.c`)
- **Hardware detection** — parses the TBS source tree (`tbsecp3-core.c`, `saa716x_budget.c`) to detect installed PCIe cards and displays them before build; zero hardcoded maps - works with any new card TBS adds

### Changes
- Build core is byte-identical to `main` (v18); only `detect_tbs_cards` is added
