#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/hmbird_attrib.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 归属: strings 对多文件会打印 "文件名:" 头, 用它把命中归到具体 .ko
F=/mnt/c/Users/USERNAME/Desktop/gt5pro-kernel/vendor-ko/vko_strings.txt.gz
zcat "$F" | awk '
  /^[^ ]+\.ko:$/ { file=$0; sub(/:$/,"",file); next }
  /register_hmbird_sched_ops|task_is_scx|hmbird/ { if (file != "") { print file"\t"$0 } }
' | head -30 | sed 's/\t/   ==> /'
echo
echo "=== 每个模块的 hmbird 命中数 ==="
zcat "$F" | awk '
  /^[^ ]+\.ko:$/ { file=$0; sub(/:$/,"",file); next }
  /hmbird/ { c[file]++ }
  END { for (f in c) printf "  %-56s %d\n", f, c[f] }
' | sort -k2 -rn | head -12
echo
echo "=== 这些 .ko 的 vermagic / 依赖(看它等哪个内核版本) ==="
zcat "$F" | awk '
  /^[^ ]+\.ko:$/ { file=$0; sub(/:$/,"",file); next }
  (/vermagic/ || /^6\.1\.141/ || /^android14-6\.1/) { if (file ~ /hmbird|sched_assist/) print "  " file ": " $0 }
' | head -6
