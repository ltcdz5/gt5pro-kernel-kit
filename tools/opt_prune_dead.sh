#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt_prune_dead.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 退掉"改了但不进本机内核镜像"的 28 个文件（清单由 opt_dead_audit.py 产出）
set -e
TREE=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
LIST=/home/builder/opt-prune/dead_files.txt
cd "$TREE"
n=0
while read -r f; do
  [ -z "$f" ] && continue
  git checkout d56788d59 -- "$f"
  n=$((n+1))
done < "$LIST"
echo "退回文件数=$n"
git --no-pager diff --cached --stat | tail -1
git commit -q -a -m "opt12-clean: 退掉 28 个不进本机内核镜像的白改文件（20 个编成 .ko 刷 boot_a 带不走 + 8 个本机不编）"
echo "HEAD=$(git rev-parse --short HEAD)"
echo "工作区剩余改动=$(git status --short | wc -l)"
echo "累计改动 vs opt7-clean=$(git --no-pager diff --name-only d56788d59..HEAD | wc -l)"
