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
    print("  No changes needed (already patched?)")'

    # -----------------------------------------------------------------------
    # dvb-frontends/dvb-pll.c
    #
    # ida_simple_get/ida_simple_remove -> ida_alloc_max/ida_free
    # Kernel 6.19: old IDA simple API removed. NOTE: dvb-pll.c is not part
    # of this installer's build targets (nothing links dvb_pll_attach), so
    # this patch is defensive - it keeps the whole tree buildable if the
    # module is ever added. File lives in dvb-frontends/, not dvb-core/.
    # -----------------------------------------------------------------------
    apply_sed_if_match \
        "$SRC/drivers/media/dvb-frontends/dvb-pll.c" \
        "dvb-pll: ida_simple_get/remove -> ida_alloc_max/ida_free" \
        "ida_simple_get(&pll_ida" \
        's/ida_simple_get(&pll_ida, 0, DVB_PLL_MAX, GFP_KERNEL)/ida_alloc_max(&pll_ida, DVB_PLL_MAX - 1, GFP_KERNEL)/g'

    apply_sed_if_match \
        "$SRC/drivers/media/dvb-frontends/dvb-pll.c" \
        "dvb-pll: ida_simple_remove -> ida_free" \
        "ida_simple_remove(&pll_ida" \
        's/ida_simple_remove(&pll_ida, nr)/ida_free(&pll_ida, nr)/g'

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
    print("  IS_REACHABLE block not found (already patched?)")'

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

    # =========================================================================
    # PERFORMANCE PATCHES — disabled by default.
    # Enable with:  TBS_PERF=1 sudo bash install_tbsdtv-smart.sh
    # These modify timing/sleeps only (no data-path or register changes),
    # but they are NOT upstream-tested - A/B on your hardware before keeping.
    # Revert: remove TBS_PERF=1 AND rm -rf /usr/src/tbs-drivers (sources are
    # patched in place; a rebuild alone does not restore originals).
    # =========================================================================
    if [[ "${TBS_PERF:-0}" != "1" ]]; then
        info "Performance patches disabled (set TBS_PERF=1 to enable)"
    else
    warn "TBS_PERF=1: applying experimental performance patches"

    # -----------------------------------------------------------------------
    # dvb-frontends/si2183.c — performance tuning (TBS-only driver)
    #
    # 1) si2183_get_tune_settings(): blind settle delay 900 ms -> 300 ms.
    #    The Si2183 firmware reports lock quickly; 900 ms per zap is pure
    #    user-visible latency. A/B test on target hardware; revert this
    #    patch if lock instability appears.
    # 2) si2183_tune(): status poll interval HZ/5 (200 ms) -> HZ/10 (100 ms)
    #    while searching for lock. Faster lock detection; slightly more I2C
    #    traffic (fine with 2-3 tuners).
    # -----------------------------------------------------------------------
    pi "si2183.c: performance patches..."

    apply_sed_if_match \
        "$SRC/drivers/media/dvb-frontends/si2183.c" \
        "si2183: min_delay_ms 900 -> 300" \
        "min_delay_ms = 900" \
        's/min_delay_ms = 900/min_delay_ms = 300/'

    apply_sed_if_match \
        "$SRC/drivers/media/dvb-frontends/si2183.c" \
        "si2183: lock poll HZ/5 -> HZ/10" \
        "*delay = HZ / 5;" \
        's/\*delay = HZ \/ 5;/\*delay = HZ \/ 10;/'

    # -----------------------------------------------------------------------
    # Performance patch set v2 — targeted at the user's cards:
    #   gx1133  = demod in TBS 6902 (TBSECP3)
    #   cx24117 = demod in Technotrend S2-4100 / TBS6922 (SAA716x)
    # All patches reduce blind waits / poll granularity. Idempotent.
    # -----------------------------------------------------------------------
    pi "gx1133.c / cx24117.c: performance patches v2..."

    # gx1133: ADC/core reset settle time in initfe 10ms -> 3ms (4x).
    apply_python_patch \
        "$SRC/drivers/media/dvb-frontends/gx1133.c" \
        "gx1133: initfe reset settle 10ms -> 3ms" \
        "static int gx1133_initfe" \
        'import sys
f = sys.argv[1]; txt = open(f).read()
a = txt.find("static int gx1133_initfe")
b = txt.find("static int gx1133_sleep")
if a < 0 or b < 0 or b < a:
    print("  anchors not found"); sys.exit(0)
seg = txt[a:b]
if "msleep(10);" not in seg:
    print("  already applied"); sys.exit(0)
open(f, "w").write(txt[:a] + seg.replace("msleep(10);", "msleep(3);") + txt[b:])
print("  OK: initfe resets 10ms -> 3ms")'

    # gx1133: tuner PLL settle after set_params 50ms -> 10ms (AV201x locks in ~1-2ms).
    apply_sed_if_match \
        "$SRC/drivers/media/dvb-frontends/gx1133.c" \
        "gx1133: tuner settle 50ms -> 10ms" \
        "msleep(50);" \
        's/msleep(50);/msleep(10);/'

    # gx1133: lock poll 20ms x 15 -> 10ms x 30 (same 300ms worst case, finer detection).
    apply_python_patch \
        "$SRC/drivers/media/dvb-frontends/gx1133.c" \
        "gx1133: lock poll 20ms/15 -> 10ms/30" \
        "i<15; i++" \
        'import sys
