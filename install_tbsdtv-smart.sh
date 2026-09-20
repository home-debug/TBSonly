#!/usr/bin/env bash
# install_tbsdtv-smart v20-dev
# WARNING: This is a development version. It may not work correctly.
# Changes from v19:
#   - Self-branch detection (main/dev) shown in header and log
#   - TBS branch validation against origin (falls back to 'latest'; 'testing' does not exist upstream)
#   - Update check: proposes switching to newer 'dev' with warning
#   - Fixed --branch argument parsing (works with a value, e.g. --branch main)
#   - USB build fixed: removed nonexistent tbs5920/tbs5922 module targets
set -euo pipefail

DRY_RUN=0
TBS_BRANCH="${TBS_BRANCH:-}"   # resolved after script-branch detection
TBS_BRANCH_FORCED=0
ORIG_ARGS=("$@")

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --branch)
            [[ $# -ge 2 ]] || { echo "ERROR: --branch requires a branch name"; exit 1; }
            TBS_BRANCH="$2"
            TBS_BRANCH_FORCED=1
            shift 2
            ;;
        --testing)
            TBS_BRANCH="testing"
            TBS_BRANCH_FORCED=1
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--dry-run] [--branch NAME|--testing]"
            echo ""
            echo "Options:"
            echo "  --dry-run       Show what would be done without modifying anything"
            echo "  --branch NAME   Use specific TBS repo branch (default: latest)"
            echo "  --testing       Shortcut for --branch testing (validated against origin)"
            echo "  -h, --help      Show this help message"
            echo ""
            echo "Environment:"
            echo "  TBS_BRANCH      Override default branch (e.g. TBS_BRANCH=main $0)"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TBS_REPO="https://github.com/tbsdtv/linux_media.git"
SRC="/usr/src/tbs-drivers"
KVER="$(uname -r)"
KMAJ=$(echo "$KVER" | cut -d. -f1)
KMIN=$(echo "$KVER" | cut -d. -f2)
BUILD_DIR="$SCRIPT_DIR/tbs-build-tmp"
INSTALL_DIR="/lib/modules/${KVER}/updates/tbs"
LOG="$SCRIPT_DIR/install_tbsdtv-smart.log"

# Always build all TBS targets
TARGET_DIRS=("dvb-frontends" "tuners" "pci/saa716x" "pci/tbsecp3" "pci/tbsci" "pci/tbsmod" "usb/dvb-usb")

# ===========================================================================
# Detect which branch of THIS repo (TBSonly) we run from (shown in header/log
# and used by the update check). TBS branch selection defaults to 'latest'
# for both main and dev - see the validation block below.
# ===========================================================================
SELF_BRANCH="unknown"
SELF_COMMIT=""
if [[ -d "$SCRIPT_DIR/.git" ]]; then
    SELF_BRANCH=$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    SELF_COMMIT=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || true)
    [[ "$SELF_BRANCH" == "HEAD" ]] && SELF_BRANCH="detached"
fi

# NOTE: tbsdtv/linux_media has only 'latest' (maintained), 'master' (stale) and
# 'gse'. There is NO 'testing' branch - defaults go to 'latest' for both
# main and dev; --branch/--testing are validated against origin below.
if [[ -z "$TBS_BRANCH" ]]; then
    TBS_BRANCH="latest"
fi

# Verify the requested TBS branch exists upstream before git clone/checkout
if ! git ls-remote --exit-code --heads "$TBS_REPO" "$TBS_BRANCH" >/dev/null 2>&1; then
    AVAIL=$(git ls-remote --heads "$TBS_REPO" 2>/dev/null | awk '{print $2}' | sed 's|refs/heads/||' | tr '\n' ' ')
    warn "TBS branch '$TBS_BRANCH' not found in $TBS_REPO"
    warn "Available branches: ${AVAIL:-<could not list - no network?>}"
    if [[ "$TBS_BRANCH_FORCED" -eq 0 ]]; then
        TBS_BRANCH="latest"
        warn "Falling back to 'latest'."
    else
        error "Use --branch with one of the available branches listed above."
    fi
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*" | tee -a "$LOG"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*" | tee -a "$LOG"; }
error() { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG"; exit 1; }
step()  { echo -e "\n${CYAN}>>> $*${NC}" | tee -a "$LOG"; }
pi()    { echo -e "${BLUE}[PATCH]${NC} $*" | tee -a "$LOG"; }
pause() { echo -e "${YELLOW}--- Press Enter to continue ---${NC}"; read -r; }

# ===========================================================================
# Privilege check
# ===========================================================================
if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} This script must be run as root or with sudo." >&2
    exit 1
