#!/system/bin/sh
# fengchi-boot 看门狗：守护意外退出就自动重启（自身也保证单实例）
MODDIR=${0%/*}
WATCH_PID=/data/adb/fengchi-watch.pid
GPID=/data/adb/fengchi-gov.pid
LOG=/sdcard/Download/fengchi-gov.log
if [ -f "$WATCH_PID" ]; then
  old=$(cat "$WATCH_PID" 2>/dev/null)
  if [ -n "$old" ] && [ -d "/proc/$old" ]; then
    c=$(tr '\0' ' ' < /proc/$old/cmdline 2>/dev/null)
    case "$c" in *fengchi-watch*) exit 0 ;; esac
  fi
fi
echo $$ > "$WATCH_PID" 2>/dev/null
mkdir -p /sdcard/Download 2>/dev/null
echo "[$(date '+%m-%d %H:%M:%S')] watchdog start pid=$$" >> "$LOG" 2>/dev/null
while true; do
  alive=0
  if [ -f "$GPID" ]; then
    p=$(cat "$GPID" 2>/dev/null)
    if [ -n "$p" ] && [ -d "/proc/$p" ]; then
      c=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null)
      case "$c" in *fengchi-gov*) alive=1 ;; esac
    fi
  fi
  if [ "$alive" = "0" ]; then
    rm -f "$GPID" 2>/dev/null
    echo "[$(date '+%m-%d %H:%M:%S')] watchdog: 守护不在，正在重启" >> "$LOG" 2>/dev/null
    sh "$MODDIR/fengchi-gov.sh" >/dev/null 2>&1 < /dev/null &
  fi
  sleep 20
done