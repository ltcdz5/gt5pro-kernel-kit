#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt12_resume.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# opt12 续跑: 修好 TU 抽取正则(含 fatal error)后, 只做"编译普查->按报错退回"迭代, 直到 0 错
set -u
T=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
W=/home/builder/opt12
export PATH="/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
cd "$T" || exit 1
git config --global --add safe.directory "$T" 2>/dev/null
MFLAGS='LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnuabeihf- CC="ccache clang" LD=ld.lld HOSTCC=clang HOSTLD=ld.lld O=out KCFLAGS+=-O2 KCFLAGS+=-Wno-error'

echo "=== 起点 $(date) 分支=$(git rev-parse --abbrev-ref HEAD) 改动=$(git diff --name-only|wc -l) ==="
for r in 1 2 3 4 5 6; do
  NOW=$(date +%s); BAD=$(find . \( -path ./out -o -path ./.git \) -prune -o -type f -newermt "@$((NOW+60))" -print 2>/dev/null|wc -l)
  [ "$BAD" -gt 0 ] && find . \( -path ./out -o -path ./.git \) -prune -o -type f -newermt "@$((NOW+60))" -exec touch {} + 2>/dev/null
  eval make -j"$(nproc --all)" $MFLAGS -k Image > "$W/resume.$r" 2>&1
  NERR=$(grep -cE "(fatal error| error):" "$W/resume.$r")
  echo "  第$r轮 $(date +%H:%M:%S) 改动=$(git diff --name-only|wc -l) 错=$NERR"
  [ "$NERR" = "0" ] && { echo "  ==> 0 错收敛"; break; }
  grep -oE '\.\./[A-Za-z0-9_./-]+\.(c|h|S):[0-9]+:[0-9]+: (fatal error|error):' "$W/resume.$r" \
    | sed -E 's@^\.\./@@; s@:[0-9]+:[0-9]+: (fatal error|error):@@' | sort -u > /tmp/rbad.$r
  git diff --name-only > /tmp/rch.$r; : > /tmp/rdr.$r
  while read -r x; do [ -z "$x" ] && continue
    grep -qxF "$x" /tmp/rch.$r && echo "$x" >> /tmp/rdr.$r
    grep -E "/$(basename "$x")\$" /tmp/rch.$r >> /tmp/rdr.$r
  done < /tmp/rbad.$r
  # 缺头文件类: 报错说 file not found 的, 把包含它的已改 .c 退掉
  grep -oE "'[A-Za-z0-9_./-]+\.h' file not found" "$W/resume.$r" | sed -E "s@'@ @g; s@ file not found@@; s@^ *@@" | sort -u > /tmp/rhdr.$r
  while read -r h; do
    [ -z "$h" ] && continue
    bl=$(basename "$h")
    git diff --name-only | while read -r f; do grep -q "$bl" "$f" 2>/dev/null && echo "$f"; done >> /tmp/rdr.$r
  done < /tmp/rhdr.$r
  sort -u /tmp/rdr.$r -o /tmp/rdr.$r
  if [ ! -s /tmp/rdr.$r ]; then
    echo "  ⛔ 仍无匹配可退。错误前 8 行:"; grep -E "(fatal error| error):" "$W/resume.$r" | head -8 | sed 's/^/     /'; exit 2
  fi
  echo "     缺的头: $(tr '\n' ' ' < /tmp/rhdr.$r)"
  echo "     本轮退回 $(wc -l < /tmp/rdr.$r): $(tr '\n' ' ' < /tmp/rdr.$r | cut -c1-150)"
  xargs -r -a /tmp/rdr.$r git checkout --
done

echo '=== 收敛后: 用 .o 判真参与编译 ==='
git diff --name-only | grep -v setlocalversion > /tmp/g.lst
: > "$W/compiled.lst"; : > "$W/dead.lst"
while read -r f; do
  if [ -f "out/$(dirname "$f")/$(basename "$f" .c).o" ]; then echo "$f" >> "$W/compiled.lst"; else echo "$f" >> "$W/dead.lst"; fi
done < /tmp/g.lst
echo "  真进本机=$(wc -l < "$W/compiled.lst")  未编译=$(wc -l < "$W/dead.lst")"
sed 's/^/    /' "$W/compiled.lst"
echo "  敏感路径命中:"; grep -E "entry-common|traps\.c|signal\.c|kernel/sched/|blk-mq\.c|mm/fault|kvm/" "$W/compiled.lst" | sed 's/^/    ⚠ /' || echo "    (无)"
git diff --numstat | awk '{a+=$1;d+=$2} END{print "  合计 +"a" -"d}'
echo "=== 结束 $(date) ==="
