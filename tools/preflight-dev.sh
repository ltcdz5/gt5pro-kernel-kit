#!/system/bin/sh
# preflight-dev.sh —— 发布前自检的设备侧部分（只读，@@@@ 分节）
echo "@@@@UNAME"; uname -r
echo "@@@@BANNER"; uname -v
echo "@@@@SLOT"; getprop ro.boot.slot_suffix
echo "@@@@LSMOD"; lsmod | wc -l
echo "@@@@DMESG"; dmesg | grep -c 'Unknown symbol'; dmesg | grep -c 'disagrees about version'; dmesg | grep -cE 'Oops|BUG: |Kernel panic'
echo "@@@@SCENE"; dumpsys package com.omarea.vtools 2>/dev/null | grep -m1 versionName; dumpsys package com.omarea.vtools 2>/dev/null | grep -m1 lastUpdateTime
echo "@@@@BOOTREASON"; getprop ro.boot.bootreason
echo "@@@@GOV"; for p in 0 2 5 7; do echo -n "$(cat /sys/devices/system/cpu/cpufreq/policy$p/scaling_governor 2>/dev/null)/$(cat /sys/devices/system/cpu/cpufreq/policy$p/scaling_max_freq 2>/dev/null) "; done; echo
echo "@@@@BATT"; cat /sys/class/power_supply/battery/status; cat /sys/class/power_supply/battery/capacity; cat /sys/class/power_supply/battery/charge_counter
echo "@@@@END"
