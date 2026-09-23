#!/usr/bin/env bash
# install_tbsdtv-smart v18
# Changes from v17/v19:
#   - All messages translated to English
#   - Git output: verbose progress (--progress flag)
#   - Pause after each major step (press Enter to continue)
#   - Removed fallback MISSING_DEFINES hardcoded list
#   - Minimum kernel: 7.0+
set -euo pipefail

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --help|-h) echo "Usage: $0 [--dry-run]"; exit 0 ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TBS_REPO="https://github.com/tbsdtv/linux_media.git"
TBS_BRANCH="latest"
SRC="/usr/src/tbs-drivers"
KVER="$(uname -r)"
KMAJ=$(echo "$KVER" | cut -d. -f1)
KMIN=$(echo "$KVER" | cut -d. -f2)
KBUILD="/lib/modules/${KVER}/build"
# ===========================================================================
# Location-based kernel source detection
# Tries standard paths in order, regardless of distribution.
# ===========================================================================
KBUILD=""
for candidate in \
    "/lib/modules/${KVER}/build" \
    "/usr/src/kernels/${KVER}" \
    "/usr/src/linux-headers-${KVER}" \
    "/usr/src/linux-${KVER}"; do
    [[ -d "$candidate" ]] && { KBUILD="$candidate"; break; }
done

# Headers source tree (rsync into BUILD_DIR) - also location-based
KHEADERS_COMMON=""
for candidate in \
    "/usr/src/linux-headers-${KVER}" \
    "/usr/src/kernels/${KVER}" \
    "/usr/src/linux-${KVER}"; do
    [[ -d "$candidate/include" ]] && { KHEADERS_COMMON="$candidate"; break; }
done
# Debian/Ubuntu split headers: -common package
if [[ -z "$KHEADERS_COMMON" ]]; then
    KHEADERS_COMMON=$(find /usr/src -maxdepth 1 -name "linux-headers-*-common" | sort -V | tail -1)
fi
# Ubuntu variant: linux-headers-x.y.z-a (no -generic suffix)
if [[ -z "$KHEADERS_COMMON" || ! -d "$KHEADERS_COMMON" ]]; then
    KVER_BASE="${KVER%%-*}"
    KHEADERS_COMMON=$(find /usr/src -maxdepth 1 -name "linux-headers-${KVER_BASE}" -type d | sort -V | tail -1)
fi

detect_distro

[[ -d "$KBUILD" ]] || {
    case "$DISTRO" in
        debian|ubuntu|linuxmint|pop) hint="apt install linux-headers-${KVER}" ;;
        fedora|rhel|centos|almalinux|rocky) hint="dnf install kernel-devel-${KVER}" ;;
        arch|manjaro) hint="pacman -S linux-headers" ;;
        opensuse*|suse*) hint="zypper in kernel-default-devel=${KVER%-default}" ;;
        gentoo) hint="emerge sys-kernel/gentoo-sources" ;;
        *) hint="install kernel headers for ${KVER}" ;;
    esac
    error "Kernel build directory not found: $KBUILD\n  Try: $hint"
}
[[ -n "$KHEADERS_COMMON" && -d "$KHEADERS_COMMON" ]] || error "Kernel headers source not found for ${KVER}"

H1="$KHEADERS_COMMON/include/media/dvb_frontend.h"
H2="$KHEADERS_COMMON/include/uapi/linux/dvb/frontend.h"
MF="$SRC/drivers/media/dvb-frontends/Makefile"
MF_SAA="$SRC/drivers/media/pci/saa716x/Makefile"
MF_TBS="$SRC/drivers/media/pci/tbsecp3/Makefile"
MF_TUNERS="$SRC/drivers/media/tuners/Makefile"
STALE=0
# Check only kernel headers - TBS Makefiles are not restored after successful run
for f in "${H1}.orig" "${H2}.orig"; do
    [[ -f "$f" ]] && { warn "Leftover from interrupted run: $f"; STALE=1; }
