#!/bin/bash
# ---------------------------------------------------------------------------
# gt5pro-kernel-kit / tools/留存4_runner2.sh
#   作者   : ltcdz5
#   许可   : GPL-2.0（见仓库根 LICENSE）
#   来源   : 本仓库自有工具；派生/借鉴第三方者逐条注明于下，并汇总于根 NOTICE.md
#   借鉴   : 见 NOTICE.md 第三节
# ---------------------------------------------------------------------------
# v5 第二轮专用：只跑一轮，并且不信本地 adb 会话的存活。
# 用法: bash 留存4_runner2.sh <标签> <Y|N>
# 依据：上一版里 B1 的本地会话在第 45 秒被静默拆掉（远端脚本却继续跑到"起点应用进程数"），
#      导致 runner 误判"本轮作废"并立刻 reboot 把远端真杀了。改成设备侧落盘 + PC 侧轮询 done。
ADB=/d/gaojizhushou/adb.exe
TAG="$1"
STATE="$2"
OUT=/c/Users/xutengfa/Downloads/v5
DEV=/data/local/tmp/留存5.$TAG.txt
mkdir -p "$OUT"

echo "===== $TAG 设定 MGLRU=$STATE：重启归一化 $(date +%H:%M:%S)"
"$ADB" reboot
sleep 8
for i in $(seq 1 100); do
  if "$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' | grep -qx 1; then
    echo "    boot_completed=1（等了约 $((i*3))s）"; break
  fi
  [ "$i" = 100 ] && { echo "    超时：等不到 boot_completed"; exit 1; }
  sleep 3
done

# 设备侧自后台跑，PC 侧断线不影响它
"$ADB" shell "su -c 'setsid sh /data/local/tmp/lx5.sh $TAG $STATE 40 120 >/dev/null 2>&1 &'"
echo "    已把一轮丢给设备侧自跑，开始轮询 $DEV"

prev=""
for i in $(seq 1 90); do
  sleep 20
  cur=$("$ADB" shell "su -c 'wc -c < $DEV'" 2>/dev/null | tr -d '\r')
  [ -z "$cur" ] && cur=0
  echo "    [$((i*20))s] 设备侧文件 $cur 字节"
  if [ "$cur" = "$prev" ] && [ "$cur" != 0 ]; then
    echo "    ⚠ 连续两次字节数不变，疑似卡住（先不 reboot，交人判断）"
  fi
  prev=$cur
  if "$ADB" shell "su -c 'grep -c \"^done\$\" $DEV'" 2>/dev/null | tr -d '\r' | grep -qx 1; then
    echo "    本轮收尾标记出现，用时约 $((i*20))s"
    "$ADB" shell "su -c 'cat $DEV'" > "$OUT/$TAG.txt" 2>&1
    echo "    已拉回 $OUT/$TAG.txt"
    grep -E "设定后 enabled=|实际启动成功|==== 结果|消失清单|终点 MGLRU|本轮墙钟|am_kill 总数|MemAvailable" "$OUT/$TAG.txt" | sed 's/^/    /'
    "$ADB" shell "dumpsys battery | grep -m1 level"
    exit 0
  fi
done
echo "    超时 30 分钟仍无 done，本轮作废（不自动 reboot）"
exit 1