f = sys.argv[1]; txt = open(f).read()
old1 = "for (i = 0; i<15; i++) {"
old2 = "msleep(20);\n\t}\n\treturn -EINVAL;"
if old1 not in txt or old2 not in txt:
    print("  anchors not found"); sys.exit(0)
txt = txt.replace(old1, "for (i = 0; i<30; i++) {", 1)
txt = txt.replace(old2, "msleep(10);\n\t}\n\treturn -EINVAL;", 1)
open(f, "w").write(txt)
print("  OK: lock poll 20ms/15 -> 10ms/30")'

    # cx24117: firmware-command busy-wait granularity 20ms -> ~1ms.
    # Every CMD_* pays one dead poll tick (~10-19ms); a zap issues 4-6 commands.
    apply_python_patch \
        "$SRC/drivers/media/dvb-frontends/cx24117.c" \
        "cx24117: EXECUTE poll 20ms -> ~1ms" \
        "CX24117_REG_EXECUTE" \
        'import sys
f = sys.argv[1]; txt = open(f).read()
old = "while (cx24117_readreg(state, CX24117_REG_EXECUTE)) {\n\t\tmsleep(20);"
new = "while (cx24117_readreg(state, CX24117_REG_EXECUTE)) {\n\t\tusleep_range(900, 1100);"
if old not in txt:
    print("  anchor not found"); sys.exit(0)
open(f, "w").write(txt.replace(old, new, 1))
print("  OK: EXECUTE poll 20ms -> ~1ms")'

    # cx24117: lock wait loop 20ms x 50 -> 10ms x 100 (same 1s worst case for
    # the DVB-S2 ROLLOFF_AUTO retry chain, finer lock detection).
    apply_python_patch \
        "$SRC/drivers/media/dvb-frontends/cx24117.c" \
        "cx24117: lock wait 20ms/50 -> 10ms/100" \
        "for (i = 0; i < 50; i++)" \
        'import sys
f = sys.argv[1]; txt = open(f).read()
old1 = "for (i = 0; i < 50; i++) {"
old2 = "\t\t\tmsleep(20);\n\t\t}"
if old1 not in txt or old2 not in txt:
    print("  anchors not found"); sys.exit(0)
txt = txt.replace(old1, "for (i = 0; i < 100; i++) {", 1)
txt = txt.replace(old2, "\t\t\tmsleep(10);\n\t\t}", 1)
open(f, "w").write(txt)
print("  OK: lock wait 20ms/50 -> 10ms/100")'

    # gx1133 + cx24117: status poll interval while searching 200ms -> 100ms.
    apply_sed_if_match \
        "$SRC/drivers/media/dvb-frontends/gx1133.c" \
        "gx1133: tune poll HZ/5 -> HZ/10" \
        "*delay = HZ / 5;" \
        's|\*delay = HZ / 5;|\*delay = HZ / 10;|'
    apply_sed_if_match \
        "$SRC/drivers/media/dvb-frontends/cx24117.c" \
        "cx24117: tune poll HZ/5 -> HZ/10" \
        "*delay = HZ / 5;" \
        's|\*delay = HZ / 5;|\*delay = HZ / 10;|'

    # -----------------------------------------------------------------------
    # Performance patch set v3 - full-tree audit (all built frontends/tuners).
    # Applied files verified against tbsdtv/linux_media@latest.
    # Skipped (measurement windows / spec): stv0900, mb86a16, stb0899,
    #   cx24117 set_voltage, diseqc paths, firmware downloads.
    # -----------------------------------------------------------------------
    pi "v3: av201x/tas2101/si2168/stv6120/m88rs6060/avl6882/stv091x..."

    # av201x (tuner in many cards; 2x msleep(20) per retune -> msleep(5);
    # AV201x PLL locks in ~1-2 ms)
    apply_python_patch \
        "$SRC/drivers/media/tuners/av201x.c" \
        "av201x: retune settle 20ms -> 5ms (x2)" \
        "REG_TUNER_CTRL" \
        'import sys
f = sys.argv[1]; txt = open(f).read()
old1 = "msleep(20);\n\n\t/* set bandwidth */"
old2 = "ret |= av201x_wr(priv, REG_TUNER_CTRL, 0x96);\n\tmsleep(20);"
n = 0
if old1 in txt:
    txt = txt.replace(old1, "msleep(5);\n\n\t/* set bandwidth */", 1); n += 1
if old2 in txt:
    txt = txt.replace(old2, "ret |= av201x_wr(priv, REG_TUNER_CTRL, 0x96);\n\tmsleep(5);", 1); n += 1
if n == 0:
    print("  anchors not found"); sys.exit(0)
