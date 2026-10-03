#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/与基线差集重数.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
set -u
T=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
cd "$T" || exit 1
echo "== 当前分支/提交 =="
git log --oneline -3
git rev-parse --abbrev-ref HEAD
echo "== 可选基线（快照/原厂点） =="
git log --oneline --all | grep -iE "snap|baseline|import|初始" | head -8
echo "== 相对 d56788d59（退料前的原始基线点）的全量差集 =="
git diff --stat d56788d59 HEAD | tail -3
echo "== 按目录归类 =="
git diff --name-only d56788d59 HEAD | sed 's#/[^/]*$##' | awk -F/ '{print $1"/"$2}' | sort | uniq -c | sort -rn | head -15
echo "== 其中真进了 vmlinux.a 的 .c 文件数（判'进没进本机'） =="
ar t out/vmlinux.a 2>/dev/null | wc -l
