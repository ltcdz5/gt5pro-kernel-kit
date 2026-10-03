#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/opt10_report.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
set -u
T=/home/builder/kwork/cctv18/repo/local/kernel_workspace/common
W=/home/builder/opt10
cd "$T" || exit 1
git config --global --add safe.directory "$T" 2>/dev/null
echo "分支=$(git rev-parse --abbrev-ref HEAD)"
echo "改动文件数=$(git diff --name-only | wc -l)"
git diff --numstat | awk '{a+=$1; d+=$2} END {print "合计 +" a " -" d}'
E=$(git diff -U0 | grep -cE '^\+[[:space:]]*(EXPORT_SYMBOL|EXPORT_SYMBOL_GPL|DEFINE_HOOK|DECLARE_HOOK)' || true)
echo "新增导出行数=$E"
echo "--- Makefile 版本字段:"
grep -E '^(VERSION|PATCHLEVEL|SUBLEVEL|EXTRAVERSION)' Makefile | sed 's/^/  /'
echo "--- 落地文件按顶层目录:"
cut -f2 "$W/landed.txt" | cut -d/ -f1-2 | sort | uniq -c | sort -rn | sed 's/^/  /'
echo "--- 跳过原因分布:"
cut -f3 "$W/skipped.tsv" | sort | uniq -c | sed 's/^/  /'
echo "--- 因新增导出被剔的文件(前 20, 去重):"
awk -F'\t' '$3=="新增导出"{print $2}' "$W/skipped.tsv" | sort -u | head -20 | sed 's/^/  /'
echo "--- 落地最多的 12 个文件:"
cut -f2 "$W/landed.txt" | sort | uniq -c | sort -rn | head -12 | sed 's/^/  /'
