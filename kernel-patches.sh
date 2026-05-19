# kernel-patches.sh
# Sourcowany przez install_tbsdtv-smart.sh
# Tu dopisuj nowe patche gdy kompilacja na nowym kernelu sie posypie.
#
# Dostepne funkcje (zdefiniowane w glownym skrypcie):
#   apply_sed_if_match FILE OPIS MARKER 'SED_WYRAZENIE'
#   apply_python_patch FILE OPIS MARKER 'KOD_PYTHON'
#   ker_ge  MAJOR MINOR   -> true jezeli biezacy kernel >= MAJOR.MINOR
#
# Marker = unikalny fragment STAREGO kodu - jezeli nie istnieje, patch jest pomijany (idempotentne)
# SRC, DRY_RUN, pi, warn - dostepne z glownego skryptu
#
# ZASADA WERSJONOWANIA PATCHY:
#   Skrypt wymaga kernela 7.0+. Wszystkie znane patche sa bezwarunkowe
#   (stosowane zawsze), bo repo TBS nie synchronizuje kodu z mainline.
#   Idempotentnosc (marker) gwarantuje, ze patch nie uszkodzi kodu,
#   jesli TBS kiedys naprawi swoje zrodla.
#
#   Gdy pojawi sie nowy blad specyficzny dla konkretnej wersji (np. 7.3+),
#   uzyj bloku: if ker_ge 7 3; then ... fi

apply_kernel_api_patches() {
    step "Aplikowanie patchy API kernela (${KVER})"

    # -----------------------------------------------------------------------
    # dvb-core/dmxdev.c
    #
    # Repo TBS nie synchronizuje dmxdev.c z mainline. Wszystkie ponizsze
    # patche dotycza zmian API ktore weszly w kernelu 6.19 i obowiazuja
    # rowniez na 7.x. Stosujemy bezwarunkowo.
    # -----------------------------------------------------------------------
    pi "dmxdev.c: patche API..."

    # from_timer() -> timer_container_of()
    # Kernel 6.19: from_timer() usunieto, zastapiono timer_container_of().
    apply_sed_if_match \
        "$SRC/drivers/media/dvb-core/dmxdev.c" \
        "dmxdev: from_timer -> timer_container_of" \
        "from_timer(dmxdevfilter" \
        's/from_timer(\(dmxdevfilter\), t, timer)/timer_container_of(dmxdevfilter, t, timer)/g'

    # del_timer() -> timer_delete()
    # Kernel 6.19: del_timer() zastapiono przez timer_delete().
    apply_sed_if_match \
        "$SRC/drivers/media/dvb-core/dmxdev.c" \
        "dmxdev: del_timer -> timer_delete" \
        "del_timer(" \
        's/del_timer(/timer_delete(/g'

    # dvb_vb2_fill_buffer: 4 argumenty -> 5 (dodano flush=NULL)
    # Kernel 6.19: makro dvb_vb2_fill_buffer rozszerzone o argument flush.
    apply_python_patch \
        "$SRC/drivers/media/dvb-core/dmxdev.c" \
        "dmxdev: dvb_vb2_fill_buffer +flush=NULL" \
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

    # dvb_vb2_init: 3 argumenty -> 4 (dodano mutex)
    # Kernel 7.0: dvb_vb2_init() rozszerzone o struct mutex *mutex jako 3. argument.
    #   Stara sygnatura: dvb_vb2_init(ctx, name, non_blocking)
    #   Nowa sygnatura:  dvb_vb2_init(ctx, name, mutex, non_blocking)
    # Wywolanie 1: dvb_dvr_open   -> &dmxdev->dvr_vb2_ctx,  mutex = &dmxdev->mutex
    # Wywolanie 2: dvb_demux_open -> &dmxdevfilter->vb2_ctx, mutex = &dmxdev->mutex
    apply_python_patch \
        "$SRC/drivers/media/dvb-core/dmxdev.c" \
        "dmxdev: dvb_vb2_init +mutex (dvr_vb2_ctx)" \
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
        "dmxdev: dvb_vb2_init +mutex (demux_filter)" \
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

    # -----------------------------------------------------------------------
    # dvb-core/dvb-pll.c
    #
    # ida_simple_get/remove -> ida_alloc_max/ida_free
    # Kernel 6.19: stare helpery IDA usuniete z API kernela.
    # -----------------------------------------------------------------------
    apply_sed_if_match \
        "$SRC/drivers/media/dvb-core/dvb-pll.c" \
        "dvb-pll: ida_simple_get/remove -> ida_alloc_max/ida_free" \
        "ida_simple_get" \
        's/ida_simple_get(\([^,]*\), 0, 0,/ida_alloc_max(\1, INT_MAX,/g; s/ida_simple_remove/ida_free/g'

    # -----------------------------------------------------------------------
    # dvb-frontends/avl6882.h
    #
    # Blok IS_REACHABLE(CONFIG_DVB_AVL6882) -> bezwarunkowy extern.
    # Przy kompilacji out-of-tree IS_REACHABLE rozwija sie do 0, co chowa
    # prototyp attach i powoduje blad linkera.
    # -----------------------------------------------------------------------
    apply_python_patch \
        "$SRC/drivers/media/dvb-frontends/avl6882.h" \
        "avl6882.h: IS_REACHABLE -> bezwarunkowy extern" \
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

    # -----------------------------------------------------------------------
    # dvb-frontends/cxd2820r_core.c
    #
    # gpio_chip.set: zmiana sygnatury void -> int
    # Kernel 6.19: callback .set w struct gpio_chip zmienil typ zwracany
    # z void na int. TBS ma stara deklaracje void, co powoduje blad przypisania.
    # -----------------------------------------------------------------------
    apply_python_patch \
        "$SRC/drivers/media/dvb-frontends/cxd2820r_core.c" \
        "cxd2820r: gpio_chip.set void -> int" \
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

    # Po zmianie void -> int funkcja musi zwracac 0 zamiast pustego return.
    apply_sed_if_match \
        "$SRC/drivers/media/dvb-frontends/cxd2820r_core.c" \
        "cxd2820r: gpio_set return; -> return 0;" \
        "static int cxd2820r_gpio_set" \
        '/static int cxd2820r_gpio_set/,/^}/ s/^\(\s*\)return;$/\1return 0;/'

    # -----------------------------------------------------------------------
    # dvb-frontends/mxl58x.c
    #
    # Funkcje zdefiniowane ale nieuzywane -> __maybe_unused.
    # Blad w kodzie TBS (nie zmiana API kernela) - dotyczy wszystkich kerneli.
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

    # -----------------------------------------------------------------------
    # Dopisuj nowe patche powyzej tej linii.
    # Jesli patch dotyczy konkretnej wersji (np. blad pojawil sie dopiero w 7.3):
    #   if ker_ge 7 3; then
    #       apply_sed_if_match ...
    #   fi
    # -----------------------------------------------------------------------

    [[ "$DRY_RUN" -eq 1 ]] && info "Dry-run: koniec." || info "Patche zastosowane."
}