done
if [[ "$STALE" -eq 1 ]]; then
    read -rp "  Restore .orig files and continue? [y/N]: " ANS
    [[ "${ANS,,}" == "y" ]] || error "Aborted. Check .orig files manually."
    cleanup; trap cleanup EXIT
fi
info "Environment OK."

pause

step "Fetching/updating TBS sources -> $SRC"
if [[ "$DRY_RUN" -eq 0 ]]; then
    if [[ -d "$SRC/.git" ]]; then
        info "Updating existing repository..."
        git -C "$SRC" fetch --progress origin              2>&1 | tee -a "$LOG"
        git -C "$SRC" checkout "$TBS_BRANCH"               2>&1 | tee -a "$LOG"
        git -C "$SRC" pull --progress origin "$TBS_BRANCH" 2>&1 | tee -a "$LOG"
    else
        info "Cloning TBS repository (this may take a few minutes)..."
        git clone --progress --depth=1 --branch "$TBS_BRANCH" "$TBS_REPO" "$SRC" 2>&1 | tee -a "$LOG"
    fi
    info "Sources ready in: $SRC"
else
    info "[DRY-RUN] Skipping git."
fi
pause

# NOTE: apply_kernel_api_patches must run before BUILD_DIR and before overwriting TBS Makefiles
apply_kernel_api_patches
[[ "$DRY_RUN" -eq 1 ]] && { info "Dry-run complete."; exit 0; }
pause

detect_tbs_cards

# Filter TARGET_DIRS by detected hardware families (empty = build all)
if [[ -n "$DETECTED_FAMILIES" ]]; then
    info "Detected families:$DETECTED_FAMILIES - filtering build targets"
    FILTERED=()
    for d in "${TARGET_DIRS[@]}"; do
        keep=0
        case "$d" in
            "usb/dvb-usb")
                [[ "$DETECTED_FAMILIES" == *"USB"* ]] && keep=1 ;;
            "pci/tbsecp3"|"pci/tbsmod")
                [[ "$DETECTED_FAMILIES" == *"TBSECP3"* ]] && keep=1 ;;
            "pci/saa716x")
                [[ "$DETECTED_FAMILIES" == *"SAA716x"* ]] && keep=1 ;;
            *)
                keep=1 ;;  # dvb-frontends, tuners, dvb-core always needed
        esac
        [[ "$keep" -eq 1 ]] && FILTERED+=("$d")
    done
    TARGET_DIRS=("${FILTERED[@]}")
    info "Build targets: ${TARGET_DIRS[*]}"
fi

pause

step "Creating isolated build directory"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/include"
rsync -a --info=progress2 "$KHEADERS_COMMON/include/" "$BUILD_DIR/include/" 2>&1 | tee -a "$LOG"
rsync -a "$SRC/include/media/"  "$BUILD_DIR/include/media/"  2>&1 | tee -a "$LOG"
rsync -a "$SRC/include/uapi/"   "$BUILD_DIR/include/uapi/"   2>&1 | tee -a "$LOG"
mkdir -p "$BUILD_DIR/include/media/tuners"
if [[ -d "$SRC/drivers/media/tuners" ]]; then
    find "$SRC/drivers/media/tuners" -name "*.h" \
        -exec cp {} "$BUILD_DIR/include/media/tuners/" \; 2>/dev/null || true
    cp "$SRC/drivers/media/tuners/tuner-i2c.h" "$BUILD_DIR/include/" 2>/dev/null || true
fi
[[ -d "$SRC/drivers/media/usb" ]] && \
    find "$SRC/drivers/media/usb" -name "*.h" \
        -exec cp {} "$BUILD_DIR/include/" \; 2>/dev/null || true
info "Build directory ready."

