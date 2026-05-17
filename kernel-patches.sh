# kernel-patches.sh
# Sourcowany przez install_tbsdtv-smart.sh
# Tu dopisuj nowe patche gdy kompilacja na nowym kernelu sie posypie.
#
# Dostepne funkcje (zdefiniowane w glownym skrypcie):
#   apply_sed_if_match FILE OPIS MARKER 'SED_WYRAZENIE'
#   apply_python_patch FILE OPIS MARKER 'KOD_PYTHON'
#   ker_ge  MAJOR MINOR        -> true jezeli biezacy kernel >= MAJOR.MINOR
#   ker_lt  MAJOR MINOR        -> true jezeli biezacy kernel <  MAJOR.MINOR
#   ker_in  MAJ1 MIN1 MAJ2 MIN2 -> true jezeli MAJ1.MIN1 <= kernel < MAJ2.MIN2
#
# Marker = unikalny fragment STAREGO kodu - jezeli nie istnieje, patch jest pomijany (idempotentne)
# SRC, DRY_RUN, pi, warn - dostepne z glownego skryptu
#
# ZASADA WERSJONOWANIA PATCHY:
#   - Uzyj ker_in gdy patch dotyczy konkretnego przedzialu wersji kernela.
#     Przyklad: ker_in 6 19 7 0  oznacza "dla kerneli >= 6.19 i < 7.0".
#   - Uzyj ker_ge bez gornej granicy tylko gdy jestes pewien, ze zmiana API
#     obowiazuje na wszystkich przyszlych kernelach (np. trwale usuniety symbol).
#   - Nie polegaj wylacznie na idempotentnosci markera jako jedynym
#     zabezpieczeniu przed aplikowaniem patcha na zly kernel.

