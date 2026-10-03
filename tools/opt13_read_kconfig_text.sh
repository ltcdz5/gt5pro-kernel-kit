#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt13_read_kconfig_text.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 从我们自己编的这棵树里取上游对这三项开销的原文描述（不靠网页内容农场）
T=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
cd "$T" || exit 1
echo "===== lib/Kconfig.ubsan（整段） ====="
cat lib/Kconfig.ubsan
echo "===== INIT_ON_ALLOC_DEFAULT_ON 的 help 原文 ====="
grep -n -A 22 "config INIT_ON_ALLOC_DEFAULT_ON" init/Kconfig lib/Kconfig* 2>/dev/null | head -40
echo "===== KFENCE_SAMPLE_INTERVAL 的 help 原文 ====="
grep -n -A 16 "config KFENCE_SAMPLE_INTERVAL" mm/Kconfig lib/Kconfig.kfence 2>/dev/null | head -30