step "Temporarily patching kernel headers"
cp "$H1" "${H1}.orig" && cp "$SRC/include/media/dvb_frontend.h" "$H1"
info "  Patched: dvb_frontend.h"
cp "$H2" "${H2}.orig" && cp "$SRC/include/uapi/linux/dvb/frontend.h" "$H2"
info "  Patched: frontend.h (uapi)"

step "Detecting missing CONFIG_DVB_* defines"
KERNEL_CONFIG="/boot/config-${KVER}"
MISSING_DEFINES=""
if [[ -f "$KERNEL_CONFIG" ]]; then
    while IFS= read -r cfg; do
        grep -q "^${cfg}=" "$KERNEL_CONFIG" 2>/dev/null && continue
        MISSING_DEFINES+=" -D${cfg}=1"
        info "  Missing: ${cfg}"
    done < <(
        grep -h "obj-\$(CONFIG_DVB" \
            "$SRC/drivers/media/dvb-frontends/Makefile" \
            "$SRC/drivers/media/dvb-core/Makefile" \
            2>/dev/null | grep -oP 'CONFIG_DVB_\w+' | sort -u
    )
    [[ -z "$MISSING_DEFINES" ]] \
        && info "All CONFIG_DVB_* defines present." \
        || info "Added $(echo "$MISSING_DEFINES" | wc -w) missing defines."
else
    warn "Kernel config not found: $KERNEL_CONFIG"
    warn "CONFIG_DVB_* defines will not be verified. Build may fail."
fi

step "Creating minimal Makefile for dvb-frontends"
cp "$MF" "${MF}.orig"
cat > "$MF" << 'MAKEFILE'
ccflags-y += -I$(srctree)/drivers/media/tuners/
cxd2820r-objs := cxd2820r_core.o cxd2820r_c.o cxd2820r_t.o cxd2820r_t2.o
drxd-objs     := drxd_firm.o drxd_hard.o
drxk-objs     := drxk_hard.o
stb0899-objs  := stb0899_drv.o stb0899_algo.o
stv0900-objs  := stv0900_core.o stv0900_sw.o
# TBS-exclusive frontends
obj-m += avl6882.o
obj-m += cxd2878.o
obj-m += gx1133.o
obj-m += gx1503.o
obj-m += m88rs6060.o
obj-m += mn88436.o
obj-m += mn88443x.o
obj-m += mtv23x.o
obj-m += mxl58x.o
obj-m += stid135/
obj-m += stv091x.o
obj-m += tas2101.o
obj-m += tas2971.o
obj-m += tbs_priv.o
# Frontends also present in kernel but TBS has modified versions
obj-m += cx24117.o
obj-m += cxd2820r.o
obj-m += dib9000.o
obj-m += isl6422.o
obj-m += lgs8gl5.o
obj-m += lnbh29.o
obj-m += mb86a16.o
obj-m += s5h1432.o
obj-m += si2168.o
obj-m += si2183.o
obj-m += stb0899.o
obj-m += stv0900.o
MAKEFILE
info "dvb-frontends Makefile ready."

step "Creating minimal Makefile for tuners"
cp "$MF_TUNERS" "${MF_TUNERS}.orig"
cat > "$MF_TUNERS" << 'MAKEFILE'
ccflags-y += -I$(srctree)/drivers/media/dvb-frontends/
# TBS-specific tuners (not in distro kernel or TBS has modified versions)
obj-m += av201x.o
obj-m += si2157.o
obj-m += stv6120.o
obj-m += tda18212.o
MAKEFILE
info "tuners Makefile ready."

