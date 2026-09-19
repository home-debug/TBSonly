# Release Notes

## v20-dev (2026-09-19) — DEVELOPMENT / UNSTABLE

> ⚠️ **This is a development version.** It contains experimental features and may not work correctly on all systems. Use the `main` branch for stable releases.

### New features
- **Script branch detection** — the installer detects which branch of this repository it runs from (`main` / `dev` / detached / zip download) and shows it in the startup header and log
- **Automatic TBS branch mapping** — running from `dev` defaults to the TBS `testing` branch, running from `main` (or unknown) defaults to `latest`; still overridable with `--branch`, `--testing` or `TBS_BRANCH=...`
- **Update check with dev warning** — on startup the script fetches origin and compares your checkout against `origin/dev`; if `dev` is ahead, it offers to switch, with a clear warning that `dev` is a development version that may not work; on confirmation it checks out `dev`, pulls and re-runs itself
  - `--dry-run` only prints the switch commands
  - non-interactive shells (cron/pipe) get manual instructions instead of a prompt

### Changes
- Header log line now distinguishes `TBS branch:` (tbsdtv/linux_media) from `Script:` (this repo)
- README: full clone-and-checkout instructions in the Usage section, "How it works" updated

### Fixes
- `--branch NAME` argument parsing fixed (previously the branch name was consumed incorrectly and could trigger "Unknown argument")

---

## v19-dev (2025-09-19) — DEVELOPMENT / UNSTABLE

> ⚠️ **This is a development version.** It contains experimental features and may not work correctly on all systems. Use the `main` branch for stable releases.

### New features
- **Root privilege check** — script exits early with clear message if not run as root
- **Cross-distro kernel source auto-detection** — automatically finds kernel headers on Debian/Ubuntu, Fedora/RHEL, Arch, and openSUSE (with install hints if missing)
- **Hardware detection (cosmetic)** — parses TBS source tree (`tbsecp3-core.c`, `saa716x_budget.c`) to detect installed PCIe cards and displays them before build; zero hardcoded maps — works with any new card TBS adds
- **USB tuner support** — added `usb/dvb-usb` target with all TBS USB tuners: 5220, 5520SE, 5580, 5590, 5880, 5881, 5920, 5922, 5925, 5930, 5301, QBox series
- **Parallel compilation** — automatically uses all CPU cores (`-j$(nproc)`)
- **TBS branch selection** — `--branch NAME`, `--testing`, or `TBS_BRANCH=...` env variable to choose which TBS repo branch to clone

### Changes
- `python3` added to required dependencies (hardware detection)
- `kernel-patches.sh` handling unchanged (still idempotent)
- Build targets now include: `dvb-core`, `dvb-frontends`, `tuners`, `pci/saa716x`, `pci/tbsecp3`, `pci/tbsci`, `pci/tbsmod`, `usb/dvb-usb`

### Fixes
- Proper cleanup of USB Makefile backup (`usb/dvb-usb/Makefile.orig`)
- Better error messages when kernel headers are missing (distro-specific install commands)
- **Ubuntu headers detection**: now correctly finds `linux-headers-x.y.z` (without `-common` suffix) used by Ubuntu
- **Arch-specific headers priority**: uses arch-specific headers tree first (contains generated/autoconf headers), falls back to common headers or KBUILD
- **Stale modules cleanup**: optional prompt to remove old modules from `/lib/modules/*/updates/` before installation (prevents version mismatch errors)

---

## v18 (2025-08-06)

- Initial public release
- English translations
- Git verbose progress (`--progress`)
- Pause after each major step
- Removed hardcoded `MISSING_DEFINES` fallback
- Minimum kernel: 7.0+
- Isolated build directory with `rsync`
- `Module.symvers` chaining for out-of-tree dependencies
- Idempotent kernel API patches via `kernel-patches.sh`