fi

[[ "$DRY_RUN" -eq 1 ]] && warn "DRY-RUN MODE - no files will be modified"
echo "=== $(date) ===" > "$LOG"
echo "  Kernel: $KVER / TBS branch: $TBS_BRANCH / Script: ${SELF_BRANCH}${SELF_COMMIT:+ $SELF_COMMIT} / DryRun: $DRY_RUN" | tee -a "$LOG"

case "$SELF_BRANCH" in
    dev)
        warn "  DEVELOPMENT version of this script (branch: dev)."
        warn "  It may not work correctly. For stable releases use 'main':"
        warn "    git checkout main && git pull origin main"
        BEHIND=$(git -C "$SCRIPT_DIR" rev-list --count HEAD..origin/dev 2>/dev/null || echo 0)
        [[ "$BEHIND" -gt 0 ]] && warn "  Local dev is $BEHIND commit(s) behind origin/dev — run: git pull origin dev"
        ;;
    main)
        info "  Stable branch (main) - OK."
        ;;
    *)
        warn "  Could not determine script branch (zip download or detached HEAD?)."
        warn "  Clone the repo to get updates: git clone https://github.com/home-debug/TBSonly.git"
        ;;
esac

ker_ge() { [[ "$KMAJ" -gt "$1" ]] || { [[ "$KMAJ" -eq "$1" ]] && [[ "$KMIN" -ge "$2" ]]; }; }

apply_sed() {
    local file="$1" desc="$2" expr="$3"
    [[ -f "$file" ]] || { warn "Patch '$desc': file not found: $file"; return 0; }
    if [[ "$DRY_RUN" -eq 1 ]]; then pi "[DRY-RUN] $desc"; return 0; fi
    pi "Applying: $desc"
    sed -i "$expr" "$file" && pi "  OK" || warn "  sed error: $file"
}

apply_sed_if_match() {
    local file="$1" desc="$2" match="$3" expr="$4"
    [[ -f "$file" ]] || { warn "Patch '$desc': file not found: $file"; return 0; }
    grep -q "$match" "$file" 2>/dev/null || { pi "Skipping (already applied): $desc"; return 0; }
    apply_sed "$file" "$desc" "$expr"
}

apply_python_patch() {
    local file="$1" desc="$2" match="$3" pycode="$4"
    [[ -f "$file" ]] || { warn "Patch '$desc': file not found: $file"; return 0; }
    grep -q "$match" "$file" 2>/dev/null || { pi "Skipping (already applied): $desc"; return 0; }
    if [[ "$DRY_RUN" -eq 1 ]]; then pi "[DRY-RUN] $desc"; return 0; fi
    pi "Applying: $desc"
    python3 -c "$pycode" "$file" && pi "  OK" || warn "  python error: $file"
}

# ===========================================================================
# Distribution & kernel source auto-detection
# ===========================================================================
detect_distro() {
    [[ -f /etc/os-release ]] && source /etc/os-release
    DISTRO="${ID:-unknown}"
    DISTRO_LIKE="${ID_LIKE:-}"
    info "  Distribution: $DISTRO"
}

