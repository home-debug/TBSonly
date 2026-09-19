# TBSonly

> **⚠️ DEVELOPMENT VERSION**  
> This is the `dev` branch. It contains experimental features and may not work correctly. For stable releases, check the `main` branch or tagged releases.

Out-of-tree driver installer for **TBS DVB tuners** on modern Linux kernels (7.0+).

This project was created with the help of **Claude AI (Anthropic)**.  
The generated code is verified and tested by a human.

## Supported cards

### PCIe — TBSECP3 bridge

Driver: `tbsecp3.ko`

| Model | Standard |
|---|---|
| TBS 6205 | DVB-T/T2/C |
| TBS 6205SE | DVB-T/T2/C, ISDB-T/C, ATSC 1.0 |
| TBS 6209 | DVB-T/T2/C/C2, ISDB-T — Octa |
| TBS 6209SE | DVB-T/T2/C/C2, ISDB-T/C, ATSC — Octa |
| TBS 6216 | DVB-T/T2/C, ISDB-T, ATSC 1.0 — Hex |
| TBS 6281TD | DVB-T/T2/C, ISDB-T/C, ATSC 1.0 |
| TBS 6290SE | DVB-T/T2/C + 2×CI |
| TBS 6504 | DVB-S/S2/S2X/T/T2/C/C2/ISDB-T |
| TBS 6504H | Quad DVB-S/S2x + Quad DVB-T/T2/C, ISDB-T/C, ATSC 1.0 |
| TBS 6508 | DVB-S/S2/S2X/T/T2/C (QAM-A/B/C)/C2/ISDB-T |
| TBS 6514 | DTMB — Quad |
| TBS 6522 | DVB-S/S2/S2X/T/T2/C/C2/ISDB-T |
| TBS 6522H | Dual DVB-S/S2x + Dual DVB-T/T2/C, ISDB-T/C, ATSC 1.0 |
| TBS 6528 | DVB-S/S2/S2X/T/T2/C/C2/ISDB-T + CI |
| TBS 6590SE | DVB-S/S2/S2X/T/T2/C/C2 + 2×CI |
| TBS 6704 | ATSC/QAM-B — Quad |
| TBS 6814 | ISDB-T — Quad |
| TBS 6902 | DVB-S/S2 |
| TBS 6902SE | DVB-S/S2/S2x |
| TBS 6903 | DVB-S/S2 |
| TBS 6904 | DVB-S/S2 |
| TBS 6904se | DVB-S/S2/S2x |
| TBS 6904x | DVB-S/S2/S2X |
| TBS 6905 | DVB-S/S2 |
| TBS 6908 | DVB-S/S2 |
| TBS 6909 | DVB-S/S2 |
| TBS 6909SE | DVB-S/S2/S2x — Octa |
| TBS 6910 | DVB-S/S2 + 2×CI |
| TBS 6910SE | DVB-S/S2/S2x + 2×CI |
| TBS 6910X | DVB-S/S2/S2X + 2×CI |
| TBS 6916 | DVB-S/S2/S2X — Octa |
| TBS 7230 | DVB-T/T2/C/C2, ISDB-T/C, ATSC — Octa |
| TBS 7901 | DVB-S/S2/S2x |

### PCIe — SAA716x bridge

Driver: `saa716x_tbs-dvb.ko`

| Model | Standard |
|---|---|
| TBS 6220 | DVB-T |
| TBS 6221 | DVB-T |
| TBS 6280 | DVB-T/T2/C — Dual |
| TBS 6281 | DVB-T/T2/C — Dual |
| TBS 6284 | DVB-T/T2/C — Quad |
| TBS 6285 | DVB-T/T2/C — Quad |
| TBS 6290 | DVB-T/T2/C — Dual |
| TBS 6922 | DVB-S/S2 |
| TBS 6923 | DVB-S/S2 |
| TBS 6925 | DVB-S/S2 |
| TBS 6982 | DVB-S/S2 — Dual |
| TBS 6982SE | DVB-S/S2 — Dual |
| TBS 6983 | DVB-S/S2 — Dual |
| TBS 6984 | DVB-S/S2 — Quad |
| TBS 6985 | DVB-S/S2 — Quad |
| TBS 6991 | DVB-S/S2 — Dual + CI |
| TBS 6991SE | DVB-S/S2 — Dual + CI |
| TBS 7220 | DVB-T |
| Technotrend TT4100 | DVB-S/S2 (TBS6922 clone) |

