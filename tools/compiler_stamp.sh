#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/compiler_stamp.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
WIN='/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images/不能刷-裸内核'
echo '=== 每个裸 Image 的完整版本串(含编译器指纹) ==='
for f in "$WIN"/*.img; do
  printf '%-34s ' "$(basename "$f" | sed 's/^boot-//; s/\.raw\.img$//')"
  strings -a "$f" | grep -m1 'Linux version' | sed 's/^Linux version //'
done
echo
echo '=== 现役 opt5 的编译器串 vs 本地 clang ==='
export PATH="/home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin:$PATH"
which clang; clang --version | head -1
ls -d /home/builder/kwork/kernel_manifest/workspace/toolchains/clang/bin >/dev/null && echo '  clang17 目录在'
