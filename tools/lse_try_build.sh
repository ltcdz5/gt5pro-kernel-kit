#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/lse_try_build.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 按 LSE 自己 README 的方式接进 drivers/staging(只加一个软链接, 事后删掉, 不 commit)
# 目的: 编出 .ko, 再逐符号比它的未定义引用 vs 我们 opt10 的导出表
set -u
C=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
L=/home/builder/kwork/lse
S=/home/builder/opt10probe/vmlinux.symvers.opt10
MD=$C/drivers/staging/lunarkernel_sched_extention
export PATH="/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
cd "$C" || exit 1
git config --global --add safe.directory "$C" 2>/dev/null

echo "=== 0) 自证 $(date) ==="
echo "  whoami=$(whoami)  分支=$(git rev-parse --abbrev-ref HEAD)"
clang --version | head -1 | sed 's/^/  /'

echo '=== 1) 接入(软链接 + 两行追加, 全部可删) ==='
ln -sfn "$L" "$MD"
MK=$C/drivers/staging/Makefile; KC=$C/drivers/staging/Kconfig
grep -q lunarkernel "$MK" || printf '\nobj-m += lunarkernel_sched_extention/\n' >> "$MK"
grep -q lunarkernel "$KC" || sed -i '/^endmenu/i source "drivers/staging/lunarkernel_sched_extention/Kconfig"' "$KC"
echo "  软链接: $(readlink "$MD")"
echo "  脏文件数=$(git status --porcelain | wc -l)(应只有 Makefile/Kconfig/软链接)"

echo '=== 2) 只编这个外部模块目录 $(date) ==='
make -C "$C" O=out ARCH=arm64 LLVM=1 CC="ccache clang" LD=ld.lld \
     CROSS_COMPILE=aarch64-linux-gnu- CLANG_TRIPLE=aarch64-linux-gnu- \
     M="$MD" CONFIG_LUNAR_SCHED_EXT=m modules > /tmp/lse.log 2>&1
RC=$?
echo "  退出码=$RC"
grep -E "error:|Error " /tmp/lse.log | head -14 | sed 's/^/  ⛔ /'
KO=$(find "$MD" -name "*.ko" 2>/dev/null | head -1)
if [ -z "$KO" ]; then
  echo "  ⇒ 没产出 .ko。停在编译层, 日志尾 22 行:"; tail -22 /tmp/lse.log
else
  echo "  产出: $(basename "$KO") $(stat -c%s "$KO") 字节"
  echo '=== 3) 它的未定义符号 vs opt10 导出表 ==='
  python3 - "$KO" "$S" <<'PY'
import sys, subprocess
ko, sym = sys.argv[1], sys.argv[2]
got = None
for tool in (["llvm-nm","-u",ko], ["aarch64-linux-gnu-nm","-u",ko], ["nm","-u",ko]):
    try:
        r = subprocess.run(tool, capture_output=True, text=True)
        if r.returncode == 0 and r.stdout.strip():
            got = r.stdout; break
    except FileNotFoundError:
        continue
need = sorted({l.split()[-1] for l in got.splitlines() if l.strip()}) if got else []
have = set()
for line in open(sym):
    t = line.rstrip("\n").split("\t")
    if len(t) >= 4: have.add(t[1])
miss = [n for n in need if n not in have]
print("  需要=%d  可提供=%d  缺=%d" % (len(need), len(need)-len(miss), len(miss)))
vh = [m for m in miss if "vh_" in m or "tracepoint" in m]
print("  --- 缺的 vendor hook/tracepoint(%d):" % len(vh))
for m in vh[:20]: print("     ", m)
print("  --- 其余缺失(前 20):")
for m in [x for x in miss if x not in vh][:20]: print("     ", m)
PY
  echo '=== 4) vermagic ==='
  strings -a "$KO" | grep -m1 vermagic | sed 's/^/  /'
fi

echo '=== 5) 收尾: 把接入痕迹撤干净 ==='
rm -f "$MD"
sed -i '/lunarkernel_sched_extention/d' "$MK"
sed -i '/drivers\/staging\/lunarkernel_sched_extention\/Kconfig/d' "$KC"
echo "  撤完 脏=$(git status --porcelain | wc -l)"
git status --porcelain | head -5 | sed 's/^/    /'
echo "=== 结束 $(date) ==="
