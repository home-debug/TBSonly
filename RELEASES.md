# Release Notes

## v19 (2025-09-19)

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
