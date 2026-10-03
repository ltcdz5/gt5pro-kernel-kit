#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt_diff_offsets.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 32 个差异字节到底落在哪：按 64KB 块聚类，并打印每块附近的可读文本
T=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
A=/home/builder/opt-prune/Image.before
B=$T/out/arch/arm64/boot/Image
cd "$T" || exit 1
cmp -l "$A" "$B" | awk '{print $1-1}' > /tmp/offs.txt
echo "差异字节数=$(wc -l < /tmp/offs.txt)"
echo "--- 按 4KB 块聚类(块起点 / 该块内差异个数 / 块内可读文本前 80 字) ---"
awk '{print int($1/4096)*4096}' /tmp/offs.txt | sort | uniq -c | while read -r cnt blk; do
  printf "%-12s %-4s  " "$blk" "$cnt"
  dd if="$B" bs=4096 skip="$((blk/4096))" count=1 2>/dev/null | strings -n 6 | head -3 | tr '\n' '|' | cut -c1-90
  echo
done
echo "--- 最小/最大差异偏移 ---"
sort -n /tmp/offs.txt | sed -n '1p;$p'
