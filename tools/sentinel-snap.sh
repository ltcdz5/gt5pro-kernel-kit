#!/system/bin/sh
# sentinel-snap.sh —— 哨兵：一次输出所有留证字段（只读，@@@@ 分节，PC 侧解析）
DBG=$(mount | grep -m1 "type debugfs" | sed 's/.* on \([^ ]*\) type.*/\1/')
echo "@@@@TS"; date +%s
echo "@@@@UNAME"; cat /proc/version | cut -c1-120
echo "@@@@BOOT"; getprop ro.boot.bootreason; getprop ro.boot.slot_suffix
echo "@@@@UP"; cut -d. -f1 /proc/uptime
echo "@@@@LSMOD"; lsmod | wc -l
echo "@@@@DMESG"; dmesg | grep -cE "Oops|BUG: |Kernel panic"; dmesg | grep -c "disagrees about version"
echo "@@@@SCENE"; dumpsys package com.omarea.vtools 2>/dev/null | grep -m1 versionName; dumpsys package com.omarea.vtools 2>/dev/null | grep -m1 lastUpdateTime
echo "@@@@CPUFREQ"; for p in 0 2 5 7; do echo -n "$(cat /sys/devices/system/cpu/cpufreq/policy$p/scaling_governor 2>/dev/null)/$(cat /sys/devices/system/cpu/cpufreq/policy$p/scaling_max_freq 2>/dev/null)/$(cat /sys/devices/system/cpu/cpufreq/policy$p/scaling_min_freq 2>/dev/null) "; done; echo
echo "@@@@BATT"; cat /sys/class/power_supply/battery/status; cat /sys/class/power_supply/battery/capacity; cat /sys/class/power_supply/battery/current_now
echo "@@@@TZ"; for z in 10 12 20 28; do cat /sys/class/thermal/thermal_zone$z/temp; done
echo "@@@@WS"; cat "$DBG/wakeup_sources"
echo "@@@@END"
