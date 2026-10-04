#!/bin/bash
# 静置期唤醒源采样：灭屏 → 设备侧自采两份(间隔 120s) → 期间 PC 不发任何 adb 命令(我自己就是唤醒源) → 拉回
set -u
ADB=/d/gaojizhushou/adb.exe
OUT=/c/Users/xutengfa/Downloads
"$ADB" shell input keyevent 26
echo "已发灭屏 $(date '+%H:%M:%S')"
sleep 3
"$ADB" shell "su -c 'setsid sh /data/local/tmp/ws.sh opt13 120 >/dev/null 2>&1 &'"
echo "采样已在设备侧自跑，静置 120s，期间不碰 adb"
sleep 145
echo "拉回 $(date '+%H:%M:%S')"
"$ADB" shell "su -c 'ls -l /data/local/tmp/ws.opt13.ok /data/local/tmp/ws.opt13.A /data/local/tmp/ws.opt13.B 2>&1; wc -l < /data/local/tmp/ws.opt13.A; wc -l < /data/local/tmp/ws.opt13.B'"
"$ADB" shell "su -c 'cat /data/local/tmp/ws.opt13.A'" > "$OUT/ws.opt13.A.txt" 2>&1
"$ADB" shell "su -c 'cat /data/local/tmp/ws.opt13.B'" > "$OUT/ws.opt13.B.txt" 2>&1
head -6 "$OUT/ws.opt13.A.txt"
echo "行数 A/B:"; wc -l "$OUT/ws.opt13.A.txt" "$OUT/ws.opt13.B.txt"
echo done-marker
