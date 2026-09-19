# TBSonly

> **⚠️ DEVELOPMENT VERSION**  
> This is the `dev` branch. It contains experimental features and may not work correctly. For stable releases, check the `main` branch or tagged releases.

Out-of-tree driver installer for **TBS DVB tuners** on modern Linux kernels (7.0+).

This project was created with the help of **Claude AI (Anthropic)**.  
The generated code is verified and tested by a human.

## Supported cards

### PCIe

| Model | Type | Status |
|---|---|---|
| TBS 6205, 6209, 6216, 6281SE/TD | DVB-T/T2/C | Supported |
| TBS 6290SE/TD | DVB-T/T2/C + ISDB-T | Supported |
| TBS 6522/H, 6528 | DVB-S/S2 + DVB-T/T2/C | Supported |
| TBS 6590/SE | DVB-S/S2 + DVB-T/T2/C | Supported |
| TBS 6902/SE, 6903/X, 6904/X/SE, 6905, 6908 | DVB-S/S2 | Supported |
| TBS 6909/X/SE, 6910/SE/X, 6912, 6916 | DVB-S/S2 + CI | Supported |
| TBS 6704 | ISDB-T | Supported |
| TBS 6301/SE, 6302SE/X/T/RV, 6304/X/T/RV, 6308/X, 6312X | DVB-S/S2 modulator | Supported |
| TBS 6322, 6324 | ISDB-T modulator | Supported |
| TBS 6331 | DVB-C modulator | Supported |
| TBS 6504/H, 6508 | DVB-S/S2X + DVB-T/T2/C | Supported |
| TBS 6814, 6514 | DVB-T/T2/C | Supported |
| TBS 7230 | ATSC | Supported |
| TBS 7901 | DVB-S/S2 + CI | Supported |
| TBS 6280, 6281, 6284, 6285 | DVB-T/T2/C (SAA716x) | Supported |
| TBS 6220, 6221 | DVB-T/T2/C (SAA716x) | Supported |
| TBS 6922, 6923, 6925 | DVB-S/S2 (SAA716x) | Supported |
| TBS 6982/SE, 6983, 6984, 6985 | DVB-S/S2 (SAA716x) | Supported |
| TBS 6991/SE | DVB-S/S2 + CI (SAA716x) | Supported |
| TBS 7220 | DVB-S/S2 (SAA716x) | Supported |
| Technotrend TT4100 | DVB-S/S2 (TBS6922 clone) | Supported |

### USB

| Model | Type | Status |
|---|---|---|
| TBS 5220 | DVB-T/T2/C | Supported |
| TBS 5520SE | DVB-S/S2 + DVB-T/T2/C | Supported |
| TBS 5580 | DVB-S/S2 + DVB-T/T2/C | Supported |
| TBS 5590 | DVB-S/S2 + DVB-T/T2/C | Supported |
| TBS 5880, 5881 | DVB-T/T2/C + ISDB-T | Supported |
| TBS 5920, 5922, 5925 | DVB-S/S2 | Supported |
| TBS 5930 | DVB-S/S2X | Supported |
| TBS 5301 | DVB-S/S2 | Supported |
| TBS QBox series | DVB-S/S2 | Supported |

## Requirements

- Linux kernel **7.0+**
- Root privileges (the script checks this automatically)
- Installed kernel headers matching your running kernel
- Dependencies: `git`, `make`, `gcc`, `rsync`, `python3`

### Installing kernel headers

| Distribution | Command |
|---|---|
| Debian / Ubuntu | `apt install linux-headers-$(uname -r)` |
| Fedora / RHEL | `dnf install kernel-devel-$(uname -r)` |
| Arch / Manjaro | `pacman -S linux-headers` |
| openSUSE | `zypper in kernel-default-devel`|

## Usage

```bash
# Clone the repository and switch to the dev branch
git clone https://github.com/home-debug/TBSonly.git
cd TBSonly
git checkout dev

# Standard build (uses all CPU cores automatically)
sudo bash install_tbsdtv-smart.sh

# Dry-run (shows what would be done without modifying anything)
sudo bash install_tbsdtv-smart.sh --dry-run

# Use TBS testing branch instead of latest
sudo bash install_tbsdtv-smart.sh --testing

# Use specific TBS branch
sudo bash install_tbsdtv-smart.sh --branch main

# Or via environment variable
TBS_BRANCH=testing sudo bash install_tbsdtv-smart.sh
```

If you already have the repository cloned, update it before building:

```bash
cd TBSonly
git fetch origin
git checkout dev
git pull origin dev
```

## How it works

1. **Auto-detects your distribution** and locates kernel build sources (`/lib/modules/*/build`, `/usr/src/kernels/*`, etc.)
2. **Detects its own branch** (`main`/`dev`) and picks the matching TBS source branch (`latest`/`testing`) automatically
3. **Checks for updates** — if the `dev` branch on origin is newer than your current checkout, the script offers to switch (with a clear warning that `dev` may not work)
4. **Parses TBS source tree** to detect which PCIe cards are physically present in your system (cosmetic — all modules are still built for compatibility)
5. **Patches kernel API mismatches** via `kernel-patches.sh` (idempotent — safe to re-run)
6. **Creates isolated build environment** with headers from both distro kernel and TBS repo
7. **Compiles only TBS-specific modules** (dvb-core, frontends, tuners, PCIe bridges, USB tuners) — not the entire kernel tree
8. **Installs to `/lib/modules/*/updates/tbs/`** and runs `depmod`

## Files

| File | Purpose |
|---|---|
| `install_tbsdtv-smart.sh` | Main installer script |
| `kernel-patches.sh` | API compatibility patches for new kernels |
| `README.md` | This file |
| `RELEASES.md` | Changelog |
| `LICENSE` | MIT License |

## Tested on

- Debian 13 (Trixie) — kernel 7.x
- Ubuntu 26.04
- Fedora 42
- Arch Linux
- openSUSE Tumbleweed

## Disclaimer

This is an **unofficial** installer. TBS does not maintain the `linux_media` tree for modern kernels. This script bridges that gap by applying community patches and building out-of-tree. Use at your own risk.

## License

This project is released under the **MIT License**. You are free to use, modify, distribute, and sublicense it, including for commercial purposes. See `LICENSE` for full text.