apply_kernel_api_patches() {
    step "Aplikowanie patchy API kernela (${KVER})"

    # -----------------------------------------------------------------------
    # KERNEL 6.19.x  (tylko 6.19 - przed 7.0)
    #
    # Te zmiany API pojawily sie w 6.19 i zostaly wchłoniete przez TBS-repo
    # zanim trafily do 7.0. Jezeli okaza sie potrzebne rowniez dla 7.0+,
    # dodaj osobny blok ker_ge 7 0 ponizej (z nowym markerem jesli kod sie zmienil).
    # -----------------------------------------------------------------------
    if ker_in 6 19 7 0; then
        pi "Kernel 6.19.x..."

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

        apply_sed_if_match \
            "$SRC/drivers/media/dvb-core/dvb-pll.c" \
            "6.19 dvb-pll: ida_simple_get/remove -> ida_alloc_max/ida_free" \
            "ida_simple_get" \
            's/ida_simple_get(\([^,]*\), 0, 0,/ida_alloc_max(\1, INT_MAX,/g; s/ida_simple_remove/ida_free/g'

    fi

    # -----------------------------------------------------------------------
    # KERNEL 7.0+
    #
    # Blok otwarty: ker_ge 7 0 bez gornej granicy.
    # Jezeli w 7.x pojawi sie kolejna zmiana, zawez ten blok do ker_in 7 0 7 x
    # i dodaj nowy blok ker_in 7 x Y y ponizej.
    # -----------------------------------------------------------------------
    if ker_ge 7 0; then
        pi "Kernel >= 7.0..."

        # dvb_vb2_init() zmienilo sygnature w kernelu 7.0:
        #   Stara (TBS / do 6.x): dvb_vb2_init(ctx, name, non_blocking)
        #   Nowa  (7.0+):         dvb_vb2_init(ctx, name, mutex, non_blocking)
        #
        # Dwa wywolania w dmxdev.c:
        #   1) dvb_dvr_open    (~linia 173): ctx = &dmxdev->dvr_vb2_ctx,  mutex = &dmxdev->mutex
        #   2) dvb_demux_open  (~linia 818): ctx = &dmxdevfilter->vb2_ctx, mutex = &dmxdev->mutex
        #
        # Oba wywolania rozlozono na dwie linie:
        #   dvb_vb2_init(&dmxdev->dvr_vb2_ctx, "dvr",
        #                file->f_flags & O_NONBLOCK);
        # Po patchu:
        #   dvb_vb2_init(&dmxdev->dvr_vb2_ctx, "dvr",
        #                &dmxdev->mutex, file->f_flags & O_NONBLOCK);

        apply_python_patch \
            "$SRC/drivers/media/dvb-core/dmxdev.c" \
            "7.0 dmxdev: dvb_vb2_init +mutex (dvr_vb2_ctx)" \
            "dvb_vb2_init(&dmxdev->dvr_vb2_ctx" \
            'import sys, re
f = sys.argv[1]; txt = open(f).read()
pat = re.compile(
    r"(dvb_vb2_init\(&dmxdev->dvr_vb2_ctx,\s*\"dvr\",)\s*(file->f_flags\s*&\s*O_NONBLOCK\s*\))",
    re.DOTALL)
new = pat.sub(r"\1\n\t\t\t\t\t     &dmxdev->mutex, \2", txt)
if new != txt:
    open(f,"w").write(new); print("  OK: dodano &dmxdev->mutex (dvr)")
else:
    print("  Brak zmian (juz naprawione?)")'

        apply_python_patch \
            "$SRC/drivers/media/dvb-core/dmxdev.c" \
            "7.0 dmxdev: dvb_vb2_init +mutex (demux_filter)" \
            "dvb_vb2_init(&dmxdevfilter->vb2_ctx" \
            'import sys, re
f = sys.argv[1]; txt = open(f).read()
pat = re.compile(
    r"(dvb_vb2_init\(&dmxdevfilter->vb2_ctx,\s*\"demux_filter\",)\s*(file->f_flags\s*&\s*O_NONBLOCK\s*\))",
    re.DOTALL)
new = pat.sub(r"\1\n\t\t     &dmxdev->mutex, \2", txt)
if new != txt:
    open(f,"w").write(new); print("  OK: dodano &dmxdev->mutex (demux_filter)")
else:
    print("  Brak zmian (juz naprawione?)")'

        # Tu dopisuj kolejne patche dla 7.0+ w miare pojawiania sie bledow.
        # Jezeli patch dotyczy tylko wybranego przedzialu (np. 7.0-7.1), uzyj:
        #   if ker_in 7 0 7 2; then ... fi
        # wewnatrz tego bloku.

    fi

    # -----------------------------------------------------------------------
    # mxl58x.c: funkcje zdefiniowane ale nieuzywane -> __maybe_unused
    # Dotyczy wszystkich kerneli (blad w kodzie TBS, nie zmiana API kernela).
    # Trzy funkcje: write_register_block, extract_from_mnemonic, CfgDemodAbortTune
    # -----------------------------------------------------------------------
    pi "mxl58x: __maybe_unused dla nieuzywanych funkcji statycznych..."

    apply_sed_if_match \
        "$SRC/drivers/media/dvb-frontends/mxl58x.c" \
        "mxl58x: write_register_block __maybe_unused" \
        "static int write_register_block(" \
        's/static int write_register_block(/static int __maybe_unused write_register_block(/g'

    apply_sed_if_match \
        "$SRC/drivers/media/dvb-frontends/mxl58x.c" \
        "mxl58x: extract_from_mnemonic __maybe_unused" \
        "static void extract_from_mnemonic(" \
        's/static void extract_from_mnemonic(/static void __maybe_unused extract_from_mnemonic(/g'

    apply_sed_if_match \
        "$SRC/drivers/media/dvb-frontends/mxl58x.c" \
        "mxl58x: CfgDemodAbortTune __maybe_unused" \
        "static int CfgDemodAbortTune(" \
        's/static int CfgDemodAbortTune(/static int __maybe_unused CfgDemodAbortTune(/g'

    [[ "$DRY_RUN" -eq 1 ]] && info "Dry-run: koniec." || info "Patche zastosowane."
}