step "Creating minimal Makefile for pci/saa716x"
cp "$MF_SAA" "${MF_SAA}.orig"
cat > "$MF_SAA" << 'MAKEFILE'
ccflags-y += -Idrivers/media/tuners
ccflags-y += -Idrivers/media/dvb-core
ccflags-y += -Idrivers/media/dvb-frontends
ccflags-y += -Idrivers/media/dvb-frontends/stid135
saa716x_core-objs := saa716x_pci.o saa716x_i2c.o saa716x_cgu.o saa716x_msi.o \
                     saa716x_dma.o saa716x_vip.o saa716x_aip.o saa716x_phi.o  \
                     saa716x_boot.o saa716x_fgpi.o saa716x_adap.o saa716x_gpio.o \
                     saa716x_greg.o saa716x_rom.o saa716x_spi.o
saa716x_tbs-dvb-objs := saa716x_budget.o tbsci-i2c.o tbs-ci.o
obj-m += saa716x_core.o
obj-m += saa716x_tbs-dvb.o
MAKEFILE
info "saa716x Makefile ready."

step "Creating minimal Makefile for usb/dvb-usb"
cp "$SRC/drivers/media/usb/dvb-usb/Makefile" "${SRC}/drivers/media/usb/dvb-usb/Makefile.orig" 2>/dev/null || true
cat > "$SRC/drivers/media/usb/dvb-usb/Makefile" << 'MAKEFILE'
ccflags-y += -Idrivers/media/dvb-core
ccflags-y += -Idrivers/media/dvb-frontends
ccflags-y += -Idrivers/media/tuners
dvb-usb-tbs5220-objs := tbs5220.o
dvb-usb-tbs5230-objs := tbs5230.o
dvb-usb-tbs5520-objs := tbs5520.o
dvb-usb-tbs5520se-objs := tbs5520se.o
dvb-usb-tbs5530-objs := tbs5530.o
dvb-usb-tbs5580-objs := tbs5580.o
dvb-usb-tbs5590-objs := tbs5590.o
dvb-usb-tbs5880-objs := tbs5880.o
dvb-usb-tbs5881-objs := tbs5881.o
dvb-usb-tbs5922se-objs := tbs5922se.o
dvb-usb-tbs5925-objs := tbs5925.o
dvb-usb-tbs5927-objs := tbs5927.o
dvb-usb-tbs5930-objs := tbs5930.o
dvb-usb-tbs5931-objs := tbs5931.o
dvb-usb-tbs5301-objs := tbs5301.o
dvb-usb-tbsqbox-objs := tbs-qbox.o
dvb-usb-tbsqbox2-objs := tbs-qbox2.o
dvb-usb-tbsqbox2ci-objs := tbs-qbox2ci.o
dvb-usb-tbsqbox22-objs := tbs-qbox22.o
dvb-usb-tbsqboxs2-objs := tbs-qboxs2.o
obj-m += dvb-usb-tbs5220.o
obj-m += dvb-usb-tbs5230.o
obj-m += dvb-usb-tbs5520.o
obj-m += dvb-usb-tbs5520se.o
obj-m += dvb-usb-tbs5530.o
obj-m += dvb-usb-tbs5580.o
obj-m += dvb-usb-tbs5590.o
obj-m += dvb-usb-tbs5880.o
obj-m += dvb-usb-tbs5881.o
obj-m += dvb-usb-tbs5922se.o
obj-m += dvb-usb-tbs5925.o
obj-m += dvb-usb-tbs5927.o
obj-m += dvb-usb-tbs5930.o
obj-m += dvb-usb-tbs5931.o
obj-m += dvb-usb-tbs5301.o
obj-m += dvb-usb-tbsqbox.o
obj-m += dvb-usb-tbsqbox2.o
obj-m += dvb-usb-tbsqbox2ci.o
obj-m += dvb-usb-tbsqbox22.o
obj-m += dvb-usb-tbsqboxs2.o
MAKEFILE
info "usb/dvb-usb Makefile ready."

