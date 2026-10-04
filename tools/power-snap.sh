# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/power-snap.sh —— 设备侧功耗/唤醒快照（只读）
#   作者 : ltcdz5   许可 : GPL-2.0（见仓库根 LICENSE）
#   用法 : 推送到设备后  adb shell su -c 'sh /data/local/tmp/power-snap.sh'
#          输出以 @@@@块名 分节，PC 侧解析；不写任何文件、不动任何旋钮
#   注意 : 必须走「脚本文件 + su -c sh 脚本」这条路径；
#          实测内联 su -c 长命令 会落到别的 SELinux 上下文里，读 battery/suspend_stats 会被拒
# ---------------------------------------------------------------------------
#!/system/bin/sh
# 功耗快照：只读、只向 stdout 打标记数据（无设备侧写文件）
DBG=$(mount | grep -m1 "type debugfs" | sed 's/.* on \([^ ]*\) type.*/\1/')
echo "@@@@TS"; date +%s
echo "@@@@BATT"; cat /sys/class/power_supply/battery/status; cat /sys/class/power_supply/battery/capacity; cat /sys/class/power_supply/battery/current_now; cat /sys/class/power_supply/battery/voltage_now
echo "@@@@INTR"; grep -m1 ^intr /proc/stat
echo "@@@@CTXT"; grep -m1 ^ctxt /proc/stat
echo "@@@@WFI"; cat /sys/devices/system/cpu/cpu0/cpuidle/state0/time; cat /sys/devices/system/cpu/cpu0/cpuidle/state0/usage
echo "@@@@SUSP"; cat /sys/power/suspend_stats/success
echo "@@@@TIS"; for p in 0 2 5 7; do echo "#p$p"; cat /sys/devices/system/cpu/cpufreq/policy$p/stats/time_in_state; done
echo "@@@@GOV"; cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor; cat /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq; cat /sys/devices/system/cpu/cpufreq/policy7/scaling_max_freq
echo "@@@@TZ"; for z in 10 12 20 28; do cat /sys/class/thermal/thermal_zone$z/temp; done
echo "@@@@WS"; cat "$DBG/wakeup_sources"
echo "@@@@END"
