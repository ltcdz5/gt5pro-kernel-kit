#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/sched_assist_read.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 只读: 把厂商 sched_assist 那批节点的权限/当前值逐条列清楚
ADB="D:/gaojizhushou/adb.exe"
D=/proc/oplus_scheduler/sched_assist
$ADB shell "su -c 'for f in $D/*; do
  n=\${f##*/};
  m=\$(ls -l \$f | cut -c1-10);
  v=\$(head -c 120 \$f 2>&1 | tr \"\n\" \"/\");
  printf \"%-28s %-11s %s\n\" \"\$n\" \"\$m\" \"\$v\";
done'" 2>&1 | tr -d '\r'