detect_kernel_sources() {
    # KBUILD — directory used by make -C (contains arch-specific Makefile + .config)
    local kbuild_candidates=(
        "/lib/modules/${KVER}/build"
        "/usr/src/kernels/${KVER}"
        "/usr/src/linux-headers-${KVER}"
        "/usr/src/linux-${KVER}"
    )

    KBUILD=""
    for dir in "${kbuild_candidates[@]}"; do
        [[ -d "$dir" && -f "$dir/Makefile" ]] && { KBUILD="$dir"; break; }
    done

    if [[ -z "$KBUILD" ]]; then
        case "$DISTRO" in
            debian|ubuntu|linuxmint|pop)
                error "Kernel build dir not found.\n  Install: apt install linux-headers-${KVER}" ;;
            fedora|rhel|centos|almalinux|rocky)
                error "Kernel build dir not found.\n  Install: dnf install kernel-devel-${KVER}" ;;
            arch|manjaro)
                error "Kernel build dir not found.\n  Install: pacman -S linux-headers" ;;
            opensuse*|suse*)
                error "Kernel build dir not found.\n  Install: zypper in kernel-default-devel=${KVER%-default}" ;;
            *)
                error "Kernel build dir not found for ${KVER}.\n  Checked: ${kbuild_candidates[*]}" ;;
        esac
    fi
    info "  KBuild: $KBUILD"

    # Headers source for rsync into BUILD_DIR
    # We need a tree with physical include/ files (not symlinks to outside).
    # Priority: arch-specific headers (has generated headers) > common headers > KBUILD fallback
    local hdr_candidates=()

    # Debian/Ubuntu arch-specific headers (contains generated/autoconf headers)
    [[ -d "/usr/src/linux-headers-${KVER}" ]] && hdr_candidates+=("/usr/src/linux-headers-${KVER}")

    # Debian "common" split headers
    local common=$(find /usr/src -maxdepth 1 -name "linux-headers-*-common" | sort -V | tail -1)
    [[ -n "$common" && -d "$common" ]] && hdr_candidates+=("$common")

    # Ubuntu "main" headers (named without -common, e.g. linux-headers-7.0.0-31)
    # These are the common headers on Ubuntu. We look for ones matching our kernel version base.
    local kver_base="${KVER%%-*}"
    local ubuntu_hdr=$(find /usr/src -maxdepth 1 -name "linux-headers-${kver_base}" -type d | sort -V | tail -1)
    [[ -n "$ubuntu_hdr" && -d "$ubuntu_hdr" && "$ubuntu_hdr" != "/usr/src/linux-headers-${KVER}" ]] && hdr_candidates+=("$ubuntu_hdr")

    # Fedora/RHEL
    [[ -d "/usr/src/kernels/${KVER}" ]] && hdr_candidates+=("/usr/src/kernels/${KVER}")

    # Arch / generic
    [[ -d "/usr/src/linux-${KVER}" ]] && hdr_candidates+=("/usr/src/linux-${KVER}")

    KHEADERS_COMMON=""
    for dir in "${hdr_candidates[@]}"; do
        if [[ -d "$dir/include" ]]; then
            KHEADERS_COMMON="$dir"
            break
        fi
    done

    # Fallback: if KBUILD itself has a full include/ tree (e.g. Fedora, Arch), use it
    if [[ -z "$KHEADERS_COMMON" && -d "$KBUILD/include" ]]; then
        KHEADERS_COMMON="$KBUILD"
    fi

    if [[ -z "$KHEADERS_COMMON" ]]; then
        warn "  Could not find dedicated headers tree. Falling back to KBUILD."
        KHEADERS_COMMON="$KBUILD"
    fi
    info "  Headers source: $KHEADERS_COMMON"
}

