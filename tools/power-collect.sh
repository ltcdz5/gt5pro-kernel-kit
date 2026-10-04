# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/power-collect.sh —— 设备侧离线自采（只读）
#   作者 : ltcdz5   许可 : GPL-2.0（见仓库根 LICENSE）
#   背景 : 拔掉 USB 就没有 adb，PC 侧采样方案不成立 ⇒ 改由设备自己记，插回后 adb pull
#   用法 : adb push power-collect.sh /data/local/tmp/ && \
#          adb shell su -c 'setsid sh /data/local/tmp/power-collect.sh <tag> <间隔秒> <时长秒> >/dev/null 2>&1 &'
#          然后拔线 → 静置 → 插回 → adb pull /data/local/tmp/power-<tag>.log
#   特点 : 检测到【拔线】与【插回】时各打一次完整 wakeup_sources 快照 ⇒ 可算纯离线窗口增量
# ---------------------------------------------------------------------------
#!/system/bin/sh
# power-collect.sh <tag> <interval_sec> <duration_sec>
# 设备侧自我采样：拔线期间自己记，插回来 adb pull。只读，不碰任何旋钮。
# 关键：检测到【拔线】与【插回】时各打一次完整 wakeup_sources 快照 => 可算纯离线窗口增量
DBG=$(mount | grep -m1 "type debugfs" | sed 's/.* on \([^ ]*\) type.*/\1/')
OUT=/data/local/tmp/power-$1.log
: > $OUT 2>/dev/null || { echo "无法写 $OUT"; exit 1; }
echo "# tag=$1 interval=$2 duration=$3 start=$(date +%s)" >> $OUT
snap() {
  echo "===== SNAP-$1 ts=$(date +%s) status=$(cat /sys/class/power_supply/battery/status) =====" >> $OUT
  cat "$DBG/wakeup_sources" >> $OUT 2>/dev/null
  echo "===== END-SNAP =====" >> $OUT
}
snap START
prev=""
i=0
while [ $i -lt $3 ]; do
  st=$(cat /sys/class/power_supply/battery/status)
  if [ "$prev" != "$st" ]; then
    case "$st" in
      Discharging) snap UNPLUG ;;
      Charging|Full) [ -n "$prev" ] && snap REPLUG ;;
    esac
    prev="$st"
  fi
  intr=$(grep -m1 ^intr /proc/stat | cut -d" " -f2)
  ctxt=$(grep -m1 ^ctxt /proc/stat | cut -d" " -f2)
  echo "$(date +%s) $st $(cat /sys/class/power_supply/battery/capacity) $(cat /sys/class/power_supply/battery/current_now) $(cat /sys/class/power_supply/battery/voltage_now) $intr $ctxt $(cat /sys/devices/system/cpu/cpu0/cpuidle/state0/time) $(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq)" >> $OUT
  i=$((i+$2)); sleep $2
done
snap END
echo "DONE $(date +%s)" >> $OUT
