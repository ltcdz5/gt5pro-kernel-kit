#!/system/bin/sh
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/唤醒源离机采样.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# 设备侧自采 wakeup_sources 两份快照（离机跑：拔 USB、真灭屏，采样期间不碰手机）
# 用法: sh ws.sh <标签> <静置秒>
# 相比上一版补了三样，否则数据不可解释：
#   1) /sys/power/suspend_stats —— 没有"确实睡过"的证据，唤醒源读数就只是"没睡时的活动"
#   2) 屏幕状态用 mWakefulness + mScreenOn 两项，防"以为灭屏了其实没灭"
#   3) 采样前先 force-stop adbd 无关的第三方活动不做（保持日常态），只记录不干预
N="$1"; IDLE="$2"
T=/data/local/tmp
D=$(grep -m1 ' debugfs ' /proc/mounts | cut -d' ' -f2)
snap() {
  {
    echo "#tag=$N name=$1 epoch=$(date +%s) uptime=$(cut -d' ' -f1 /proc/uptime) debugfs=$D"
    echo "#$(dumpsys power | grep -m1 -E 'mWakefulness=')"
    echo "#$(dumpsys power | grep -m1 -E 'mScreenOn=|Display Power')"
    echo "#battery=$(dumpsys battery | grep -m1 -E '  level' | tr -d ' ')"
    echo "#plugged_AC=$(dumpsys battery | grep -m1 'AC powered' | tr -d ' ')"
    echo "#plugged_USB=$(dumpsys battery | grep -m1 'USB powered' | tr -d ' ')"
    echo "#suspend_stats_below:"
    cat /sys/power/suspend_stats/success 2>/dev/null | sed 's/^/#success=/'
    cat /sys/power/suspend_stats/failed_suspend 2>/dev/null | sed 's/^/#failed_suspend=/'
    cat /sys/power/suspend_stats/last_failed_errno 2>/dev/null | sed 's/^/#last_failed_errno=/'
    cat /sys/power/suspend_stats/abort_suspend 2>/dev/null | sed 's/^/#abort_suspend=/'
    cat "$D/wakeup_sources"
  } > "$T/ws.$N.$1"
}
snap A 0
sleep "$IDLE"
snap B "$IDLE"
echo done > "$T/ws.$N.ok"
