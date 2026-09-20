# kernel-patches.sh
# Sourced by install_tbsdtv-smart.sh
# Add new patches here when compilation fails on a new kernel version.
#
# Available functions (defined in main script):
#   apply_sed_if_match FILE DESC MARKER 'SED_EXPRESSION'
#   apply_python_patch FILE DESC MARKER 'PYTHON_CODE'
#   ker_ge  MAJOR MINOR   -> true if current kernel >= MAJOR.MINOR
#
# MARKER = unique fragment of OLD code - patch is skipped if marker not found (idempotent)
# SRC, DRY_RUN, pi, warn - available from main script

apply_kernel_api_patches() {
    step "Applying kernel API patches (${KVER})"

    # -----------------------------------------------------------------------
    # dvb-core/dmxdev.c
    # -----------------------------------------------------------------------
    pi "dmxdev.c: API patches..."

    # from_timer() -> timer_container_of()
    apply_sed_if_match \
        "$SRC/drivers/media/dvb-core/dmxdev.c" \
        "dmxdev: from_timer -> timer_container_of" \
        "from_timer(dmxdevfilter" \
        's/from_timer(\(dmxdevfilter\), t, timer)/timer_container_of(dmxdevfilter, t, timer)/g'

    # del_timer() -> timer_delete()
    apply_sed_if_match \
        "$SRC/drivers/media/dvb-core/dmxdev.c" \
        "dmxdev: del_timer -> timer_delete" \
        "del_timer(" \
        's/del_timer(/timer_delete(/g'

    # dvb_vb2_fill_buffer: 4 args -> 5 (added flush=NULL)
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
    open(f,"w").write(new); print("  OK: added flush=NULL")
else:
    print("  No calls to patch")'''

    # dvb_vb2_init: 3 args -> 4 (added mutex)
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
    open(f,"w").write(new); print("  OK: added &dmxdev->mutex (dvr)")
else:
    print("  No changes needed (already patched?)")'''

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
    open(f,"w").write(new); print("  OK: added &dmxdev->mutex (demux_filter)")
else:
    print("  No changes needed (already patched?)")'''

    # -----------------------------------------------------------------------
    # dvb-frontends/avl6882.h
    # -----------------------------------------------------------------------
    apply_python_patch \
        "$SRC/drivers/media/dvb-frontends/avl6882.h" \
        "avl6882.h: IS_REACHABLE -> unconditional extern" \
        "IS_REACHABLE(CONFIG_DVB_AVL6882)" \
        'import sys, re
f = sys.argv[1]; txt = open(f).read()
pat = re.compile(
    r"#if\s+IS_REACHABLE\(CONFIG_DVB_AVL6882\).*?"
    r"(extern\s+struct\s+dvb_frontend\s*\*\s*avl6882_attach[^;]+;)"
    r".*?#endif[^\n]*CONFIG_DVB_AVL6882[^\n]*", re.DOTALL)
new = pat.sub(r"\1", txt)
if new != txt:
    open(f,"w").write(new); print("  OK: replaced IS_REACHABLE block")
else:
    print("  IS_REACHABLE block not found (already patched?)")'''

    # -----------------------------------------------------------------------
    # dvb-frontends/cxd2820r_core.c
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
    print("  No changes needed")'''

    # After void -> int change, function must return 0 instead of bare return.
    apply_sed_if_match \
        "$SRC/drivers/media/dvb-frontends/cxd2820r_core.c" \
        "cxd2820r: gpio_set return; -> return 0;" \
        "static int cxd2820r_gpio_set" \
        '/static int cxd2820r_gpio_set/,/^}/ s/^\(\s*\)return;$/\1return 0;/'

    # -----------------------------------------------------------------------
    # dvb-frontends/mxl58x.c
    # -----------------------------------------------------------------------
    pi "mxl58x: __maybe_unused for unused static functions..."

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
    # Add new patches above this line.
    # -----------------------------------------------------------------------

    [[ "$DRY_RUN" -eq 1 ]] && info "Dry-run: done." || info "All patches applied."
}