# ===========================================================================
# Check upstream for a newer 'dev' branch and offer to switch
# (users normally run 'main'; dev is development — may not work)
# ===========================================================================
check_for_dev_update() {
    [[ -d "$SCRIPT_DIR/.git" ]] || return 0

    step "Checking for updates on origin..."

    git -C "$SCRIPT_DIR" fetch origin --quiet 2>/dev/null \
        || { warn "  Could not reach origin — continuing without update check."; return 0; }

    # Is there a dev branch upstream at all?
    if ! git -C "$SCRIPT_DIR" rev-parse --verify --quiet origin/dev >/dev/null; then
        info "  No 'dev' branch on origin — you are up to date."
        return 0
    fi

    # Is origin/dev actually NEWER (ahead) than what we run now?
    local ahead
    ahead=$(git -C "$SCRIPT_DIR" rev-list --count HEAD..origin/dev 2>/dev/null || echo 0)

    if [[ "$ahead" -eq 0 ]]; then
        info "  'dev' is not ahead of your current branch — nothing newer available."
        return 0
    fi

    local dev_date cur_date
    dev_date=$(git -C "$SCRIPT_DIR" log -1 --format='%cd' --date=short origin/dev 2>/dev/null || echo "?")
    cur_date=$(git -C "$SCRIPT_DIR" log -1 --format='%cd' --date=short HEAD 2>/dev/null || echo "?")

    warn "  Newer version available on 'dev': $ahead new commit(s) since $dev_date"
    warn "  You are running '$SELF_BRANCH' (current commit: $cur_date)"
    echo -e "${YELLOW}  +----------------------------------------------------+"
    echo -e "  |  WARNING: 'dev' is a DEVELOPMENT version.          |"
    echo -e "  |  It may NOT work correctly.                        |"
    echo -e "  |  Stable releases are on 'main'.                    |"
    echo -e "  +----------------------------------------------------+${NC}"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[DRY-RUN] Would run: git checkout dev && git pull --ff-only origin dev"
        return 0
    fi

    if [[ -t 0 ]]; then
        read -rp "  Switch to 'dev' and continue with the newer version? [y/N]: " ANS
        if [[ "${ANS,,}" == "y" ]]; then
            git -C "$SCRIPT_DIR" checkout dev 2>&1 | tee -a "$LOG"
            git -C "$SCRIPT_DIR" pull --ff-only origin dev 2>&1 | tee -a "$LOG"
            info "  Switched to 'dev'. Re-starting script..."
            SELF_PATH="$SCRIPT_DIR/$(basename "$0")"
            sleep 1
            [[ ${#ORIG_ARGS[@]} -gt 0 ]] && exec bash "$SELF_PATH" "${ORIG_ARGS[@]}"
            exec bash "$SELF_PATH"
        fi
        info "  Staying on '$SELF_BRANCH'."
    else
        warn "  Non-interactive shell — to switch manually run:"
        warn "    git checkout dev && git pull origin dev"
    fi
}

# ===========================================================================
# Optional cleanup of stale modules from previous runs
# ===========================================================================
check_stale_modules() {
    local updates_dir="/lib/modules/${KVER}/updates"
    if [[ -d "$updates_dir" && -n "$(ls -A "$updates_dir" 2>/dev/null)" ]]; then
        warn "  Existing modules found in: $updates_dir"
        warn "  Old modules may cause version mismatch errors."
        read -rp "  Remove existing modules before install? [y/N]: " ANS
        if [[ "${ANS,,}" == "y" ]]; then
            rm -rf "${updates_dir:?}"/*
            info "  Cleared: $updates_dir"
        fi
    fi
}

# ===========================================================================
# TBS Hardware Detection (cosmetic only, does not affect build targets)
# ===========================================================================
# ===========================================================================
# TBS Hardware Detection (cosmetic only, does not affect build targets)
# ===========================================================================
detect_tbs_cards() {
    local py_script py_out
    py_script=$(mktemp /tmp/detect_tbs.XXXXXX.py)

    cat > "$py_script" << 'PYEOF'
# -*- coding: utf-8 -*-
import re, os, glob, subprocess, sys

def _open(p):
    return open(p, encoding="utf-8", errors="replace")

src = sys.argv[1] if len(sys.argv) > 1 else "/usr/src/tbs-drivers"

def parse_tbs_pci_map(src_path):
    tbs_map = {}

    # --- TBSECP3 ---
    cards = os.path.join(src_path, "drivers/media/pci/tbsecp3/tbsecp3-cards.c")
    core  = os.path.join(src_path, "drivers/media/pci/tbsecp3/tbsecp3-core.c")

    board_names = {}
    if os.path.exists(cards):
        with _open(cards) as f:
            content = f.read()
        for m in re.finditer(r'\[([A-Z_0-9]+)\]\s*=\s*\{[^}]*?\.name\s*=\s*"([^"]+)"', content, re.DOTALL):
            board_names[m.group(1)] = m.group(2).strip()

    if os.path.exists(core):
        with _open(core) as f:
            content = f.read()
        for m in re.finditer(r'TBSECP3_ID\(([A-Z_0-9]+),0x([0-9a-fA-F]+),0x([0-9a-fA-F]+)\)', content):
            bid, sv, sd = m.groups()
            name = board_names.get(bid, bid)
            key = (0x544d, 0x6178, int(sv, 16), int(sd, 16))
            tbs_map[key] = name

    # --- SAA716x ---
    budget = os.path.join(src_path, "drivers/media/pci/saa716x/saa716x_budget.c")
    if not os.path.exists(budget):
        return tbs_map

    defs = {}
    for h in glob.glob(os.path.join(src_path, "drivers/media/pci/saa716x/*.h")):
        with _open(h) as f:
            for m in re.finditer(r'#define\s+([A-Z_][A-Z0-9_]*)\s+0x([0-9a-fA-F]+)', f.read()):
                defs[m.group(1)] = int(m.group(2), 16)

    defs.setdefault('NXP_SEMICONDUCTOR', 0x1131)
    defs.setdefault('SAA7160', 0x7160)
    defs.setdefault('SAA7161', 0x7161)
    defs.setdefault('SAA7162', 0x7162)

    with _open(budget) as f:
        budget_lines = f.readlines()

    for line in budget_lines:
        m = re.search(
            r'MAKE_ENTRY\(\s*([A-Z_0-9]+)\s*,\s*([A-Z_0-9]+)\s*,\s*([A-Z_0-9]+)\s*,\s*&([a-z_0-9]+)',
            line)
        if not m:
            continue

        sv_n, sd_n, chip_n, cfg_name = m.groups()
        sv = defs.get(sv_n)
        sd = defs.get(sd_n)
        chip = defs.get(chip_n)
        if sv is None or sd is None or chip is None:
            continue

        cm = re.search(r'/\*\s*(.+?)\s*\*/', line)
        model = cm.group(1).strip() if cm else f"{sv_n} {sd_n}"

        tbs_m = re.search(r'tbs(\d+)', cfg_name, re.IGNORECASE)
        if tbs_m:
            clone = f"TBS{tbs_m.group(1)}"
            if clone not in model:
                model += f" ({clone})"

        key = (0x1131, chip, sv, sd)
        tbs_map[key] = model

    return tbs_map

def scan_pci():
    try:
        out = subprocess.check_output(["lspci", "-vmm", "-nn"], text=True)
    except Exception:
        return []

    cards = []
    current = {}
    for line in out.splitlines():
        if line.startswith("Slot:"):
            if current:
                cards.append(current)
            current = {"slot": line[5:].strip()}
        elif line.startswith("Vendor:"):
            m = re.search(r'\[([0-9a-fA-F]{4})\]', line)
            if m: current["vendor"] = int(m.group(1), 16)
        elif line.startswith("Device:"):
            m = re.search(r'\[([0-9a-fA-F]{4})\]', line)
            if m: current["device"] = int(m.group(1), 16)
        elif line.startswith("SVendor:"):
            m = re.search(r'\[([0-9a-fA-F]{4})\]', line)
            if m: current["svendor"] = int(m.group(1), 16)
        elif line.startswith("SDevice:"):
            m = re.search(r'\[([0-9a-fA-F]{4})\]', line)
            if m: current["sdevice"] = int(m.group(1), 16)
        elif line.startswith("Rev:"):
            current["rev"] = line[4:].strip()

    if current:
        cards.append(current)
    return cards

def main():
    try:
        _main_impl()
    except Exception as e:
        print("WARN|Detection error: " + repr(e))

def _main_impl():
    if not os.path.isdir(src):
        print("WARN|TBS sources not found. Skipping detection.")
        sys.exit(0)

    tbs_map = parse_tbs_pci_map(src)
    found = []

    for card in scan_pci():
        v = card.get("vendor")
        d = card.get("device")
        sv = card.get("svendor")
        sd = card.get("sdevice")
        if v is None or d is None or sv is None or sd is None:
            continue

        key = (v, d, sv, sd)
        if key in tbs_map:
            if v == 0x544d:
                family = "TBSECP3"
            elif v == 0x1131:
                family = "SAA716x"
            else:
                print(f"WARN|Unknown TBS bridge vendor {v:04x}: {tbs_map[key]}  [PCI {card.get('slot', '?')}]")
                print("WARN|  No driver module assigned - please update the script.")
                continue
            found.append({
                "family": family,
                "name": tbs_map[key],
                "slot": card.get("slot", "?"),
                "sub": f"{sv:04x}:{sd:04x}",
                "rev": card.get("rev", "-")
            })

    if not found:
        print("WARN|No TBS cards detected via lspci.")
        return

    for c in found:
        print(f"INFO|Found {c['name']}  [PCI {c['slot']}, subdev {c['sub']}, rev {c['rev']}]")
        print(f"INFO|  -> requires {c['family']} driver")

    print(f"INFO|Total TBS cards detected: {len(found)}")

if __name__ == "__main__":
    main()
PYEOF

    step "Detecting TBS cards from source tree..."

    if ! command -v lspci >/dev/null 2>&1; then
        warn "  lspci not found (package: pciutils). Skipping hardware detection."
        rm -f "$py_script"
        return
    fi

    if [[ ! -d "$SRC/drivers/media/pci/tbsecp3" && ! -d "$SRC/drivers/media/pci/saa716x" ]]; then
        warn "  TBS sources not found yet. Skipping hardware detection."
        rm -f "$py_script"
        return
    fi

    py_out=$(python3 "$py_script" "$SRC" 2>>"$LOG" || true)

    while IFS='|' read -r prefix msg; do
        case "$prefix" in
            INFO) info "  $msg" ;;
            WARN) warn "  $msg" ;;
        esac
    done <<< "$py_out"

    rm -f "$py_script"
}

# Load patches from separate file
PATCHES_FILE="$SCRIPT_DIR/kernel-patches.sh"
[[ -f "$PATCHES_FILE" ]] || error "Patches file not found: $PATCHES_FILE"
# shellcheck source=kernel-patches.sh
source "$PATCHES_FILE"

# ===========================================================================
cleanup() {
    info "Cleanup - restoring original files..."
    local h1="$KHEADERS_COMMON/include/media/dvb_frontend.h"
    local h2="$KHEADERS_COMMON/include/uapi/linux/dvb/frontend.h"
    local mf="$SRC/drivers/media/dvb-frontends/Makefile"
    local mf_saa="$SRC/drivers/media/pci/saa716x/Makefile"
    local mf_tbs="$SRC/drivers/media/pci/tbsecp3/Makefile"
    local mf_tuners="$SRC/drivers/media/tuners/Makefile"
    local mf_usb="$SRC/drivers/media/usb/dvb-usb/Makefile"
    # Kernel headers: always restore (outside TBS tree)
    [[ -f "${h1}.orig" ]]        && mv "${h1}.orig"        "$h1"        && info "  Restored: dvb_frontend.h"
    [[ -f "${h2}.orig" ]]        && mv "${h2}.orig"        "$h2"        && info "  Restored: frontend.h"
    # TBS Makefiles: do NOT restore - they must remain modified for modprobe to work
    # Just remove the .orig backups
    [[ -f "${mf}.orig" ]]        && rm "${mf}.orig"        && info "  Removed backup: dvb-frontends/Makefile.orig"
    [[ -f "${mf_saa}.orig" ]]    && rm "${mf_saa}.orig"    && info "  Removed backup: saa716x/Makefile.orig"
    [[ -f "${mf_tbs}.orig" ]]    && rm "${mf_tbs}.orig"    && info "  Removed backup: tbsecp3/Makefile.orig"
    [[ -f "${mf_tuners}.orig" ]] && rm "${mf_tuners}.orig" && info "  Removed backup: tuners/Makefile.orig"
    [[ -f "${mf_usb}.orig" ]]    && rm "${mf_usb}.orig"    && info "  Removed backup: usb/dvb-usb/Makefile.orig"
}
trap cleanup EXIT

step "Checking kernel version (required: 7.0+)"
ker_ge 7 0 || error "Kernel $KVER is too old. Required: 7.0+"
info "Kernel $KVER - OK"

step "Fetching/updating TBS sources -> $SRC"
command -v git >/dev/null 2>&1 || error "Missing dependency: git (install it first)"
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

step "Checking build environment"
echo "  Kernel:         $KVER"            | tee -a "$LOG"
echo "  TBS sources:    $SRC"             | tee -a "$LOG"
echo "  Log:            $LOG"             | tee -a "$LOG"

detect_distro
detect_kernel_sources

for cmd in git make gcc rsync python3; do
    command -v "$cmd" &>/dev/null || error "Missing dependency: $cmd"
done

check_for_dev_update

# TBS-extended headers: the TBS tree carries frontend extensions (modcode,
# set_property, read_temp, FE_ECP3FW_*, FE_24CXX_*) that distro headers lack.
# The temporary header patch MUST source from the TBS tree.
H1="$SRC/include/media/dvb_frontend.h"
H2="$SRC/include/uapi/linux/dvb/frontend.h"
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

detect_tbs_cards

pause


# NOTE: apply_kernel_api_patches must run before BUILD_DIR and before overwriting TBS Makefiles
apply_kernel_api_patches
[[ "$DRY_RUN" -eq 1 ]] && { info "Dry-run complete."; exit 0; }
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
if [[ "$H1" == "$SRC/include/media/dvb_frontend.h" ]]; then
    info "  dvb_frontend.h: already sourced from the TBS tree - no patch needed"
elif [[ -e "$H1" ]]; then
    cp "$H1" "${H1}.orig" && cp "$SRC/include/media/dvb_frontend.h" "$H1"
    info "  Patched: dvb_frontend.h"
else
    H1="$SRC/include/media/dvb_frontend.h"
    info "  dvb_frontend.h: target missing, using TBS header directly"
fi
if [[ "$H2" == "$SRC/include/uapi/linux/dvb/frontend.h" ]]; then
    info "  frontend.h (uapi): already sourced from the TBS tree - no patch needed"
elif [[ -e "$H2" ]]; then
    cp "$H2" "${H2}.orig" && cp "$SRC/include/uapi/linux/dvb/frontend.h" "$H2"
    info "  Patched: frontend.h (uapi)"
else
    H2="$SRC/include/uapi/linux/dvb/frontend.h"
    info "  frontend.h (uapi): target missing, using TBS header directly"
fi

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

step "Creating minimal Makefile for usb/dvb-usb"
cp "$SRC/drivers/media/usb/dvb-usb/Makefile" "${SRC}/drivers/media/usb/dvb-usb/Makefile.orig" 2>/dev/null || true
cat > "$SRC/drivers/media/usb/dvb-usb/Makefile" << 'MAKEFILE'
ccflags-y += -Idrivers/media/dvb-core
ccflags-y += -Idrivers/media/dvb-frontends
ccflags-y += -Idrivers/media/tuners
dvb-usb-tbs5520-objs := tbs5520.o
dvb-usb-tbs5520se-objs := tbs5520se.o
dvb-usb-tbs5580-objs := tbs5580.o
dvb-usb-tbs5590-objs := tbs5590.o
dvb-usb-tbs5880-objs := tbs5880.o
dvb-usb-tbs5881-objs := tbs5881.o
dvb-usb-tbs5925-objs := tbs5925.o
dvb-usb-tbs5930-objs := tbs5930.o
dvb-usb-tbs5220-objs := tbs5220.o
dvb-usb-tbs5230-objs := tbs5230.o
dvb-usb-tbs5301-objs := tbs5301.o
dvb-usb-tbs5530-objs := tbs5530.o
dvb-usb-tbs5922se-objs := tbs5922se.o
dvb-usb-tbs5927-objs := tbs5927.o
dvb-usb-tbs5931-objs := tbs5931.o
dvb-usb-tbsqbox-objs := tbs-qbox.o
dvb-usb-tbsqbox2-objs := tbs-qbox2.o
dvb-usb-tbsqbox2ci-objs := tbs-qbox2ci.o
dvb-usb-tbsqbox22-objs := tbs-qbox22.o
dvb-usb-tbsqboxs2-objs := tbs-qboxs2.o
obj-m += dvb-usb-tbs5520.o
obj-m += dvb-usb-tbs5520se.o
obj-m += dvb-usb-tbs5580.o
obj-m += dvb-usb-tbs5590.o
obj-m += dvb-usb-tbs5880.o
obj-m += dvb-usb-tbs5881.o
obj-m += dvb-usb-tbs5925.o
obj-m += dvb-usb-tbs5930.o
obj-m += dvb-usb-tbs5220.o
obj-m += dvb-usb-tbs5230.o
obj-m += dvb-usb-tbs5301.o
obj-m += dvb-usb-tbs5530.o
obj-m += dvb-usb-tbs5922se.o
obj-m += dvb-usb-tbs5927.o
obj-m += dvb-usb-tbs5931.o
obj-m += dvb-usb-tbsqbox.o
obj-m += dvb-usb-tbsqbox2.o
obj-m += dvb-usb-tbsqbox2ci.o
obj-m += dvb-usb-tbsqbox22.o
obj-m += dvb-usb-tbsqboxs2.o
MAKEFILE
info "usb/dvb-usb Makefile ready."
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
            KBUILD_EXTRA_SYMBOLS="$COMBINED_SYMVERS" -j$(nproc) modules 2>&1 \
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
check_stale_modules
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
