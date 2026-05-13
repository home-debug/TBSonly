# kernel-patches.sh
# Sourcowany przez install_tbsdtv-smart.sh
# Tu dopisuj nowe patche gdy kompilacja na nowym kernelu sie posypie.
#
# Dostepne funkcje (zdefiniowane w glownym skrypcie):
#   apply_sed_if_match FILE OPIS MARKER 'SED_WYRAZENIE'
#   apply_python_patch FILE OPIS MARKER 'KOD_PYTHON'
#   ker_ge MAJOR MINOR  -> true jezeli biezacy kernel >= MAJOR.MINOR
#
# Marker = unikalny fragment STAREGO kodu - jezeli nie istnieje, patch jest pomijany (idempotentne)
# SRC, DRY_RUN, pi, warn - dostepne z glownego skryptu

apply_kernel_api_patches() {
    step "Aplikowanie patchy API kernela (${KVER})"

    # -----------------------------------------------------------------------
    # KERNEL 6.19
    # -----------------------------------------------------------------------
    if ker_ge 6 19; then
        pi "Kernel >= 6.19..."

        apply_sed_if_match \
            "$SRC/drivers/media/dvb-core/dmxdev.c" \
            "6.19 dmxdev: from_timer -> timer_container_of" \
            "from_timer(dmxdevfilter" \
            's/from_timer(\(dmxdevfilter\), t, timer)/timer_container_of(dmxdevfilter, t, timer)/g'

        apply_sed_if_match \
            "$SRC/drivers/media/dvb-core/dmxdev.c" \
            "6.19 dmxdev: del_timer -> timer_delete" \
            "del_timer(" \
            's/del_timer(/timer_delete(/g'

        apply_python_patch \
            "$SRC/drivers/media/dvb-core/dmxdev.c" \
            "6.19 dmxdev: dvb_vb2_fill_buffer +flush=NULL" \
            "dvb_vb2_fill_buffer" \
            'import sys, re
f = sys.argv[1]; txt = open(f).read()
pat = re.compile(r"dvb_vb2_fill_buffer(\([^)]+?),(\s*buffer_flags\s*)\)", re.DOTALL)
def add_null(m):
    s = m.group(0); return s[:s.rfind(")")] + ", NULL)"
new = pat.sub(add_null, txt)
if new != txt:
    open(f,"w").write(new); print("  OK: dodano flush=NULL")
else:
    print("  Brak wywolan do poprawki")'

        apply_python_patch \
            "$SRC/drivers/media/dvb-frontends/avl6882.h" \
            "6.19 avl6882.h: IS_REACHABLE -> bezwarunkowy extern" \
            "IS_REACHABLE(CONFIG_DVB_AVL6882)" \
            'import sys, re
f = sys.argv[1]; txt = open(f).read()
pat = re.compile(
    r"#if\s+IS_REACHABLE\(CONFIG_DVB_AVL6882\).*?"
    r"(extern\s+struct\s+dvb_frontend\s*\*\s*avl6882_attach[^;]+;)"
    r".*?#endif[^\n]*CONFIG_DVB_AVL6882[^\n]*", re.DOTALL)
new = pat.sub(r"\1", txt)
if new != txt:
    open(f,"w").write(new); print("  OK: zastapiono blok IS_REACHABLE")
else:
    print("  Brak bloku IS_REACHABLE (juz naprawione?)")'

        apply_python_patch \
            "$SRC/drivers/media/dvb-frontends/cxd2820r_core.c" \
            "6.19 cxd2820r: gpio_chip.set void -> int" \
            "static void cxd2820r_gpio_set" \
            'import sys
f = sys.argv[1]; txt = open(f).read()
new = txt.replace(
    "static void cxd2820r_gpio_set(struct gpio_chip *chip, unsigned nr, int val)",
    "static int cxd2820r_gpio_set(struct gpio_chip *chip, unsigned nr, int val)"
)
if new != txt:
    open(f,"w").write(new); print("  OK: gpio_set void -> int")
else:
    print("  Brak zmian do aplikacji")'

        apply_sed_if_match \
            "$SRC/drivers/media/dvb-frontends/cxd2820r_core.c" \
            "6.19 cxd2820r: gpio_set return; -> return 0;" \
            "static int cxd2820r_gpio_set" \
            '/static int cxd2820r_gpio_set/,/^}/ s/^\(\s*\)return;$/\1return 0;/'

    fi

    # -----------------------------------------------------------------------
    # KERNEL 7.x
    # Tu dopisz bledy z kompilacji na 7.x
    # -----------------------------------------------------------------------
    if ker_ge 7 0; then
        pi "Kernel >= 7.0 - brak patchy, uruchom kompilacje i zbierz bledy"
    fi

    [[ "$DRY_RUN" -eq 1 ]] && info "Dry-run: koniec." || info "Patche zastosowane."
}