### PCIe — modulators (TBSMOD)

Driver: `tbsmod.ko` / `tbsdtv` modulator targets (`pci/tbsmod`)

| Model | Type |
|---|---|
| TBS 6301, 6301SE | DVB-S/S2 modulator |
| TBS 6302SE/X/T/RV | DVB-S/S2 modulator |
| TBS 6304/X/T/RV | DVB-S/S2 modulator |
| TBS 6308/X | DVB-S/S2 modulator |
| TBS 6312X | DVB-S/S2 modulator |
| TBS 6322, 6324 | ISDB-T modulator |
| TBS 6331 | DVB-C modulator |

### USB

Driver: `dvb-usb-*` family (`usb/dvb-usb` target)

| Model | Type |
|---|---|
| TBS 5220 | DVB-T/T2/C |
| TBS 5520 | DVB-S/S2/T/T2/C |
| TBS 5520SE | DVB-S/S2 + DVB-T/T2/C |
| TBS 5580 | DVB-S/S2 + DVB-T/T2/C |
| TBS 5590 | DVB-S/S2 + DVB-T/T2/C |
| TBS 5880, 5881 | DVB-T/T2/C + ISDB-T |
| TBS 5925 | DVB-S/S2 |
| TBS 5930 | DVB-S/S2X |
| TBS 5301 | DVB-S/S2 |
| TBS QBox | DVB-S/S2 |
| TBS QBox2 | DVB-S/S2 |
| TBS QBox2CI | DVB-S/S2 + CI |
| TBS QBox22 | DVB-S/S2 |
| TBS QBoxS2 | DVB-S/S2 |

### Compiled frontend and tuner modules

Shared modules used across the cards above:

**Frontends** (`dvb-frontends/`):
`avl6882`, `cx24117`, `cxd2820r`, `cxd2878`, `dib9000`, `gx1133`, `gx1503`,
`isl6422`, `lgs8gl5`, `lnbh29`, `m88rs6060`, `mb86a16`, `mn88436`, `mn88443x`,
`mtv23x`, `mxl58x`, `s5h1432`, `si2168`, `si2183`, `stb0899`, `stid135`,
`stv0900`, `stv091x`, `tas2101`, `tas2971`, `tbs_priv`

**Tuners** (`tuners/`):
`av201x`, `si2157`, `stv6120`, `tda18212`

### Not yet supported (planned)

| Category | Cards | Status |
|---|---|---|
| USB | TBS 5230, 5530, 5922SE, 5927, 5931 | Planned — driver sources exist in the TBS tree, not enabled in the build yet |
| USB | TBS 5920, 5922 | Not supported — no driver sources exist in the TBS tree at all |
| PCIe Capture | TBS 6301T, 6302T, 690a | Planned |

> **Note:** the card tables above are maintained manually. The script itself
> detects your actual hardware automatically from the TBS source tree at
> build time — the table is for reference only.

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

# Use specific TBS branch (validated against origin; note: tbsdtv/linux_media
# has only 'latest', 'master' and 'gse' - there is no 'testing' branch)
sudo bash install_tbsdtv-smart.sh --branch master

# Or via environment variable
TBS_BRANCH=latest sudo bash install_tbsdtv-smart.sh
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
2. **Detects its own branch** (`main`/`dev`) and shows it in the header; TBS sources default to `latest` (the only maintained branch)
3. **Validates the TBS branch against origin** (`latest`/`master`/`gse` exist; `testing` does not) and falls back to `latest` instead of failing
4. **Checks for updates** — if the `dev` branch on origin is newer than your current checkout, the script offers to switch (with a clear warning that `dev` may not work)
5. **Parses TBS source tree** to detect which PCIe cards are physically present in your system (cosmetic — all modules are still built for compatibility)
6. **Patches kernel API mismatches** via `kernel-patches.sh` (idempotent — safe to re-run)
7. **Creates isolated build environment** with headers from both distro kernel and TBS repo
8. **Compiles only TBS-specific modules** (dvb-core, frontends, tuners, PCIe bridges, USB tuners) — not the entire kernel tree
9. **Installs to `/lib/modules/*/updates/tbs/`** and runs `depmod`

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
