#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt_diff_context.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
T=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
A=/home/builder/opt-prune/Image.before
B=$T/out/arch/arm64/boot/Image
for blk in 20430848 24653824 36667392; do
  echo "===== 块 $blk ====="
  for f in "$A" "$B"; do
    echo "-- $(basename "$f")"
    dd if="$f" bs=4096 skip="$((blk/4096))" count=1 2>/dev/null | strings -n 4 | grep -aiE "version|SMP|2026|PREEMPT|clang" | head -4
  done
done
