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
#
# VERSIONING POLICY:
#   Script requires kernel 7.0+. All known patches are unconditional
#   (always applied), because the TBS repo does not track mainline kernel API changes.
#   Idempotency (marker check) ensures patches won't corrupt code if TBS
#   ever fixes their sources upstream.
#
#   When a new error appears specific to a particular version (e.g. 7.3+),
#   wrap it in: if ker_ge 7 3; then ... fi

apply_kernel_api_patches() {
    step "Applying kernel API patches (${KVER})"

    # -----------------------------------------------------------------------
    # dvb-core/dmxdev.c
    #
    # TBS repo does not sync dmxdev.c with mainline. All patches below address
    # API changes introduced in kernel 6.19+ and still required on 7.x.
    # Applied unconditionally (marker check handles idempotency).
    # -----------------------------------------------------------------------
    pi "dmxdev.c: API patches..."

    # from_timer() -> timer_container_of()
    # Kernel 6.19: from_timer() removed, replaced by timer_container_of().
    apply_sed_if_match \
        "$SRC/drivers/media/dvb-core/dmxdev.c" \
        "dmxdev: from_timer -> timer_container_of" \
        "from_timer(dmxdevfilter" \
        's/from_timer(\(dmxdevfilter\), t, timer)/timer_container_of(dmxdevfilter, t, timer)/g'

    # del_timer() -> timer_delete()
    # Kernel 6.19: del_timer() replaced by timer_delete().
    apply_sed_if_match \
        "$SRC/drivers/media/dvb-core/dmxdev.c" \
        "dmxdev: del_timer -> timer_delete" \
        "del_timer(" \
        's/del_timer(/timer_delete(/g'

    # dvb_vb2_fill_buffer: 4 args -> 5 (added flush=NULL)
    # Kernel 6.19: dvb_vb2_fill_buffer macro extended with flush argument.
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
    print("  No calls to patch")'

    # dvb_vb2_init: 3 args -> 4 (added mutex)
    # Kernel 7.0: dvb_vb2_init() extended with struct mutex *mutex as 3rd argument.
    #   Old signature: dvb_vb2_init(ctx, name, non_blocking)
    #   New signature: dvb_vb2_init(ctx, name, mutex, non_blocking)
    # Call 1: dvb_dvr_open    -> &dmxdev->dvr_vb2_ctx,  mutex = &dmxdev->mutex
    # Call 2: dvb_demux_open  -> &dmxdevfilter->vb2_ctx, mutex = &dmxdev->mutex
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
    print("  No changes needed (already patched?)")'

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
    print("  No changes needed (already patched?)"'

    # -----------------------------------------------------------------------
    # dvb-frontends/avl6882.h
    #
    # IS_REACHABLE(CONFIG_DVB_AVL6882) block -> unconditional extern.
    # When compiling out-of-tree, IS_REACHABLE expands to 0, hiding the
    # attach prototype and causing a linker error.
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
    print("  IS_REACHABLE block not found (already patched?)"'

    # -----------------------------------------------------------------------
    # dvb-frontends/cxd2820r_core.c
    #
    # gpio_chip.set: signature change void -> int
    # Kernel 6.19: .set callback in struct gpio_chip changed return type
    # from void to int. TBS has old void declaration causing type mismatch.
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
    print("  No changes needed")'

    # After void -> int change, function must return 0 instead of bare return.
    apply_sed_if_match \
        "$SRC/drivers/media/dvb-frontends/cxd2820r_core.c" \
        "cxd2820r: gpio_set return; -> return 0;" \
        "static int cxd2820r_gpio_set" \
        '/static int cxd2820r_gpio_set/,/^}/ s/^\(\s*\)return;$/\1return 0;/'

    # -----------------------------------------------------------------------
    # dvb-frontends/mxl58x.c
    #
    # Unused static functions -> __maybe_unused.
    # TBS code bug (not a kernel API change) - affects all kernels.
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
    # If a patch is specific to a kernel version (e.g. error first appeared in 7.3):
    #   if ker_ge 7 3; then
    #       apply_sed_if_match ...
    #   fi
    # -----------------------------------------------------------------------

    [[ "$DRY_RUN" -eq 1 ]] && info "Dry-run: done." || info "All patches applied."
}
