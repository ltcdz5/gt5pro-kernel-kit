#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/images_出清单.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 给 images/ 做一份"哪个文件是什么"的清单：大小 + md5 + 用途（用途由人工填，脚本只保证数是真的）
set -u
cd /mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images || exit 1
OUT=/mnt/c/Users/xutengfa/Desktop/gt5pro-kernel/images/清单.txt
{
  echo "# images/ 文件清单（$(date '+%Y-%m-%d %H:%M') 生成，逐文件 md5）"
  echo "# 用途列是人工标注，改文件后请重跑本脚本（tools/images_出清单.sh）"
  echo
  for f in *; do
    [ -f "$f" ] || continue
    [ "$f" = "清单.txt" ] && continue
    printf "%12s  %s  %s\n" "$(stat -c %s "$f")" "$(md5sum "$f" | cut -c1-32)" "$f"
  done
  echo
  echo "=== 子目录 ==="
  for d in */; do [ -d "$d" ] && printf "%12s  (目录)  %s\n" "$(du -sb "$d" | cut -f1)" "$d"; done
  echo
  echo "=== 合计 ==="
  du -sh . | cut -f1
} > "$OUT"
echo "已写出 $OUT"
wc -l "$OUT"