step "Creating minimal Makefile for pci/tbsecp3"
cp "$MF_TBS" "${MF_TBS}.orig"
cat > "$MF_TBS" << 'MAKEFILE'
ccflags-y += -Idrivers/media/tuners
ccflags-y += -Idrivers/media/dvb-core
ccflags-y += -Idrivers/media/dvb-frontends
ccflags-y += -Idrivers/media/dvb-frontends/stid135
tbsecp3-objs := tbsecp3-core.o tbsecp3-cards.o tbsecp3-i2c.o tbsecp3-dma.o \
                tbsecp3-dvb.o tbsecp3-ca.o tbsecp3-asi.o tbsecp3-ci.o
obj-m += tbsecp3.o
MAKEFILE
info "tbsecp3 Makefile ready."
pause

step "Compilation"
EXTRA_CFLAGS="-I${BUILD_DIR}/include -I${BUILD_DIR}/include/uapi \
    -I${SRC}/drivers/media/tuners \
    -I${SRC}/drivers/media/dvb-frontends \
    -I${SRC}/drivers/media/dvb-frontends/stid135 \
    -include linux/version.h \
    ${MISSING_DEFINES}"

# IS_REACHABLE(CONFIG_X) = IS_BUILTIN(X) || (IS_MODULE(X) && defined(MODULE))
# IS_MODULE(X) checks CONFIG_X_MODULE=1, not CONFIG_X=m.
# Dynamically detect all CONFIG_* used in IS_REACHABLE, IS_ENABLED
# or manual defined(CONFIG_X_MODULE) guards in TBS headers and add _MODULE=1.
REACHABLE_DEFINES=""
while IFS= read -r cfg; do
    REACHABLE_DEFINES+=" -D${cfg}_MODULE=1"
done < <(
    {
        grep -rh "IS_REACHABLE(CONFIG_" \
            "$SRC/drivers/media/dvb-frontends/" \
            "$SRC/drivers/media/tuners/" \
            2>/dev/null \
        | grep -oP 'IS_REACHABLE\(CONFIG_\w+\)' \
        | grep -oP 'CONFIG_\w+(?=\))'

        grep -rh "IS_ENABLED(CONFIG_" \
            "$SRC/drivers/media/dvb-frontends/" \
            "$SRC/drivers/media/tuners/" \
            2>/dev/null \
        | grep -oP 'IS_ENABLED\(CONFIG_\w+\)' \
        | grep -oP 'CONFIG_\w+(?=\))'

        grep -rh "defined(CONFIG_.*_MODULE)" \
            "$SRC/drivers/media/dvb-frontends/" \
            "$SRC/drivers/media/tuners/" \
            2>/dev/null \
        | grep -oP 'CONFIG_\w+(?=_MODULE)'
    } | sort -u
)
EXTRA_CFLAGS+=" $REACHABLE_DEFINES"
info "Added $(echo "$REACHABLE_DEFINES" | wc -w) _MODULE=1 defines for IS_REACHABLE guards"
info "Added $(echo "$MISSING_DEFINES" | wc -w) missing CONFIG_DVB_* defines"
ERRORS=(); SUCCESS=()

# COMBINED_SYMVERS: each module sees symbols from all previously compiled modules.
# Fixes "undefined symbol" at modpost for modules depending on dvb-core / frontends.
COMBINED_SYMVERS="$BUILD_DIR/Module.symvers"
: > "$COMBINED_SYMVERS"

