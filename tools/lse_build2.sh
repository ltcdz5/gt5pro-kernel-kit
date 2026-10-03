#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/lse_build2.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# LSE 6.1 适配第 1 轮: 只加 ccflags 修 trace 头解析, 编 .ko, 再逐符号比导出表
set -u
C=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
L=/home/builder/kwork/lse
S=/home/builder/opt10probe/vmlinux.symvers.opt10
MD=$C/drivers/staging/lunarkernel_sched_extention
export PATH="/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
cd "$C" || exit 1
git config --global --add safe.directory "$C" 2>/dev/null

echo "=== 0) 自证 $(date) ==="
echo "  whoami=$(whoami)  分支=$(git rev-parse --abbrev-ref HEAD)  LSE=$(cd $L && git rev-parse --short HEAD)"
clang --version | head -1 | sed 's/^/  /'

echo '=== 1) 只改它自己的 Makefile 一行(加 -I$(src) 修 trace 路径解析) ==='
cp -f "$L/Makefile" /tmp/lse_Makefile.orig
grep -q 'ccflags-y' "$L/Makefile" || printf '\nccflags-y += -I$(src) -I$(srctree)/drivers/staging/lunarkernel_sched_extention\nGCOV_PROFILE :=\n' >> "$L/Makefile"
sed -i '/^GCOV_PROFILE :=$/d' "$L/Makefile"
tail -3 "$L/Makefile" | sed 's/^/  /'

echo '=== 2) 接进 staging(软链接+两行, 事后撤) ==='
ln -sfn "$L" "$MD"
grep -q lunarkernel "$C/drivers/staging/Makefile" || printf '\nobj-m += lunarkernel_sched_extention/\n' >> "$C/drivers/staging/Makefile"
grep -q lunarkernel "$C/drivers/staging/Kconfig" || sed -i '/^endmenu/i source "drivers/staging/lunarkernel_sched_extention/Kconfig"' "$C/drivers/staging/Kconfig"

echo "=== 3) 编 $(date) ==="
make -C "$C" O=out ARCH=arm64 LLVM=1 CC="ccache clang" LD=ld.lld \
     CROSS_COMPILE=aarch64-linux-gnu- CLANG_TRIPLE=aarch64-linux-gnu- \
     M="$MD" modules > /tmp/lse2.log 2>&1
RC=$?
echo "  退出码=$RC   error 行数=$(grep -cE 'error:' /tmp/lse2.log)   警告数=$(grep -c 'warning:' /tmp/lse2.log)"
grep -E "error:" /tmp/lse2.log | sed -E 's@^.*(/[^ :]+\.(c|h)):[0-9]+:[0-9]+: error:@\2: @' | sort -u | head -20 | sed 's/^/  ⛔ /'
KO=$(find "$MD/" -maxdepth 1 -name "*.ko" 2>/dev/null | head -1)
if [ -z "$KO" ]; then
  echo "  ⇒ 仍无 .ko。日志尾 18 行:"; tail -18 /tmp/lse2.log | sed 's/^/    /'
else
  cp -f "$KO" /home/builder/opt10probe/
  echo "  产出: $(basename "$KO") $(stat -c%s "$KO") 字节 → 已留副本到 opt10probe/"
  echo '=== 4) 它需要的内核符号 vs opt10 导出表 ==='
  python3 - "$KO" "$S" <<'PY'
import sys, subprocess
ko, sym = sys.argv[1], sys.argv[2]
got = ""
for tool in (["llvm-nm","-u",ko], ["nm","-u",ko]):
    try:
        r = subprocess.run(tool, capture_output=True, text=True)
        if r.returncode == 0 and r.stdout.strip():
            got = r.stdout; break
    except FileNotFoundError:
        continue
need = sorted({l.split()[-1] for l in got.splitlines() if l.strip()})
have = set()
for line in open(sym):
    t = line.rstrip("\n").split("\t")
    if len(t) >= 4: have.add(t[1])
miss = [n for n in need if n not in have]
print("  需要=%d  我们能提供=%d  缺=%d" % (len(need), len(need)-len(miss), len(miss)))
print("  --- 缺失清单(%d):" % len(miss))
for m in miss: print("     ", m)
PY
  echo '=== 5) 模块自校验 ==='
  strings -a "$KO" | grep -m1 "^vermagic" | sed 's/^/  /'
  echo "  它自己是否新增导出=$(llvm-nm --defined-only "$KO" 2>/dev/null | grep -c ' T \\| D ' ) 条(无关,模块导出不影响内核)"
fi

echo '=== 6) 撤干净 ==='
rm -f "$MD"; cp -f /tmp/lse_Makefile.orig "$L/Makefile"
git checkout -- drivers/staging/Makefile drivers/staging/Kconfig
echo "  内核树脏=$(git status --porcelain | wc -l)   LSE脏=$(cd $L && git status --porcelain | wc -l)"
echo "=== 结束 $(date) ==="
