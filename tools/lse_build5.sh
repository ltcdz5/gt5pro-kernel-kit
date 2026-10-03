#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/lse_build5.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# LSE 第 4 轮: 去掉 gcov 插桩重编 -> 推到设备 -> insmod -> 读回一切
set -u
C=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
L=/home/builder/kwork/lse
OUT=/home/builder/opt10probe
MD=$C/drivers/staging/lunarkernel_sched_extention
ADB="D:/gaojizhushou/adb.exe"
export PATH="/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
cd "$C" || exit 1
git config --global --add safe.directory "$C" 2>/dev/null

cleanup() {
  rm -f "$MD"; cp -f /tmp/lse_Makefile.orig "$L/Makefile" 2>/dev/null
  [ -f /tmp/lse_main.h.orig ] && cp -f /tmp/lse_main.h.orig "$L/lse_main.h"
  [ -f /tmp/lse_tse.c.orig ] && cp -f /tmp/lse_tse.c.orig "$L/lse_task_struct_ext.c"
  git checkout -- drivers/staging/Makefile drivers/staging/Kconfig 2>/dev/null
  rm -f out/Module.symvers
  git -C "$L" clean -fdq 2>/dev/null; git -C "$L" checkout -- . 2>/dev/null
  echo "  内核树脏=$(git status --porcelain|wc -l)  LSE脏=$(git -C $L status --porcelain|wc -l)"
}

echo "=== 0) 起点 $(date) ==="
git -C "$L" clean -fdq 2>/dev/null; git -C "$L" checkout -- . 2>/dev/null
echo "  whoami=$(whoami) 树脏=$(git status --porcelain|wc -l)"

echo '=== 1) 三处适配: -I$(src) / cputime 头顺序 / 去掉 GCOV 插桩 ==='
cp -f "$L/Makefile" /tmp/lse_Makefile.orig
cp -f "$L/lse_main.h" /tmp/lse_main.h.orig
cp -f "$L/lse_task_struct_ext.c" /tmp/lse_tse.c.orig
printf '\nccflags-y += -I$(src)\n' >> "$L/Makefile"
sed -i 's/^GCOV_PROFILE := y/GCOV_PROFILE :=/' "$L/Makefile"
for f in lse_main.h lse_task_struct_ext.c; do
  grep -q 'linux/sched/cputime.h' "$L/$f" || \
    sed -i 's|^#include <\.\./kernel/sched/sched\.h>$|#include <linux/sched/cputime.h>\n#include <../kernel/sched/sched.h>|' "$L/$f"
done
grep -nE "GCOV|ccflags" "$L/Makefile" | sed 's/^/  /'

echo '=== 2) 供 Module.symvers + 接进 staging ==='
cp -f /home/builder/opt10probe/vmlinux.symvers.opt10 out/Module.symvers
ln -sfn "$L" "$MD"
grep -q lunarkernel "$C/drivers/staging/Makefile" || printf '\nobj-m += lunarkernel_sched_extention/\n' >> "$C/drivers/staging/Makefile"
grep -q lunarkernel "$C/drivers/staging/Kconfig" || sed -i '/^endmenu/i source "drivers/staging/lunarkernel_sched_extention/Kconfig"' "$C/drivers/staging/Kconfig"

echo "=== 3) 编 $(date) ==="
make -C "$C" O=out ARCH=arm64 LLVM=1 CC="ccache clang" LD=ld.lld \
     CROSS_COMPILE=aarch64-linux-gnu- CLANG_TRIPLE=aarch64-linux-gnu- \
     M="$MD" CONFIG_LUNAR_SCHED_EXT=m modules > /tmp/lse5.log 2>&1
RC=$?
echo "  退出码=$RC error=$(grep -cE 'error:' /tmp/lse5.log) 未解决=$(grep -c 'undefined!' /tmp/lse5.log)"
grep -E "error:|undefined!" /tmp/lse5.log | head -10 | sed 's/^/  ⛔ /'
KO=$(find "$MD/" -maxdepth 1 -name "*.ko" 2>/dev/null | head -1)
[ -z "$KO" ] && { echo "  ⇒ 无 .ko, 停"; cleanup; exit 1; }
cp -f "$KO" "$OUT/lunar_bsp_ext_sched.ko"
K="$OUT/lunar_bsp_ext_sched.ko"
echo "  ✅ 去插桩后 $(stat -c%s "$K") 字节(上一版 1,496,664)  md5=$(md5sum "$K" | cut -c1-32)"
strings -a "$K" | grep -m1 "^vermagic=" | sed 's/^/  /'
echo "  gcov 残留符号=$(strings -a "$K" | grep -c gcov)"

echo '=== 4) 撤构建接线 ==='
cleanup
ls -l "$K" | sed 's/^/  成品留下: /'
echo "=== 结束 $(date) ==="
