#!/bin/bash
# kernel-patches.sh - FINAL
# DZIAŁA TYLKO NA: kernel 7.x
# KARTY: TBS 6922 + TBS 6902
#
# TBS repo jest frozen na kernel 6.12 - wszystkie zmiany API do 7.0
# muszą być patchowane. Ten plik zawiera WSZYSTKIE potrzebne patche.
# Nie ma wykrywania wersji - patche są aplikowane zawsze (są idempotentne).

apply_kernel_api_patches() {
    step "Aplikowanie patchy API kernela (${KVER})"

    # ========================================================================
    # 1. from_timer -> timer_container_of (zmiana API w 6.19)
    # ========================================================================
    apply_sed_if_match \
        "$SRC/drivers/media/dvb-core/dmxdev.c" \
        "dmxdev: from_timer -> timer_container_of" \
        "from_timer(dmxdevfilter" \
        's/from_timer(\(dmxdevfilter\), t, timer)/timer_container_of(dmxdevfilter, t, timer)/g'

    # ========================================================================
    # 2. del_timer -> timer_delete (zmiana API w 6.19)
    # ========================================================================
    apply_sed_if_match \
        "$SRC/drivers/media/dvb-core/dmxdev.c" \
        "dmxdev: del_timer -> timer_delete" \
        "del_timer(" \
        's/del_timer(/timer_delete(/g'

    # ========================================================================
    # 3. dvb_vb2_fill_buffer + flush=NULL (zmiana API w 6.19)
    # ========================================================================
    apply_python_patch \
        "$SRC/drivers/media/dvb-core/dmxdev.c" \
        "dmxdev: dvb_vb2_fill_buffer +flush=NULL" \
        "dvb_vb2_fill_buffer" \
        'import sys, re
f = sys.argv[1]; txt = open(f).read()
pat = re.compile(r"dvb_vb2_fill_buffer(\([^)]+?),(\s*buffer_flags\s*)\)", re.DOTALL)
new = pat.sub(r"\1, NULL, \2)", txt)
if new != txt:
    open(f,"w").write(new); print("  OK: dodano flush=NULL")
else:
    print("  Brak wywolan do poprawki")'

    # ========================================================================
    # 4. avl6882.h: IS_REACHABLE -> bezwarunkowy extern (zmiana API w 6.19)
    # ========================================================================
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
    print("  Brak bloku IS_REACHABLE")'

    # ========================================================================
    # 5. cxd2820r: gpio_chip.set void -> int (zmiana API w 6.19)
    # ========================================================================
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
    print("  Brak zmian")'

    # ========================================================================
    # 6. cxd2820r: return; -> return 0; (po zmianie sygnatury)
    # ========================================================================
    apply_sed_if_match \
        "$SRC/drivers/media/dvb-frontends/cxd2820r_core.c" \
        "cxd2820r: gpio_set return; -> return 0;" \
        "static int cxd2820r_gpio_set" \
        '/static int cxd2820r_gpio_set/,/^}/ s/^\(\s*\)return;$/\1return 0;/'

    # ========================================================================
    # 7. dvb-pll: ida_simple_get -> ida_alloc_max (zmiana API w 6.19)
    # ========================================================================
    apply_sed_if_match \
        "$SRC/drivers/media/dvb-core/dvb-pll.c" \
        "dvb-pll: ida_simple_get -> ida_alloc_max" \
        "ida_simple_get" \
        's/ida_simple_get(\([^,]*\), 0, 0,/ida_alloc_max(\1, INT_MAX,/g; s/ida_simple_remove/ida_free/g'

    # ========================================================================
    # 8. dvb_vb2_init + mutex (zmiana API w 7.0 - nowy argument)
    # ========================================================================
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
    print("  Brak zmian")'

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
    print("  Brak zmian")'

    # ========================================================================
    # 9. mxl58x: __maybe_unused (BŁĄD W KODZIE TBS, nie zmiana API kernela)
    #    Potrzebny na wszystkich kernelach, bo TBS ma nieużywane funkcje.
    # ========================================================================
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

    info "Patche zastosowane."
}