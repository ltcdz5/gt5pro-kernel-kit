#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/check_ufs_fixes.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 判定 5 条上游 UFS 核心修复是否已在我们树里: 反向套成功=已合入
cd /home/builder/kwork/cctv18/repo/local/kernel_workspace/common || exit 1
P=/mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/patches/ufs-upstream
declare -A NAME=(
 [776ad090f]="Always initialize the UIC done completion"
 [4a07d6ce4]="Move link recovery for hibern8 exit failure to wl_resume"
 [4bf9c3a7a]="Fix EH failure after W-LUN resume error"
 [843c13760]="fix incorrect buffer duplication in ufshcd_read_string_desc"
 [d06eb2620]="Fix use-after free in init error and remove paths"
)
for k in 776ad090f 4a07d6ce4 4bf9c3a7a 843c13760 d06eb2620; do
  f="$P/$k.patch"
  printf "%-11s %-58s " "$k" "${NAME[$k]:0:56}"
  if [ ! -f "$f" ]; then echo "补丁文件缺失"; continue; fi
  if git apply -R --check "$f" >/dev/null 2>&1; then
    echo "===> 已合入"
  elif git apply --check "$f" >/dev/null 2>&1; then
    echo "===> 缺失(能干净套上)"
  else
    # 试 -3 -way 与只检查 ufshcd.c
    if git apply -R --check --3way "$f" >/dev/null 2>&1; then
      echo "===> 已合入(需三方合并)"
    else
      echo "===> 缺失, 且上下文与绿厂改动有冲突(要手工挑)"
    fi
  fi
done
echo
echo "=== 我们这棵树的基线日期线索 ==="
grep -m1 -E "^(VERSION|PATCHLEVEL|SUBLEVEL|EXTRAVERSION)" Makefile | tr '\n' ' '; echo
git log -1 --format='  cctv18 基线: %h %cI %s' 7a244ff18 | cut -c1-100
