#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/冷启动基线.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 冷启动基线（opt13）：3 轮 reboot→boot_completed 的墙钟 + 框架阶段时间戳差值
# 口径说明：功耗不能用这条通道测（插 USB 会分流且限亮度），这里只测"时间"。
set -u
ADB=/d/gaojizhushou/adb.exe
for r in 1 2 3; do
  echo "===== 第 $r 轮 发 reboot 时刻 $(date '+%H:%M:%S')"
  T0=$(date +%s)
  "$ADB" reboot
  sleep 10
  "$ADB" wait-for-device
  for i in $(seq 1 120); do
    V=$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
    [ "$V" = "1" ] && break
    sleep 2
  done
  T1=$(date +%s)
  echo "   reboot→boot_completed 墙钟 = $((T1-T0)) s（轮询粒度 2s）"
  "$ADB" shell "su -c 'echo 开机后uptime=; cat /proc/uptime | cut -d\" \" -f1; echo 电量=; dumpsys battery | grep -m1 level'"
  echo "   框架阶段时间戳（同一时钟，取差值有效）:"
  "$ADB" shell "logcat -b events -d | grep -E 'boot_progress_preload_start|boot_progress_start|boot_progress_enable_screen' | tail -4" | sed 's/^/     /'
  sleep 20
done
echo done-marker
