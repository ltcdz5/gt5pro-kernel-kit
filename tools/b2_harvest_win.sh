#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/b2_harvest_win.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 在 Windows/Git Bash 侧跑(gh 只在这边)。取 ACK 中涉及我们路径的提交清单。
set -u
OUT="$1"
SHA=android14-6.1-2025-09
SINCE=2025-07-01T00:00:00Z
mkdir -p "$OUT"
PATHS="mm include/linux arch/arm64 drivers/android fs/f2fs net/unix fs/eventpoll.c fs/pipe.c kernel/sched kernel/exit.c kernel/fork.c net/core block"
: > "$OUT/_all.tsv"
for p in $PATHS; do
  f=$(echo "$p" | tr '/' '_')
  if gh api "repos/aosp-mirror/kernel_common/commits?sha=$SHA&path=$p&since=$SINCE&per_page=100" \
      --jq ".[] | [\"$p\", .sha[0:12], .commit.author.date[0:10], (.commit.message|split(\"\n\")[0])] | @tsv" \
      > "$OUT/list_$f.tsv" 2>"$OUT/err_$f.txt"; then
    printf '%-18s 提交=%s\n' "$p" "$(wc -l < "$OUT/list_$f.tsv")"
  else
    printf '%-18s 失败: %s\n' "$p" "$(head -c 90 "$OUT/err_$f.txt")"
  fi
  cat "$OUT/list_$f.tsv" >> "$OUT/_all.tsv"
done
echo
sort -u -k2,2 "$OUT/_all.tsv" > "$OUT/_uniq.tsv"
echo "涉及我们路径的提交(去重) = $(wc -l < "$OUT/_uniq.tsv")"
echo "总提交数(未去重) = $(wc -l < "$OUT/_all.tsv")"
echo
echo "=== 标题里带 revert/bad backport 的(这些不能当'净收益'搬) ==="
grep -iE "revert|bad backport" "$OUT/_uniq.tsv" | cut -c1-110 | sed 's/^/  /'
echo
echo "=== 前 20 条 ==="
head -20 "$OUT/_uniq.tsv" | cut -c1-108 | sed 's/^/  /'
