#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt_diff_hex.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
T=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
A=/home/builder/opt-prune/Image.before
B=$T/out/arch/arm64/boot/Image
cmp -l "$A" "$B" | awk '{print $1-1}' | awk '$1>=24653824 && $1<24657920' > /tmp/mid.txt
echo "该块内差异偏移个数=$(wc -l < /tmp/mid.txt)"
first=$(head -1 /tmp/mid.txt); last=$(tail -1 /tmp/mid.txt)
echo "首=$first 尾=$last"
base=$((first/16*16))
echo "--- before @ $base ---"
dd if="$A" bs=16 skip="$((base/16))" count=8 2>/dev/null | od -A d -t x1z -v | head -12
echo "--- after  @ $base ---"
dd if="$B" bs=16 skip="$((base/16))" count=8 2>/dev/null | od -A d -t x1z -v | head -12
echo "--- 该区域前后文本(before) ---"
dd if="$A" bs=4096 skip="$((24653824/4096))" count=1 2>/dev/null | strings -n 5 | head -6
