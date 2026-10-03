#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt10_iterate.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# opt10 迭代收敛: 编译(-k 全量普查) -> 报错 TU 反查我们改过的文件 -> 退回 -> 再编, 直到 0 错
set -u
T=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
OUT=/home/builder/opt10probe
W=/home/builder/opt10
cd "$T" || exit 1
export PATH="/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
git config --global --add safe.directory "$T" 2>/dev/null
MFLAGS='LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- CC="ccache clang" LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error'
MAXR=${MAXR:-6}
LOG=$W/iter.log; : > "$LOG"

set_sfx() { sed -i 's/^echo "-android14-11-o-ltcdz5-[a-z0-9]*"$/echo "-android14-11-o-ltcdz5-opt10"/' scripts/setlocalversion; }

echo "=== 起始 $(date)  whoami=$(whoami) ==="
clang --version | head -1
echo "起始改动文件=$(git diff --name-only | wc -l)"

echo "--- 第 0 轮: 退回头文件类改动(只留纯 .c 修复)"
git diff --name-only | grep -E '(\.h|\.tbl)$|^include/|^scripts/|^lib/Kconfig' > "$LOG.drop0" || true
echo "    退回 $(wc -l < "$LOG.drop0") 个头文件/生成脚本类改动"
sed 's/^/      - /' "$LOG.drop0" | head -25
xargs -a "$LOG.drop0" -r git checkout --
echo "    剩余改动文件=$(git diff --name-only | wc -l)"

for r in $(seq 1 $MAXR); do
  set_sfx
  echo "--- 第 $r 轮: make -k Image $(date +%H:%M:%S)"
  eval make -j"$(nproc --all)" $MFLAGS -k Image > "$LOG.r$r" 2>&1
  NERR=$(grep -cE "error:" "$LOG.r$r")
  CH=$(git diff --name-only | wc -l)
  echo "    改动文件=$CH  error 数=$NERR  用时看时间戳"
  if [ "$NERR" = "0" ]; then
    echo "    ==> 收敛, 编译 0 错"
    break
  fi
  # 报错涉及的 TU 路径(内核构建里写成 ../a/b/c.c)
  grep -oE '\.\./[A-Za-z0-9_./-]+\.(c|h):[0-9]+:[0-9]+: error:' "$LOG.r$r" \
    | sed -E 's@^\.\./@@; s@:[0-9]+:[0-9]+: error:@@' | sort -u > "$LOG.bad$r"
  # 与我们改过的文件求交(先按全路径, 再按 basename 兜底)
  git diff --name-only > "$LOG.ch$r"
  : > "$LOG.drop$r"
  while read -r bad; do
    [ -z "$bad" ] && continue
    grep -qxF "$bad" "$LOG.ch$r" && echo "$bad" >> "$LOG.drop$r"
    b=$(basename "$bad")
    grep -E "/$b\$" "$LOG.ch$r" >> "$LOG.drop$r"
  done < "$LOG.bad$r"
  sort -u "$LOG.drop$r" -o "$LOG.drop$r"
  echo "    报错 TU 数=$(wc -l < "$LOG.bad$r")  其中属于我们改过的=$(wc -l < "$LOG.drop$r")"
  sed 's/^/      - /' "$LOG.drop$r" | head -15
  if [ ! -s "$LOG.drop$r" ]; then
    echo "    ⛔ 有错但没有任何错落在我们改过的文件里 => 错在别的依赖上, 停(不硬编成功)"
    grep -E "error:" "$LOG.r$r" | head -10 | sed 's/^/      /'
    exit 2
  fi
  xargs -a "$LOG.drop$r" -r git checkout --
done

set_sfx
echo "=== 收敛后 $(date) ==="
echo "落地文件=$(git diff --name-only | wc -l)"
git diff --numstat | awk '{a+=$1; d+=$2} END {print "  合计 +" a " -" d}'
echo "  新增导出行数=$(git diff -U0 | grep -cE '^\+[[:space:]]*(EXPORT_SYMBOL|EXPORT_SYMBOL_GPL|DEFINE_HOOK|DECLARE_HOOK)' || true)"
echo "=== 正式再编一遍(不带 -k) ==="
eval make -j"$(nproc --all)" $MFLAGS Image > "$LOG.final" 2>&1
RC=$?
echo "  退出码=$RC  error=$(grep -cE 'error:' "$LOG.final")"
[ $RC -ne 0 ] && { tail -20 "$LOG.final"; exit 1; }
echo "=== 读数 + 两道闸 ==="
strings out/arch/arm64/boot/Image | grep -m1 'Linux version' | cut -c1-64 | sed 's/^/  /'
mkdir -p "$OUT"
cp -f out/vmlinux.symvers "$OUT/vmlinux.symvers.opt10"
cp -f out/System.map "$OUT/System.map.opt10"
cp -f out/arch/arm64/boot/Image "$OUT/Image.opt10"
md5sum "$OUT/Image.opt10" | sed 's/^/  /'
echo "  test_task_ux 镜像内=$(strings -a "$OUT/Image.opt10" | grep -c test_task_ux)  opt5基线=$(strings -a "$BASE/Image.opt5" | grep -c test_task_ux)"
python3 /mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/kernel-kit/tools/gate_new_exports.py "$OUT/vmlinux.symvers.opt10"
echo "  config 与 opt9 差异行数=$(diff "$W/config.opt9" out/.config | grep -cE '^[<>]')"
echo "=== 全类型布局比对 ==="
python3 - <<'PY'
import struct
PAT = bytes([0x9f, 0xeb, 0x01, 0x00, 0x18, 0x00, 0x00, 0x00])
d = open('/home/builder/opt10probe/Image.opt10', 'rb').read()
h = d.find(PAT)
to, tl, so, sl = struct.unpack_from('<IIII', d, h + 8)
open('/home/builder/abi/btf/opt10.btf', 'wb').write(d[h:h+24+to+tl+so+sl])
PY
pahole /home/builder/abi/btf/opt10.btf > /home/builder/abi/full/opt10.txt 2>/dev/null
echo "  全类型差异行数=$(diff /home/builder/abi/full/opt5.txt /home/builder/abi/full/opt10.txt | grep -cE '^[<>]')  (opt9=0 opt8=12)"
diff /home/builder/abi/full/opt5.txt /home/builder/abi/full/opt10.txt | grep -E '^[<>]' | head -16 | sed 's/^/    /'
echo "=== 最终落地清单 ==="
git diff --name-only | sed 's/^/  /'
echo "=== 结束 $(date) ==="
