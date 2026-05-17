#!/usr/bin/env bash
# install_tbsdtv-smart v17
# Zmiany wzgledem v16:
#   - EXTRA_CFLAGS: dodano ${SRC}/dvb-frontends i stid135 (mb86a16.h i inne TBS-only headers)
#   - Dynamiczne wykrywanie CONFIG_*_MODULE=1 dla IS_REACHABLE i recznie pisanych guardow
#     (obejmuje IS_REACHABLE(CONFIG_X) i defined(CONFIG_X_MODULE) w headerach TBS)
#   - cleanup: Makefile TBS nie sa przywracane z .orig - tylko naglowki kernela
#   - Wykrywanie "pozostalosci" sprawdza tylko naglowki kernela
set -euo pipefail

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --help|-h) echo "Uzycie: $0 [--dry-run]"; exit 0 ;;
        *) echo "Nieznany argument: $arg"; exit 1 ;;
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
KHEADERS_COMMON=$(find /usr/src -maxdepth 1 -name "linux-headers-*-common" | sort -V | tail -1)
BUILD_DIR="$SCRIPT_DIR/tbs-build-tmp"
INSTALL_DIR="/lib/modules/${KVER}/updates/tbs"
LOG="$SCRIPT_DIR/install_tbsdtv-smart.log"

