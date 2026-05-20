# TBS Technology — Linux Driver Build Script

An automated build script for [TBS Technology](https://www.tbsdtv.com/) PCIe DVB card drivers
on recent Linux kernels. Compiles drivers directly from the official
[tbsdtv/linux_media](https://github.com/tbsdtv/linux_media) repository (branch `latest`)
with all patches required to build cleanly on kernel 7.x.

> **Tested on:** Debian Testing (Trixie), kernel **7.0.7+deb14-amd64**  
> **Last verified:** May 2026

---

## Requirements

- Debian Testing (Trixie) or compatible
- Kernel **7.0+**
- Root access

Install build dependencies:

```bash
apt install build-essential git rsync python3 \
    linux-headers-$(uname -r) linux-headers-$(uname -r | sed 's/-[^-]*$//')-common
```

---

## Usage

```bash
# Clone the script repository
git clone https://github.com/home-debug/TBSonly.git
cd TBSonly

# Build and install
bash install_tbsdtv-smart.sh

# Dry-run (no files modified — shows what would be done)
bash install_tbsdtv-smart.sh --dry-run
```

The script will:
1. Clone or update the TBS source tree into `/usr/src/tbs-drivers`
2. Apply all kernel API compatibility patches automatically
3. Compile all supported modules
4. Ask before installing — modules are copied to `/lib/modules/$(uname -r)/updates/tbs/`
5. Run `depmod` so modules are available immediately after reboot

After installation verify with:

```bash
dmesg | grep -i tbs
lsmod | grep tbs
```

---

## How it works

The TBS source repository (`tbsdtv/linux_media`) is a fork of the full Linux media
tree and does not track upstream kernel API changes. This script patches the TBS
sources at build time to fix incompatibilities introduced in kernel 6.19+ and 7.0+,
without modifying the TBS repository itself. All patches are idempotent — safe to
run repeatedly on the same source tree.

Patched files:
- `dvb-core/dmxdev.c` — timer API, `dvb_vb2_fill_buffer`, `dvb_vb2_init`
- `dvb-core/dvb-pll.c` — IDA API
- `dvb-frontends/avl6882.h` — `IS_REACHABLE` guard
- `dvb-frontends/cxd2820r_core.c` — `gpio_chip.set` signature
- `dvb-frontends/mxl58x.c` — unused static functions

---

## Supported PCIe Cards — TBSECP3 bridge

Driver: `tbsecp3.ko`

| Model | Standard |
|-------|----------|
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

---

## Supported PCIe Cards — SAA716x bridge

Driver: `saa716x_tbs-dvb.ko`

| Model | Standard |
|-------|----------|
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

---

## Compiled frontend and tuner modules

Shared modules used across the cards above:

**Frontends** (`dvb-frontends/`):
`avl6882`, `cx24117`, `cxd2820r`, `cxd2878`, `dib9000`, `gx1133`, `gx1503`,
`isl6422`, `lgs8gl5`, `lnbh29`, `m88rs6060`, `mb86a16`, `mn88436`, `mn88443x`,
`mtv23x`, `mxl58x`, `s5h1432`, `si2168`, `si2183`, `stb0899`, `stid135`,
`stv0900`, `stv091x`, `tas2101`, `tas2971`, `tbs_priv`

**Tuners** (`tuners/`):
`av201x`, `si2157`, `stv6120`, `tda18212`

---

## Not yet supported (planned)

| Category | Cards | Status |
|----------|-------|--------|
| USB | TBS 5220, 5230, 5301, 5520, 5520SE, 5530, 5580, 5590, 5880, 5881, 5922SE, 5925, 5927, 5930, 5931, QBox, QBox2, QBox2CI, QBox22, QBoxS2 | Planned |
| PCIe Capture | TBS 6301, 6301T, 6302SE/T/X, 6304, 6304SE/T/X, 6308X, 6312X, 6322, 6324, 6331, 690a | Planned |

---

## Disclaimer

This script was created for **personal use** and is shared as-is, without any
warranty, support, or guarantee of fitness for any particular purpose.

**Use at your own risk.** The author accepts no responsibility for any damage,
data loss, system instability, hardware malfunction, or any other issue arising
from the use of this script or the compiled drivers. By using this script, you
agree that you do so entirely at your own risk.

**AI-generated content.** This script and its associated files were generated
with the assistance of an AI language model. They have been tested in a specific
environment (Debian Testing, kernel 7.0.x) but may not work correctly in other
configurations. Always review the code before running it on your system.

**Third-party intellectual property.** All TBS driver source code is the
intellectual property of [TBS Technology](https://www.tbsdtv.com/) and is
subject to their respective licenses. This script does not redistribute any TBS
source code — it only automates the process of cloning the official
[tbsdtv/linux_media](https://github.com/tbsdtv/linux_media) repository and
applying build-time patches to fix kernel API incompatibilities. No driver
functionality is altered.

This project is not affiliated with, endorsed by, or supported by TBS Technology
in any way. All product names and trademarks are the property of their respective
owners.
