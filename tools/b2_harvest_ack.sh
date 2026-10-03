#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/b2_harvest_ack.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 按 path 拉 ACK 的提交(含 patch), 合成一个补丁集; 秒级~分钟级, 只几 MB
set -u
OUT=/mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/patches/ack-0709
mkdir -p "$OUT"
SHA=android14-6.1-2025-09
SINCE=2025-07-01T00:00:00Z
PATHS="mm include/linux arch/arm64 drivers/android fs/f2fs net/unix fs/eventpoll.c fs/pipe.c kernel/sched kernel/exit.c kernel/fork.c net/core"
: > "$OUT/_index.tsv"
for p in $PATHS; do
  f=$(echo "$p" | tr '/' '_')
  gh api "repos/aosp-mirror/kernel_common/commits?sha=$SHA&path=$p&since=$SINCE&per_page=100" \
     --jq ".[] | \"\(.sha)\t\(.commit.author.date[0:10])\t\(.commit.message | split(\"\n\")[0])\"" \
     > "$OUT/list_$f.tsv" 2>"$OUT/err_$f.txt"
  printf '%-18s 提交=%s\n' "$p" "$(wc -l < "$OUT/list_$f.tsv")"
  cut -f1 "$OUT/list_$f.tsv" >> "$OUT/_index.tsv"
done
sort -u "$OUT/_index.tsv" > "$OUT/_shas.txt"
echo "去重后涉及我们路径的提交数 = $(wc -l < "$OUT/_shas.txt")"
echo "=== 逐条取 patch(每条一次调用) ==="
: > "$OUT/ack.patches.txt"
i=0
while read -r s; do
  [ -z "$s" ] && continue
  i=$((i+1))
  gh api "repos/aosp-mirror/kernel_common/commits/$s" \
    --jq '"##### \(.sha[0:11]) \(.commit.author.date[0:10]) \(.commit.message | split("\n")[0])", (.files[] | "  FILE \(.filename)  +\(.additions)/-\(.deletions)")' \
    >> "$OUT/ack.patches.txt" 2>/dev/null
  [ $((i % 20)) -eq 0 ] && echo "  已取 $i"
done < "$OUT/_shas.txt"
echo "总计取 $i 条; 索引文件行数=$(wc -l < "$OUT/ack.patches.txt")"
echo
echo "=== 这批里碰 .h 的条目(需要闸门关注) ==="
grep -E 'FILE .*\.h ' "$OUT/ack.patches.txt" | awk '{print $2}' | sort | uniq -c | sort -rn | head -12 | sed 's/^/  /'