# tuners kompiluje sie przed frontends/saa/tbs zeby Module.symvers byl dostepny
TARGET_DIRS=("dvb-core" "dvb-frontends" "tuners" "pci/saa716x" "pci/tbsecp3" "pci/tbsci" "pci/tbsmod")

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*" | tee -a "$LOG"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*" | tee -a "$LOG"; }
error() { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG"; exit 1; }
step()  { echo -e "\n${CYAN}>>> $*${NC}" | tee -a "$LOG"; }
pi()    { echo -e "${BLUE}[PATCH]${NC} $*" | tee -a "$LOG"; }

[[ "$DRY_RUN" -eq 1 ]] && warn "TRYB DRY-RUN - zadne pliki nie beda modyfikowane"
echo "=== $(date) ===" > "$LOG"
echo "  Kernel: $KVER / DryRun: $DRY_RUN" | tee -a "$LOG"

ker_ge() { [[ "$KMAJ" -gt "$1" ]] || { [[ "$KMAJ" -eq "$1" ]] && [[ "$KMIN" -ge "$2" ]]; }; }
ker_lt() { ! ker_ge "$1" "$2"; }
# ker_in MAJ1 MIN1 MAJ2 MIN2 -> true jezeli MAJ1.MIN1 <= kernel < MAJ2.MIN2
ker_in() { ker_ge "$1" "$2" && ker_lt "$3" "$4"; }

apply_sed() {
    local file="$1" desc="$2" expr="$3"
    [[ -f "$file" ]] || { warn "Patch '$desc': brak pliku $file"; return 0; }
    if [[ "$DRY_RUN" -eq 1 ]]; then pi "[DRY-RUN] $desc"; return 0; fi
    pi "Aplikuje: $desc"
    sed -i "$expr" "$file" && pi "  OK" || warn "  sed blad: $file"
}

apply_sed_if_match() {
    local file="$1" desc="$2" match="$3" expr="$4"
    [[ -f "$file" ]] || { warn "Patch '$desc': brak pliku $file"; return 0; }
    grep -q "$match" "$file" 2>/dev/null || { pi "Pomijam (nieaktualne): $desc"; return 0; }
    apply_sed "$file" "$desc" "$expr"
}

apply_python_patch() {
    local file="$1" desc="$2" match="$3" pycode="$4"
    [[ -f "$file" ]] || { warn "Patch '$desc': brak pliku $file"; return 0; }
    grep -q "$match" "$file" 2>/dev/null || { pi "Pomijam (nieaktualne): $desc"; return 0; }
    if [[ "$DRY_RUN" -eq 1 ]]; then pi "[DRY-RUN] $desc"; return 0; fi
    pi "Aplikuje: $desc"
    python3 -c "$pycode" "$file" && pi "  OK" || warn "  python blad: $file"
}

# Ladowanie patchy z osobnego pliku
PATCHES_FILE="$SCRIPT_DIR/kernel-patches.sh"
[[ -f "$PATCHES_FILE" ]] || error "Brak pliku z patchami: $PATCHES_FILE"
# shellcheck source=kernel-patches.sh
source "$PATCHES_FILE"

# ===========================================================================
cleanup() {
    info "Sprzatam - przywracam oryginalne pliki..."
    local h1="$KHEADERS_COMMON/include/media/dvb_frontend.h"
    local h2="$KHEADERS_COMMON/include/uapi/linux/dvb/frontend.h"
    local mf="$SRC/drivers/media/dvb-frontends/Makefile"
    local mf_saa="$SRC/drivers/media/pci/saa716x/Makefile"
    local mf_tbs="$SRC/drivers/media/pci/tbsecp3/Makefile"
    local mf_tuners="$SRC/drivers/media/tuners/Makefile"
    # Naglowki kernela: zawsze przywracamy (sa poza drzewem TBS)
    [[ -f "${h1}.orig" ]]        && mv "${h1}.orig"        "$h1"        && info "  Przywrocono: dvb_frontend.h"
    [[ -f "${h2}.orig" ]]        && mv "${h2}.orig"        "$h2"        && info "  Przywrocono: frontend.h"
    # Makefile TBS: NIE przywracamy - sa czescia drzewa TBS i musza pozostac
    # zmodyfikowane zeby insmod/modprobe moglo je znalezc. Usuwamy tylko .orig.
    [[ -f "${mf}.orig" ]]        && rm "${mf}.orig"        && info "  Usunieto backup: dvb-frontends/Makefile.orig"
    [[ -f "${mf_saa}.orig" ]]    && rm "${mf_saa}.orig"    && info "  Usunieto backup: saa716x/Makefile.orig"
    [[ -f "${mf_tbs}.orig" ]]    && rm "${mf_tbs}.orig"    && info "  Usunieto backup: tbsecp3/Makefile.orig"
    [[ -f "${mf_tuners}.orig" ]] && rm "${mf_tuners}.orig" && info "  Usunieto backup: tuners/Makefile.orig"
}
trap cleanup EXIT

step "Sprawdzanie wersji kernela (wymagany 6.12+)"
ker_ge 6 12 || error "Kernel $KVER jest za stary. Wymagany 6.12+."
info "Kernel $KVER - OK"

step "Sprawdzanie srodowiska"
echo "  Kernel:          $KVER"            | tee -a "$LOG"
echo "  KBuild:          $KBUILD"          | tee -a "$LOG"
echo "  Zrodla TBS:      $SRC"             | tee -a "$LOG"
echo "  Naglowki common: $KHEADERS_COMMON" | tee -a "$LOG"
echo "  Log:             $LOG"             | tee -a "$LOG"

[[ -d "$KBUILD" ]] || error "Brak katalogu build kernela: $KBUILD"
[[ -n "$KHEADERS_COMMON" && -d "$KHEADERS_COMMON" ]] || error "Brak linux-headers-*-common"
for cmd in git make gcc rsync python3; do
    command -v "$cmd" &>/dev/null || error "Brak: $cmd"
done

H1="$KHEADERS_COMMON/include/media/dvb_frontend.h"
H2="$KHEADERS_COMMON/include/uapi/linux/dvb/frontend.h"
MF="$SRC/drivers/media/dvb-frontends/Makefile"
MF_SAA="$SRC/drivers/media/pci/saa716x/Makefile"
MF_TBS="$SRC/drivers/media/pci/tbsecp3/Makefile"
MF_TUNERS="$SRC/drivers/media/tuners/Makefile"
STALE=0
# Sprawdzamy tylko naglowki kernela - Makefile TBS nie sa przywracane po udanym przebiegu
for f in "${H1}.orig" "${H2}.orig"; do
    [[ -f "$f" ]] && { warn "Pozostalosc po przerwanym uruchomieniu: $f"; STALE=1; }
done
if [[ "$STALE" -eq 1 ]]; then
    read -rp "  Przywrocic pliki .orig i kontynuowac? [t/N]: " ANS
    [[ "${ANS,,}" == "t" ]] || error "Anulowano. Sprawdz recznie pliki .orig."
    cleanup; trap cleanup EXIT
fi
info "Srodowisko OK."

step "Pobieranie/aktualizacja zrodel TBS -> $SRC"
if [[ "$DRY_RUN" -eq 0 ]]; then
    if [[ -d "$SRC/.git" ]]; then
        git -C "$SRC" fetch origin              2>&1 | tee -a "$LOG"
        git -C "$SRC" checkout "$TBS_BRANCH"    2>&1 | tee -a "$LOG"
        git -C "$SRC" pull origin "$TBS_BRANCH" 2>&1 | tee -a "$LOG"
    else
        git clone --depth=1 --branch "$TBS_BRANCH" "$TBS_REPO" "$SRC" 2>&1 | tee -a "$LOG"
    fi
    info "Zrodla gotowe w: $SRC"
else
    info "[DRY-RUN] Pomijam git."
fi

# UWAGA: apply_kernel_api_patches musi byc przed BUILD_DIR i przed nadpisaniem Makefile TBS
apply_kernel_api_patches
[[ "$DRY_RUN" -eq 1 ]] && { info "Dry-run zakończony."; exit 0; }

step "Tworzenie izolowanego katalogu budowania"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/include"
rsync -a "$KHEADERS_COMMON/include/" "$BUILD_DIR/include/" 2>&1 | tee -a "$LOG"
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
info "Katalog budowania gotowy."

step "Tymczasowe patchowanie naglowkow kernela"
cp "$H1" "${H1}.orig" && cp "$SRC/include/media/dvb_frontend.h" "$H1"
info "  Patchowano: dvb_frontend.h"
cp "$H2" "${H2}.orig" && cp "$SRC/include/uapi/linux/dvb/frontend.h" "$H2"
info "  Patchowano: frontend.h (uapi)"

# UWAGA: wykrywanie CONFIG_DVB_* musi byc przed nadpisaniem Makefile TBS
step "Wykrywanie brakujacych CONFIG_DVB_*"
KERNEL_CONFIG="/boot/config-${KVER}"
MISSING_DEFINES=""
if [[ -f "$KERNEL_CONFIG" ]]; then
    while IFS= read -r cfg; do
        grep -q "^${cfg}=" "$KERNEL_CONFIG" 2>/dev/null && continue
        MISSING_DEFINES+=" -D${cfg}=1"
        info "  Brak: ${cfg}"
    done < <(
        grep -h "obj-\$(CONFIG_DVB" \
            "$SRC/drivers/media/dvb-frontends/Makefile" \
            "$SRC/drivers/media/dvb-core/Makefile" \
            2>/dev/null | grep -oP 'CONFIG_DVB_\w+' | sort -u
    )
    [[ -z "$MISSING_DEFINES" ]] \
        && info "Wszystkie CONFIG_DVB_* obecne." \
        || info "Dodano definicji: $(echo "$MISSING_DEFINES" | wc -w)"
else
    warn "Brak $KERNEL_CONFIG - uzywam domyslnego zestawu dla 6.12+"
    MISSING_DEFINES="-DCONFIG_DVB_AVL6882=1 -DCONFIG_DVB_CXD2820R=1 \
        -DCONFIG_DVB_CXD2878=1 -DCONFIG_DVB_DIB9000=1 \
        -DCONFIG_DVB_DRXD=1 -DCONFIG_DVB_DRXK=1 \
        -DCONFIG_DVB_GX1133=1 -DCONFIG_DVB_GX1503=1 \
        -DCONFIG_DVB_ISL6422=1 -DCONFIG_DVB_LGS8GL5=1 \
        -DCONFIG_DVB_LNBH29=1 -DCONFIG_DVB_M88RS6060=1 \
        -DCONFIG_DVB_MN88436=1 -DCONFIG_DVB_MN88443X=1 \
        -DCONFIG_DVB_MTV23X=1 -DCONFIG_DVB_MXL58X=1 \
        -DCONFIG_DVB_S5H1432=1 -DCONFIG_DVB_SI2183=1 \
        -DCONFIG_DVB_STB0899=1 -DCONFIG_DVB_STV0900=1 \
        -DCONFIG_DVB_STV091X=1 -DCONFIG_DVB_TAS2101=1 \
        -DCONFIG_DVB_TAS2971=1"
fi

step "Tworzenie minimalnego Makefile dla dvb-frontends"
cp "$MF" "${MF}.orig"
cat > "$MF" << 'MAKEFILE'
ccflags-y += -I$(srctree)/drivers/media/tuners/
cxd2820r-objs := cxd2820r_core.o cxd2820r_c.o cxd2820r_t.o cxd2820r_t2.o
drxd-objs     := drxd_firm.o drxd_hard.o
drxk-objs     := drxk_hard.o
stb0899-objs  := stb0899_drv.o stb0899_algo.o
stv0900-objs  := stv0900_core.o stv0900_sw.o
# TBS-exclusive frontendy
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
# Frontendy obecne w kernelu, ale TBS ma zmodyfikowane wersje
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
info "Makefile dvb-frontends gotowy."

step "Tworzenie minimalnego Makefile dla tuners"
cp "$MF_TUNERS" "${MF_TUNERS}.orig"
cat > "$MF_TUNERS" << 'MAKEFILE'
ccflags-y += -I$(srctree)/drivers/media/dvb-frontends/
# Tunery TBS-specific (nie ma w kernelu dystrybucji lub TBS ma zmodyfikowane wersje)
obj-m += av201x.o
obj-m += si2157.o
obj-m += stv6120.o
obj-m += tda18212.o
MAKEFILE
info "Makefile tuners gotowy."

step "Tworzenie minimalnego Makefile dla pci/saa716x"
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
info "Makefile saa716x gotowy."

step "Tworzenie minimalnego Makefile dla pci/tbsecp3"
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
info "Makefile tbsecp3 gotowy."

step "Kompilacja"
EXTRA_CFLAGS="-I${BUILD_DIR}/include -I${BUILD_DIR}/include/uapi -I${SRC}/drivers/media/tuners -I${SRC}/drivers/media/dvb-frontends -I${SRC}/drivers/media/dvb-frontends/stid135 -include linux/version.h ${MISSING_DEFINES}"
# IS_REACHABLE(CONFIG_X) = IS_BUILTIN(X) || (IS_MODULE(X) && defined(MODULE))
# IS_MODULE(X) sprawdza CONFIG_X_MODULE=1, nie CONFIG_X=m.
# Dla modulow TBS z IS_REACHABLE w headerach dodajemy _MODULE=1 zeby
# uniknac redefinicji funkcji attach (static inline vs extern).
# IS_REACHABLE(CONFIG_X) = IS_BUILTIN(X) || (IS_MODULE(X) && defined(MODULE))
# IS_MODULE(X) sprawdza CONFIG_X_MODULE=1, nie CONFIG_X=m.
# Wykrywamy dynamicznie wszystkie CONFIG_* uzywane w IS_REACHABLE lub recznie
# przez defined(CONFIG_X_MODULE) w headerach TBS i dodajemy _MODULE=1.
REACHABLE_DEFINES=""
while IFS= read -r cfg; do
    REACHABLE_DEFINES+=" -D${cfg}_MODULE=1"
done < <(
    {
        # Wzorzec 1: IS_REACHABLE(CONFIG_FOO)
        grep -rh "IS_REACHABLE(CONFIG_" \
            "$SRC/drivers/media/dvb-frontends/" \
            "$SRC/drivers/media/tuners/" \
            2>/dev/null \
        | grep -oP 'IS_REACHABLE\(CONFIG_\w+\)' \
        | grep -oP 'CONFIG_\w+(?=\))'

        # Wzorzec 3: IS_ENABLED(CONFIG_FOO) - jak IS_REACHABLE ale bez MODULE check
        grep -rh "IS_ENABLED(CONFIG_" \
            "$SRC/drivers/media/dvb-frontends/" \
            "$SRC/drivers/media/tuners/" \
            2>/dev/null \
        | grep -oP 'IS_ENABLED\(CONFIG_\w+\)' \
        | grep -oP 'CONFIG_\w+(?=\))'
        # Wzorzec 2: defined(CONFIG_FOO_MODULE) -> wyciagamy CONFIG_FOO
        grep -rh "defined(CONFIG_.*_MODULE)" \
            "$SRC/drivers/media/dvb-frontends/" \
            "$SRC/drivers/media/tuners/" \
            2>/dev/null \
        | grep -oP 'CONFIG_\w+(?=_MODULE)'
    } | sort -u
)
EXTRA_CFLAGS+=" $REACHABLE_DEFINES"
info "Dodano $(echo "$REACHABLE_DEFINES" | wc -w) definicji _MODULE dla IS_REACHABLE"
info "EXTRA_CFLAGS: $(echo "$MISSING_DEFINES" | wc -w) definicji CONFIG_DVB_*"
ERRORS=(); SUCCESS=()

# COMBINED_SYMVERS: kazdy kolejny modul widzi symbole wszystkich poprzednich.
# Rozwiazuje "undefined symbol" przy modpost dla modulow zaleznych od dvb-core / frontends.
COMBINED_SYMVERS="$BUILD_DIR/Module.symvers"
: > "$COMBINED_SYMVERS"

for subdir in "${TARGET_DIRS[@]}"; do
    target="$SRC/drivers/media/$subdir"
    [[ -d "$target" ]] || { warn "Nie istnieje: $subdir"; continue; }
    [[ -f "$target/Makefile" ]] || { warn "Brak Makefile: $subdir"; continue; }
    info "Kompiluje: $subdir"
    MODULE_LOG=$(mktemp)
    # KCFLAGS zamiast EXTRA_CFLAGS od kernela 6.19
    # KBUILD_EXTRA_SYMBOLS: przekazuje symbole z wczesniej skompilowanych modulow
    if make -C "$KBUILD" M="$target" KCFLAGS="$EXTRA_CFLAGS" \
            KBUILD_EXTRA_SYMBOLS="$COMBINED_SYMVERS" modules 2>&1 \
            | tee "$MODULE_LOG" | tee -a "$LOG"; then
        info "  OK: $subdir"; SUCCESS+=("$subdir")
        # Akumuluj symbole dla nastepnych modulow w kolejce
        [[ -f "$target/Module.symvers" ]] && \
            cat "$target/Module.symvers" >> "$COMBINED_SYMVERS"
    else
        warn "  BLAD: $subdir"; ERRORS+=("$subdir")
        echo -e "${RED}  --- Bledy w $subdir ---${NC}" | tee -a "$LOG"
        grep -E "^.*error:" "$MODULE_LOG" | sed "s|$SRC/||" | sort -u | head -30 \
            | while read -r line; do echo -e "  ${RED}>>>${NC} $line" | tee -a "$LOG"; done
        echo -e "${RED}  ---${NC}" | tee -a "$LOG"
    fi
    rm -f "$MODULE_LOG"
done

step "Wynik kompilacji"
KO_COUNT=$(find "$SRC/drivers/media" -name "*.ko" 2>/dev/null | wc -l)

if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo -e "${YELLOW}  ╔════════════════════════════╗"
    echo -e "  ║  KOMPILACJA CZESCIOWA      ║"
    echo -e "  ╚════════════════════════════╝${NC}"
    for e in "${ERRORS[@]}"; do warn "  BLAD: $e"; done
    info "Skompilowane:"; for s in "${SUCCESS[@]}"; do echo "    OK: $s" | tee -a "$LOG"; done
    info "Modulow .ko: $KO_COUNT"
    warn "Co dalej: dodaj patch do kernel-patches.sh i uruchom ponownie"
    warn "Log: $LOG"
    exit 1
fi

echo -e "${GREEN}  ╔════════════════════════════╗"
echo -e "  ║  KOMPILACJA OK!            ║"
echo -e "  ╚════════════════════════════╝${NC}"
info "Skompilowane:"; for s in "${SUCCESS[@]}"; do echo "    OK: $s" | tee -a "$LOG"; done
info "Modulow .ko: $KO_COUNT"
find "$SRC/drivers/media" -name "*.ko" 2>/dev/null | sort \
    | while read -r f; do echo "    $(basename "$f")" | tee -a "$LOG"; done
info "Log: $LOG"

step "Instalacja modulow"
echo -e "${CYAN}  Instalowac moduly dla kernela ${KVER}?"
echo -e "  Cel: ${INSTALL_DIR}${NC}"
read -rp "  [t/N]: " ANSWER
if [[ "${ANSWER,,}" != "t" ]]; then
    warn "Instalacja pominieta. Moduly sa w: $SRC/drivers/media"
    exit 0
fi

info "Instaluje do: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
find "$SRC/drivers/media" -name "*.ko" | while read -r ko; do
    subpath="${ko#$SRC/drivers/media/}"
    destdir="$INSTALL_DIR/$(dirname "$subpath")"
    mkdir -p "$destdir"
    cp "$ko" "$destdir/"
    echo "  Skopiowano: $(basename "$ko")" | tee -a "$LOG"
done

info "depmod -a $KVER"
depmod -a "$KVER" 2>&1 | tee -a "$LOG"

echo -e "${GREEN}  ╔════════════════════════════╗"
echo -e "  ║  INSTALACJA OK!            ║"
echo -e "  ║  Uruchom ponownie system.  ║"
echo -e "  ╚════════════════════════════╝${NC}"
info "Katalog: $INSTALL_DIR / Log: $LOG"