open(f, "w").write(txt)
print("  OK: av201x settles patched:", n)'

    # tas2101: lock poll granularity 20ms x 15 -> 10ms x 30 (same 300ms bound)
    apply_python_patch \
        "$SRC/drivers/media/dvb-frontends/tas2101.c" \
        "tas2101: lock poll 20ms/15 -> 10ms/30" \
        "for (i = 0; i<15; i++)" \
        'import sys
f = sys.argv[1]; txt = open(f).read()
hdr = "for (i = 0; i<15; i++) {"
i = txt.find(hdr)
if i < 0:
    print("  anchor not found"); sys.exit(0)
seg = txt[i:i+700]
if "msleep(20);" not in seg:
    print("  loop body anchor not found"); sys.exit(0)
seg = seg.replace("i<15", "i<30", 1).replace("msleep(20);", "msleep(10);", 1)
open(f, "w").write(txt[:i] + seg + txt[i+700:])
print("  OK: tas2101 poll 10ms/30")'

    apply_sed_if_match \
        "$SRC/drivers/media/dvb-frontends/tas2101.c" \
        "tas2101: tune poll HZ/5 -> HZ/10" \
        "*delay = HZ / 5;" \
        's|\*delay = HZ / 5;|\*delay = HZ / 10;|'

    # si2168: blind settle 900ms -> 300ms (same as si2183)
    apply_sed_if_match \
        "$SRC/drivers/media/dvb-frontends/si2168.c" \
        "si2168: min_delay_ms 900 -> 300" \
        "min_delay_ms = 900" \
        's/min_delay_ms = 900/min_delay_ms = 300/'

    # stv6120: redundant VCO-cal settle 10-12ms -> 2-3ms (cal-done already
    # awaited in wait_for_call_done)
    apply_python_patch \
        "$SRC/drivers/media/tuners/stv6120.c" \
        "stv6120: VCO settle 10ms -> 2ms" \
        "usleep_range(10000,12000);" \
        'import sys
f = sys.argv[1]; txt = open(f).read()
old = "usleep_range(10000,12000);"
if old not in txt:
    print("  anchor not found"); sys.exit(0)
open(f, "w").write(txt.replace(old, "usleep_range(2000,3000);", 1))
print("  OK: stv6120 VCO settle 2-3ms")'

    # m88rs6060: internal lock wait 20ms x 150 (3s blind) -> 10ms x 300
    apply_python_patch \
        "$SRC/drivers/media/dvb-frontends/m88rs6060.c" \
        "m88rs6060: lock wait 20ms/150 -> 10ms/300" \
        "for (i = 0; i < 150; i++)" \
        'import sys
f = sys.argv[1]; txt = open(f).read()
hdr = "for (i = 0; i < 150; i++) {"
i = txt.find(hdr)
if i < 0:
    print("  anchor not found"); sys.exit(0)
seg = txt[i:i+400]
if "msleep(20);" not in seg:
    print("  loop body anchor not found"); sys.exit(0)
seg = seg.replace("i < 150", "i < 300", 1).replace("msleep(20);", "msleep(10);", 1)
open(f, "w").write(txt[:i] + seg + txt[i+400:])
print("  OK: m88rs6060 lock wait 10ms/300")'

    # m88rs6060: tune poll HZ/2 (500ms!) -> HZ/10
    apply_sed_if_match \
        "$SRC/drivers/media/dvb-frontends/m88rs6060.c" \
        "m88rs6060: tune poll HZ/2 -> HZ/10" \
        "*delay = HZ / 2;" \
        's|\*delay = HZ / 2;|\*delay = HZ / 10;|'

    # avl6882: tune poll HZ/5 -> HZ/10
    apply_sed_if_match \
        "$SRC/drivers/media/dvb-frontends/avl6882.c" \
        "avl6882: tune poll HZ/5 -> HZ/10" \
        "*delay = HZ / 5;" \
        's|\*delay = HZ / 5;|\*delay = HZ / 10;|'

    # avl6882: firmware-cmd wait granularity 20ms -> 10ms per command
    apply_sed_if_match \
        "$SRC/drivers/media/dvb-frontends/avl6882.c" \
        "avl6882: DEMOD_WAIT_MS 20 -> 10" \
        "define DEMOD_WAIT_MS" \
        's|#define DEMOD_WAIT_MS\t\t(20)|#define DEMOD_WAIT_MS\t\t(10)|'

    # stv091x: tune poll HZ (1s!) -> HZ/10
    apply_sed_if_match \
        "$SRC/drivers/media/dvb-frontends/stv091x.c" \
        "stv091x: tune poll HZ -> HZ/10" \
        "*delay = HZ;" \
        's|\*delay = HZ;|\*delay = HZ / 10;|'

    fi # TBS_PERF

    # -----------------------------------------------------------------------
    # Add new patches above this line.
    # If a patch is specific to a kernel version (e.g. error first appeared in 7.3):
    #   if ker_ge 7 3; then
    #       apply_sed_if_match ...
    #   fi
    # -----------------------------------------------------------------------

    [[ "$DRY_RUN" -eq 1 ]] && info "Dry-run: done." || info "All patches applied."
}
