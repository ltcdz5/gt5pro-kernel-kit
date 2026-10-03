#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/check_stale_symvers.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
BASE=/home/builder/opt5-baseline
echo '=== 1) symvers 与本轮构建的时间关系 ==='
ls -l --time-style=+%H:%M:%S "$TREE/out/Module.symvers" "$TREE/out/vmlinux" "$TREE/out/arch/arm64/boot/Image" /home/builder/a3probe/Module.symvers.a3 2>&1
echo
echo '=== 2) 这些 hook 名字到底在不在镜像里(opt5 基线 vs a3) ==='
for h in android_vh_lock_task_fork android_vh_resched_curr_lazy android_vh_clear_curr_lazy test_task_ux; do
  printf '  %-32s opt5镜像=%-4s a3镜像=%-4s opt6镜像=%s\n' "$h" \
    "$(strings -a $BASE/Image.opt5 | grep -c "$h")" \
    "$(strings -a /home/builder/a3probe/Image.a3 | grep -c "$h")" \
    "$(strings -a $BASE/Image.opt6 | grep -c "$h")"
done
echo
echo '=== 3) System.map 里有没有(符号真存在才有地址) ==='
for h in android_vh_lock_task_fork test_task_ux; do
  printf '  %-32s opt5=%-4s a3=%-4s\n' "$h" \
    "$(grep -c "$h" $BASE/System.map)" "$(grep -c "$h" /home/builder/a3probe/System.map.a3)"
done
echo
echo '=== 4) 整棵树里这些 hook 的定义点(git grep 全树, 不只两个目录) ==='
git grep -c 'android_vh_lock_task_fork' 2>/dev/null | head -5
echo "  全树命中文件数=$(git grep -l 'android_vh_lock_task_fork' 2>/dev/null | wc -l)"
echo
echo '=== 5) opt5 与 a3 的 symvers 行数/大小(陈旧的话会明显不匹配) ==='
wc -l "$BASE/Module.symvers" /home/builder/a3probe/Module.symvers.a3