for subdir in "${TARGET_DIRS[@]}"; do
    target="$SRC/drivers/media/$subdir"
    [[ -d "$target" ]] || { warn "Directory not found: $subdir"; continue; }
    [[ -f "$target/Makefile" ]] || { warn "No Makefile in: $subdir"; continue; }
    info "Compiling: $subdir"
    MODULE_LOG=$(mktemp)
    if make -C "$KBUILD" M="$target" KCFLAGS="$EXTRA_CFLAGS" \
            KBUILD_EXTRA_SYMBOLS="$COMBINED_SYMVERS" modules 2>&1 \
            | tee "$MODULE_LOG" | tee -a "$LOG"; then
        info "  OK: $subdir"; SUCCESS+=("$subdir")
        [[ -f "$target/Module.symvers" ]] && \
            cat "$target/Module.symvers" >> "$COMBINED_SYMVERS"
    else
        warn "  FAILED: $subdir"; ERRORS+=("$subdir")
        echo -e "${RED}  --- Errors in $subdir ---${NC}" | tee -a "$LOG"
        grep -E "^.*error:" "$MODULE_LOG" | sed "s|$SRC/||" | sort -u | head -30 \
            | while read -r line; do echo -e "  ${RED}>>>${NC} $line" | tee -a "$LOG"; done
        echo -e "${RED}  ---${NC}" | tee -a "$LOG"
    fi
    rm -f "$MODULE_LOG"
done

step "Build result"
KO_COUNT=$(find "$SRC/drivers/media" -name "*.ko" 2>/dev/null | wc -l)

if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo -e "${YELLOW}  ╔════════════════════════════╗"
    echo -e "  ║  PARTIAL BUILD             ║"
    echo -e "  ╚════════════════════════════╝${NC}"
    for e in "${ERRORS[@]}"; do warn "  FAILED: $e"; done
    info "Compiled:"; for s in "${SUCCESS[@]}"; do echo "    OK: $s" | tee -a "$LOG"; done
    info "Modules .ko: $KO_COUNT"
    warn "Next step: add a patch to kernel-patches.sh and run again"
    warn "Log: $LOG"
    exit 1
fi

echo -e "${GREEN}  ╔════════════════════════════╗"
echo -e "  ║  BUILD OK!                 ║"
echo -e "  ╚════════════════════════════╝${NC}"
info "Compiled:"; for s in "${SUCCESS[@]}"; do echo "    OK: $s" | tee -a "$LOG"; done
info "Modules .ko: $KO_COUNT"
find "$SRC/drivers/media" -name "*.ko" 2>/dev/null | sort \
    | while read -r f; do echo "    $(basename "$f")" | tee -a "$LOG"; done
info "Log: $LOG"
pause

step "Module installation"
# Ubuntu user report: stale modules in updates/ cause version mismatch errors
UPDATES_DIR="/lib/modules/${KVER}/updates"
if [[ -d "$UPDATES_DIR" && -n "$(ls -A "$UPDATES_DIR" 2>/dev/null)" ]]; then
    warn "  Existing modules found in: $UPDATES_DIR"
    warn "  Old modules may cause version mismatch errors (Ubuntu report)."
    read -rp "  Remove existing modules before install? [y/N]: " ANS
    if [[ "${ANS,,}" == "y" ]]; then
        rm -rf "${UPDATES_DIR:?}"/*
        info "  Cleared: $UPDATES_DIR"
    fi
fi

echo -e "${CYAN}  Install modules for kernel ${KVER}?"
echo -e "  Target: ${INSTALL_DIR}${NC}"
read -rp "  [Y/n]: " ANSWER
if [[ "${ANSWER,,}" == "n" ]]; then
    warn "Installation skipped. Modules are in: $SRC/drivers/media"
    exit 0
fi

info "Installing to: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
find "$SRC/drivers/media" -name "*.ko" | while read -r ko; do
    subpath="${ko#$SRC/drivers/media/}"
    destdir="$INSTALL_DIR/$(dirname "$subpath")"
    mkdir -p "$destdir"
    cp "$ko" "$destdir/"
    echo "  Copied: $(basename "$ko")" | tee -a "$LOG"
done

info "Running depmod -a $KVER"
depmod -a "$KVER" 2>&1 | tee -a "$LOG"

echo -e "${GREEN}  ╔════════════════════════════╗"
echo -e "  ║  INSTALLATION OK!          ║"
echo -e "  ║  Please reboot the system. ║"
echo -e "  ╚════════════════════════════╝${NC}"
info "Directory: $INSTALL_DIR / Log: $LOG"
