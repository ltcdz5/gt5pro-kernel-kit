#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/lse_build3.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# LSE 6.1 适配第 2 轮: 补 out/Module.symvers 让 MODPOST 出 .ko, 然后做符号差 + vermagic 核对
set -u
C=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
L=/home/builder/kwork/lse
S=/home/builder/opt10probe/vmlinux.symvers.opt10
OUT=/home/builder/opt10probe
MD=$C/drivers/staging/lunarkernel_sched_extention
export PATH="/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
cd "$C" || exit 1
git config --global --add safe.directory "$C" 2>/dev/null

echo "=== 0) 清掉上一轮在模块目录里的构建垃圾 $(date) ==="
git -C "$L" checkout -- . 2>/dev/null
git -C "$L" clean -fdq 2>/dev/null
echo "  LSE 脏=$(git -C $L status --porcelain | wc -l)  树脏=$(git status --porcelain | wc -l)"

echo '=== 1) 只加那一行 ccflags ==='
cp -f "$L/Makefile" /tmp/lse_Makefile.orig
printf '\nccflags-y += -I$(src)\n' >> "$L/Makefile"

echo '=== 2) 供上 Module.symvers(MODPOST 必需, 用 opt10 实测的 vmlinux.symvers) ==='
ls -l out/Module.symvers 2>&1 | sed 's/^/  前: /'
cp -f "$S" out/Module.symvers
echo "  后: out/Module.symvers 行数=$(wc -l < out/Module.symvers)"

echo '=== 3) 接进 staging ==='
ln -sfn "$L" "$MD"
grep -q lunarkernel "$C/drivers/staging/Makefile" || printf '\nobj-m += lunarkernel_sched_extention/\n' >> "$C/drivers/staging/Makefile"
grep -q lunarkernel "$C/drivers/staging/Kconfig" || sed -i '/^endmenu/i source "drivers/staging/lunarkernel_sched_extention/Kconfig"' "$C/drivers/staging/Kconfig"

echo "=== 4) 编 $(date) ==="
make -C "$C" O=out ARCH=arm64 LLVM=1 CC="ccache clang" LD=ld.lld \
     CROSS_COMPILE=aarch64-linux-gnu- CLANG_TRIPLE=aarch64-linux-gnu- \
     M="$MD" CONFIG_LUNAR_SCHED_EXT=m modules > /tmp/lse3.log 2>&1
RC=$?
echo "  退出码=$RC  error=$(grep -cE 'error:' /tmp/lse3.log)  未解决符号告警=$(grep -c 'undefined!' /tmp/lse3.log)"
grep -E "error:|undefined!" /tmp/lse3.log | head -20 | sed 's/^/  ⛔ /'
KO=$(find "$MD/" -maxdepth 1 -name "*.ko" 2>/dev/null | head -1)
if [ -z "$KO" ]; then
  echo "  ⇒ 还没出 .ko，日志尾 16 行:"; tail -16 /tmp/lse3.log | sed 's/^/    /'
else
  cp -f "$KO" "$OUT/lunar_bsp_ext_sched.ko"
  K="$OUT/lunar_bsp_ext_sched.ko"
  echo "  ✅ 产出 $(basename "$K")  $(stat -c%s "$K") 字节"
  md5sum "$K" | sed 's/^/  /'
  echo '=== 5) 它需要的内核符号 vs opt10 导出表 ==='
  python3 - "$K" "$S" <<'PY'
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
have = {}
for line in open(sym):
    t = line.rstrip("\n").split("\t")
    if len(t) >= 4: have[t[1]] = t[0]
miss = [n for n in need if n not in have]
print("  需要=%d  可提供=%d  缺=%d" % (len(need), len(need)-len(miss), len(miss)))
for m in miss: print("     缺:", m)
PY
  echo '=== 6) vermagic 与 CRC 段 ==='
  strings -a "$K" | grep -m1 "^vermagic=" | sed 's/^/  /'
  readelf -S "$K" 2>/dev/null | grep -E "__versions|vermagic" | sed 's/^/  /'
fi

echo '=== 7) 撤干净 ==='
rm -f "$MD"; cp -f /tmp/lse_Makefile.orig "$L/Makefile"
git checkout -- drivers/staging/Makefile drivers/staging/Kconfig
rm -f out/Module.symvers
echo "  内核树脏=$(git status --porcelain|wc -l)  LSE脏=$(git -C $L status --porcelain|wc -l)"
echo "=== 结束 $(date) ==="
