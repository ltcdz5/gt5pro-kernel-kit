#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/lse_build4.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# LSE 6.1 适配第 3 轮: 修 6.1/6.6 头包含顺序(account_group_exec_runtime), 继续往出 .ko 推
set -u
C=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
L=/home/builder/kwork/lse
S=/home/builder/opt10probe/vmlinux.symvers.opt10
OUT=/home/builder/opt10probe
MD=$C/drivers/staging/lunarkernel_sched_extention
export PATH="/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
cd "$C" || exit 1
git config --global --add safe.directory "$C" 2>/dev/null

cleanup() {
  rm -f "$MD"
  [ -f /tmp/lse_Makefile.orig ] && cp -f /tmp/lse_Makefile.orig "$L/Makefile"
  [ -f /tmp/lse_main.h.orig ] && cp -f /tmp/lse_main.h.orig "$L/lse_main.h"
  [ -f /tmp/lse_tse.c.orig ] && cp -f /tmp/lse_tse.c.orig "$L/lse_task_struct_ext.c"
  git checkout -- drivers/staging/Makefile drivers/staging/Kconfig 2>/dev/null
  rm -f out/Module.symvers
  git -C "$L" clean -fdq 2>/dev/null; git -C "$L" checkout -- . 2>/dev/null
  echo "  内核树脏=$(git status --porcelain|wc -l)  LSE脏=$(git -C $L status --porcelain|wc -l)"
}

echo "=== 0) 起点 $(date)  树脏=$(git status --porcelain|wc -l) ==="
git -C "$L" clean -fdq 2>/dev/null; git -C "$L" checkout -- . 2>/dev/null
echo "  whoami=$(whoami)  LSE=$(cd $L && git rev-parse --short HEAD)"

echo '=== 1) 两处适配补丁(都只动它自己的文件, 收尾还原) ==='
cp -f "$L/Makefile" /tmp/lse_Makefile.orig
cp -f "$L/lse_main.h" /tmp/lse_main.h.orig
cp -f "$L/lse_task_struct_ext.c" /tmp/lse_tse.c.orig
printf '\nccflags-y += -I$(src)\n' >> "$L/Makefile"
for f in lse_main.h lse_task_struct_ext.c; do
  grep -q 'linux/sched/cputime.h' "$L/$f" || \
    sed -i 's|^#include <\.\./kernel/sched/sched\.h>$|#include <linux/sched/cputime.h>\n#include <../kernel/sched/sched.h>|' "$L/$f"
done
grep -n "cputime.h\|kernel/sched/sched.h" "$L/lse_main.h" "$L/lse_task_struct_ext.c" | sed 's/^/  /'

echo '=== 2) 供 Module.symvers ==='
cp -f "$S" out/Module.symvers; echo "  行数=$(wc -l < out/Module.symvers)"

echo '=== 3) 接进 staging ==='
ln -sfn "$L" "$MD"
grep -q lunarkernel "$C/drivers/staging/Makefile" || printf '\nobj-m += lunarkernel_sched_extention/\n' >> "$C/drivers/staging/Makefile"
grep -q lunarkernel "$C/drivers/staging/Kconfig" || sed -i '/^endmenu/i source "drivers/staging/lunarkernel_sched_extention/Kconfig"' "$C/drivers/staging/Kconfig"

echo "=== 4) 编 $(date) ==="
make -C "$C" O=out ARCH=arm64 LLVM=1 CC="ccache clang" LD=ld.lld \
     CROSS_COMPILE=aarch64-linux-gnu- CLANG_TRIPLE=aarch64-linux-gnu- \
     M="$MD" CONFIG_LUNAR_SCHED_EXT=m modules > /tmp/lse4.log 2>&1
RC=$?
echo "  退出码=$RC  error=$(grep -cE 'error:' /tmp/lse4.log)  未解决=$(grep -c 'undefined!' /tmp/lse4.log)"
grep -E "error:" /tmp/lse4.log | sed -E 's@.*/(lse[a-z_]*\.c|cpufreq_lse\.c|trace_lse\.h|lse_main\.h):([0-9]+):[0-9]+: error:@  ⛔ \1:\2: @' | sort -u | head -14
grep -E "undefined!" /tmp/lse4.log | head -14 | sed 's/^/  ⛔/'
KO=$(find "$MD/" -maxdepth 1 -name "*.ko" 2>/dev/null | head -1)
if [ -z "$KO" ]; then
  echo "  ⇒ 无 .ko"
else
  cp -f "$KO" "$OUT/lunar_bsp_ext_sched.ko"; K="$OUT/lunar_bsp_ext_sched.ko"
  echo "  ✅ 产出 $(stat -c%s "$K") 字节"; md5sum "$K" | sed 's/^/  /'
  echo '=== 5) 符号差 ==='
  python3 - "$K" "$S" <<'PY'
import sys, subprocess
ko, sym = sys.argv[1], sys.argv[2]
got = ""
for tool in (["llvm-nm","-u",ko], ["nm","-u",ko]):
    try:
        r = subprocess.run(tool, capture_output=True, text=True)
        if r.returncode == 0 and r.stdout.strip(): got = r.stdout; break
    except FileNotFoundError: continue
need = sorted({l.split()[-1] for l in got.splitlines() if l.strip()})
have = set()
for line in open(sym):
    t = line.rstrip("\n").split("\t")
    if len(t) >= 4: have.add(t[1])
miss = [n for n in need if n not in have]
print("  需要=%d  可提供=%d  缺=%d" % (len(need), len(need)-len(miss), len(miss)))
for m in miss: print("     缺:", m)
PY
  echo '=== 6) vermagic ==='
  strings -a "$K" | grep -m1 "^vermagic=" | sed 's/^/  /'
fi
echo '=== 7) 撤干净 ==='
cleanup
echo "=== 结束 $(date) ==="
